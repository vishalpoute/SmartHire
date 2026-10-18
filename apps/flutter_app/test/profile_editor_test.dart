import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smarthire/features/profile/domain/profile.dart';
import 'package:smarthire/features/profile/domain/profile_repository.dart';
import 'package:smarthire/features/profile/presentation/profile_cubit.dart';
import 'package:smarthire/features/profile/presentation/profile_editor.dart';

class Profiles implements ProfileRepository {
  bool fail = true;
  int writes = 0;
  @override
  Future<SavedProfile?> load() async => null;
  @override
  Future<SavedProfile> save(ProfileDraft draft) async {
    writes++;
    if (fail) throw Exception('private server error');
    return SavedProfile(
      uid: 'owner',
      updatedAt: DateTime.utc(2026),
      draft: draft,
    );
  }
}

void main() {
  testWidgets('back preserves drafts until explicit discard', (tester) async {
    final cubit = ProfileCubit(Profiles());
    addTearDown(cubit.close);
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute<void>(
                  builder: (_) => Scaffold(
                    appBar: AppBar(),
                    body: BlocProvider.value(
                      value: cubit,
                      child: const ProfileEditor(),
                    ),
                  ),
                ),
              ),
              child: const Text('Open editor'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open editor'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, 'Ada');
    await tester.pump();
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('Discard unsaved changes?'), findsOneWidget);
    await tester.tap(find.text('Keep editing'));
    await tester.pumpAndSettle();
    expect(find.text('Ada'), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.tap(find.text('Discard changes'));
    await tester.pumpAndSettle();
    expect(find.text('Open editor'), findsOneWidget);
    expect(find.byType(TextField), findsNothing);
  });
  testWidgets('successful save permits leaving without discard prompt', (
    tester,
  ) async {
    final repo = Profiles()..fail = false;
    final cubit = ProfileCubit(repo);
    addTearDown(cubit.close);
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute<void>(
                  builder: (_) => Scaffold(
                    appBar: AppBar(),
                    body: BlocProvider.value(
                      value: cubit,
                      child: const ProfileEditor(),
                    ),
                  ),
                ),
              ),
              child: const Text('Open editor'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open editor'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, 'Ada');
    await tester.pump();
    await tester.ensureVisible(find.text('Save profile'));
    await tester.tap(find.text('Save profile'));
    await tester.pumpAndSettle();
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('Open editor'), findsOneWidget);
    expect(find.text('Discard unsaved changes?'), findsNothing);
  });
  for (final width in [360.0, 1440.0]) {
    testWidgets('editor validates and preserves failed edits at $width', (
      tester,
    ) async {
      tester.view.physicalSize = Size(width, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final repo = Profiles();
      final cubit = ProfileCubit(repo);
      addTearDown(cubit.close);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: BlocProvider.value(
              value: cubit,
              child: const ProfileEditor(),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Save profile'));
      await tester.pumpAndSettle();
      expect(find.text('Use between 2 and 80 characters.'), findsOneWidget);
      expect(repo.writes, 0);
      await tester.enterText(find.byType(TextField).at(0), 'Ada');
      await tester.enterText(find.byType(TextField).at(3), 'Dart, Flutter');
      await tester.ensureVisible(find.text('Save profile'));
      await tester.tap(find.text('Save profile'));
      await tester.pumpAndSettle();
      expect(
        find.text('Unable to save your profile. Your edits are still here.'),
        findsOneWidget,
      );
      expect(find.text('Ada'), findsOneWidget);
      expect(find.text('private server error'), findsNothing);
      repo.fail = false;
      await tester.ensureVisible(find.text('Save profile'));
      await tester.tap(find.text('Save profile'));
      await tester.pumpAndSettle();
      expect(find.text('Profile saved.'), findsOneWidget);
      expect(repo.writes, 2);
      expect(tester.takeException(), isNull);
    });
  }
}
