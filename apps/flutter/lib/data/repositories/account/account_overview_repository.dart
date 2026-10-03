import 'package:app_account/app_account.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show SupabaseClient;

import 'package:pomodoist/data/services/account/account_overview_service.dart';
import 'package:pomodoist/domain/models/account/account_overview.dart';

/// Owns account overview loading and the related install registration.
final class AccountOverviewRepository {
  const AccountOverviewRepository(
    this._account, {
    required SupabaseClient client,
  }) : _client = client;

  final AccountClient _account;
  final SupabaseClient _client;

  Future<PomodoistAccountOverview> load({
    Future<String> Function()? deviceId,
    required Duration timeout,
  }) => AccountOverviewService(
    _account,
    client: _client,
  ).load(deviceId: deviceId, timeout: timeout);
}
