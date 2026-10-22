import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shuyo/data/models/home_layout.dart';
import 'package:shuyo/data/services/client_settings_service.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('order, groups and visibility survive a new settings service', () async {
    final layout = HomeLayout.defaults()
        .setEnabled(HomeModule.campusMap, false)
        .move(3, 1)
        .removeGroup('services')
        .addDivider('saved_line');
    await ClientSettingsService().saveHomeLayout(layout);
    final restored = await ClientSettingsService().loadHomeLayout();
    expect(restored.toJson(), layout.toJson());
  });

  test('demo changes and reset do not alter the normal layout', () async {
    final service = ClientSettingsService();
    final normal = HomeLayout.defaults().setEnabled(HomeModule.otp, false);
    final demo =
        HomeLayout.defaults().setEnabled(HomeModule.todayCourse, false);
    await service.saveHomeLayout(normal);
    await service.saveHomeLayout(demo, isDemo: true);
    expect((await service.loadHomeLayout()).toJson(), normal.toJson());
    expect(
        (await service.loadHomeLayout(isDemo: true)).toJson(), demo.toJson());
    await service.saveHomeLayout(HomeLayout.defaults(), isDemo: true);
    expect((await service.loadHomeLayout()).toJson(), normal.toJson());
  });

  test('malformed preferences keep the home usable without overwriting storage',
      () async {
    for (final invalid in [
      '{bad json',
      jsonEncode({'entries': []}),
      42
    ]) {
      SharedPreferences.setMockInitialValues({
        ClientSettingsService.homeLayoutKey: invalid,
      });
      final layout = await ClientSettingsService().loadHomeLayout();
      expect(layout.toJson(), HomeLayout.defaults().toJson());
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.get(ClientSettingsService.homeLayoutKey), invalid);
    }
  });
}
