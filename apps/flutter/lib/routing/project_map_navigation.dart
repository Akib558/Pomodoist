import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

bool isProjectMapFullscreen(Uri location) =>
    location.queryParameters['mapFullscreen'] == '1' &&
    (location.pathSegments.length == 2 &&
            location.pathSegments.first == 'project' ||
        location.path == '/projects' &&
            location.queryParameters['tab'] != 'labels');

Uri projectMapFullscreenUri(Uri location, bool fullscreen) {
  final query = Map<String, dynamic>.from(location.queryParametersAll);
  if (fullscreen) {
    query['mapFullscreen'] = '1';
  } else {
    query.remove('mapFullscreen');
  }
  return Uri(
    scheme: location.scheme,
    userInfo: location.userInfo,
    host: location.hasAuthority ? location.host : null,
    port: location.hasPort ? location.port : null,
    path: location.path,
    queryParameters: query.isEmpty ? null : query,
    fragment: location.hasFragment ? location.fragment : null,
  );
}

void setProjectMapFullscreen(BuildContext context, bool fullscreen) {
  final router = GoRouter.of(context);
  Router.neglect(
    context,
    () => router.go(
      projectMapFullscreenUri(router.state.uri, fullscreen).toString(),
    ),
  );
}
