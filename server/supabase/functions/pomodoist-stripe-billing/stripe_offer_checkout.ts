import type Stripe from "npm:stripe@22.4.0";
import {
  assertStripeOfferObjects,
  type StripeOfferHistory,
  stripeOfferKind,
} from "./stripe_offers.ts";
import {
  type StripeBillingAccountContext,
  stripeCheckoutParams,
  type StripeCheckoutSessionInput,
} from "./pomodoist_stripe_billing.ts";

export async function loadStripeOffer(
  stripe: Stripe,
  context: StripeBillingAccountContext,
  priceIds: Record<string, string>,
  couponIds: Record<string, string>,
  livemode = false,
) {
  for (const product of ["pomodoist.pro.monthly", "pomodoist.pro.annual"]) {
    const [price, coupon] = await Promise.all([
      stripe.prices.retrieve(priceIds[product]),
      stripe.coupons.retrieve(couponIds[product]),
    ]);
    assertStripeOfferObjects(
      price,
      coupon,
      product.endsWith("monthly"),
      livemode,
    );
  }
  const history: StripeOfferHistory[] = [];
  if (context.stripeCustomerId != null) {
    const customer = await stripe.customers.retrieve(context.stripeCustomerId);
    if (customer.deleted || customer.livemode !== livemode) {
      throw new Error("Stripe customer mode mismatch.");
    }
    // Iterate every page. Canceled subscriptions remain in Stripe's history;
    // zero-amount trial invoices must not be mistaken for a paid return offer.
    for await (
      const subscription of stripe.subscriptions.list({
        customer: customer.id,
        status: "all",
        limit: 100,
      })
    ) {
      if (subscription.livemode !== livemode) {
        throw new Error("Stripe subscription mode mismatch.");
      }
      let paid = false;
      for await (
        const invoice of stripe.invoices.list({
          customer: customer.id,
          subscription: subscription.id,
          status: "paid",
          limit: 100,
        })
      ) {
        if (invoice.livemode !== livemode) {
          throw new Error("Stripe invoice mode mismatch.");
        }
        if (invoice.total > 0) paid = true;
      }
      history.push({
        status: subscription.status,
        trialStart: subscription.trial_start,
        endedAt: subscription.ended_at,
        paid,
        campaign: subscription.metadata.return_campaign ?? null,
      });
    }
  }
  return stripeOfferKind(history, context, Math.floor(Date.now() / 1000));
}

export type StripeCheckoutReservation = {
  id: string;
  expiresAt: number;
  input: StripeCheckoutSessionInput;
};

export async function createReservedStripeCheckout(
  stripe: Stripe,
  input: StripeCheckoutSessionInput,
  reserve: () => Promise<StripeCheckoutReservation>,
  release: (id: string) => Promise<void>,
  verify: () => Promise<boolean>,
  now = Math.floor(Date.now() / 1000),
  livemode = false,
): Promise<{ url: string | null }> {
  const owns = (session: Stripe.Checkout.Session) =>
    session.customer === input.customerId &&
    session.client_reference_id === input.userId &&
    session.metadata?.supabase_user_id === input.userId &&
    /^pomodoist\.pro\.(monthly|annual|lifetime(?:\.launch)?)$/.test(
      session.metadata?.product_id ?? "",
    );
  const eligible = async () => {
    if (!await verify()) throw new Error("offer_not_eligible");
  };
  const expire = async (session: Stripe.Checkout.Session) => {
    let closed: Stripe.Checkout.Session;
    try {
      closed = await stripe.checkout.sessions.expire(session.id);
    } catch {
      // A concurrent expiration is harmless; completion or an unknown result is not.
      closed = await stripe.checkout.sessions.retrieve(session.id);
    }
    if (
      closed.livemode !== livemode || !owns(closed) ||
      closed.status !== "expired"
    ) {
      throw new Error("offer_pending");
    }
  };
  for (let attempt = 0; attempt < 2; attempt++) {
    const reservation = await reserve();
    if (
      reservation.input.customerId !== input.customerId ||
      reservation.input.userId !== input.userId
    ) {
      throw new Error("offer_pending");
    }
    let existing: Stripe.Checkout.Session | null = null;
    const legacy: Stripe.Checkout.Session[] = [];
    for await (
      const session of stripe.checkout.sessions.list({
        customer: input.customerId,
        limit: 100,
      })
    ) {
      if (session.livemode !== livemode) {
        throw new Error("Stripe Checkout mode mismatch.");
      }
      if (session.status == null) throw new Error("offer_pending");
      if (session.metadata?.offer_reservation === reservation.id) {
        if (!owns(session) || existing != null) {
          throw new Error("offer_pending");
        }
        existing = session;
      } else if (session.status === "open") {
        if (
          !owns(session) || session.metadata?.offer_reservation ||
          session.payment_status === "paid"
        ) {
          throw new Error("offer_pending");
        }
        legacy.push(session);
      } else if (
        session.status === "complete" && session.payment_status === "unpaid"
      ) {
        throw new Error("offer_pending");
      }
    }
    if (
      existing?.status === "complete" && existing.payment_status === "unpaid"
    ) {
      throw new Error("offer_pending");
    }
    await eligible();
    if (existing != null) {
      existing = await stripe.checkout.sessions.retrieve(existing.id);
      if (
        existing.livemode !== livemode || !owns(existing) ||
        existing.metadata?.offer_reservation !== reservation.id ||
        existing.metadata?.product_id !== reservation.input.productId ||
        existing.status == null ||
        (existing.status === "open" && existing.payment_status === "paid") ||
        (existing.status === "complete" && existing.payment_status === "unpaid")
      ) throw new Error("offer_pending");
    }
    if (legacy.length > 0) {
      if (attempt > 0) throw new Error("offer_pending");
      for (const session of legacy) await expire(session);
      await eligible();
    }
    const matches =
      (["productId", "selectedOffer", "priceId", "couponId", "mode"] as const)
        .every((key) => reservation.input[key] === input[key]);
    if (
      (existing != null && (existing.status !== "open" || !matches)) ||
      reservation.expiresAt <= now
    ) {
      if (attempt > 0) throw new Error("offer_pending");
      if (existing?.status === "open") {
        if (existing.payment_status === "paid") {
          throw new Error("offer_pending");
        }
        await expire(existing);
        await eligible();
      }
      if (existing?.status === "complete") await eligible();
      // Only the old ID is released. Late creators cannot use an expired anchored deadline.
      await release(reservation.id);
      continue;
    }
    // Another plan may still be creating its session. Never release that live reservation.
    if (!matches) throw new Error("offer_pending");
    if (existing != null) return { url: existing.url };
    const params = stripeCheckoutParams(
      reservation.input,
    ) as Stripe.Checkout.SessionCreateParams;
    params.expires_at = reservation.expiresAt;
    params.metadata = { ...params.metadata, offer_reservation: reservation.id };
    const created = await stripe.checkout.sessions.create(params, {
      idempotencyKey: `pomodoist-test-offer:${reservation.id}`,
    });
    if (created.livemode !== livemode) {
      throw new Error("Stripe Checkout mode mismatch.");
    }
    // Idempotency can replay the original response after another request expired the session.
    const session = await stripe.checkout.sessions.retrieve(created.id);
    if (
      session.livemode !== livemode || !owns(session) ||
      session.metadata?.offer_reservation !== reservation.id
    ) {
      throw new Error("offer_pending");
    }
    if (session.status !== "open") throw new Error("offer_pending");
    return { url: session.url };
  }
  throw new Error("offer_pending");
}
