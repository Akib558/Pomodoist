import 'support/test_app.dart';
import 'dart:async';
import 'dart:convert';

import 'package:app_account/app_account.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show defaultTargetPlatform;
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart'
    show SupabaseClient, AuthClientOptions;
import 'package:pomodoist/config/account_providers.dart';
import 'package:pomodoist/config/billing_store_dependencies.dart';
import 'package:pomodoist/ui/settings/widgets/settings_screen.dart';
import 'package:pomodoist/ui/settings/widgets/settings_navigation.dart';
import 'package:pomodoist/ui/core/localization/app_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUpAll(loadTestAppResources);
  test('late account bootstrap success replaces timeout error', () async {
    final completer = Completer<AccountClient?>();
    final account = _FakeAccountClient();
    var attempts = 0;
    final container = ProviderContainer(
      overrides: [
        accountBootstrapInitializerProvider.overrideWithValue(() {
          attempts += 1;
          return completer.future;
        }),
        accountBootstrapTimeoutProvider.overrideWithValue(
          const Duration(milliseconds: 10),
        ),
      ],
    );
    addTearDown(container.dispose);
    final subscription = container.listen(
      accountBootstrapProvider,
      (_, _) {},
      fireImmediately: true,
    );
    addTearDown(subscription.close);

    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(container.read(accountBootstrapProvider).hasError, isTrue);
    expect(container.read(accountClientProvider), isNull);

    completer.complete(account);
    await Future<void>.delayed(Duration.zero);

    expect(container.read(accountBootstrapProvider).value, same(account));
    expect(container.read(accountClientProvider), same(account));
    expect(attempts, 1);
  });

  test('account bootstrap retry reuses an unfinished initialization', () async {
    final completer = Completer<AccountClient?>();
    final account = _FakeAccountClient();
    var attempts = 0;
    final container = ProviderContainer(
      overrides: [
        accountBootstrapInitializerProvider.overrideWithValue(() {
          attempts += 1;
          return completer.future;
        }),
        accountBootstrapTimeoutProvider.overrideWithValue(
          const Duration(milliseconds: 10),
        ),
      ],
    );
    addTearDown(container.dispose);
    container.listen(
      accountBootstrapProvider,
      (_, _) {},
      fireImmediately: true,
    );
    await Future<void>.delayed(const Duration(milliseconds: 20));

    final retry = container.read(accountBootstrapProvider.notifier).retry();
    await Future<void>.delayed(Duration.zero);
    expect(attempts, 1);

    completer.complete(account);
    await retry;

    expect(container.read(accountBootstrapProvider).value, same(account));
  });

  test('account bootstrap retry starts over after a real failure', () async {
    final account = _FakeAccountClient();
    var attempts = 0;
    final container = ProviderContainer(
      overrides: [
        accountBootstrapInitializerProvider.overrideWithValue(() {
          attempts += 1;
          return attempts == 1
              ? Future<AccountClient?>.error(StateError('failed'))
              : Future<AccountClient?>.value(account);
        }),
      ],
    );
    addTearDown(container.dispose);
    container.listen(
      accountBootstrapProvider,
      (_, _) {},
      fireImmediately: true,
    );
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);
    expect(container.read(accountBootstrapProvider).hasError, isTrue);

    await container.read(accountBootstrapProvider.notifier).retry();

    expect(attempts, 2);
    expect(container.read(accountClientProvider), same(account));
  });

  testWidgets('settings contains account bootstrap timeout and retry', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues(const {});
    final pending = Completer<AccountClient?>();
    var attempts = 0;

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          accountBootstrapInitializerProvider.overrideWithValue(() {
            attempts += 1;
            return pending.future;
          }),
          accountBootstrapTimeoutProvider.overrideWithValue(
            const Duration(milliseconds: 10),
          ),
          accountOverviewProvider.overrideWith((ref) async => null),
          applePurchasesSupportedProvider.overrideWithValue(false),
        ],
        child: MaterialApp(
          builder: testAppBuilder,
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
          ],
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: SettingsScreen(
              location: settingsLocation(SettingsSection.account),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 20));

    expect(find.byKey(const Key('account-bootstrap-error')), findsOneWidget);
    expect(find.byKey(const Key('account-bootstrap-retry')), findsOneWidget);
    expect(find.text('Subscription options'), findsOneWidget);

    await tester.tap(find.byKey(const Key('account-bootstrap-retry')));
    await tester.pump(const Duration(milliseconds: 20));
    expect(attempts, 1);
  });

  test('registerInstall failure does not block account overview', () async {
    PackageInfo.setMockInitialValues(
      appName: 'Pomodoist',
      packageName: 'test',
      version: '2.4.1',
      buildNumber: '37',
      buildSignature: '',
    );
    final overview = AccountOverview(
      profile: const AccountProfile(id: 'user'),
      apps: const [],
      generatedAt: DateTime.utc(2026, 7, 11),
    );
    final account = _OverviewAccountClient(
      overview: () async => overview,
      registerInstallCallback: () async => throw StateError('offline'),
    );
    final client = await _overviewClient(account);
    addTearDown(client.dispose);
    final container = ProviderContainer(
      overrides: [
        accountClientProvider.overrideWithValue(account),
        accountOverviewSupabaseClientProvider.overrideWithValue(client),
        accountAuthStateProvider.overrideWithValue(
          const AsyncData(AccountAuthState(signedIn: true)),
        ),
        pomodoistDeviceIdProvider.overrideWith((ref) async => 'device'),
        accountRequestTimeoutProvider.overrideWithValue(
          const Duration(milliseconds: 10),
        ),
      ],
    );
    addTearDown(container.dispose);

    final loaded = await container.read(accountOverviewProvider.future);
    expect(loaded?.profile.id, overview.profile.id);
    expect(loaded?.generatedAt, overview.generatedAt);
    await Future<void>.delayed(Duration.zero);
    expect(account.recordedVersion, '2.4.1+37');
    expect(account.recordedPlatform, defaultTargetPlatform.name.toLowerCase());
    expect(account.recordedDeviceId, 'device');
  });

  test(
    'account overview loads through a stale signed-out auth state',
    () async {
      final overview = AccountOverview(
        profile: const AccountProfile(id: 'user'),
        apps: const [],
        generatedAt: DateTime.utc(2026, 7, 11),
      );
      final account = _OverviewAccountClient(
        overview: () async => overview,
        registerInstallCallback: () async {},
      );
      final client = await _overviewClient(account);
      addTearDown(client.dispose);
      final container = ProviderContainer(
        overrides: [
          accountClientProvider.overrideWithValue(account),
          accountOverviewSupabaseClientProvider.overrideWithValue(client),
          // The auth stream can report a stale signed-out snapshot while the
          // live session is intact, so the profile must still load.
          accountAuthStateProvider.overrideWithValue(
            const AsyncData(AccountAuthState(signedIn: false)),
          ),
          pomodoistDeviceIdProvider.overrideWith((ref) async => 'device'),
          accountRequestTimeoutProvider.overrideWithValue(
            const Duration(milliseconds: 10),
          ),
        ],
      );
      addTearDown(container.dispose);

      final loaded = await container.read(accountOverviewProvider.future);
      expect(loaded?.profile.id, overview.profile.id);
      expect(loaded?.generatedAt, overview.generatedAt);
    },
  );

  testWidgets('account overview failure remains until login retry', (
    tester,
  ) async {
    final pending = Completer<AccountOverview>();
    final overview = AccountOverview(
      profile: const AccountProfile(
        id: 'user',
        displayName: 'Test User',
        email: 'user@example.com',
      ),
      apps: const [],
      generatedAt: DateTime.utc(2026, 7, 11),
    );
    var overviewCalls = 0;
    final account = _OverviewAccountClient(
      overview: () {
        overviewCalls += 1;
        return overviewCalls == 1 ? pending.future : Future.value(overview);
      },
      registerInstallCallback: () async {},
    );
    final client = (await tester.runAsync(() => _overviewClient(account)))!;
    addTearDown(client.dispose);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          accountClientProvider.overrideWithValue(account),
          accountOverviewSupabaseClientProvider.overrideWithValue(client),
          accountAuthStateProvider.overrideWithValue(
            const AsyncData(AccountAuthState(signedIn: true)),
          ),
          pomodoistDeviceIdProvider.overrideWith((ref) async => 'device'),
          accountRequestTimeoutProvider.overrideWithValue(
            const Duration(milliseconds: 10),
          ),
        ],
        child: MaterialApp(
          builder: testAppBuilder,
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
          ],
          supportedLocales: AppLocalizations.supportedLocales,
          home: const LoginScreen(),
        ),
      ),
    );
    await tester.pump();
    expect(find.byKey(const Key('login-account-loading')), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 20));
    await tester.pump(const Duration(milliseconds: 250));

    expect(overviewCalls, 1);
    expect(find.byKey(const Key('login-account-loading')), findsNothing);
    expect(find.byKey(const Key('login-account-retry')), findsOneWidget);

    await tester.tap(find.byKey(const Key('login-account-retry')));
    await tester.pumpAndSettle();

    expect(overviewCalls, 2);
    expect(find.text('user@example.com'), findsOneWidget);
  });
}

class _FakeAccountClient implements AccountClient {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _OverviewAccountClient implements AccountClient {
  @override
  AccountSession get currentSession => const AccountSession(userId: 'user');
  _OverviewAccountClient({
    required this.overview,
    required this.registerInstallCallback,
  });

  final Future<AccountOverview> Function() overview;
  final Future<void> Function() registerInstallCallback;
  String? recordedVersion;
  String? recordedPlatform;
  String? recordedDeviceId;

  @override
  String? get currentUserId => 'user';

  @override
  Future<AccountOverview> getOverview() => overview();

  @override
  Future<void> registerInstall({
    required String appId,
    required String deviceId,
    String? platform,
    String? appVersion,
  }) {
    recordedVersion = appVersion;
    recordedPlatform = platform;
    recordedDeviceId = deviceId;
    return registerInstallCallback();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<SupabaseClient> _overviewClient(_OverviewAccountClient account) async {
  final client = SupabaseClient(
    'https://example.test',
    'test-key',
    authOptions: const AuthClientOptions(autoRefreshToken: false),
    httpClient: MockClient((request) async {
      if (request.url.path.startsWith('/auth/')) {
        return http.Response(
          jsonEncode({
            'access_token': 'bootstrap-test',
            'refresh_token': 'refresh-test',
            'token_type': 'bearer',
            'expires_in': 3600,
            'user': {
              'id': 'user',
              'aud': 'authenticated',
              'created_at': '2026-01-01T00:00:00Z',
            },
          }),
          200,
          headers: {'content-type': 'application/json'},
          request: request,
        );
      }
      expect(request.url.path, '/rest/v1/rpc/get_account_overview');
      final overview = await account.overview();
      return http.Response(
        jsonEncode({
          'profile': {
            'id': overview.profile.id,
            'displayName': overview.profile.displayName,
            'email': overview.profile.email,
            'pomodoistIsPro': overview.profile.pomodoistIsPro,
          },
          'apps': [],
          'generatedAt': overview.generatedAt.toIso8601String(),
        }),
        200,
        headers: {'content-type': 'application/json'},
        request: request,
      );
    }),
  );
  await client.auth.signInWithPassword(
    email: 'user@example.test',
    password: 'test',
  );
  return client;
}
