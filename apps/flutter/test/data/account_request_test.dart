import 'dart:async';
import 'dart:convert';

import 'package:app_account/app_account.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:drift/native.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import 'package:pomodoist/data/services/account/account_overview_service.dart';
import 'package:pomodoist/data/services/auth/account_request.dart';
import 'package:pomodoist/data/services/local/database/app_database.dart';
import '../support/account_sync_engine.dart';

void main() {
  late SupabaseClient client;
  late AccountClient account;
  var token = 'session-a';

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    token = 'session-a';
    client = SupabaseClient(
      'https://supabase.example.test',
      'anon-key',
      authOptions: const AuthClientOptions(autoRefreshToken: false),
      httpClient: MockClient((request) async {
        if (request.url.path.endsWith('/logout')) {
          return http.Response('', 204);
        }
        if (request.url.path.startsWith('/rest/v1/')) {
          return http.Response(
            '{"code":"PT401","message":"Session is no longer active"}',
            401,
            headers: {'content-type': 'application/json'},
            request: request,
          );
        }
        return http.Response(
          jsonEncode({
            'access_token': token,
            'refresh_token': 'refresh-$token',
            'expires_in': 3600,
            'token_type': 'bearer',
            'user': {
              'id': 'user',
              'aud': 'authenticated',
              'created_at': '2026-10-01T00:00:00Z',
            },
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      }),
    );
    account = AccountClient.fromSupabaseClient(client);
    await client.auth.signInWithPassword(
      email: 'user@example.test',
      password: 'password',
    );
  });
  tearDown(() => client.dispose());

  test('overview rejection signs out the revoked account', () async {
    await expectLater(
      AccountOverviewService(account).load(),
      throwsA(isA<PostgrestException>()),
    );
    expect(client.auth.currentSession, isNull);
  });

  test('sync rejection signs out the revoked account', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    await db.ensureSeedData();
    final engine = testSyncEngine(db: db, account: account, uuid: const Uuid());
    await expectLater(engine.syncNow(), throwsA(isA<PostgrestException>()));
    expect(client.auth.currentSession, isNull);
  });

  test(
    'revoked session response clears the session and preserves the error',
    () async {
      const error = PostgrestException(
        message: 'Session is no longer active',
        code: 'PT401',
      );
      await expectLater(
        accountRequest(account, () async => throw error),
        throwsA(same(error)),
      );
      expect(client.auth.currentSession, isNull);
    },
  );

  test(
    'a late revoked response cannot sign out a newer session of the same account',
    () async {
      final pending = Completer<void>();
      final request = accountRequest(account, () => pending.future);
      token = 'session-b';
      await client.auth.signInWithPassword(
        email: 'user@example.test',
        password: 'password',
      );
      final expected = expectLater(request, throwsA(isA<PostgrestException>()));
      pending.completeError(
        const PostgrestException(message: 'Revoked', code: 'PT401'),
      );
      await expected;
      expect(client.auth.currentSession?.accessToken, 'session-b');
    },
  );

  test('authorization and transport failures keep the session', () async {
    for (final error in <Object>[
      const PostgrestException(message: 'Forbidden', code: '42501'),
      const PostgrestException(message: 'Expired JWT', code: 'PGRST301'),
      http.ClientException('Offline'),
    ]) {
      await expectLater(
        accountRequest(account, () async => throw error),
        throwsA(same(error)),
      );
      expect(client.auth.currentSession?.accessToken, 'session-a');
    }
    expect(await accountRequest(account, () async => 42), 42);
  });
}
