import 'dart:async';

import 'package:dio/dio.dart';

import '../domain/profile.dart';
import '../domain/profile_repository.dart';

class ProfileSession {
  const ProfileSession({
    required this.uid,
    required this.token,
    required this.verified,
  });
  final String uid;
  final String token;
  final bool verified;
}

class ProfileFailure implements Exception {
  const ProfileFailure(this.message);
  final String message;
}

/// A session-bound API client. Never logs or stores bearer tokens in defaults.
class ApiProfileRepository implements ProfileRepository {
  ApiProfileRepository({
    required Uri origin,
    required this.session,
    required this.currentUid,
    HttpClientAdapter? adapter,
  }) {
    if (origin.scheme != 'https' ||
        origin.host.isEmpty ||
        origin.userInfo.isNotEmpty ||
        origin.hasQuery ||
        origin.hasFragment ||
        (origin.path.isNotEmpty && origin.path != '/')) {
      throw ArgumentError('Profile API requires an HTTPS origin.');
    }
    _dio = Dio(
      BaseOptions(
        baseUrl: origin.origin,
        connectTimeout: const Duration(seconds: 10),
        sendTimeout: const Duration(seconds: 15),
        receiveTimeout: const Duration(seconds: 20),
        followRedirects: false,
        validateStatus: (_) => true,
      ),
    );
    if (adapter != null) _dio.httpClientAdapter = adapter;
  }
  late final Dio _dio;
  final Future<ProfileSession?> Function() session;
  final String? Function() currentUid;

  @override
  Future<SavedProfile?> load() => _request('GET');

  @override
  Future<SavedProfile> save(ProfileDraft draft) async {
    if (draft.validate().isNotEmpty) {
      throw const ProfileFailure('Please check your profile fields.');
    }
    return (await _request('PUT', draft: draft))!;
  }

  Future<SavedProfile?> _request(String method, {ProfileDraft? draft}) async {
    final cancel = CancelToken();
    try {
      final session = await this.session().timeout(const Duration(seconds: 10));
      if (session == null ||
          session.uid.isEmpty ||
          session.token.isEmpty ||
          session.uid != currentUid()) {
        throw const ProfileFailure('Please sign in again.');
      }
      if (!session.verified) {
        throw const ProfileFailure(
          'Verify your email before editing your profile.',
        );
      }
      final response = await _dio
          .request<Object?>(
            '/api/v1/profile',
            data: draft?.toJson(),
            cancelToken: cancel,
            options: Options(
              method: method,
              contentType: Headers.jsonContentType,
              headers: {'Authorization': 'Bearer ${session.token}'},
            ),
          )
          .timeout(
            const Duration(seconds: 30),
            onTimeout: () {
              cancel.cancel();
              throw TimeoutException('Profile request timed out');
            },
          );
      if (session.uid != currentUid()) {
        throw const ProfileFailure(
          'Your session changed. Please sign in again.',
        );
      }
      final status = response.statusCode;
      if (status == 404 && method == 'GET') return null;
      if (status == 401) throw const ProfileFailure('Please sign in again.');
      if (status == 403) {
        throw const ProfileFailure(
          'Verify your email before editing your profile.',
        );
      }
      if (status == 422) {
        throw const ProfileFailure('Please check your profile fields.');
      }
      if (status != 200 || response.data is! Map<String, dynamic>) {
        throw const ProfileFailure(
          'Profile service is unavailable. Please retry.',
        );
      }
      final profile = SavedProfile.fromJson(
        response.data! as Map<String, dynamic>,
      );
      if (profile.uid != session.uid) {
        throw const ProfileFailure('Unable to verify profile ownership.');
      }
      return profile;
    } on ProfileFailure {
      rethrow;
    } catch (_) {
      throw const ProfileFailure(
        'Unable to reach the profile service. Please retry.',
      );
    }
  }

  void close() => _dio.close(force: true);
}
