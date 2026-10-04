import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

const newHabitDetailsId = 'new';

Uri habitDetailUri(Uri background, String? habitId) {
  final query = Map<String, dynamic>.from(background.queryParametersAll);
  if (habitId == null) {
    query.remove('habit');
  } else {
    query.remove('task');
    query['habit'] = habitId;
  }
  return Uri(
    scheme: background.scheme,
    userInfo: background.userInfo,
    host: background.hasAuthority ? background.host : null,
    port: background.hasPort ? background.port : null,
    path: background.path,
    queryParameters: query.isEmpty ? null : query,
    fragment: background.hasFragment ? background.fragment : null,
  );
}

void openHabitDetails(BuildContext context, String? habitId) {
  final router = GoRouter.of(context);
  final current = router.state.uri;
  final target = habitDetailUri(current, habitId ?? newHabitDetailsId);
  if (target == current) return;
  if (current.queryParameters.containsKey('habit')) {
    Router.neglect(context, () => router.go(target.toString()));
  } else {
    Router.navigate(context, () => router.go(target.toString()));
  }
}

void closeHabitDetails(BuildContext context) {
  final router = GoRouter.of(context);
  Router.neglect(
    context,
    () => router.go(habitDetailUri(router.state.uri, null).toString()),
  );
}
