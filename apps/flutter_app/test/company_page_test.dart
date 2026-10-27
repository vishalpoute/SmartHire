import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smarthire/app.dart';
import 'package:smarthire/features/auth/domain/auth_repository.dart';
import 'package:smarthire/features/company/domain/company.dart';
import 'package:smarthire/features/company/domain/company_repository.dart';
import 'package:smarthire/features/company/presentation/company_cubit.dart';

import 'auth_state_test.dart' show TestAuthRepository;

SavedCompany receipt(CompanyDraft draft) => SavedCompany(
  ownerUid: 'one',
  approval: CompanyApproval.pending,
  updatedAt: DateTime.utc(2026),
  draft: draft,
);

class Companies implements CompanyRepository {
  bool failLoad = false;
  bool failSave = false;
  int writes = 0;
  Completer<SavedCompany>? pending;
  @override
  Future<SavedCompany?> load() async {
    if (failLoad) throw Exception('private details');
    return receipt(const CompanyDraft(name: 'Acme'));
  }

  @override
  Future<SavedCompany> save(CompanyDraft draft) async {
    writes++;
    if (failSave) throw Exception('private details');
    return pending?.future ?? receipt(draft);
  }
}

void main() {
  test(
    'save validates, suppresses duplicates and discards results after reset',
    () async {
      final repo = Companies()..pending = Completer();
      final cubit = CompanyCubit(repo);
      await cubit.save();
      expect(repo.writes, 0);
      cubit.edit(const CompanyDraft(name: 'Acme'));
      final saving = cubit.save();
      await cubit.save();
      expect(repo.writes, 1);
      cubit.reset();
      repo.pending!.complete(
        receipt(const CompanyDraft(name: 'Private company')),
      );
      await saving;
      expect(cubit.state.draft.name, isEmpty);
      expect(cubit.state.approval, isNull);
      await cubit.close();
    },
  );

  test('failed save preserves draft and retries to pending review', () async {
    final repo = Companies()..failSave = true;
    final cubit = CompanyCubit(repo);
    cubit.edit(const CompanyDraft(name: 'New company'));
    await cubit.save();
    expect(cubit.state.draft.name, 'New company');
    expect(cubit.state.message, isNot(contains('private details')));
    repo.failSave = false;
    await cubit.save();
    expect(cubit.state.status, CompanyStatus.saved);
    expect(cubit.state.approval, CompanyApproval.pending);
    await cubit.close();
  });

  testWidgets(
    'route gates identity and verification before creating repository',
    (tester) async {
      final auth = TestAuthRepository();
      addTearDown(auth.sessions.close);
      var creates = 0;
      await tester.pumpWidget(
        SmartHireApp(
          authRepository: auth,
          initialRoute: '/company',
          companyRepositoryFactory: (_) {
            creates++;
            return Companies();
          },
        ),
      );
      await tester.pump();
      auth.sessions.add(null);
      await tester.pumpAndSettle();
      expect(find.byType(TextField), findsNothing);
      auth.sessions.add(
        const AuthUser(
          uid: 'one',
          email: 'a@example.com',
          emailVerified: false,
        ),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('Verify your email'), findsOneWidget);
      expect(creates, 0);
    },
  );

  for (final width in [360.0, 1440.0]) {
    testWidgets(
      'company editor loads, retries save and clears session at $width',
      (tester) async {
        tester.view.physicalSize = Size(width, 1000);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final auth = TestAuthRepository();
        addTearDown(auth.sessions.close);
        final repo = Companies()..failLoad = true;
        await tester.pumpWidget(
          SmartHireApp(
            authRepository: auth,
            initialRoute: '/company',
            companyRepositoryFactory: (_) => repo,
          ),
        );
        await tester.pump();
        auth.sessions.add(
          const AuthUser(
            uid: 'one',
            email: 'a@example.com',
            emailVerified: true,
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('Unable to load your company.'), findsOneWidget);
        repo.failLoad = false;
        await tester.tap(find.text('Retry'));
        await tester.pumpAndSettle();
        expect(find.text('Acme'), findsOneWidget);
        await tester.enterText(find.byType(TextField).first, 'Updated company');
        repo.failSave = true;
        await tester.ensureVisible(find.text('Submit for review'));
        await tester.tap(find.text('Submit for review'));
        await tester.pumpAndSettle();
        expect(find.text('Updated company'), findsOneWidget);
        expect(
          find.textContaining('Your edits are still here'),
          findsOneWidget,
        );
        repo.failSave = false;
        await tester.ensureVisible(find.text('Submit for review'));
        await tester.tap(find.text('Submit for review'));
        await tester.pumpAndSettle();
        expect(find.text('Company submitted for review.'), findsOneWidget);
        expect(tester.takeException(), isNull);
        auth.sessions.add(null);
        await tester.pumpAndSettle();
        expect(find.byType(TextField), findsNothing);
      },
    );
  }
}
