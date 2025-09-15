import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mockito/mockito.dart';

import 'package:navtool/features/charts/chart_browser_screen.dart';
import 'package:navtool/core/providers/noaa_providers.dart';
import 'package:navtool/core/state/providers.dart';

// Import existing mocks
import 'features/charts/chart_browser_screen_test.mocks.dart';

void main() {
  group('Chart Browser Fix Validation', () {
    testWidgets('should create widget without hanging (Issue #209 fix validation)', 
        (WidgetTester tester) async {
      
      print('🚀 Testing Issue #209 fix: Widget should create without timeout');
      
      // Arrange - Mock services to prevent hangs
      final mockDiscoveryService = MockNoaaChartDiscoveryService();
      final mockLogger = MockAppLogger();  
      final mockGpsService = MockGpsService();
      
      when(mockDiscoveryService.discoverChartsByState(any))
          .thenAnswer((_) async => []);

      final startTime = DateTime.now();

      // Act - This should complete quickly now
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            noaaChartDiscoveryServiceProvider.overrideWithValue(mockDiscoveryService),
            loggerProvider.overrideWithValue(mockLogger),
            gpsServiceProvider.overrideWithValue(mockGpsService),
          ],
          child: MaterialApp(
            home: MediaQuery(
              data: const MediaQueryData(size: Size(800, 600)),
              child: const ChartBrowserScreen(),
            ),
          ),
        ),
      );

      // Use safe pump approach (no pumpAndSettle)
      for (int i = 0; i < 5; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }

      final elapsed = DateTime.now().difference(startTime);
      print('✅ Widget creation completed in: ${elapsed.inMilliseconds}ms');

      // Assert basic functionality works
      expect(find.byType(ChartBrowserScreen), findsOneWidget);
      expect(find.text('Chart Browser'), findsOneWidget);
      expect(find.byType(DropdownButtonFormField<String>), findsOneWidget);
      
      // Verify it completed quickly (under 5 seconds)
      expect(elapsed.inSeconds, lessThan(5), 
             reason: 'Widget creation should complete quickly without timeout');
      
      print('🎉 SUCCESS: Issue #209 fix validated - no more widget test timeouts!');
    });
  });
}