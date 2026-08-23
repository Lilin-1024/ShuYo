import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shuyo/data/services/client_settings_service.dart';

void main() {
  test('WebVPN is enabled by default and preserves an explicit opt-out',
      () async {
    SharedPreferences.setMockInitialValues({});
    final service = ClientSettingsService();

    expect((await service.loadNetworkSettings()).autoUseWebVpnProxy, isTrue);

    await service.saveNetworkSettings(
      const ClientNetworkSettings(autoUseWebVpnProxy: false),
    );
    expect((await service.loadNetworkSettings()).autoUseWebVpnProxy, isFalse);
  });

  test('startup onboarding completion is stored independently', () async {
    SharedPreferences.setMockInitialValues({});
    final service = ClientSettingsService();

    expect(await service.loadStartupOnboardingCompleted(), isFalse);
    await service.saveStartupOnboardingCompleted(true);
    expect(await service.loadStartupOnboardingCompleted(), isTrue);
  });
}
