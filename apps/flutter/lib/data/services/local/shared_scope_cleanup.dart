import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:pomodoist/data/services/local/database/app_database.dart';

/// Includes leftovers from clients that deleted membership before cached rows.
Future<Set<String>> localSharedScopeIds(AppDatabase db) async {
  final rows = await db.customSelect('''
    SELECT id AS scope_id FROM shared_scopes
    UNION SELECT scope_id FROM projects WHERE scope_id IS NOT NULL
    UNION SELECT scope_id FROM tasks WHERE scope_id IS NOT NULL
    UNION SELECT scope_id FROM labels WHERE scope_id IS NOT NULL
    UNION SELECT scope_id FROM shared_entities WHERE scope_id <> '_account'
    UNION SELECT scope_id FROM sync_commands
      WHERE scope_id IS NOT NULL AND status <> 'revoked'
  ''').get();
  return rows.map((row) => row.read<String>('scope_id')).toSet();
}

/// Removes only this scope's local copies, never issuing server mutations.
Future<void> removeSharedScope(AppDatabase db, String scopeId) async {
  await db.transaction(() async {
    final projects = await (db.select(
      db.projects,
    )..where((row) => row.scopeId.equals(scopeId))).get();
    final projectIds = projects.map((row) => row.id).toList();
    final tasks =
        await (db.select(db.tasks)..where(
              (row) =>
                  row.scopeId.equals(scopeId) | row.projectId.isIn(projectIds),
            ))
            .get();
    final ids = tasks.map((row) => row.id).toList();
    await (db.delete(db.taskLabels)..where((row) => row.taskId.isIn(ids))).go();
    await (db.delete(
      db.taskCompletions,
    )..where((row) => row.taskId.isIn(ids))).go();
    await (db.delete(db.reminders)..where((row) => row.taskId.isIn(ids))).go();
    await (db.delete(
      db.sections,
    )..where((row) => row.projectId.isIn(projectIds))).go();
    await (db.delete(db.tasks)..where((row) => row.id.isIn(ids))).go();
    await (db.delete(db.projects)..where(
          (row) => row.scopeId.equals(scopeId) & row.id.isIn(projectIds),
        ))
        .go();
    // Keep only the user's unsent text; do not retain cached shared snapshots.
    final pending = await (db.select(
      db.syncCommands,
    )..where((row) => row.scopeId.equals(scopeId))).get();
    for (final command in pending) {
      final payload = jsonDecode(command.payloadJson) as Map<String, dynamic>;
      final ownText = <String, dynamic>{
        for (final key in ['content', 'description', 'body'])
          if (payload[key] is String) key: payload[key],
      };
      if (ownText.isEmpty) {
        await (db.delete(
          db.syncCommands,
        )..where((row) => row.id.equals(command.id))).go();
      } else {
        await (db.update(
          db.syncCommands,
        )..where((row) => row.id.equals(command.id))).write(
          SyncCommandsCompanion(
            status: const Value('revoked'),
            payloadJson: Value(jsonEncode(ownText)),
            lastError: const Value('access_revoked'),
          ),
        );
      }
    }
    await (db.delete(
      db.labels,
    )..where((row) => row.scopeId.equals(scopeId))).go();
    await (db.delete(
      db.sharedEntities,
    )..where((row) => row.scopeId.equals(scopeId))).go();
    await (db.delete(
      db.sharedScopes,
    )..where((row) => row.id.equals(scopeId))).go();
  });
}
