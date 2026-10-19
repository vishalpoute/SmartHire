import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smarthire/app.dart';
import 'package:smarthire/features/jobs/domain/public_jobs_repository.dart';
import 'package:smarthire/features/jobs/presentation/public_jobs_cubit.dart';

PublishedJob fixture(String id) => PublishedJob(
  id: id,
  title: 'Published role',
  company: 'Approved company',
  description: 'Role description',
  location: '',
  workMode: PublishedWorkMode.remote,
  employmentType: EmploymentType.fullTime,
  requiredSkills: ['Dart'],
  preferredSkills: [],
  publishedAt: DateTime.utc(2026),
);

class Repository implements PublicJobsRepository {
  final requests = <String?>[];
  Future<PublicJobsPage> Function(String?)? handler;
  bool failDetail = false;
  @override
  Future<PublicJobsPage> page({int pageSize = 10, String? cursor}) {
    requests.add(cursor);
    return handler?.call(cursor) ?? Future.value(PublicJobsPage(items: []));
  }

  @override
  Future<PublishedJob?> detail(String id) async {
    if (failDetail) throw Exception('private');
    return fixture(id);
  }
}

void main() {
  test('sparse pages continue, duplicate clicks guarded and failures retry same cursor', () async {
    final repo = Repository();
    final pending = Completer<PublicJobsPage>();
    repo.handler = (cursor) async => cursor == null
        ? PublicJobsPage(items: [], nextCursor: 'cursor')
        : pending.future;
    final cubit = PublicJobsCubit(repo);
    addTearDown(cubit.close);
    await cubit.refresh();
    final loading = cubit.loadMore();
    await cubit.loadMore();
    expect(repo.requests, [null, 'cursor']);
    pending.completeError(Exception('private diagnostics'));
    await loading;
    expect(cubit.state.nextCursor, 'cursor');
    expect(cubit.state.error, isNot(contains('private')));
    repo.handler = (_) async => PublicJobsPage(items: [fixture('one')]);
    await cubit.loadMore();
    expect(cubit.state.items.single.id, 'one');
    expect(cubit.state.error, isNull);
    expect(cubit.state.nextCursor, isNull);
  });
  test(
    'refresh supersedes late load-more response and close prevents emissions',
    () async {
      final repo = Repository();
      final stale = Completer<PublicJobsPage>();
      repo.handler = (cursor) async => cursor == null
          ? PublicJobsPage(items: [], nextCursor: 'cursor')
          : stale.future;
      final cubit = PublicJobsCubit(repo);
      await cubit.refresh();
      final loading = cubit.loadMore();
      repo.handler = (_) async => PublicJobsPage(items: [fixture('fresh')]);
      await cubit.refresh();
      stale.complete(PublicJobsPage(items: [fixture('stale')]));
      await loading;
      expect(cubit.state.items.single.id, 'fresh');
      final late = Completer<PublicJobsPage>();
      repo.handler = (_) => late.future;
      final refreshing = cubit.refresh();
      await cubit.close();
      late.complete(PublicJobsPage(items: [fixture('after-close')]));
      await refreshing;
    },
  );
  for (final width in [360.0, 1440.0]) {
    testWidgets(
      'live discovery empty state fits $width without fictional fallback',
      (tester) async {
        tester.view.physicalSize = Size(width, 900);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await tester.pumpWidget(
          SmartHireApp(publicJobsRepository: Repository()),
        );
        await tester.pumpAndSettle();
        expect(find.textContaining('No published roles yet'), findsOneWidget);
        expect(find.textContaining('Fictional jobs'), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );
  }
  testWidgets('load more and direct details use live repository', (
    tester,
  ) async {
    final repo = Repository();
    repo.handler = (cursor) async => PublicJobsPage(items: [fixture('1' * 32)]);
    await tester.pumpWidget(SmartHireApp(publicJobsRepository: repo));
    await tester.pumpAndSettle();
    await tester.tap(find.text('View role'));
    await tester.pumpAndSettle();
    expect(find.text('Role description'), findsOneWidget);
    expect(
      find.text('Applications are not available in this preview.'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });
  testWidgets(
    'initial failure retries without exposing repository diagnostics',
    (tester) async {
      final repo = Repository();
      repo.handler = (_) async => throw Exception('private diagnostic');
      await tester.pumpWidget(SmartHireApp(publicJobsRepository: repo));
      await tester.pumpAndSettle();
      expect(find.text('Could not load jobs. Please retry.'), findsOneWidget);
      expect(find.textContaining('private diagnostic'), findsNothing);
      repo.handler = (_) async => PublicJobsPage(items: []);
      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();
      expect(find.textContaining('No published roles yet'), findsOneWidget);
    },
  );
}
