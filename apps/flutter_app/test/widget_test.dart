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
    });
  }
}
