import 'dart:async';
import 'dart:convert';
import 'dart:io' show HandshakeException, Platform, SocketException;
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:local_auth/local_auth.dart';
import 'notify.dart';

const store = FlutterSecureStorage();
final _auth = LocalAuthentication();

/// An error with a message that is safe to show to the member. toString() is the message, so
/// existing code that shows '$e' keeps working.
class ApiError implements Exception {
  final String message;
  final int status;
  final bool needsConsent;
  ApiError(this.message, {this.status = 0, this.needsConsent = false});
  @override
  String toString() => message;
}

/// The one message a member should see for any failed request. Server messages pass through unchanged.
/// Anything else (a crash in our own code, no data) gets a plain line, never raw Dart error text.
String friendly(Object e) {
  if (e is ApiError) return e.message;
  return 'Something went wrong. Please try again.';
}

class Api {
  /// Sent with crash reports so the team knows which build crashed.
  static const appVersion = '1.3.1+9';
  static String get base => (dotenv.env['API_BASE_URL'] ?? '').trim().replaceAll(RegExp(r'/+$'), '');
  static const _timeout = Duration(seconds: 25);

  /// Set by the app shell: called when the server says the sign-in has expired.
  static void Function()? onSessionExpired;

  static Future<Map<String, String>> _h() async => {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer ${await store.read(key: 'token') ?? ''}',
      };

  static Future<dynamic> call(String method, String path, [Map? body]) async {
    final uri = Uri.parse('$base$path');
    final h = await _h();
    http.Response r;
    try {
      final req = method == 'GET'
          ? http.get(uri, headers: h)
          : method == 'DELETE'
              ? http.delete(uri, headers: h)
              : http.post(uri, headers: h, body: jsonEncode(body ?? {}));
      r = await req.timeout(_timeout);   // never wait forever on a slow network
    } on TimeoutException catch (e) {
      debugPrint('API timeout $method $path: $e');
      throw ApiError('This is taking too long. Check your network and try again.');
    } on SocketException catch (e) {
      debugPrint('API socket error $method $path: $e');
      throw ApiError('No internet connection. Check your network and try again.');
    } on HandshakeException catch (e) {
      debugPrint('API TLS error $method $path: $e');
      throw ApiError('Could not open a secure connection. Check your network and try again.');
    } on http.ClientException catch (e) {
      debugPrint('API client error $method $path: $e');
      throw ApiError('No internet connection. Check your network and try again.');
    }
    dynamic data = {};
    try { data = r.body.isEmpty ? {} : jsonDecode(r.body); } catch (_) { data = {}; }
    final map = data is Map ? data : {};
    // The server marks an expired or replaced sign-in with code "session_expired". (A wrong PIN is also a 401, but it is NOT this.)
    if (r.statusCode == 401 && map['code'] == 'session_expired') {
      await store.delete(key: 'token');
      onSessionExpired?.call();
      throw ApiError('Your session expired. Please sign in again.', status: 401);
    }
    if (r.statusCode == 403 && map.isEmpty) {
      // Not a CSave JSON answer: usually the request was blocked before it reached the app server.
      debugPrint('API blocked $method $path: HTTP 403, body ${r.body.length > 80 ? r.body.substring(0, 80) : r.body}');
      throw ApiError('We cannot reach CSave right now. Please try again in a few minutes.', status: 403);
    }
    if (r.statusCode >= 400) {
      throw ApiError((map['error'] ?? 'Something went wrong. Try again.').toString(), status: r.statusCode, needsConsent: map['needsConsent'] == true);
    }
    return data;
  }

  /// Returns true when signed in, false when a staff email code is still needed.
  static Future<bool> login(String email, String pass) async {
    final d = await call('POST', '/api/auth/login', {'email': email, 'password': pass, 'deviceId': await Telemetry._device()});
    await store.write(key: 'email', value: email);
    if (d['otpRequired'] == true) return false;
    await store.write(key: 'token', value: d['token']);
    return true;
  }

  static Future<void> verifyOtp(String email, String code) async {
    final d = await call('POST', '/api/auth/verify-otp', {'email': email, 'code': code});
    await store.write(key: 'token', value: d['token']);
  }

  /// Signing out (from Profile or the lock screen) forgets the member on this phone: the session, the stored
  /// password used by fingerprint sign-in, the fingerprint switch, and their scheduled alarms.
  static Future<void> forgetDevice() async {
    await store.delete(key: 'token');
    await store.delete(key: 'bioPass');
    await store.write(key: 'bio', value: '0');
    try { await Notify.cancelAll(); } catch (_) {}
  }

  /// Full sign-out, as if the app had just been installed: also clears the saved email,
  /// device ID and reminder setting. The theme is kept.
  static Future<void> clearAccount() async {
    await forgetDevice();
    await store.delete(key: 'email');
    await store.delete(key: 'device');
    await store.delete(key: 'alarms');
  }

  static Future<Map> wallet() async => Map<String, dynamic>.from(await call('GET', '/api/wallet'));
  /// Nigerian banks from Flutterwave, as {code, name}. The member picks one; the code is what the server needs.
  static Future<List<Map>> banks() async => List<Map>.from(await call('GET', '/api/banks'));
  // method: 'card', 'ussd' or 'bank'. The server uses it to choose which payment options to show.
  static Future<Map> fundWallet(num amount, String method) async =>
      Map<String, dynamic>.from(await call('POST', '/api/wallet/fund', {'amount': amount, 'method': method}));
  static Future<Map> transferToPlan(String planId, num amount) async =>
      Map<String, dynamic>.from(await call('POST', '/api/wallet/transfer-to-plan', {'planId': planId, 'amount': amount}));
  static Future<Map> extendPlan(String id, DateTime newDate) async =>
      Map<String, dynamic>.from(await call('POST', '/api/plans/$id/extend', {'unlockDate': newDate.toIso8601String()}));
  static Future<Map> pausePlan(String id) async => Map<String, dynamic>.from(await call('POST', '/api/plans/$id/pause'));
  static Future<Map> resumePlan(String id) async => Map<String, dynamic>.from(await call('POST', '/api/plans/$id/resume'));
}

/// Lets the technical team see crashes and how many sessions there were (no personal data is sent).
/// The server wants the app key (TELEMETRY_KEY in flutter_app.env) and a random per-install id. Without a key this does nothing.
class Telemetry {
  static String get _key => dotenv.env['TELEMETRY_KEY'] ?? '';
  static Future<String> _device() async {
    var d = await store.read(key: 'device');
    if (d == null) {
      final r = Random.secure();
      d = List.generate(32, (_) => r.nextInt(16).toRadixString(16)).join();
      await store.write(key: 'device', value: d);
    }
    return d;
  }

  static Future<Map<String, String>> _headers() async =>
      {...await Api._h(), 'x-app-key': _key, 'x-device-id': await _device()};

  static Future<void> session() async {
    if (_key.isEmpty) return;
    try { await http.post(Uri.parse('${Api.base}/api/telemetry/session'), headers: await _headers()).timeout(const Duration(seconds: 10)); } catch (_) {}
  }

  static Future<void> crash(Object e, StackTrace? st, {String screen = ''}) async {
    if (_key.isEmpty) return;
    try {
      await http.post(Uri.parse('${Api.base}/api/telemetry/crash'), headers: await _headers(),
          body: jsonEncode({'platform': Platform.operatingSystem, 'appVersion': Api.appVersion, 'screen': screen, 'message': e.toString(), 'stack': st?.toString() ?? ''}))
          .timeout(const Duration(seconds: 10));
    } catch (_) {}
  }
}

class Bio {
  // The phone checks the fingerprint. CSave never sees or stores it.
  static Future<bool> available() async =>
      await _auth.canCheckBiometrics && (await _auth.getAvailableBiometrics()).isNotEmpty;

  static Future<bool> prompt(String reason) async {
    try {
      return await _auth.authenticate(
        localizedReason: reason,
        options: const AuthenticationOptions(biometricOnly: true, stickyAuth: true),
      );
    } catch (_) { return false; }
  }

  static Future<bool> get enabled async => (await store.read(key: 'bio')) == '1';
  static Future<void> setEnabled(bool v) => store.write(key: 'bio', value: v ? '1' : '0');
}
