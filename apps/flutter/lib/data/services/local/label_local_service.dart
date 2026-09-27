import 'package:drift/drift.dart';

import 'package:pomodoist/data/services/local/database/app_database.dart';

class LabelLocalService {
  LabelLocalService(this._db);

  final AppDatabase _db;

  Stream<List<LabelRow>> watchActiveUserLabels() {
    final statement = _db.select(_db.labels)
      ..where(
        (label) =>
            label.scopeId.isNull() &
            label.kind.equals(labelKindUser) &
            label.isDeleted.equals(false),
      )
      ..orderBy([(label) => OrderingTerm.asc(label.orderKey)]);
    return statement.watch();
  }

  Future<List<LabelRow>> activeUserLabels() {
    return (_db.select(_db.labels)..where(
          (label) =>
              label.scopeId.isNull() &
              label.kind.equals(labelKindUser) &
              label.isDeleted.equals(false),
        ))
        .get();
  }

  Stream<Map<String, int>> watchOpenTaskCounts() => _db
      .customSelect(
        "SELECT tl.label_id, COUNT(*) AS task_count "
        "FROM task_labels tl JOIN tasks t ON t.id = tl.task_id "
        "JOIN labels l ON l.id = tl.label_id "
        "WHERE tl.kind = 'user' AND l.kind = 'user' "
        "AND l.scope_id IS NULL AND l.is_deleted = 0 "
        "AND t.is_deleted = 0 AND t.status != 'completed' "
        "GROUP BY tl.label_id",
        readsFrom: {_db.taskLabels, _db.tasks, _db.labels},
      )
      .watch()
      .map(
        (rows) => {
          for (final row in rows)
            row.read<String>('label_id'): row.read<int>('task_count'),
        },
      );

  Future<void> insertLabel(LabelsCompanion label) {
    return _db.into(_db.labels).insert(label);
  }

  Future<int> updateLabel(String id, LabelsCompanion patch) {
    return (_db.update(_db.labels)..where(
          (row) =>
              row.id.equals(id) &
              row.scopeId.isNull() &
              row.kind.equals(labelKindUser) &
              row.isDeleted.equals(false),
        ))
        .write(patch);
  }

  Future<LabelRow?> findActiveUserLabel(String id) {
    return (_db.select(_db.labels)
          ..where(
            (label) =>
                label.id.equals(id) &
                label.scopeId.isNull() &
                label.kind.equals(labelKindUser) &
                label.isDeleted.equals(false),
          )
          ..limit(1))
        .getSingleOrNull();
  }

  Future<void> markDeleted(String id, DateTime updatedAt) {
    return (_db.update(
      _db.labels,
    )..where((label) => label.id.equals(id))).write(
      LabelsCompanion(
        isDeleted: const Value(true),
        updatedAt: Value(updatedAt),
      ),
    );
  }
}
