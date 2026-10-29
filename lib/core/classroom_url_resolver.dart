class ClassroomUrlResolver {
  const ClassroomUrlResolver._();

  static const directHost = 'classroom.cc.shu.edu.cn';
  static const directBaseUrl = 'https://$directHost';
  static const webVpnHost =
      'https-classroom-cc-shu-edu-cn-443.webvpn.shu.edu.cn';
  static const webVpnBaseUrl = 'https://$webVpnHost';

  static bool _usesWebVpn = false;
  static int _revision = 0;

  static bool get usesWebVpn => _usesWebVpn;
  static int get revision => _revision;

  static void configure({required bool useWebVpn}) {
    if (_usesWebVpn != useWebVpn) _revision++;
    _usesWebVpn = useWebVpn;
  }

  static String get baseUrl => usesWebVpn ? webVpnBaseUrl : directBaseUrl;

  static Uri get baseUri => Uri.parse(baseUrl);

  static Uri uri(String path) {
    final normalized = path.startsWith('/') ? path : '/$path';
    return Uri.parse('$baseUrl$normalized');
  }
}

class ClassroomAccessWindow {
  const ClassroomAccessWindow._();

  static bool isExternalAccessOpen(DateTime instant) {
    final shanghaiTime = instant.toUtc().add(const Duration(hours: 8));
    return shanghaiTime.hour >= 7 && shanghaiTime.hour < 23;
  }

  static String directFailureMessage({
    String? detail,
    DateTime? now,
  }) {
    final prefix =
        detail == null || detail.trim().isEmpty ? '' : '${detail.trim()}。';
    if (!isExternalAccessOpen(now ?? DateTime.now())) {
      return '$prefix当前处于空教室查询外网关闭时段（每日23:00至次日07:00）。'
          '请连接校园网、学校VPN，或开启WebVPN后重试。';
    }
    final fallback = prefix.isEmpty ? '空教室系统暂时无法访问，请稍后重试。' : prefix;
    return '$fallback外网开放时段为每日07:00至23:00。';
  }
}
