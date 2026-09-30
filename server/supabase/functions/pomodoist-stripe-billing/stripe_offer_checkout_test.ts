import { assertEquals, assertRejects } from "@std/assert";
import type Stripe from "npm:stripe@22.4.0";
import {
  createReservedStripeCheckout,
  type StripeCheckoutReservation,
} from "./stripe_offer_checkout.ts";
import type { StripeCheckoutSessionInput } from "./pomodoist_stripe_billing.ts";
const input: StripeCheckoutSessionInput = {
  customerId: "cus_test",
  userId: "user",
  productId: "pomodoist.pro.monthly",
  priceId: "price_test",
  couponId: "coupon_return",
  selectedOffer: "return",
  mode: "subscription",
  surface: "web",
  successUrl: "http://localhost/success",
  cancelUrl: "http://localhost/cancel",
};
const reservation = { id: "reservation", expiresAt: 2500, input };
const url = "https://checkout.stripe.com/test";

function checkoutSession(overrides: Partial<Stripe.Checkout.Session> = {}) {
  return {
    id: "cs_existing",
    customer: input.customerId,
    client_reference_id: input.userId,
    livemode: false,
    status: "open",
    payment_status: "unpaid",
    url,
    metadata: {
      supabase_user_id: input.userId,
      product_id: input.productId,
      offer_reservation: reservation.id,
    },
    ...overrides,
  } as Stripe.Checkout.Session;
}

function checkoutFixture(selected = input) {
  const f = {
    current: { ...reservation } as StripeCheckoutReservation | null,
    sessions: [] as Stripe.Checkout.Session[],
    creates: [] as string[],
    expires: [] as string[],
    releases: [] as string[],
    reserves: 0,
    verify: async () => true,
    onCreate: async (_session: Stripe.Checkout.Session) => {},
    onExpire: async (_session: Stripe.Checkout.Session) => {},
    onRelease: async (_id: string) => {},
  };
  const cached = new Map<string, Stripe.Checkout.Session>();
  const stripe = {
    checkout: {
      sessions: {
        list: async function* () {
          for (const session of f.sessions) yield structuredClone(session);
        },
        retrieve: async (id: string) =>
          structuredClone(f.sessions.find((s) => s.id === id)!),
        expire: async (id: string) => {
          const session = f.sessions.find((s) => s.id === id)!;
          f.expires.push(id);
          await f.onExpire(session);
          session.status = "expired";
          session.url = null;
          return structuredClone(session);
        },
        create: async (
          params: Stripe.Checkout.SessionCreateParams,
          options: { idempotencyKey: string },
        ) => {
          const previous = cached.get(options.idempotencyKey);
          if (previous) return structuredClone(previous);
          f.creates.push(options.idempotencyKey);
          const session = checkoutSession({
            id: `cs_new_${f.creates.length}`,
            metadata: params.metadata as Record<string, string>,
            customer: params.customer as string,
          });
          f.sessions.push(session);
          cached.set(options.idempotencyKey, structuredClone(session));
          await f.onCreate(session);
          return structuredClone(cached.get(options.idempotencyKey)!);
        },
      },
    },
  } as unknown as Stripe;
  const run = () =>
    createReservedStripeCheckout(stripe, selected, async () => {
      f.reserves++;
      return f.current ??= {
        id: `new_${f.reserves}`,
        expiresAt: 2500,
        input: selected,
      };
    }, async (id) => {
      f.releases.push(id);
      await f.onRelease(id);
      // Mirrors the existing SQL compare-and-delete boundary, never a blanket delete.
      if (f.current?.id === id) {
        f.current = null;
      }
    }, () =>
      f.verify(), 100);
  return { f, run };
}

Deno.test("expired reservation without a Stripe session recovers in the same request", async () => {
  const { f, run } = checkoutFixture();
  f.current!.expiresAt = 99;
  assertEquals(await run(), { url });
  assertEquals(f.reserves, 2);
  assertEquals(f.releases, ["reservation"]);
  assertEquals(f.creates.length, 1);
});

Deno.test("expired and eligible completed sessions allow a fresh repeat purchase", async () => {
  for (const status of ["expired", "complete"] as const) {
    const { f, run } = checkoutFixture();
    f.sessions.push(
      checkoutSession({
        status,
        payment_status: status === "complete" ? "paid" : "unpaid",
      }),
    );
    assertEquals(await run(), { url });
    assertEquals(f.releases, ["reservation"]);
    assertEquals(f.creates.length, 1);
  }
});

Deno.test("switching plans closes the old session before replacing its reservation", async () => {
  const selected = {
    ...input,
    productId: "pomodoist.pro.annual",
    priceId: "price_annual",
  };
  const { f, run } = checkoutFixture(selected);
  f.sessions.push(checkoutSession());
  assertEquals(await run(), { url });
  assertEquals(f.expires, ["cs_existing"]);
  assertEquals(f.current!.input.productId, "pomodoist.pro.annual");
  assertEquals(f.creates.length, 1);
});

Deno.test("changed offer terms close the old checkout before using new terms", async () => {
  for (
    const selected of [
      { ...input, priceId: "price_updated" },
      { ...input, couponId: "coupon_updated" },
      { ...input, selectedOffer: "trial" as const, couponId: null },
    ]
  ) {
    const { f, run } = checkoutFixture(selected);
    f.sessions.push(checkoutSession());
    assertEquals(await run(), { url });
    assertEquals(f.expires, ["cs_existing"]);
    assertEquals(f.current!.input, selected);
    assertEquals(f.creates.length, 1);
  }
});

Deno.test("unknown Stripe session state preserves the reservation", async () => {
  for (
    const metadata of [
      checkoutSession().metadata!,
      { supabase_user_id: input.userId, product_id: input.productId },
    ]
  ) {
    const { f, run } = checkoutFixture();
    f.current!.expiresAt = 99;
    f.sessions.push(checkoutSession({ status: null, metadata }));
    await assertRejects(run, Error, "offer_pending");
    assertEquals(f.releases, []);
    assertEquals(f.creates, []);
  }
});

Deno.test("reuse refreshes a session that expired after listing", async () => {
  const { f, run } = checkoutFixture();
  f.sessions.push(checkoutSession());
  f.verify = async () => {
    f.sessions[0].status = "expired";
    f.sessions[0].url = null;
    return true;
  };
  assertEquals(await run(), { url });
  assertEquals(f.releases, ["reservation"]);
  assertEquals(f.creates.length, 1);
});

Deno.test("an expired idempotent creation response is never returned as an active checkout", async () => {
  const { f, run } = checkoutFixture();
  f.onCreate = async (session) => {
    session.status = "expired";
    session.url = null;
  };
  await assertRejects(run, Error, "offer_pending");
  assertEquals(f.releases, []);
  assertEquals(f.creates.length, 1);
});

Deno.test("completion after listing requires fresh eligibility before releasing the reservation", async () => {
  const { f, run } = checkoutFixture();
  f.sessions.push(checkoutSession());
  f.verify = async () => {
    f.sessions[0].status = "complete";
    f.sessions[0].payment_status = "paid";
    f.verify = async () => false;
    return true;
  };
  await assertRejects(run, Error, "offer_not_eligible");
  assertEquals(f.releases, []);
  assertEquals(f.creates, []);
});

Deno.test("eligibility changed while closing a session prevents replacement", async () => {
  const { f, run } = checkoutFixture({
    ...input,
    productId: "pomodoist.pro.annual",
  });
  f.sessions.push(checkoutSession());
  f.onExpire = async () => {
    f.verify = async () => false;
  };
  await assertRejects(run, Error, "offer_not_eligible");
  assertEquals(f.expires, ["cs_existing"]);
  assertEquals(f.releases, []);
  assertEquals(f.creates, []);
});

Deno.test("owned legacy open checkout is closed and replaced without a second click", async () => {
  const { f, run } = checkoutFixture();
  f.sessions.push(
    checkoutSession({
      metadata: { supabase_user_id: input.userId, product_id: input.productId },
    }),
  );
  assertEquals(await run(), { url });
  assertEquals(f.expires, ["cs_existing"]);
  assertEquals(f.creates.length, 1);
});

Deno.test("legacy cleanup and expired reservation recover together in the same request", async () => {
  const { f, run } = checkoutFixture();
  f.current!.expiresAt = 99;
  f.sessions.push(checkoutSession({
    metadata: { supabase_user_id: input.userId, product_id: input.productId },
  }));
  assertEquals(await run(), { url });
  assertEquals(f.reserves, 2);
  assertEquals(f.expires, ["cs_existing"]);
  assertEquals(f.releases, ["reservation"]);
  assertEquals(f.creates.length, 1);
});

Deno.test("unowned sessions and processing payments never unlock a replacement", async () => {
  for (
    const session of [
      checkoutSession({ metadata: {}, client_reference_id: null }),
      checkoutSession({ status: "complete", payment_status: "unpaid" }),
      checkoutSession({
        metadata: {
          supabase_user_id: "another-user",
          product_id: input.productId,
        },
      }),
    ]
  ) {
    const { f, run } = checkoutFixture();
    f.sessions.push(session);
    await assertRejects(run, Error, "offer_pending");
    assertEquals(f.expires, []);
    assertEquals(f.releases, []);
    assertEquals(f.creates, []);
  }
});

Deno.test("unknown concurrent creation keeps the original reservation when another plan is requested", async () => {
  const { f, run } = checkoutFixture({
    ...input,
    productId: "pomodoist.pro.annual",
  });
  await assertRejects(run, Error, "offer_pending");
  assertEquals(f.current!.id, "reservation");
  assertEquals(f.releases, []);
  assertEquals(f.creates, []);
});

Deno.test("changed eligibility cannot release or replace an old checkout", async () => {
  const { f, run } = checkoutFixture();
  f.sessions.push(checkoutSession({ status: "expired" }));
  f.verify = async () => false;
  await assertRejects(run, Error, "offer_not_eligible");
  assertEquals(f.releases, []);
  assertEquals(f.creates, []);
});

Deno.test("payment completed during expiration is not replaced", async () => {
  const { f, run } = checkoutFixture({
    ...input,
    productId: "pomodoist.pro.annual",
  });
  f.sessions.push(checkoutSession());
  f.onExpire = async (session) => {
    session.status = "complete";
    session.payment_status = "paid";
    throw new Error("Session is no longer open");
  };
  await assertRejects(run, Error, "offer_pending");
  assertEquals(f.releases, []);
  assertEquals(f.creates, []);
});

Deno.test("Stripe failure before expiration confirmation preserves the reservation", async () => {
  const { f, run } = checkoutFixture({
    ...input,
    productId: "pomodoist.pro.annual",
  });
  f.sessions.push(checkoutSession());
  f.onExpire = async () => {
    throw new Error("Stripe unavailable");
  };
  await assertRejects(run, Error, "offer_pending");
  assertEquals(f.releases, []);
  assertEquals(f.creates, []);
});

Deno.test("recovery is bounded even when another expired reservation appears", async () => {
  const { f, run } = checkoutFixture();
  f.current!.expiresAt = 99;
  f.onRelease = async () => {
    f.current = { ...reservation, id: "next_expired", expiresAt: 99 };
  };
  await assertRejects(run, Error, "offer_pending");
  assertEquals(f.reserves, 2);
  assertEquals(f.releases, ["reservation"]);
  assertEquals(f.current!.id, "next_expired");
});

Deno.test("stale release preserves a newer open reservation and returns its checkout", async () => {
  const { f, run } = checkoutFixture();
  f.current!.expiresAt = 99;
  f.onRelease = async () => {
    f.current = { ...reservation, id: "newer" };
    f.sessions.push(
      checkoutSession({
        id: "cs_newer",
        url: "https://checkout.stripe.com/newer",
        metadata: {
          supabase_user_id: input.userId,
          product_id: input.productId,
          offer_reservation: "newer",
        },
      }),
    );
  };
  assertEquals(await run(), { url: "https://checkout.stripe.com/newer" });
  assertEquals(f.current!.id, "newer");
  assertEquals(f.releases, ["reservation"]);
  assertEquals(f.creates, []);
});

Deno.test("concurrent identical recovery creates only one payable checkout", async () => {
  const { f, run } = checkoutFixture();
  f.current!.expiresAt = 99;
  assertEquals(await Promise.all([run(), run()]), [{ url }, { url }]);
  assertEquals(f.creates.length, 1);
  assertEquals(f.sessions.filter((s) => s.status === "open").length, 1);
});
Deno.test("concurrent requests share anchored parameters and Stripe idempotency key across retries", async () => {
  const params: unknown[] = [];
  const keys: string[] = [];
  const stripe = {
    checkout: {
      sessions: {
        list: async function* () {},
        create: async (p: unknown, options: { idempotencyKey: string }) => {
          params.push(p);
          keys.push(options.idempotencyKey);
          return checkoutSession();
        },
        retrieve: async () => checkoutSession(),
      },
    },
  } as unknown as Stripe;
  await Promise.all(
    [input, { ...input, locale: "fr" }].map((i) =>
      createReservedStripeCheckout(
        stripe,
        i,
        async () => reservation,
        async () => {},
        async () => true,
        100,
      )
    ),
  );
  assertEquals(params[0], params[1]);
  assertEquals(keys, [
    "pomodoist-test-offer:reservation",
    "pomodoist-test-offer:reservation",
  ]);
  await assertRejects(
    () =>
      createReservedStripeCheckout(
        stripe,
        { ...input, productId: "pomodoist.pro.annual" },
        async () => reservation,
        async () => {},
        async () => true,
        100,
      ),
    Error,
    "offer_pending",
  );
  assertEquals(keys.length, 2);
});
Deno.test("closed browser preserves open offer; expired cancellation releases without redemption; async processing stays locked", async () => {
  for (
    const [status, payment_status, releases, succeeds] of [
      ["open", "unpaid", 0, true],
      ["expired", "unpaid", 1, false],
      ["complete", "unpaid", 0, false],
      ["complete", "paid", 1, false],
    ] as const
  ) {
    let released = 0;
    const stripe = {
      checkout: {
        sessions: {
          list: async function* () {
            yield checkoutSession({
              status,
              payment_status,
            });
          },
          retrieve: async () => checkoutSession({ status, payment_status }),
          create: () => {
            throw new Error("must not create");
          },
        },
      },
    } as unknown as Stripe;
    const run = () =>
      createReservedStripeCheckout(
        stripe,
        input,
        async () => reservation,
        async () => {
          released++;
        },
        async () => true,
        100,
      );
    if (succeeds) assertEquals(await run(), { url });
    else await assertRejects(run, Error, "offer_pending");
    assertEquals(released, releases);
  }
});
Deno.test("fresh eligibility errors and legacy open sessions never create checkout", async () => {
  for (const legacy of [false, true]) {
    const stripe = {
      checkout: {
        sessions: {
          list: async function* () {
            if (legacy) yield { status: "open", livemode: false, metadata: {} };
          },
          create: () => {
            throw new Error("must not create");
          },
        },
      },
    } as unknown as Stripe;
    await assertRejects(
      () =>
        createReservedStripeCheckout(
          stripe,
          input,
          async () => reservation,
          async () => {},
          async () => {
            throw new Error("verification_failed");
          },
          100,
        ),
      Error,
      legacy ? "offer_pending" : "verification_failed",
    );
  }
});

Deno.test("full Stripe history distinguishes free trials, paid credits and consumed return campaign", async () => {
  const { loadStripeOffer } = await import("./stripe_offer_checkout.ts");
  for (const livemode of [false, true]) {
    const subscriptions = [
      {
        id: "sub_trial",
        status: "canceled",
        trial_start: 1,
        ended_at: 100,
        livemode,
        metadata: {},
      },
      {
        id: "sub_return",
        status: "canceled",
        trial_start: null,
        ended_at: 200,
        livemode,
        metadata: { return_campaign: "return_2026_v1" },
      },
    ];
    const seen: string[] = [];
    let fundedReturn = false;
    const stripe = {
      prices: {
        retrieve: async (id: string) => ({
          livemode,
          active: true,
          currency: "usd",
          unit_amount: id === "monthly" ? 499 : 2999,
          recurring: {
            interval: id === "monthly" ? "month" : "year",
            interval_count: 1,
            usage_type: "licensed",
          },
          product: "prod_test",
        }),
      },
      coupons: {
        retrieve: async (id: string) => ({
          livemode,
          valid: true,
          currency: "usd",
          amount_off: id === "monthly" ? 300 : 1500,
          percent_off: null,
          duration: id === "monthly" ? "repeating" : "once",
          duration_in_months: id === "monthly" ? 3 : null,
        }),
      },
      customers: { retrieve: async () => ({ id: "cus_test", livemode }) },
      subscriptions: {
        list: async function* () {
          for (const subscription of subscriptions) yield subscription;
        },
      },
      invoices: {
        list: async function* ({ subscription }: { subscription: string }) {
          seen.push(subscription);
          yield {
            livemode,
            total: fundedReturn && subscription === "sub_return" ? 199 : 0,
            amount_paid: 0,
          };
        },
      },
    } as unknown as Stripe;
    const context = {
      stripeCustomerId: "cus_test",
      profileCreatedAt: "2026-01-01",
      hasActiveEntitlement: false,
      hasLifetimePurchase: false,
      firstSubscriptionPaidAt: null,
    };
    const ids = {
      "pomodoist.pro.monthly": "monthly",
      "pomodoist.pro.annual": "annual",
    };
    assertEquals(
      await loadStripeOffer(stripe, context, ids, ids, livemode),
      "return",
    );
    assertEquals(seen, ["sub_trial", "sub_return"]);
    fundedReturn = true;
    assertEquals(
      await loadStripeOffer(stripe, context, ids, ids, livemode),
      "standard",
    );
  }
});

Deno.test("live Checkout rejects test sessions before reuse or creation", async () => {
  for (const livemode of [false, true]) {
    for (const existing of [false, true]) {
      const session = checkoutSession({
        livemode,
      });
      const stripe = {
        checkout: {
          sessions: {
            list: async function* () {
              if (existing) yield session;
            },
            create: async () => session,
            retrieve: async () => session,
          },
        },
      } as unknown as Stripe;
      const checkout = () =>
        createReservedStripeCheckout(
          stripe,
          input,
          async () => reservation,
          async () => {},
          async () => true,
          100,
          true,
        );
      if (livemode) assertEquals(await checkout(), { url });
      else await assertRejects(checkout, Error, "mode mismatch");
    }
  }
});
