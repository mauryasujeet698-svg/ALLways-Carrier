import 'dart:convert';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;

/// Server-authoritative shifts plus optional low-latency Redis/H3 location transport.
///
/// LOCATION_SERVICE_URL is set only after the Cloud Run + private Redis service
/// is deployed. Otherwise the apps use callable shift/dispatch endpoints and a
/// bounded Firestore compatibility projection.
class PartnerShiftService {
  static final FirebaseFunctions _functions =
      FirebaseFunctions.instanceFor(region: 'asia-south1');
  static const String _baseUrl = String.fromEnvironment('LOCATION_SERVICE_URL');
  static bool get locationServiceEnabled => _baseUrl.trim().isNotEmpty;
  static String get _base => _baseUrl.replaceFirst(RegExp(r'/+$'), '');

  static Future<String?> setShift({required String role, required bool online}) async {
    if (locationServiceEnabled) {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        throw FirebaseFunctionsException(code: 'unauthenticated', message: 'Please sign in again.');
      }
      final token = await user.getIdToken(true);
      final response = await http.post(
        Uri.parse('$_base/v1/shift'),
        headers: {'Authorization': 'Bearer $token', 'Content-Type': 'application/json'},
        body: jsonEncode({'role': role, 'online': online}),
      ).timeout(const Duration(seconds: 15));
      final payload = _decode(response.body);
      if (response.statusCode < 200 || response.statusCode >= 300 ||
          payload is! Map || payload['ok'] != true) {
        final message = payload is Map ? (payload['error'] ?? 'The server rejected the shift change') : 'The server rejected the shift change';
        throw FirebaseFunctionsException(code: _httpCode(response.statusCode), message: message.toString());
      }
      final id = (payload['shiftSessionId'] ?? '').toString().trim();
      return id.isEmpty ? null : id;
    }

    final callable = _functions.httpsCallable(
      'setPartnerShift',
      options: HttpsCallableOptions(timeout: const Duration(seconds: 15)),
    );
    final result = await callable.call({'role': role, 'online': online});
    final payload = result.data;
    if (payload is! Map || payload['ok'] != true) {
      throw FirebaseFunctionsException(code: 'failed-precondition', message: 'The server did not confirm the shift change.');
    }
    final id = (payload['shiftSessionId'] ?? '').toString().trim();
    return id.isEmpty ? null : id;
  }

  /// activeJobId lets the location service exclude busy workers from candidate matching.
  static Future<bool> updateLocation({
    required String role,
    required double latitude,
    required double longitude,
    required String? shiftSessionId,
    String? activeJobId,
  }) async {
    if (!locationServiceEnabled) return false;
    if (shiftSessionId == null || shiftSessionId.isEmpty) {
      throw FirebaseFunctionsException(code: 'failed-precondition', message: 'The active shift session is missing. Go offline and back online.');
    }
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) throw FirebaseFunctionsException(code: 'unauthenticated', message: 'Please sign in again.');
    final token = await user.getIdToken();
    final response = await http.post(
      Uri.parse('$_base/v1/locations'),
      headers: {'Authorization': 'Bearer $token', 'Content-Type': 'application/json'},
      body: jsonEncode({
        'role': role,
        'latitude': latitude,
        'longitude': longitude,
        'shiftSessionId': shiftSessionId,
        if (activeJobId != null && activeJobId.trim().isNotEmpty) 'activeJobId': activeJobId.trim(),
      }),
    ).timeout(const Duration(seconds: 8));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      final payload = _decode(response.body);
      final message = payload is Map ? (payload['error'] ?? 'Live location service rejected the update') : 'Live location service rejected the update';
      throw FirebaseFunctionsException(code: _httpCode(response.statusCode), message: message.toString());
    }
    return true;
  }

  static Future<void> acceptRide({required String rideId}) async {
    final result = await _functions.httpsCallable(
      'acceptRide',
      options: HttpsCallableOptions(timeout: const Duration(seconds: 15)),
    ).call({'rideId': rideId});
    final payload = result.data;
    if (payload is! Map || payload['ok'] != true) {
      throw FirebaseFunctionsException(code: 'failed-precondition', message: 'The server did not confirm the ride assignment.');
    }
  }

  static dynamic _decode(String body) {
    try { return jsonDecode(body); } catch (_) { return null; }
  }

  static String _httpCode(int status) {
    if (status == 401) return 'unauthenticated';
    if (status == 403) return 'permission-denied';
    if (status == 409) return 'failed-precondition';
    if (status == 429) return 'resource-exhausted';
    return status >= 500 ? 'unavailable' : 'failed-precondition';
  }
}
