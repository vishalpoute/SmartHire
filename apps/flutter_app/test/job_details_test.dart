import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smarthire/app.dart';
import 'package:smarthire/core/routing/app_routes.dart';

void main() {
  for (final width in [360.0, 1440.0]) {
    testWidgets('direct job link supports saving and copying at $width', (
      tester,
    ) async {
      tester.view.physicalSize = Size(width, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      String? copied;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') {
            copied = (call.arguments as Map)['text'] as String;
          }
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );
      await tester.pumpWidget(
        SmartHireApp(initialRoute: AppRoutes.jobDetails('fern-mobile')),
      );
      await tester.pumpAndSettle();
      expect(find.text('About the role'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('Save role'));
      await tester.pumpAndSettle();
      expect(find.text('Saved role'), findsOneWidget);
      await tester.tap(find.text('Copy link'));
      await tester.pumpAndSettle();
      expect(Uri.parse(copied!).fragment, '/jobs/fern-mobile');
      await tester.tap(find.byTooltip('Back to jobs'));
      await tester.pumpAndSettle();
      expect(find.text('Discover opportunities'), findsOneWidget);
      expect(find.byTooltip('Unsave Flutter Developer'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
  testWidgets('unknown role link offers recovery', (tester) async {
    await tester.pumpWidget(const SmartHireApp(initialRoute: '/jobs/missing'));
    await tester.pumpAndSettle();
    expect(find.text('Role unavailable'), findsOneWidget);
    await tester.tap(find.text('Explore jobs'));
    await tester.pumpAndSettle();
    expect(find.text('Discover opportunities'), findsOneWidget);
  });
}
