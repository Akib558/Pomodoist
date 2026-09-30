import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pomodoist/config/providers.dart';
import 'package:pomodoist/data/repositories/habits/habit_repository.dart';
import 'package:pomodoist/data/repositories/habits/habit_repository_impl.dart';
import 'package:pomodoist/domain/models/habits/habit_models.dart';

final habitRepositoryProvider = Provider<HabitRepository>(
  (ref) => DriftHabitRepository(
    ref.watch(appDatabaseProvider),
    ref.watch(syncQueueRepositoryProvider),
  ),
);
final habitsProvider = StreamProvider<List<Habit>>(
  (ref) => ref.watch(habitRepositoryProvider).watchHabits(),
);
final habitCheckInsProvider = StreamProvider<List<HabitCheckIn>>(
  (ref) => ref.watch(habitRepositoryProvider).watchCheckIns(),
);
