import 'dart:async';

import 'package:dio/dio.dart';

import '../../profile/data/api_profile_repository.dart';
import '../domain/recruiter_review.dart';

class ApiRecruiterReviewRepository implements RecruiterReviewRepository {
  ApiRecruiterReviewRepository({
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
      throw ArgumentError('Review API requires an HTTPS origin.');
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
  Future<ReviewPage> load({String? cursor}) async {
    if (cursor != null && !validReviewText(cursor, 128)) {
      throw const ReviewFailure('Invalid page. Reload the review queue.');
    }
    final json = await _request('GET', cursor: cursor);
    final page = ReviewPage.fromJson(json);
    if (cursor != null && page.nextCursor == cursor) {
      throw const ReviewFailure('Unable to advance. Reload the review queue.');
    }
    return page;
  }

  @override
  Future<void> review(
    ReviewSubmission submission,
    ReviewDecision decision,
    String reason,
  ) async {
    final body = submission.command(decision, reason);
    final json = await _request('POST', body: body);
    if (json['target_uid'] != submission.company.ownerUid ||
        json['decision'] != decision.name) {
      throw const ReviewFailure(
        'Unexpected review response. Reload the queue.',
        reloadRequired: true,
      );
    }
  }

  Future<Map<String, dynamic>> _request(
    String method, {
    String? cursor,
    Map<String, Object>? body,
  }) async {
    final cancel = CancelToken();
    try {
      final identity = await session().timeout(const Duration(seconds: 10));
      if (identity == null ||
          identity.uid.isEmpty ||
          identity.token.isEmpty ||
          !identity.verified ||
          identity.uid != currentUid()) {
        throw const ReviewFailure(
          'Sign in with a verified administrator account.',
        );
      }
      if (body?['target_uid'] == identity.uid) {
        throw const ReviewFailure('You cannot review your own company.');
      }
      final response = await _dio
          .request<Object?>(
            '/api/v1/admin/recruiter-reviews',
            data: body,
            queryParameters: method == 'GET'
                ? {'page_size': 10, 'cursor': ?cursor}
                : null,
            cancelToken: cancel,
            options: Options(
              method: method,
              contentType: Headers.jsonContentType,
              headers: {'Authorization': 'Bearer ${identity.token}'},
            ),
          )
          .timeout(
            const Duration(seconds: 30),
            onTimeout: () {
              cancel.cancel();
              throw TimeoutException('Review request timed out');
            },
          );
      if (identity.uid != currentUid()) {
        throw const ReviewFailure(
          'Your session changed. Please sign in again.',
        );
      }
      if (response.statusCode == 401) {
        throw const ReviewFailure('Please sign in again.');
      }
      if (response.statusCode == 403) {
        throw const ReviewFailure('Administrator access is required.');
      }
      if (response.statusCode == 409) {
        throw const ReviewFailure(
          'This submission changed. Reload before reviewing.',
          reloadRequired: true,
        );
      }
      if (response.statusCode == 429) {
        throw const ReviewFailure('Too many requests. Please wait and retry.');
      }
      if (response.statusCode != 200 ||
          response.data is! Map<String, dynamic>) {
        throw const ReviewFailure(
          'Review service is unavailable. Please retry.',
        );
      }
      return response.data! as Map<String, dynamic>;
    } on ReviewFailure {
      rethrow;
    } catch (_) {
      throw const ReviewFailure('Review service is unavailable. Please retry.');
    }
  }

  void close() => _dio.close(force: true);
}
