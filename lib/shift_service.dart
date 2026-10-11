import 'dart:convert';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;

/// Server-authoritative shift and location transport shared by partner apps.
///
/// LOCATION_SERVICE_URL is optional until the Cloud Run/Redis service is
/// deployed. Without it, shifts use the callable backend and GPS is projected
/// to Firestore at a lower rate for compatibility with existing trip maps.
class PartnerShiftService {
  static final FirebaseFunctions _functions =
      FirebaseFunctions.instanceFor(region: 'asia-south1');
  static const String _baseUrl = String.fromEnvironment('LOCATION_SERVICE_URL');
  static bool get locationServiceEnabled => _baseUrl.trim().isNotEmpty;

  static Future<String?> setShift({
    required String role,
    required bool online,
  }) async {
    if (locationServiceEnabled) {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        throw FirebaseFunctionsException(code: 'unauthenticated', message: 'Please sign in again.');
      }
      final token = await user.getIdToken();
      final response = await http
          .post(
            Uri.parse('${_baseUrl.replaceFirst(RegExp(r'/+$'), '')}/v1/shift'),
            headers: <String, String>{
              'Authorization': 'Bearer $token',
              'Content-Type': 'application/json',
            },
            body: jsonEncode(<String, dynamic>{'role': role, 'online': online}),
          )
          .timeout(const Duration(seconds: 15));
      final payload = jsonDecode(response.body);
      if (response.statusCode < 200 || response.statusCode >= 300 ||
          payload is! Map || payload['ok'] != true) {
        final message = payload is Map ? (payload['error'] ?? 'The server rejected the shift change') : 'The server rejected the shift change';
        throw FirebaseFunctionsException(code: 'failed-precondition', message: message.toString());
      }
      return (payload['shiftSessionId'] ?? '').toString().trim().isEmpty
          ? null
          : payload['shiftSessionId'].toString();
    }

    final callable = _functions.httpsCallable(
      'setPartnerShift',
      options: HttpsCallableOptions(timeout: const Duration(seconds: 15)),
    );
    final result = await callable.call(<String, dynamic>{'role': role, 'online': online});
    final payload = result.data;
    if (payload is! Map || payload['ok'] != true) {
      throw FirebaseFunctionsException(
        code: 'failed-precondition',
        message: 'The server did not confirm the shift change.',
      );
    }
    return (payload['shiftSessionId'] ?? '').toString().trim().isEmpty
        ? null
        : payload['shiftSessionId'].toString();
  }

  /// Returns false when Redis/Cloud Run has not been configured; callers may
  /// then use their conservative Firestore compatibility projection.
  static Future<bool> updateLocation({
    required String role,
    required double latitude,
    required double longitude,
    required String? shiftSessionId,
  }) async {
    if (!locationServiceEnabled) return false;
    if (shiftSessionId == null || shiftSessionId.isEmpty) {
      throw FirebaseFunctionsException(
        code: 'failed-precondition',
        message: 'The active shift session is missing. Go offline and back online.',
      );
    }
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      throw FirebaseFunctionsException(code: 'unauthenticated', message: 'Please sign in again.');
    }
    final token = await user.getIdToken();
    final response = await http
        .post(
          Uri.parse('${_baseUrl.replaceFirst(RegExp(r'/+$'), '')}/v1/locations'),
          headers: <String, String>{
            'Authorization': 'Bearer $token',
            'Content-Type': 'application/json',
          },
          body: jsonEncode(<String, dynamic>{
            'role': role,
            'latitude': latitude,
            'longitude': longitude,
            'shiftSessionId': shiftSessionId,
          }),
        )
        .timeout(const Duration(seconds: 8));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw FirebaseFunctionsException(
        code: 'unavailable',
        message: 'Live location service rejected the update.',
      );
    }
    return true;
  }

  static Future<void> acceptRide({required String rideId}) async {
    final callable = _functions.httpsCallable(
      'acceptRide',
      options: HttpsCallableOptions(timeout: const Duration(seconds: 15)),
    );
    final result = await callable.call(<String, dynamic>{'rideId': rideId});
    final payload = result.data;
    if (payload is! Map || payload['ok'] != true) {
      throw FirebaseFunctionsException(
        code: 'failed-precondition',
        message: 'The server did not confirm the ride assignment.',
      );
    }
  }
}
