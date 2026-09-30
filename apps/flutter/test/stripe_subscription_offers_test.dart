import 'package:app_account/app_account.dart';
import 'package:pomodoist/data/services/billing/account_billing_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:pomodoist/domain/models/billing/billing_models.dart';
import 'package:pomodoist/ui/billing/widgets/billing_paywall.dart';
import 'package:pomodoist/ui/core/localization/app_localizations_en.dart';

void main() {
  test(
    'account changes during SDK requests discard both success and server errors',
    () async {
      for (final status in [200, 409]) {
        for (final checkout in [false, true]) {
          late _TransportAccount account;
          final backend = SupabaseClient(
            'https://example.invalid',
            'unit-test-key',
            httpClient: MockClient((_) async {
              account.userId = 'another-account';
              return http.Response(
                status == 409
                    ? '{"code":"offer_pending"}'
                    : '{"url":"https://checkout.stripe.com/test"}',
                status,
                headers: {'content-type': 'application/json'},
              );
            }),
          );
          addTearDown(backend.dispose);
          account = _TransportAccount(
            AccountClient.fromSupabaseClient(backend),
          );
          final service = AccountBillingService(
            account: account,
            locale: () => 'en',
            onLinked: () {},
          );
          await expectLater(
            checkout
                ? service.createStripeCheckout(
                    pomodoistMonthlyProductId,
                    BillingCheckoutSurface.web,
                    'trial',
                  )
                : service.loadStripeCatalog(),
            throwsA(
              isA<StripeBillingException>().having(
                (e) => e.code,
                'code',
                'authentication_required',
              ),
            ),
          );
        }
      }
    },
  );
  test(
    'real SDK errors preserve server codes for catalog and checkout',
    () async {
      for (final code in [
        'offer_pending',
        'authentication_required',
        'offer_not_eligible',
      ]) {
        final backend = SupabaseClient(
          'https://example.invalid',
          'unit-test-key',
          httpClient: MockClient(
            (_) async => http.Response(
              '{"code":"$code"}',
              409,
              headers: {'content-type': 'application/json'},
            ),
          ),
        );
        addTearDown(backend.dispose);
        final service = AccountBillingService(
          account: _TransportAccount(AccountClient.fromSupabaseClient(backend)),
          locale: () => 'en',
          onLinked: () {},
        );
        final expected = throwsA(
          isA<StripeBillingException>().having((e) => e.code, 'code', code),
        );
        await expectLater(service.loadStripeCatalog(), expected);
        await expectLater(
          service.createStripeCheckout(
            pomodoistMonthlyProductId,
            BillingCheckoutSurface.web,
            'trial',
          ),
          expected,
        );
      }
    },
  );
  test(
    'pending payment has a payment status message rather than a return offer error',
    () {
      final l10n = AppLocalizationsEn();
      final message = stripeBillingErrorMessage(l10n, 'offer_pending');
      expect(message.toLowerCase(), contains('payment'));
      expect(message, isNot(l10n.billingReturnFailed));
      expect(
        stripeBillingErrorMessage(l10n, 'checkout_failed').toLowerCase(),
        isNot(contains('connection')),
      );
    },
  );
  Map<String, Object?> catalog(String kind) => {
    'enabled': true,
    'introEligible': false,
    'offersEnabled': true,
    'subscriptionOffer': kind,
    'prices': {
      pomodoistMonthlyProductId: r'$4.99',
      pomodoistAnnualProductId: r'$29.99',
    },
    'launchOffer': {'eligible': false, 'endsAt': null},
  };
  test(
    'all release clients negotiate offers and preserve legacy catalogs',
    () async {
      for (final offers in [false, true]) {
        final account = _BillingAccount();
        final service = AccountBillingService(
          account: account,
          locale: () => 'ru',
          onLinked: () {},
        );
        account.response = AccountFunctionResponse(
          status: 200,
          data: offers
              ? catalog('return')
              : {
                  ...catalog('return'),
                  'offersEnabled': false,
                  'subscriptionOffer': null,
                },
        );
        final result = await service.loadStripeCatalog();
        expect(result.subscriptionOffer, offers ? 'return' : null);
        expect(account.requests.last['offerVersion'], 1);
        account.response = const AccountFunctionResponse(
          status: 200,
          data: {'url': 'https://checkout.stripe.com/test'},
        );
        await service.createStripeCheckout(
          pomodoistMonthlyProductId,
          BillingCheckoutSurface.web,
          offers ? 'return' : null,
        );
        expect(
          account.requests.last['selectedOffer'],
          offers ? 'return' : null,
        );
        expect(account.requests.last['offerVersion'], 1);
      }
    },
  );
  test(
    'transport errors and changed account cannot start a replacement checkout',
    () async {
      final account = _BillingAccount();
      final service = AccountBillingService(
        account: account,
        locale: () => 'en',
        onLinked: () {},
      );
      account.response = const AccountFunctionResponse(
        status: 409,
        data: {'code': 'offer_pending'},
      );
      await expectLater(
        service.createStripeCheckout(
          pomodoistAnnualProductId,
          BillingCheckoutSurface.web,
          'return',
        ),
        throwsA(
          isA<StripeBillingException>().having(
            (e) => e.code,
            'code',
            'offer_pending',
          ),
        ),
      );
      expect(account.requests.length, 1);
      account.userId = 'another-account';
      await expectLater(
        service.loadStripeCatalog(),
        throwsA(isA<StripeBillingException>()),
      );
      expect(account.requests.length, 1);
    },
  );
  test(
    'versioned catalog rejects unknown offers and mixed legacy introductions',
    () {
      expect(
        StripeBillingCatalog.fromJson(catalog('trial')).subscriptionOffer,
        'trial',
      );
      expect(
        () => StripeBillingCatalog.fromJson(catalog('unknown')),
        throwsFormatException,
      );
      expect(
        () => StripeBillingCatalog.fromJson({
          ...catalog('return'),
          'introEligible': true,
        }),
        throwsFormatException,
      );
      expect(
        () => StripeBillingCatalog.fromJson({
          ...catalog('return'),
          'offersEnabled': false,
        }),
        throwsFormatException,
      );
    },
  );
  test(
    'same localized presentation models express Stripe trial and return terms',
    () {
      for (final id in [pomodoistMonthlyProductId, pomodoistAnnualProductId]) {
        final trial = stripeSubscriptionOffer('trial', id)!;
        expect(trial.price, 0);
        expect(trial.periodValue, 7);
        expect(trial.periodUnit, BillingOfferPeriodUnit.day);
        expect(trial.paymentMode, BillingOfferPaymentMode.freeTrial);
        expect(stripeSubscriptionOffer('standard', id), isNull);
        expect(stripeSubscriptionOffer('blocked', id), isNull);
      }
      final monthly = stripeSubscriptionOffer(
        'return',
        pomodoistMonthlyProductId,
      )!;
      final annual = stripeSubscriptionOffer(
        'return',
        pomodoistAnnualProductId,
      )!;
      expect(monthly.price, 1.99);
      expect(monthly.periodCount, 3);
      expect(annual.price, 14.99);
      expect(annual.periodCount, 1);
      expect(annual.periodUnit, BillingOfferPeriodUnit.year);
      expect(
        stripeSubscriptionOffer('trial', pomodoistLifetimeProductId),
        isNull,
      );
    },
  );
}

class _TransportAccount extends Fake implements AccountClient {
  _TransportAccount(this.actual);
  final AccountClient actual;
  String userId = 'account';
  @override
  String get currentUserId => userId;
  @override
  Future<AccountFunctionResponse> invokeFunction(
    String functionName, {
    Map<String, String>? headers,
    Object? body,
    Map<String, dynamic>? queryParameters,
    String? region,
  }) => actual.invokeFunction(
    functionName,
    headers: headers,
    body: body,
    queryParameters: queryParameters,
    region: region,
  );
}

class _BillingAccount extends Fake implements AccountClient {
  String userId = 'account';
  final requests = <Map<String, Object?>>[];
  AccountFunctionResponse response = const AccountFunctionResponse(status: 500);
  @override
  String? get currentUserId => userId;
  @override
  Future<AccountFunctionResponse> invokeFunction(
    String functionName, {
    Map<String, String>? headers,
    Object? body,
    Map<String, dynamic>? queryParameters,
    String? region,
  }) async {
    expect(functionName, 'pomodoist-stripe-billing');
    requests.add(Map<String, Object?>.from(body! as Map));
    return response;
  }
}
