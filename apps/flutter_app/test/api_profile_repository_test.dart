import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smarthire/features/profile/data/api_profile_repository.dart';
import 'package:smarthire/features/profile/domain/profile.dart';

class Adapter implements HttpClientAdapter {
  int status = 200;
  Object body = {
    'uid': 'owner',
    'display_name': 'Ada',
    'headline': '',
    'location': '',
    'skills': ['Dart'],
    'updated_at': '2026-10-18T00:00:00Z',
  };
  RequestOptions? request;
  void Function()? beforeResponse;
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? stream,
    Future<void>? cancelFuture,
  ) async {
    request = options;
    beforeResponse?.call();
    return ResponseBody.fromString(
      jsonEncode(body),
      status,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  late Adapter adapter;
  late ApiProfileRepository repo;
  String? uid = 'owner';
  bool verified = true;
  bool signedIn = true;
  setUp(() {
    uid = 'owner';
    verified = true;
    signedIn = true;
    adapter = Adapter();
    repo = ApiProfileRepository(
      origin: Uri.parse('https://api.example.com'),
      adapter: adapter,
      currentUid: () => uid,
      session: () async => signedIn
          ? ProfileSession(
              uid: 'owner',
              token: 'test-token',
              verified: verified,
            )
          : null,
    );
  });
  tearDown(() => repo.close());
  test(
    'GET uses bearer header, fixed ownerless path and bounded transport',
    () async {
      expect((await repo.load())!.uid, 'owner');
      final request = adapter.request!;
      expect(request.uri.toString(), 'https://api.example.com/api/v1/profile');
      expect(request.headers['Authorization'], 'Bearer test-token');
      expect(request.followRedirects, isFalse);
      expect(request.connectTimeout, const Duration(seconds: 10));
    },
  );
  test('PUT only sends editable fields', () async {
    await repo.save(ProfileDraft(displayName: 'Ada', skills: [' Dart ']));
    expect(adapter.request!.method, 'PUT');
    expect(adapter.request!.data, {
      'display_name': 'Ada',
      'headline': '',
      'location': '',
      'skills': ['Dart'],
    });
  });
  test('absent profile is empty only for GET', () async {
    adapter.status = 404;
    expect(await repo.load(), isNull);
    await expectLater(
      repo.save(ProfileDraft(displayName: 'Ada')),
      throwsA(isA<ProfileFailure>()),
    );
  });
  test(
    'missing or unverified session and invalid draft never send data',
    () async {
      signedIn = false;
      await expectLater(repo.load(), throwsA(isA<ProfileFailure>()));
      signedIn = true;
      verified = false;
      await expectLater(repo.load(), throwsA(isA<ProfileFailure>()));
      await expectLater(
        repo.save(ProfileDraft(displayName: '')),
        throwsA(isA<ProfileFailure>()),
      );
      expect(adapter.request, isNull);
    },
  );
  test('wrong owner and session change reject successful response', () async {
    adapter.body = {...adapter.body as Map, 'uid': 'another'};
    await expectLater(repo.load(), throwsA(isA<ProfileFailure>()));
    adapter.beforeResponse = () => uid = null;
    await expectLater(repo.load(), throwsA(isA<ProfileFailure>()));
  });
  test('errors and malformed bodies never expose server diagnostics', () async {
    for (final status in [401, 403, 422, 500, 302, 200]) {
      adapter.status = status;
      adapter.body = {'secret': 'internal diagnostic'};
      await expectLater(
        repo.load(),
        throwsA(
          isA<ProfileFailure>().having(
            (e) => e.message,
            'safe message',
            isNot(contains('diagnostic')),
          ),
        ),
      );
    }
  });
  test('insecure or credential-bearing destinations are rejected', () {
    for (final url in [
      'http://api.example.com',
      'https://user:pass@api.example.com',
      'https://api.example.com/path',
    ]) {
      expect(
        () => ApiProfileRepository(
          origin: Uri.parse(url),
          session: () async => null,
          currentUid: () => null,
        ),
        throwsArgumentError,
      );
    }
  });
}
