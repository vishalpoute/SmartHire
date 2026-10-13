import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smarthire/app.dart';

void main() {
  for (final width in [360.0, 1440.0]) {
    testWidgets('account navigation and validation at $width', (tester) async {
      tester.view.physicalSize = Size(width, 1100);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(const SmartHireApp());
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Sign in'));
      await tester.pumpAndSettle();
      expect(find.text('Welcome back.'), findsOneWidget);
      await tester.tap(find.byKey(const Key('account-submit')));
      await tester.pumpAndSettle();
      expect(find.text('Enter your email address'), findsOneWidget);
      await tester.tap(find.text('New to SmartHire? Create an account'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('account-name')),
        'Alex Example',
      );
      await tester.enterText(
        find.byKey(const Key('account-email')),
        'alex@example.com',
      );
      await tester.enterText(
        find.byKey(const Key('account-password')),
        'demo-password',
      );
      await tester.enterText(
        find.byKey(const Key('account-confirm')),
        'mismatch',
      );
      await tester.ensureVisible(find.byKey(const Key('account-submit')));
      await tester.tap(find.byKey(const Key('account-submit')));
      await tester.pumpAndSettle();
      expect(find.text('Passwords must match'), findsOneWidget);
      await tester.enterText(
        find.byKey(const Key('account-confirm')),
        'demo-password',
      );
      await tester.ensureVisible(find.byKey(const Key('account-submit')));
      await tester.tap(find.byKey(const Key('account-submit')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('account-preview-result')), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.ensureVisible(find.text('Explore jobs'));
      await tester.tap(find.text('Explore jobs'));
      await tester.pumpAndSettle();
      expect(find.text('Discover opportunities'), findsOneWidget);
    });
  }
  testWidgets('password reset validates without claiming an email was sent', (
    tester,
  ) async {
    await tester.pumpWidget(const SmartHireApp());
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Sign in'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Forgot password?'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('account-email')), 'invalid');
    await tester.tap(find.byKey(const Key('account-submit')));
    await tester.pumpAndSettle();
    expect(find.text('Enter a valid email address'), findsOneWidget);
    expect(find.byKey(const Key('account-password')), findsNothing);
    expect(find.byKey(const Key('account-preview-result')), findsNothing);
  });
}
