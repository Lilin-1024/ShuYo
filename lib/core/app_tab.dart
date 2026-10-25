enum AppTab {
  home('home', '首页'),
  rate('rate', '课评'),
  progress('progress', '学业'),
  schedule('schedule', '日程');

  const AppTab(this.storageId, this.label);

  final String storageId;
  final String label;

  static AppTab fromStorageId(String? value) {
    for (final tab in values) {
      if (tab.storageId == value) return tab;
    }
    return AppTab.home;
  }
}
