import 'dart:async';

class HttpTimeout {
  const HttpTimeout._();

  static const normal = Duration(seconds: 12);
  static const upload = Duration(seconds: 30);

  static Future<T> request<T>(
    Future<T> future, {
    Duration timeout = normal,
    String message = '网络请求超时，请稍后再试',
  }) {
    return future.timeout(
      timeout,
      onTimeout: () => throw TimeoutException(message, timeout),
    );
  }
}
