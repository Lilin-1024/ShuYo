import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shuyo/data/services/chaoxing_booking_client.dart';
import 'package:shuyo/data/services/session_cookie_jar.dart';

void main() {
  late HttpServer server;
  late StreamSubscription<HttpRequest> subscription;
  late ChaoxingBookingClient client;
  late DateTime now;
  final paths = <String>[];
  final days = <String>[];
  final writtenCookies = <SessionCookie>[];
  Map<String, String>? submitForm;
  Map<String, String>? signbackForm;
  String? signbackReferer;
  Map<String, String>? signQuery;
  String? signReferer;
  Map<String, String>? seatCheckQuery;
  Map<String, String>? seatCodeQuery;
  Map<String, String>? reserveInfoQuery;
  Map<String, String>? addressQuery;
  String? locationRequestBody;
  Map<String, String>? locationQuery;
  Map<String, String>? authorizeQuery;
  String? authorizeCookie;
  String currentSno = 'STUDENT_1';
  bool changeDayOnSelect = false;
  bool cancelDropsConnection = false;
  bool signbackDropsConnection = false;
  bool signDropsConnection = false;
  bool signPreflightFixture = false;
  int seatExistCount = 0;
  String detailSeatNum = '003';
  bool truncatedFiveReadRedirect = false;
  bool malformedFiveReadCookie = false;
  bool officeExpired = false;
  String? dataCookie;

  setUp(() async {
    paths.clear();
    days.clear();
    writtenCookies.clear();
    submitForm = null;
    signbackForm = null;
    signbackReferer = null;
    signQuery = null;
    signReferer = null;
    seatCheckQuery = null;
    seatCodeQuery = null;
    reserveInfoQuery = null;
    addressQuery = null;
    locationRequestBody = null;
    locationQuery = null;
    authorizeQuery = null;
    authorizeCookie = null;
    currentSno = 'STUDENT_1';
    changeDayOnSelect = false;
    cancelDropsConnection = false;
    signbackDropsConnection = false;
    signDropsConnection = false;
    signPreflightFixture = false;
    seatExistCount = 0;
    detailSeatNum = '003';
    truncatedFiveReadRedirect = false;
    malformedFiveReadCookie = false;
    officeExpired = false;
    dataCookie = null;
    now = DateTime.utc(2026, 10, 18, 1); // 09:00 in Shanghai.
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    subscription = server.listen((request) async {
      final path = request.uri.path;
      paths.add('${request.method} $path');
      final cookie = request.headers.value(HttpHeaders.cookieHeader) ?? '';
      Object body = '';
      switch (path) {
        case '/front/third/apps/seat/index':
          if (!cookie.contains('fid=35480') || officeExpired) {
            request.response.statusCode = 302;
            request.response.headers.set(HttpHeaders.locationHeader, '/login');
          } else {
            body = '<script>window.userLoginInfo = '
                '{"userInfo":{"uid":"USER_1","uname":"测试用户",'
                '"sno":"$currentSno"}} || {};</script>';
          }
        case '/login':
          body = '<html>登录</html>';
        case '/oauth/authorize':
          authorizeQuery = request.uri.queryParameters;
          authorizeCookie = cookie;
          request.response.statusCode = 302;
          request.response.headers.set(HttpHeaders.locationHeader,
              '/oauthlogin/loginByCodeSchoolid?code=ONCE&schoolid=2434&type=xxt');
        case '/oauthlogin/loginByCodeSchoolid':
          if (truncatedFiveReadRedirect) {
            final socket =
                await request.response.detachSocket(writeHeaders: false);
            socket.write('HTTP/1.1 302 Found\r\n'
                'Location: /api/v2/login6\r\n'
                'Content-Length: 12\r\n'
                'Connection: close\r\n\r\nx');
            await socket.flush();
            await Future<void>.delayed(const Duration(milliseconds: 50));
            await socket.close();
            return;
          }
          request.response.statusCode = 302;
          if (malformedFiveReadCookie) {
            request.response.headers.add(
                HttpHeaders.setCookieHeader, 'legacy-marker-without-a-value');
          }
          request.response.headers
              .set(HttpHeaders.locationHeader, '/api/v2/login6');
        case '/api/v2/login6':
          officeExpired = false;
          request.response.statusCode = 302;
          request.response.headers.set(HttpHeaders.locationHeader, '/landing');
          request.response.headers
              .add(HttpHeaders.setCookieHeader, 'fid=35480; Path=/; HttpOnly');
        case '/landing':
          body = '<html>学习通</html>';
        case '/data/apps/seat/index':
          dataCookie = cookie;
          body = {
            'success': true,
            'data': {
              'curReserves': signPreflightFixture
                  ? [
                      {'id': 123, 'roomId': 6508, 'seatNum': '003'}
                    ]
                  : <Object>[],
              'nearReserves': [
                {'id': 123, 'seatNum': '003', 'today': '2026-10-18'}
              ],
            },
          };
        case '/data/apps/seat/room/list':
          days.add(request.uri.queryParameters['day'] ?? '');
          body = {
            'success': true,
            'data': {
              'seatRoomList': [
                {
                  'id': 6508,
                  'capacity': 3,
                  'startSeatNum': 1,
                  'secondLevelName': '嘉定联合馆',
                  'thirdLevelName': '一楼自修室',
                }
              ]
            },
          };
        case '/data/apps/seat/room/info':
          final form = Uri.splitQueryString(await utf8.decodeStream(request));
          days.add(form['toDay'] ?? '');
          body = {
            'success': true,
            'data': {
              'seatRoom': {
                'id': 6508,
                'capacity': 3,
                'startSeatNum': 1,
                'secondLevelName': '嘉定联合馆',
                'thirdLevelName': '一楼自修室',
              }
            },
          };
        case '/data/apps/seat/getusedseatnums':
          final form = Uri.splitQueryString(await utf8.decodeStream(request));
          days.add(form['day'] ?? '');
          body = {
            'success': true,
            'data': {
              'seatReserves': [
                {'seatNum': '002'}
              ]
            },
          };
        case '/front/third/apps/seat/select':
          days.add(request.uri.queryParameters['day'] ?? '');
          body = '<input type="hidden" id="submit_enc" value="TEST_SALT" />';
          if (changeDayOnSelect) now = DateTime.utc(2026, 10, 18, 16);
        case '/data/apps/seat/submit':
          submitForm = Uri.splitQueryString(await utf8.decodeStream(request));
          days.add(submitForm!['day'] ?? '');
          body = {
            'success': true,
            'data': {
              'seatReserve': {'id': 123, 'seatNum': '003'}
            },
          };
        case '/data/apps/seat/cancel':
          if (cancelDropsConnection) {
            final socket = await request.response.detachSocket();
            socket.destroy();
            return;
          }
          body = {'success': true};
        case '/data/apps/seat/check/exist':
          seatCheckQuery = request.uri.queryParameters;
          body = {
            'success': true,
            'data': {'existCount': seatExistCount}
          };
        case '/front/apps/seat/code':
          seatCodeQuery = request.uri.queryParameters;
          request.response.statusCode = 302;
          request.response.headers.set(HttpHeaders.locationHeader,
              '/front/third/apps/seat/code?id=6508&seatNum=3');
        case '/front/third/apps/seat/code':
          body = '<html>座位操作页</html>';
        case '/data/apps/seat/reserve/info':
          reserveInfoQuery = request.uri.queryParameters;
          body = {
            'success': true,
            'data': {
              'seatConfig': {'isPosition': 1, 'deptId': 35480},
              'seatReserve': {
                'id': 123,
                'roomId': 6508,
                'seatNum': detailSeatNum,
                'status': 0,
              },
            },
          };
        case '/api/data/apps/reserve/wx/location':
          locationQuery = request.uri.queryParameters;
          locationRequestBody = await utf8.decodeStream(request);
          body = {
            'success': true,
            'data': {'locationType': 1}
          };
        case '/data/apps/seat/address':
          addressQuery = request.uri.queryParameters;
          body = {
            'success': true,
            'data': {
              'addressArr': [
                {'location': 'fixture', 'offsetReal': 100}
              ]
            }
          };
        case '/data/apps/seat/sign':
          signQuery = request.uri.queryParameters;
          signReferer = request.headers.value(HttpHeaders.refererHeader);
          if (signDropsConnection) {
            final socket = await request.response.detachSocket();
            socket.destroy();
            return;
          }
          body = {'success': true};
        case '/data/apps/seat/signback':
          signbackForm = Uri.splitQueryString(await utf8.decodeStream(request));
          signbackReferer = request.headers.value(HttpHeaders.refererHeader);
          if (signbackDropsConnection) {
            final socket = await request.response.detachSocket();
            socket.destroy();
            return;
          }
          body = {'success': true};
        default:
          request.response.statusCode = 404;
      }
      request.response.write(body is String ? body : jsonEncode(body));
      await request.response.close();
    });
    final base = Uri.parse('http://127.0.0.1:${server.port}');
    client = ChaoxingBookingClient(
      serviceUri: base,
      ssoUri: base,
      oauthRedirectUri: base
          .resolve('/oauthlogin/loginByCodeSchoolid?schoolid=2434&type=xxt'),
      clock: () => now,
      accountIdLoader: () async => 'STUDENT_1',
      cookieLoader: (uri) async => uri.host == base.host
          ? [
              SessionCookie(
                name: 'SHU_OAUTH2',
                value: 'TEST_SSO',
                domain: base.host,
              ),
              for (final cookie in writtenCookies)
                if (cookie.value.isNotEmpty &&
                    (uri.path.isEmpty ? '/' : uri.path).startsWith(cookie.path))
                  cookie,
            ]
          : [],
      cookieSetter: (cookie) async => writtenCookies.add(cookie),
    );
  });

  tearDown(() async {
    client.dispose();
    await subscription.cancel();
    await server.close(force: true);
  });

  test('exchanges SSO, scopes cookies, and returns same-day rooms', () async {
    final user = await client.bootstrap();
    expect(user['sno'], 'STUDENT_1');
    expect(authorizeQuery, containsPair('scope', ''));
    expect(authorizeQuery, containsPair('state', ''));
    expect(authorizeQuery?['response_type'], 'code');
    expect(authorizeCookie, contains('SHU_OAUTH2=TEST_SSO'));
    expect(writtenCookies.any((cookie) => cookie.name == 'fid'), isTrue);
    expect((await client.home())['nearReserves'], isNotEmpty);
    final rooms = await client.rooms();
    expect(rooms.single['id'], 6508);
    expect(days, ['2026-10-18']);
  });

  test('follows a 5read redirect even if its unused body is cut short',
      () async {
    truncatedFiveReadRedirect = true;
    expect((await client.bootstrap())['sno'], 'STUDENT_1');
    expect(paths, contains('GET /api/v2/login6'));
  });

  test('an invalid 5read cookie does not interrupt the redirect chain',
      () async {
    malformedFiveReadCookie = true;
    expect((await client.bootstrap())['sno'], 'STUDENT_1');
    expect(paths, contains('GET /api/v2/login6'));
  });

  test('upgrades known OAuth redirects to TLS without changing the code', () {
    const callbackHost = 'zhstsg-jx.5read.com';
    final passport = Uri.parse(
        'http://passport2-api.chaoxing.com/api/v2/login6?code=ONE_TIME');
    expect(
      ChaoxingBookingClient.secureExchangeRedirect(passport,
          callbackHost: callbackHost),
      Uri.parse(
          'https://passport2-api.chaoxing.com/api/v2/login6?code=ONE_TIME'),
    );
    final callback = Uri.parse('http://$callbackHost/oauthlogin?code=ONCE');
    expect(
      ChaoxingBookingClient.secureExchangeRedirect(callback,
          callbackHost: callbackHost),
      Uri.parse('https://$callbackHost/oauthlogin?code=ONCE'),
    );
    final foreign = Uri.parse('http://example.com/?code=ONCE');
    expect(
      ChaoxingBookingClient.secureExchangeRedirect(foreign,
          callbackHost: callbackHost),
      foreign,
    );
    final customPort = Uri.parse('http://passport2-api.chaoxing.com:8080/');
    expect(
      ChaoxingBookingClient.secureExchangeRedirect(customPort,
          callbackHost: callbackHost),
      customPort,
    );
  });

  test('derives seats and submits with a fresh signed form', () async {
    await client.bootstrap();
    final seats =
        await client.availability(roomId: '6508', start: '9:00', end: '10:00');
    expect(seats['used'], ['002']);
    expect(seats['available'], ['001', '003']);
    expect(seats['availableCount'], 2);

    final id = await client.submit(
        roomId: '6508', start: '09:00', end: '10:00', seatNum: '3');
    expect(id, '123');
    expect(submitForm?['seatNum'], '003');
    expect(submitForm?['captcha'], '');
    expect(submitForm?['wyToken'], '');
    expect(submitForm?['enc'], '64c14ccca64d805c65430f9ac89a23db');
    expect(days, everyElement('2026-10-18'));
    await client.cancel(id);
    expect(paths, contains('GET /data/apps/seat/cancel'));
  });

  test('a disconnected cancel reports an uncertain result without retry',
      () async {
    await client.bootstrap();
    cancelDropsConnection = true;
    await expectLater(
      client.cancel('123'),
      throwsA(isA<ChaoxingBookingException>()
          .having((error) => error.kind, 'kind', ChaoxingFailureKind.uncertain)
          .having((error) => error.message, 'message', contains('取消结果未确认'))),
    );
    expect(paths.where((path) => path == 'GET /data/apps/seat/cancel'),
        hasLength(1));
  });

  test('sign uses the reservation ID and seat operation page referer',
      () async {
    await client.bootstrap();
    await client.sign('123');
    expect(paths.where((path) => path == 'GET /data/apps/seat/sign'),
        hasLength(1));
    expect(signQuery, {'id': '123'});
    expect(Uri.parse(signReferer!).path, '/front/apps/seat/code');
    await expectLater(
        client.sign('not-an-id'), throwsA(isA<ChaoxingBookingException>()));
    expect(paths.where((path) => path == 'GET /data/apps/seat/sign'),
        hasLength(1));
  });

  test('disconnected sign remains uncertain and is not retried', () async {
    await client.bootstrap();
    signDropsConnection = true;
    await expectLater(
      client.sign('123'),
      throwsA(isA<ChaoxingBookingException>().having(
          (error) => error.kind, 'kind', ChaoxingFailureKind.uncertain)),
    );
    expect(paths.where((path) => path == 'GET /data/apps/seat/sign'),
        hasLength(1));
  });

  test('seat-page sign reads observed endpoints with no fake location payload',
      () async {
    await client.bootstrap();
    signPreflightFixture = true;
    await client.signWithSeatPage(
        reserveId: '123', roomId: '6508', seatNum: '003');
    expect(seatCheckQuery, {'seatNum': '003', 'roomId': '6508'});
    expect(seatCodeQuery, {'id': '6508', 'seatNum': '3'});
    expect(reserveInfoQuery, {'id': '6508', 'seatNum': '3'});
    expect(locationQuery, isEmpty);
    expect(locationRequestBody, isEmpty);
    expect(addressQuery, {'deptId': '35480', 'roomId': '6508'});
    expect(signQuery, {'id': '123'});
    expect(Uri.parse(signReferer!).path, '/front/third/apps/seat/code');
    final readsAndSign = paths
        .skipWhile((path) => path != 'GET /data/apps/seat/check/exist')
        .toList();
    expect(readsAndSign, [
      'GET /data/apps/seat/check/exist',
      'GET /front/apps/seat/code',
      'GET /front/third/apps/seat/code',
      'GET /data/apps/seat/reserve/info',
      'GET /data/apps/seat/index',
      'POST /api/data/apps/reserve/wx/location',
      'GET /data/apps/seat/address',
      'GET /data/apps/seat/sign',
    ]);
  });

  test('seat-page sign stops before writing if seat is occupied or mismatched',
      () async {
    await client.bootstrap();
    signPreflightFixture = true;
    seatExistCount = 1;
    await expectLater(
      client.signWithSeatPage(reserveId: '123', roomId: '6508', seatNum: '003'),
      throwsA(isA<ChaoxingBookingException>()),
    );
    expect(paths, isNot(contains('GET /data/apps/seat/sign')));
    expect(seatCodeQuery, isNull);

    seatExistCount = 0;
    detailSeatNum = '004';
    await expectLater(
      client.signWithSeatPage(reserveId: '123', roomId: '6508', seatNum: '003'),
      throwsA(isA<ChaoxingBookingException>()),
    );
    expect(paths, isNot(contains('GET /data/apps/seat/sign')));
    expect(locationRequestBody, isNull);
  });

  test('seat release posts the reservation ID from the seat home page',
      () async {
    await client.bootstrap();
    await client.signback('123');
    expect(paths.where((path) => path == 'POST /data/apps/seat/signback'),
        hasLength(1));
    expect(signbackForm, {'id': '123'});
    expect(Uri.parse(signbackReferer!).path, '/front/third/apps/seat/index');
    await expectLater(
        client.signback('not-an-id'), throwsA(isA<ChaoxingBookingException>()));
    expect(paths.where((path) => path == 'POST /data/apps/seat/signback'),
        hasLength(1));
  });

  test('disconnected seat release remains uncertain and is not retried',
      () async {
    await client.bootstrap();
    signbackDropsConnection = true;
    await expectLater(
      client.signback('123'),
      throwsA(isA<ChaoxingBookingException>().having(
          (error) => error.kind, 'kind', ChaoxingFailureKind.uncertain)),
    );
    expect(paths.where((path) => path == 'POST /data/apps/seat/signback'),
        hasLength(1));
  });

  test('rejects past-day rollover and invalid intervals before submission',
      () async {
    await client.bootstrap();
    await expectLater(
      client.submit(roomId: '6508', start: '09:15', end: '10:15', seatNum: '3'),
      throwsA(isA<ChaoxingBookingException>()),
    );
    expect(paths, isNot(contains('POST /data/apps/seat/submit')));
    changeDayOnSelect = true;
    await expectLater(
      client.submit(roomId: '6508', start: '09:00', end: '10:00', seatNum: '3'),
      throwsA(isA<ChaoxingBookingException>()
          .having((error) => error.message, 'message', contains('日期已经变化'))),
    );
    expect(paths, isNot(contains('POST /data/apps/seat/submit')));
  });

  test('a different student is blocked and business cookies are removed',
      () async {
    currentSno = 'OTHER_STUDENT';
    await expectLater(
      client.bootstrap(),
      throwsA(isA<ChaoxingBookingException>().having(
          (error) => error.kind, 'kind', ChaoxingFailureKind.loginRequired)),
    );
    expect(
        writtenCookies
            .any((cookie) => cookie.name == 'fid' && cookie.value.isEmpty),
        isTrue);
    expect(paths.where((path) => path == 'GET /oauth/authorize'), hasLength(1));
  });

  test('reentering verifies office and renews an expired business session',
      () async {
    await client.bootstrap();
    officeExpired = true;
    await client.bootstrap();
    expect(paths.where((path) => path == 'GET /oauth/authorize'), hasLength(2));
    expect(client.user?['sno'], 'STUDENT_1');
  });

  test('loads and clears path-scoped business cookies', () async {
    writtenCookies.add(const SessionCookie(
        name: 'fid', value: '35480', domain: '127.0.0.1', path: '/front'));
    writtenCookies.add(const SessionCookie(
        name: 'dataMarker', value: 'DATA', domain: '127.0.0.1', path: '/data'));
    await client.bootstrap();
    expect(paths.where((path) => path == 'GET /oauth/authorize'), isEmpty);
    await client.home();
    expect(dataCookie, contains('dataMarker=DATA'));
    await client.clearSession();
    expect(
        writtenCookies.any((cookie) =>
            cookie.name == 'fid' &&
            cookie.path == '/front' &&
            cookie.value.isEmpty),
        isTrue);
    expect(
        writtenCookies.any((cookie) =>
            cookie.name == 'dataMarker' &&
            cookie.path == '/data' &&
            cookie.value.isEmpty),
        isTrue);
  });

  test('clearSession removes all business subdomains and paths only', () async {
    SharedPreferences.setMockInitialValues({});
    final jar = SessionCookieJar();
    for (final cookie in [
      const SessionCookie(
          name: 'front',
          value: 'a',
          domain: 'office.chaoxing.com',
          path: '/front'),
      const SessionCookie(
          name: 'data',
          value: 'b',
          domain: 'office.chaoxing.com',
          path: '/data/apps'),
      const SessionCookie(
          name: 'other-subdomain', value: 'c', domain: 'i.chaoxing.com'),
      const SessionCookie(
          name: 'callback',
          value: 'd',
          domain: 'zhstsg-jx.5read.com',
          path: '/oauthlogin'),
      const SessionCookie(
          name: 'campus', value: 'e', domain: 'newsso.shu.edu.cn'),
      const SessionCookie(
          name: 'other-library', value: 'f', domain: 'other.5read.com'),
    ]) {
      await jar.setCookie(cookie);
    }
    final storedClient = ChaoxingBookingClient(cookieJar: jar);
    addTearDown(storedClient.dispose);

    await storedClient.clearSession();

    expect(await jar.getCookiesForDomainTree(domain: 'chaoxing.com'), isEmpty);
    expect(await jar.getCookiesForDomainTree(domain: 'zhstsg-jx.5read.com'),
        isEmpty);
    expect(
      (await jar.getCookiesForDomainTree(domain: 'newsso.shu.edu.cn'))
          .single
          .name,
      'campus',
    );
    expect(
      (await jar.getCookiesForDomainTree(domain: 'other.5read.com'))
          .single
          .name,
      'other-library',
    );
  });
}
