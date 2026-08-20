import 'package:flutter/foundation.dart';

enum ClientUpdateSource { backend, appStore }

class ClientUpdatePolicy {
  const ClientUpdatePolicy._();

  static ClientUpdateSource get source => forPlatform(defaultTargetPlatform);

  @visibleForTesting
  static ClientUpdateSource forPlatform(TargetPlatform platform) {
    return platform == TargetPlatform.iOS
        ? ClientUpdateSource.appStore
        : ClientUpdateSource.backend;
  }
}
