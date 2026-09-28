import 'package:pomodoist/utils/result.dart';
import 'package:pomodoist/domain/models/tasks/task_models.dart';

abstract interface class LabelRepository {
  Stream<List<LabelItem>> watchLabels();
  Stream<Map<String, int>> watchOpenTaskCounts();
  Future<Result<LabelItem?>> findByName(String name);
  Future<Result<String>> createLabel(
    String name, {
    String? icon,
    String? color,
  });
  Future<Result<void>> updateLabel(
    String id, {
    required String name,
    required String color,
    required String icon,
  });
  Future<Result<void>> updateLabelIcon(String id, String icon);
  Future<Result<void>> deleteLabel(String id);
}
