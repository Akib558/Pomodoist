import 'package:pomodoist/utils/result.dart';

const appZoomPreferenceKey = 'app.zoomPercent';
const appZoomMinimum = 50;
const appZoomMaximum = 200;

/// Persisted interface zoom shared by every native window.
abstract interface class AppZoomRepository {
  Future<Result<int?>> read();
  Future<Result<void>> write(int percent);
}
