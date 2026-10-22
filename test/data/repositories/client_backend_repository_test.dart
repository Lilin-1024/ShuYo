import 'package:flutter_test/flutter_test.dart';
import 'package:shuyo/data/repositories/client_backend_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('uses the first observed update build as baseline', () async {
    SharedPreferences.setMockInitialValues({});
    final repository = ClientBackendRepository();

    expect(await repository.shouldPromptUpdate(8), isFalse);
    expect(await repository.shouldPromptUpdate(8), isFalse);
    expect(await repository.shouldPromptUpdate(9), isTrue);

    await repository.markUpdatePrompted(9);

    expect(await repository.shouldPromptUpdate(9), isFalse);
  });

  test('initializes update baseline when current build is already latest',
      () async {
    SharedPreferences.setMockInitialValues({});
    final repository = ClientBackendRepository();

    await repository.ensureUpdateBaselineInitialized(8);

    expect(await repository.shouldPromptUpdate(9), isTrue);
  });

  test('keeps previous prompted build when migrating baseline', () async {
    SharedPreferences.setMockInitialValues({
      'client.backend.update.last_prompted': 7,
    });
    final repository = ClientBackendRepository();

    expect(await repository.shouldPromptUpdate(8), isTrue);
  });
}
