import 'package:pomodoist/domain/models/tasks/task_time.dart';

const learningTourInvitationPendingPreferenceKey =
    'learningTour.invitationPending.v1';

const reengagementNotificationsEnabledPreferenceKey =
    'notifications.reengagement.enabled';
const quickAddDefaultTimedBlockMinutesPreferenceKey =
    'quickAdd.defaultTimedBlockMinutes';
const taskTimeDisplayModePreferenceKey = 'tasks.timeDisplayMode';
const projectViewModePreferenceKey = 'projects.viewMode';
const projectCatalogViewModePreferenceKey = 'projects.catalogViewMode';
const taskListStylePreferenceKey = 'tasks.listStyle';
const taskBranchStylePreferenceKey = 'tasks.branchStyle';
const taskRowSpacingPreferenceKey = 'tasks.rowSpacing';
const taskBranchExpansionPreferenceKey = 'tasks.branchExpansion.v1';
const timelineVisibleStartMinutesPreferenceKey = 'timeline.visibleStartMinutes';
const timelineVisibleEndMinutesPreferenceKey = 'timeline.visibleEndMinutes';
const timelineHourWidthPreferenceKey = 'timeline.hourWidth';
const timelineCollapsedProjectIdsPreferenceKey = 'timeline.collapsedProjectIds';
const defaultQuickAddTimedBlockMinutes = 30;
const minQuickAddTimedBlockMinutes = 1;
const maxQuickAddTimedBlockMinutes = 480;
const timelineSnapMinutes = 15;
const defaultTimelineVisibleStartMinutes = 0;
const defaultTimelineVisibleEndMinutes = 24 * 60;
const defaultTimelineHourWidth = 192;
const timelineHourWidthLevels = <int>[96, 144, 192, 288, 384];

enum ProjectViewMode { list, map }

enum TaskListStyle { modern, classic }

enum TaskBranchStyle { connected, grouped }

enum TaskRowSpacing { compact, comfortable, spacious }

class TimelineVisibleHours {
  const TimelineVisibleHours({
    required this.startMinutes,
    required this.endMinutes,
  });

  final int startMinutes;
  final int endMinutes;

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is TimelineVisibleHours &&
            other.startMinutes == startMinutes &&
            other.endMinutes == endMinutes;
  }

  @override
  int get hashCode => Object.hash(startMinutes, endMinutes);
}

class TaskPreferences {
  TaskPreferences({
    this.reengagementEnabled = true,
    this.quickAddMinutes = defaultQuickAddTimedBlockMinutes,
    this.timeDisplayMode = TaskTimeDisplayMode.smart,
    this.listStyle = TaskListStyle.modern,
    this.projectViewMode = ProjectViewMode.list,
    this.projectCatalogViewMode = ProjectViewMode.list,
    this.branchStyle = TaskBranchStyle.connected,
    this.rowSpacing = TaskRowSpacing.comfortable,
    this.visibleHours = const TimelineVisibleHours(
      startMinutes: 0,
      endMinutes: 1440,
    ),
    this.hourWidth = defaultTimelineHourWidth,
    Set<String> collapsedProjectIds = const {},
    Map<String, Map<String, bool>> branchExpansion = const {},
  }) : collapsedProjectIds = Set.unmodifiable(collapsedProjectIds),
       branchExpansion = Map.unmodifiable({
         for (final entry in branchExpansion.entries)
           entry.key: Map<String, bool>.unmodifiable(entry.value),
       });
  final bool reengagementEnabled;
  final int quickAddMinutes;
  final TaskTimeDisplayMode timeDisplayMode;
  final TaskListStyle listStyle;
  final ProjectViewMode projectViewMode;
  final ProjectViewMode projectCatalogViewMode;
  final TaskBranchStyle branchStyle;
  final TaskRowSpacing rowSpacing;
  final TimelineVisibleHours visibleHours;
  final int hourWidth;
  final Set<String> collapsedProjectIds;
  final Map<String, Map<String, bool>> branchExpansion;
  TaskPreferences copyWith({
    bool? reengagementEnabled,
    int? quickAddMinutes,
    TaskTimeDisplayMode? timeDisplayMode,
    TaskListStyle? listStyle,
    ProjectViewMode? projectViewMode,
    ProjectViewMode? projectCatalogViewMode,
    TaskBranchStyle? branchStyle,
    TaskRowSpacing? rowSpacing,
    TimelineVisibleHours? visibleHours,
    int? hourWidth,
    Set<String>? collapsedProjectIds,
    Map<String, Map<String, bool>>? branchExpansion,
  }) => TaskPreferences(
    reengagementEnabled: reengagementEnabled ?? this.reengagementEnabled,
    quickAddMinutes: quickAddMinutes ?? this.quickAddMinutes,
    timeDisplayMode: timeDisplayMode ?? this.timeDisplayMode,
    listStyle: listStyle ?? this.listStyle,
    projectViewMode: projectViewMode ?? this.projectViewMode,
    projectCatalogViewMode:
        projectCatalogViewMode ?? this.projectCatalogViewMode,
    rowSpacing: rowSpacing ?? this.rowSpacing,
    branchStyle: branchStyle ?? this.branchStyle,
    visibleHours: visibleHours ?? this.visibleHours,
    hourWidth: hourWidth ?? this.hourWidth,
    collapsedProjectIds: collapsedProjectIds ?? this.collapsedProjectIds,
    branchExpansion: branchExpansion ?? this.branchExpansion,
  );
}
