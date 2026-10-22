import 'dart:async';

import 'package:dio/dio.dart';

import '../../profile/data/api_profile_repository.dart' show ProfileSession;
import '../domain/company.dart';
import '../domain/company_repository.dart';

/// Reuses the existing verified Firebase session boundary; never caches tokens.
class ApiCompanyRepository implements CompanyRepository {
  ApiCompanyRepository({
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
      throw ArgumentError('Company API requires an HTTPS origin.');
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
  Future<SavedCompany?> load() => _request('GET');

  @override
  Future<SavedCompany> save(CompanyDraft draft) async {
    if (draft.validate().isNotEmpty) {
      throw const CompanyFailure('Please check your company fields.');
    }
    final saved = (await _request('PUT', draft: draft))!;
    if (saved.approval != CompanyApproval.pending) {
      throw const CompanyFailure('Unable to verify company submission.');
    }
    return saved;
  }

  Future<SavedCompany?> _request(String method, {CompanyDraft? draft}) async {
    final cancel = CancelToken();
    try {
      final identity = await session().timeout(const Duration(seconds: 10));
      if (identity == null ||
          identity.uid.isEmpty ||
          identity.token.isEmpty ||
          identity.uid != currentUid()) {
        throw const CompanyFailure('Please sign in again.');
      }
      if (!identity.verified) {
        throw const CompanyFailure(
          'Verify your email before editing your company.',
        );
      }
      final response = await _dio
          .request<Object?>(
            '/api/v1/company',
            data: draft?.toJson(),
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
              throw TimeoutException('Company request timed out');
            },
          );
      if (identity.uid != currentUid()) {
        throw const CompanyFailure(
          'Your session changed. Please sign in again.',
        );
      }
      final status = response.statusCode;
      if (status == 404 && method == 'GET') return null;
      if (status == 401) throw const CompanyFailure('Please sign in again.');
      if (status == 403) {
        throw const CompanyFailure('You do not have access to this company.');
      }
      if (status == 429) {
        throw const CompanyFailure('Too many requests. Please wait and retry.');
      }
      if (status == 422) {
        throw const CompanyFailure('Please check your company fields.');
      }
      if (status != 200 || response.data is! Map<String, dynamic>) {
        throw const CompanyFailure(
          'Company service is unavailable. Please retry.',
        );
      }
      return SavedCompany.fromJson(
        response.data! as Map<String, dynamic>,
        expectedOwnerUid: identity.uid,
      );
    } on CompanyFailure {
      rethrow;
    } catch (_) {
      throw const CompanyFailure(
        'Unable to reach the company service. Please retry.',
      );
    }
  }

  void close() => _dio.close(force: true);
}
