import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shuyo/data/services/academic_account_store.dart';
import 'package:shuyo/data/services/academic_profile_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('nicknames are display preferences scoped to the real student ID',
      () async {
    final account = AcademicAccountStore();
    final profile = AcademicProfilePreferences();
    await account.saveStudentId('25120000');

    expect(await profile.loadNickname('25120000'), isNull);
    await profile.saveNickname('25120000', '  小明  ');
    expect(await profile.loadNickname('25120000'), '小明');
    expect(await profile.loadNickname('25120001'), isNull);
    expect(await account.loadStudentId(), '25120000');

    await account.clear();
    expect(await profile.loadNickname('25120000'), '小明');
    await profile.saveNickname('25120000', ' ');
    expect(await profile.loadNickname('25120000'), isNull);
  });

  test('preferred campus defaults to 宝山 and persists independently', () async {
    final profile = AcademicProfilePreferences();
    expect(await profile.loadPreferredCampus(), '宝山');
    await profile.savePreferredCampus('嘉定');
    expect(await AcademicProfilePreferences().loadPreferredCampus(), '嘉定');
    expect(await profile.loadNickname('25120000'), isNull);
  });
}
