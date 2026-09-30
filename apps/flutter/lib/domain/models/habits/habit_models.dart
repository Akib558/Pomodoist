/// Habit dates are calendar values, never instants converted through UTC.
DateTime habitDate(DateTime value) =>
    DateTime(value.year, value.month, value.day);
String habitDayKey(DateTime value) =>
    '${value.year.toString().padLeft(4, '0')}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}';
DateTime habitDateFromKey(String value) {
  if (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(value)) {
    throw const FormatException('Invalid habit date');
  }
  final date = DateTime.tryParse(value);
  if (date == null || date.year < 1 || habitDayKey(date) != value) {
    throw const FormatException('Invalid habit date');
  }
  return habitDate(date);
}

DateTime habitEndAfterDays(DateTime start, int days) {
  if (days < 1) throw ArgumentError.value(days);
  return DateTime(start.year, start.month, start.day + days - 1);
}

class HabitSchedule {
  HabitSchedule({
    required DateTime effectiveFrom,
    required DateTime startDate,
    DateTime? endDate,
    required Iterable<int> weekdays,
    required this.targetPerDay,
  }) : effectiveFrom = habitDate(effectiveFrom),
       startDate = habitDate(startDate),
       endDate = endDate == null ? null : habitDate(endDate),
       weekdays = List.unmodifiable(weekdays) {
    if (targetPerDay < 1 ||
        targetPerDay > 99 ||
        this.weekdays.isEmpty ||
        this.weekdays.any((d) => d < 1 || d > 7) ||
        this.weekdays.toSet().length != this.weekdays.length ||
        this.endDate != null && this.endDate!.isBefore(this.startDate)) {
      throw ArgumentError('Invalid habit schedule');
    }
  }
  final DateTime effectiveFrom, startDate;
  final DateTime? endDate;
  final List<int> weekdays;
  final int targetPerDay;
  bool includes(DateTime value) {
    final day = habitDate(value);
    return !day.isBefore(startDate) &&
        (endDate == null || !day.isAfter(endDate!)) &&
        weekdays.contains(day.weekday);
  }

  Map<String, Object?> toJson() => {
    'effectiveFrom': habitDayKey(effectiveFrom),
    'startDate': habitDayKey(startDate),
    'endDate': endDate == null ? null : habitDayKey(endDate!),
    'weekdays': weekdays,
    'targetPerDay': targetPerDay,
  };
  factory HabitSchedule.fromJson(Map<String, dynamic> json) => HabitSchedule(
    effectiveFrom: habitDateFromKey(json['effectiveFrom'] as String),
    startDate: habitDateFromKey(json['startDate'] as String),
    endDate: json['endDate'] == null
        ? null
        : habitDateFromKey(json['endDate'] as String),
    weekdays: (json['weekdays'] as List).cast<int>(),
    targetPerDay: json['targetPerDay'] as int,
  );
}

class Habit {
  Habit({
    required this.id,
    required this.userId,
    required this.title,
    this.projectId,
    this.reminderMinutes,
    required Iterable<HabitSchedule> scheduleHistory,
    required this.createdAt,
    required this.updatedAt,
    this.isDeleted = false,
  }) : scheduleHistory = List.unmodifiable(scheduleHistory) {
    if (id.isEmpty ||
        title.trim().isEmpty ||
        title.length > 200 ||
        this.scheduleHistory.isEmpty ||
        reminderMinutes != null &&
            (reminderMinutes! < 0 || reminderMinutes! > 1439)) {
      throw ArgumentError('Invalid habit');
    }
    for (var i = 1; i < this.scheduleHistory.length; i++) {
      if (!this.scheduleHistory[i].effectiveFrom.isAfter(
        this.scheduleHistory[i - 1].effectiveFrom,
      )) {
        throw ArgumentError('Habit schedule versions must be ordered');
      }
    }
  }
  final String id, userId, title;
  final String? projectId;
  final int? reminderMinutes;
  final List<HabitSchedule> scheduleHistory;
  final DateTime createdAt, updatedAt;
  final bool isDeleted;
  HabitSchedule? scheduleFor(DateTime value) {
    final day = habitDate(value);
    HabitSchedule? result;
    for (final schedule in scheduleHistory) {
      if (!schedule.effectiveFrom.isAfter(day)) result = schedule;
    }
    return result;
  }

  bool isScheduledOn(DateTime day) =>
      !isDeleted && (scheduleFor(day)?.includes(day) ?? false);
  bool isFinishedOn(DateTime value) =>
      !isDeleted &&
      scheduleHistory.last.endDate != null &&
      scheduleHistory.last.endDate!.isBefore(habitDate(value));
  Map<String, Object?> toJson() => {
    'id': id,
    'userId': userId,
    'title': title,
    'projectId': projectId,
    'reminderMinutes': reminderMinutes,
    'scheduleHistory': scheduleHistory.map((s) => s.toJson()).toList(),
    'createdAt': createdAt.toUtc().toIso8601String(),
    'updatedAt': updatedAt.toUtc().toIso8601String(),
    'isDeleted': isDeleted,
  };
  factory Habit.fromJson(Map<String, dynamic> json) => Habit(
    id: json['id'] as String,
    userId: json['userId'] as String,
    title: json['title'] as String,
    projectId: json['projectId'] as String?,
    reminderMinutes: json['reminderMinutes'] as int?,
    scheduleHistory: (json['scheduleHistory'] as List).map(
      (s) => HabitSchedule.fromJson(Map<String, dynamic>.from(s as Map)),
    ),
    createdAt: DateTime.parse(json['createdAt'] as String),
    updatedAt: DateTime.parse(json['updatedAt'] as String),
    isDeleted: json['isDeleted'] as bool? ?? false,
  );
}

class HabitDraft {
  HabitDraft({
    required String title,
    required DateTime startDate,
    DateTime? endDate,
    Iterable<int> weekdays = const [1, 2, 3, 4, 5, 6, 7],
    this.targetPerDay = 1,
    this.projectId,
    this.reminderMinutes,
  }) : title = title.trim(),
       startDate = habitDate(startDate),
       endDate = endDate == null ? null : habitDate(endDate),
       weekdays = List.unmodifiable(weekdays) {
    if (this.title.isEmpty ||
        this.title.length > 200 ||
        reminderMinutes != null &&
            (reminderMinutes! < 0 || reminderMinutes! > 1439)) {
      throw ArgumentError('Invalid habit draft');
    }
    schedule(this.startDate);
  }
  final String title;
  final DateTime startDate;
  final DateTime? endDate;
  final List<int> weekdays;
  final int targetPerDay;
  final String? projectId;
  final int? reminderMinutes;
  HabitSchedule schedule(DateTime effectiveFrom) => HabitSchedule(
    effectiveFrom: effectiveFrom,
    startDate: startDate,
    endDate: endDate,
    weekdays: weekdays,
    targetPerDay: targetPerDay,
  );
}

class HabitCheckIn {
  HabitCheckIn({
    required this.id,
    required this.userId,
    required this.habitId,
    required DateTime day,
    required this.createdAt,
    required this.updatedAt,
    this.isDeleted = false,
  }) : day = habitDate(day) {
    if (id.isEmpty || userId.isEmpty || habitId.isEmpty) {
      throw ArgumentError('Invalid habit check-in');
    }
  }
  final String id, userId, habitId;
  final DateTime day, createdAt, updatedAt;
  final bool isDeleted;
  Map<String, Object?> toJson() => {
    'id': id,
    'userId': userId,
    'habitId': habitId,
    'day': habitDayKey(day),
    'createdAt': createdAt.toUtc().toIso8601String(),
    'updatedAt': updatedAt.toUtc().toIso8601String(),
    'isDeleted': isDeleted,
  };
  factory HabitCheckIn.fromJson(Map<String, dynamic> json) => HabitCheckIn(
    id: json['id'] as String,
    userId: json['userId'] as String,
    habitId: json['habitId'] as String,
    day: habitDateFromKey(json['day'] as String),
    createdAt: DateTime.parse(json['createdAt'] as String),
    updatedAt: DateTime.parse(json['updatedAt'] as String),
    isDeleted: json['isDeleted'] as bool? ?? false,
  );
}

int habitCompletionCount(
  String id,
  DateTime day,
  Iterable<HabitCheckIn> checkIns,
) => checkIns
    .where((c) => c.habitId == id && !c.isDeleted && c.day == habitDate(day))
    .length;
