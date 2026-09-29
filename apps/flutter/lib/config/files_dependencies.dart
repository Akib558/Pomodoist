import 'package:pomodoist/config/focus_dependencies.dart';
import 'package:pomodoist/data/services/local/preferences_service.dart';
import 'package:pomodoist/data/repositories/files/file_view_preferences_repository.dart';
import 'package:pomodoist/data/repositories/files/file_view_preferences_repository_contract.dart';
import 'package:pomodoist/data/repositories/files/files_repository_contract.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pomodoist/config/account_providers.dart';
import 'package:pomodoist/config/providers.dart';
import 'package:pomodoist/data/repositories/files/files_repository.dart';
import 'package:pomodoist/data/services/files/files_service.dart';

final filesRepositoryProvider = Provider<FilesRepositoryContract?>((ref) {
  ref.watch(accountSessionProvider);
  final account = ref.watch(accountClientProvider);
  final sessions = ref.watch(accountSessionRepositoryProvider);
  final session = sessions.currentSession;
  final actor = session.userId;
  if (account == null || actor == null) return null;
  final repository = FilesRepository(
    db: ref.watch(appDatabaseProvider),
    service: FilesService.account(account),
    isSessionCurrent: () =>
        account.currentUserId == actor && sessions.currentSession == session,
  );
  ref.onDispose(repository.dispose);
  return repository;
});
final fileViewPreferencesRepositoryProvider =
    Provider<FileViewPreferencesRepositoryContract>(
      (ref) => FileViewPreferencesRepository(
        PreferencesService(() => ref.read(sharedPreferencesProvider.future)),
      ),
    );
