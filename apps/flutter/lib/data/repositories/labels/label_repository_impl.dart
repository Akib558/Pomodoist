import 'package:pomodoist/utils/result.dart';
import 'package:pomodoist/data/repositories/labels/label_repository.dart';
import 'package:collection/collection.dart';
import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import 'package:pomodoist/data/services/local/database/app_database.dart';
import 'package:pomodoist/data/services/local/label_local_service.dart';
import 'package:pomodoist/data/services/local/outbox_service.dart';
import 'package:pomodoist/domain/models/tasks/task_models.dart';
import 'package:pomodoist/domain/models/tasks/project_colors.dart';

class DriftLabelRepository implements LabelRepository {
  DriftLabelRepository(AppDatabase db, this._syncQueue, {Uuid? uuid})
    : _db = db,
      _uuid = uuid ?? const Uuid(),
      _labels = LabelLocalService(db);

  final AppDatabase _db;
  final OutboxService _syncQueue;
  final Uuid _uuid;
  final LabelLocalService _labels;

  @override
  Stream<List<LabelItem>> watchLabels() {
    return _labels.watchActiveUserLabels().map(
      (rows) => rows.map(_mapLabel).toList(),
    );
  }

  @override
  Stream<Map<String, int>> watchOpenTaskCounts() =>
      _labels.watchOpenTaskCounts();

  @override
  Future<Result<LabelItem?>> findByName(String name) =>
      Result.capture<LabelItem?>(() async {
        final normalizedName = name.trim().toLowerCase();
        final row = (await _labels.activeUserLabels()).firstWhereOrNull(
          (label) => label.name.trim().toLowerCase() == normalizedName,
        );
        return row == null ? null : _mapLabel(row);
      });

  @override
  Future<Result<String>> createLabel(
    String name, {
    String? icon,
    String? color,
  }) => Result.capture<String>(() async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) throw ArgumentError.value(name, 'name');
    if (icon != null) _validateIcon(icon);
    if (color != null) _validateColor(color);
    final existing = await findByName(
      trimmed,
    ).then((result) => result.getOrThrow());
    if (existing != null) {
      return existing.id;
    }
    final now = DateTime.now().toUtc();
    final id = _uuid.v4();
    await _db.transaction(() async {
      await _labels.insertLabel(
        LabelsCompanion.insert(
          id: id,
          userId: localUserId,
          name: trimmed,
          color: Value(color),
          icon: Value(icon),
          kind: const Value(labelKindUser),
          orderKey: now.microsecondsSinceEpoch.toString().padLeft(20, '0'),
          createdAt: now,
          updatedAt: now,
        ),
      );
      await _syncQueue.enqueue(
        type: 'label.create',
        clientId: id,
        payload: {'id': id, 'name': trimmed, 'icon': ?icon, 'color': ?color},
      );
    });
    return id;
  });

  void _validateIcon(String icon) {
    if (!LabelIcon.values.any((value) => value.name == icon)) {
      throw ArgumentError.value(icon, 'icon', 'Unknown label icon');
    }
  }

  void _validateColor(String color) {
    if (!isPaletteProjectColor(color)) {
      throw ArgumentError.value(color, 'color', 'Unknown label color');
    }
  }

  @override
  Future<Result<void>> updateLabel(
    String id, {
    required String name,
    required String color,
    required String icon,
  }) => Result.capture<void>(() async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) throw ArgumentError.value(name, 'name');
    _validateColor(color);
    _validateIcon(icon);
    await _db.transaction(() async {
      final current = await _labels.findActiveUserLabel(id);
      if (current == null) throw StateError('Label no longer exists');
      final duplicate = (await _labels.activeUserLabels()).any(
        (label) =>
            label.id != id &&
            label.name.trim().toLowerCase() == trimmed.toLowerCase(),
      );
      if (duplicate) throw LabelNameTakenException();
      if (current.name == trimmed &&
          current.color == color &&
          current.icon == icon) {
        return;
      }
      await _labels.updateLabel(
        id,
        LabelsCompanion(
          name: Value(trimmed),
          color: Value(color),
          icon: Value(icon),
          updatedAt: Value(DateTime.now().toUtc()),
        ),
      );
      await _syncQueue.enqueue(
        type: 'label.update',
        clientId: id,
        payload: {'id': id, 'name': trimmed, 'color': color, 'icon': icon},
      );
    });
  });

  @override
  Future<Result<void>> updateLabelIcon(String id, String icon) =>
      Result.capture<void>(() async {
        _validateIcon(icon);
        await _db.transaction(() async {
          final changed = await _labels.updateLabel(
            id,
            LabelsCompanion(
              icon: Value(icon),
              updatedAt: Value(DateTime.now().toUtc()),
            ),
          );
          if (changed == 0) throw StateError('Label no longer exists');
          await _syncQueue.enqueue(
            type: 'label.update',
            clientId: id,
            payload: {'id': id, 'icon': icon},
          );
        });
      });

  @override
  Future<Result<void>> deleteLabel(String id) => Result.capture<void>(() async {
    final now = DateTime.now().toUtc();
    await _db.transaction(() async {
      final label = await _labels.findActiveUserLabel(id);
      if (label == null) {
        return;
      }
      await _labels.markDeleted(id, now);
      await _syncQueue.enqueue(
        type: 'label.delete',
        clientId: id,
        payload: {'id': id},
      );
    });
  });

  LabelItem _mapLabel(LabelRow row) => LabelItem(
    id: row.id,
    userId: row.userId,
    name: row.name,
    color: row.color,
    icon: row.icon,
    orderKey: row.orderKey,
    isFavorite: row.isFavorite,
    isDeleted: row.isDeleted,
    createdAt: row.createdAt,
    updatedAt: row.updatedAt,
  );
}
