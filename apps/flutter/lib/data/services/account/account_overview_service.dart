import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:app_account/app_account.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show SupabaseClient;
import 'package:pomodoist/data/services/auth/account_request.dart';

import 'package:pomodoist/domain/models/account/account_overview.dart';
import 'package:pomodoist/domain/models/account/avatar_emoji.dart';

final class AccountOverviewService {
  const AccountOverviewService(this._account, {required SupabaseClient client})
    : _client = client;

  final AccountClient _account;
  final SupabaseClient _client;

  Future<PomodoistAccountOverview> load({
    Future<String> Function()? deviceId,
    Duration timeout = const Duration(seconds: 30),
  }) async {
    if (deviceId != null) unawaited(_registerInstall(deviceId, timeout));
    return accountRequest(_account, () async {
      final userId = _account.currentUserId;
      if (userId == null || _client.auth.currentUser?.id != userId) {
        throw StateError('The account session has changed.');
      }
      final data = await _client
          .rpc<Object?>('get_account_overview')
          .timeout(timeout);
      if (_account.currentUserId != userId) {
        throw StateError('The account session has changed.');
      }
      final json = Map<String, Object?>.from(data as Map);
      final profile = json['profile'];
      return map(
        AccountOverview.fromJson(json),
        avatarEmoji: profile is Map
            ? readAvatarEmoji(profile['avatarEmoji'])
            : null,
      );
    });
  }

  Future<void> _registerInstall(
    Future<String> Function() deviceId,
    Duration timeout,
  ) async {
    final userId = _account.currentUserId;
    try {
      final info = await PackageInfo.fromPlatform().timeout(timeout);
      final id = await deviceId().timeout(timeout);
      if (userId == null || _account.currentUserId != userId) return;
      await _account
          .registerInstall(
            appId: AccountAppId.pomodoist,
            deviceId: id,
            platform: kIsWeb ? 'web' : defaultTargetPlatform.name.toLowerCase(),
            appVersion: info.buildNumber.isEmpty
                ? info.version
                : '${info.version}+${info.buildNumber}',
          )
          .timeout(timeout);
    } on Object {
      // Install registration is advisory and must never block the profile.
    }
  }

  static PomodoistAccountOverview map(
    AccountOverview overview, {
    String? avatarEmoji,
  }) => PomodoistAccountOverview(
    profile: PomodoistAccountProfile(
      id: overview.profile.id,
      email: overview.profile.email,
      displayName: overview.profile.displayName,
      avatarEmoji: avatarEmoji,
      isPro: overview.profile.pomodoistIsPro,
    ),
    apps: [
      for (final app in overview.apps)
        PomodoistAccountAppSummary(
          id: app.id,
          displayName: app.displayName,
          entitlements: [
            for (final entitlement in app.entitlements)
              PomodoistAccountEntitlement(
                appId: entitlement.appId,
                entitlementId: entitlement.entitlementId,
                status: entitlement.status,
                purchaseType: entitlement.purchaseType,
                source: entitlement.source,
                productId: entitlement.productId,
                store: entitlement.store,
                validUntil: entitlement.validUntil,
                renewsAt: entitlement.renewsAt,
              ),
          ],
        ),
    ],
    generatedAt: overview.generatedAt,
  );
}
