import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shuyo/core/app_tab.dart';
import 'package:shuyo/data/services/client_settings_service.dart';
import 'package:shuyo/data/services/academic_native_auth_service.dart';
import 'package:shuyo/data/services/verification_delivery_service.dart';
import 'package:shuyo/shared/theme/custom_background.dart';
import 'package:shuyo/shared/theme/shuyo_theme.dart';

void main() {
  test('custom theme without a photo survives restart', () async {
    SharedPreferences.setMockInitialValues({});
    final service = ClientSettingsService();
    final settings = CustomBackground.withoutPhoto(
      ShuYoThemes.byId(ShuYoThemes.defaultId).colors,
    );
    await service.saveCustomBackground(settings);
    await service.saveThemeId(ShuYoThemes.customBackgroundId);

    final restored = await service.loadCustomBackground();
    expect(restored?.hasPhoto, isFalse);
    expect(restored?.opacity, 0);
    expect(await service.loadThemeId(), ShuYoThemes.customBackgroundId);
  });

  test(
      'custom background keeps edits across theme changes and loads only with its photo',
      () async {
    SharedPreferences.setMockInitialValues({});
    final directory =
        await Directory.systemTemp.createTemp('shuyo_theme_test_');
    addTearDown(() => directory.delete(recursive: true));
    final photo = File('${directory.path}/background.png');
    await photo.writeAsBytes([1, 2, 3]);
    final service = ClientSettingsService();
    final settings = CustomBackground(
      imagePath: photo.path,
      opacity: 75,
      background: const Color(0xFFFAFAFA),
      surface: Colors.white,
      text: const Color(0xFF101010),
      accent: const Color(0xFF35458A),
    );

    await service.saveCustomBackground(settings);
    await service.saveThemeId('paper_light');
    final restored = await service.loadCustomBackground();
    expect(restored?.imagePath, photo.path);
    expect(restored?.opacity, 75);
    expect(restored?.accent, settings.accent);

    final oldJson = Map<String, dynamic>.from(settings.toJson())
      ..remove('opacity')
      ..['transparency'] = 50;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      ClientSettingsService.customBackgroundKey,
      jsonEncode(oldJson),
    );
    expect((await service.loadCustomBackground())?.opacity, 23);

    await photo.delete();
    expect(await service.loadCustomBackground(), isNull);
  });

  test('WebVPN is disabled by default and preserves an explicit opt-in',
      () async {
    SharedPreferences.setMockInitialValues({});
    final service = ClientSettingsService();

    expect((await service.loadNetworkSettings()).webVpnEnabled, isFalse);

    await service.saveNetworkSettings(
      const ClientNetworkSettings(webVpnEnabled: true),
    );
    expect((await service.loadNetworkSettings()).webVpnEnabled, isTrue);
  });

  test('startup onboarding completion is stored independently', () async {
    SharedPreferences.setMockInitialValues({});
    final service = ClientSettingsService();

    expect(await service.loadStartupOnboardingCompleted(), isFalse);
    await service.saveStartupOnboardingCompleted(true);
    expect(await service.loadStartupOnboardingCompleted(), isTrue);
  });

  test('startup display defaults to home and stores stable tab IDs', () async {
    SharedPreferences.setMockInitialValues({});
    final service = ClientSettingsService();

    expect(await service.loadStartupTab(), AppTab.home);
    await service.saveStartupTab(AppTab.progress);
    expect(await service.loadStartupTab(), AppTab.progress);

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString(ClientSettingsService.startupTabKey), 'progress');
    await prefs.setString(ClientSettingsService.startupTabKey, 'removed-tab');
    expect(await service.loadStartupTab(), AppTab.home);
  });

  test('verification delivery alternates methods between login flows',
      () async {
    SharedPreferences.setMockInitialValues({});
    final service = VerificationDeliveryService();
    const methods = AcademicVerificationMethod.values;

    expect(
      await service.preferredMethod(methods),
      AcademicVerificationMethod.wecom,
    );
    await service.markSent(AcademicVerificationMethod.wecom);
    expect(
      await service.preferredMethod(methods),
      AcademicVerificationMethod.sms,
    );
    expect(
      await service.remainingCooldown(AcademicVerificationMethod.wecom),
      greaterThan(Duration.zero),
    );
  });
}
