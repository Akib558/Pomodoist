part of 'account_sync_engine.dart';

extension HabitAccountSync on AccountSyncEngine {
  Future<SharedEntityRow?> _habitSyncMarker(String type, String id) =>
      (_db.select(_db.sharedEntities)..where(
            (r) =>
                r.scopeId.equals('_account') &
                r.entityType.equals(type) &
                r.entityId.equals(id),
          ))
          .getSingleOrNull();
  Future<void> _applyHabitEntity(AccountSyncEntity entity) async {
    final marker = await _habitSyncMarker(entity.entityType, entity.entityId);
    if (marker != null &&
        (marker.serverRevision > entity.serverRevision ||
            marker.isDeleted && !entity.deleted)) {
      return;
    }
    final data = syncDataWithoutSyncMetadata(entity.data)
      ..['id'] = entity.entityId;
    if (entity.deleted) {
      if (entity.entityType == 'habit') {
        await (_db.update(
          _db.habits,
        )..where((h) => h.id.equals(entity.entityId))).write(
          HabitsCompanion(
            isDeleted: const Value(true),
            updatedAt: Value(entity.deletedAt ?? DateTime.now().toUtc()),
          ),
        );
      } else {
        await (_db.update(
          _db.habitCheckIns,
        )..where((c) => c.id.equals(entity.entityId))).write(
          HabitCheckInsCompanion(
            isDeleted: const Value(true),
            updatedAt: Value(entity.deletedAt ?? DateTime.now().toUtc()),
          ),
        );
      }
    } else if (entity.entityType == 'habit') {
      final existing = await (_db.select(
        _db.habits,
      )..where((h) => h.id.equals(entity.entityId))).getSingleOrNull();
      if (existing?.isDeleted ?? false) return;
      final habit = Habit.fromJson({
        ...?existing == null ? null : habitFromRow(existing).toJson(),
        ...data,
      });
      final pending =
          await (_db.select(_db.syncCommands)..where(
                (c) =>
                    c.clientId.equals(entity.entityId) &
                    c.type.equals('habit.update') &
                    c.status.equals('pending'),
              ))
              .get();
      if (pending.isNotEmpty &&
          existing != null &&
          existing.updatedAt.isAfter(habit.updatedAt)) {
        return;
      }
      await _db.into(_db.habits).insertOnConflictUpdate(habitToRow(habit));
    } else {
      final existing = await (_db.select(
        _db.habitCheckIns,
      )..where((c) => c.id.equals(entity.entityId))).getSingleOrNull();
      if (existing?.isDeleted ?? false) return;
      final checkIn = HabitCheckIn.fromJson({
        ...?existing == null ? null : habitCheckInFromRow(existing).toJson(),
        ...data,
      });
      final parent = await (_db.select(
        _db.habits,
      )..where((h) => h.id.equals(checkIn.habitId))).getSingleOrNull();
      if ((parent?.isDeleted ?? false) ||
          (await _habitSyncMarker('habit', checkIn.habitId))?.isDeleted ==
              true) {
        return;
      }
      await _db
          .into(_db.habitCheckIns)
          .insertOnConflictUpdate(habitCheckInToRow(checkIn));
    }
    await _db
        .into(_db.sharedEntities)
        .insertOnConflictUpdate(
          SharedEntitiesCompanion.insert(
            scopeId: '_account',
            entityType: entity.entityType,
            entityId: entity.entityId,
            dataJson: '{}',
            serverRevision: Value(entity.serverRevision),
            isDeleted: Value(entity.deleted),
          ),
        );
  }
}
