import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smarthire/app.dart';

void main() {
  for (final width in [360.0, 768.0, 1440.0]) {
    testWidgets('discovery fits a $width pixel viewport', (tester) async {
      tester.view.physicalSize = Size(width, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(const SmartHireApp());
      await tester.pumpAndSettle();
      expect(find.text('Discover opportunities'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.enterText(
        find.byKey(const Key('job-search')),
        'nonexistent',
      );
      await tester.pumpAndSettle();
      expect(
        find.text('No roles found. Try another skill or work mode.'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pumpAndSettle();
      await tester.drag(find.byType(CustomScrollView), const Offset(0, -500));
      await tester.pumpAndSettle();
      final reset = find.text('Reset filters');
      await tester.ensureVisible(reset);
      await tester.pumpAndSettle();
      await tester.tap(reset);
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<TextField>(find.byKey(const Key('job-search')))
            .controller!
            .text,
        isEmpty,
      );
      expect(
        find.text('No roles found. Try another skill or work mode.'),
        findsNothing,
      );
      expect(tester.takeException(), isNull);
    });
  }
}
