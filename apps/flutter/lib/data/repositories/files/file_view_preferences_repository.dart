import 'package:pomodoist/data/services/local/preferences_service.dart';
import 'package:pomodoist/data/repositories/files/file_view_preferences_repository_contract.dart';

class FileViewPreferencesRepository
    implements FileViewPreferencesRepositoryContract {
  const FileViewPreferencesRepository(this.preferences);
  final PreferencesService preferences;
  String _key(String projectId) => 'files.view.$projectId';
  @override
  Future<({bool gallery, bool byTask})> load(String projectId) async {
    final value = (await preferences.read([
      _key(projectId),
    ])).getOrThrow()[_key(projectId)];
    return (
      gallery: value is String && value.startsWith('gallery'),
      byTask: value is String && value.endsWith(':tasks'),
    );
  }

  @override
  Future<void> save(
    String projectId, {
    required bool gallery,
    required bool byTask,
  }) async => (await preferences.write({
    _key(projectId):
        '${gallery ? 'gallery' : 'list'}:${byTask ? 'tasks' : 'all'}',
  })).getOrThrow();
}
