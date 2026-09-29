import 'dart:convert';
import 'package:app_account/app_account.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uuid/uuid.dart';
import 'package:pomodoist/data/services/local/database/app_database.dart';
import 'package:pomodoist/data/services/local/shared_scope_cleanup.dart';
import 'package:pomodoist/data/services/collaboration/collaboration_api.dart';
import 'support/account_sync_engine.dart';

class _Account implements AccountClient {
  List<AccountSyncEntity> changes = [];
  @override
  String? get currentUserId => 'me';
  @override
  Future<AccountSyncPullResult> pullChanges({
    required String appId,
    required String deviceId,
    required int sinceRevision,
    int limit = 500,
  }) async => AccountSyncPullResult(
    nextCursor: changes.isEmpty ? sinceRevision : changes.last.serverRevision,
    hasMore: false,
    changes: changes
        .where((change) => change.serverRevision > sinceRevision)
        .toList(),
  );
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  late AppDatabase db;
  late _Account account;
  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    await db.ensureSeedData();
    account = _Account();
  });
  tearDown(() async => db.close());
  AccountSyncEntity entity(int revision, {bool deleted = false}) =>
      AccountSyncEntity(
        entityType: 'attachment',
        entityId: 'file',
        serverRevision: revision,
        updatedAt: DateTime.utc(2026, 9, 29),
        deletedAt: deleted ? DateTime.utc(2026, 9, 29) : null,
        data: {
          'id': 'file',
          'name': 'a.pdf',
          'scopeId': null,
          'projectId': 'p',
          'taskId': null,
          'bytes': 3,
          'contentType': 'application/pdf',
          'createdAt': '2026-09-29T00:00:00Z',
        },
      );
  test(
    'personal attachment replaces stale shared cache and later deletion retains revision tombstone',
    () async {
      await db
          .into(db.sharedEntities)
          .insert(
            SharedEntitiesCompanion.insert(
              scopeId: 'old-scope',
              entityType: 'attachment',
              entityId: 'file',
              dataJson: '{}',
            ),
          );
      account.changes = [entity(1)];
      final engine = testSyncEngine(
        db: db,
        account: account,
        uuid: const Uuid(),
      );
      await engine.pullLatest();
      var row = await db.select(db.sharedEntities).getSingle();
      expect(row.scopeId, '_account');
      expect(row.serverRevision, 1);
      expect(jsonDecode(row.dataJson)['name'], 'a.pdf');
      account.changes = [entity(2, deleted: true)];
      await engine.pullLatest();
      row = await db.select(db.sharedEntities).getSingle();
      expect(row.isDeleted, true);
      expect(row.serverRevision, 2);
    },
  );
  test(
    'shared sync transfers cached attachment and revocation clears it',
    () async {
      await db
          .into(db.sharedEntities)
          .insert(
            SharedEntitiesCompanion.insert(
              scopeId: '_account',
              entityType: 'attachment',
              entityId: 'file',
              dataJson: '{}',
            ),
          );
      final engine = testSyncEngine(
        db: db,
        account: account,
        uuid: const Uuid(),
        collaboration: CollaborationApi(
          (body) async => switch (body['action']) {
            'state' => {
              'scopes': [
                {
                  'id': 'scope',
                  'rootProjectId': 'p',
                  'ownerId': 'other',
                  'role': 'observer',
                },
              ],
            },
            'pull' => {
              'changes': [
                {
                  'entityType': 'attachment',
                  'entityId': 'file',
                  'serverRevision': 2,
                  'updatedAt': '2026-09-29T00:00:00Z',
                  'data': entity(1).data,
                },
              ],
              'nextCursor': 2,
              'hasMore': false,
            },
            _ => throw StateError('unexpected action'),
          },
        ),
      );
      await engine.syncShared();
      final rows = await (db.select(
        db.sharedEntities,
      )..where((r) => r.entityType.equals('attachment'))).get();
      expect(rows.length, 1);
      expect(rows.single.scopeId, 'scope');
      expect(jsonDecode(rows.single.dataJson)['scopeId'], 'scope');
      await removeSharedScope(db, 'scope');
      expect(await db.select(db.sharedEntities).get(), isEmpty);
    },
  );
  test('account reset clears personal and shared file metadata', () async {
    for (final scope in ['_account', 'scope']) {
      await db
          .into(db.sharedEntities)
          .insert(
            SharedEntitiesCompanion.insert(
              scopeId: scope,
              entityType: 'attachment',
              entityId: scope,
              dataJson: '{}',
            ),
          );
    }
    await db.resetAccountData();
    expect(await db.select(db.sharedEntities).get(), isEmpty);
  });
}
