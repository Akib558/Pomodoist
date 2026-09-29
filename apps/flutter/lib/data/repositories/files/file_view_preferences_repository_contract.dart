abstract interface class FileViewPreferencesRepositoryContract {
  Future<({bool gallery, bool byTask})> load(String projectId);
  Future<void> save(
    String projectId, {
    required bool gallery,
    required bool byTask,
  });
}
