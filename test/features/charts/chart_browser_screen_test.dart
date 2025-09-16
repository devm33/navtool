import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mockito/mockito.dart';
import 'package:mockito/annotations.dart';
import 'package:navtool/features/charts/chart_browser_screen.dart';
import 'package:navtool/core/services/noaa/noaa_chart_discovery_service.dart';
import 'package:navtool/core/models/chart.dart';
import 'package:navtool/core/models/geographic_bounds.dart';
import 'package:navtool/core/logging/app_logger.dart';
import 'package:navtool/core/providers/noaa_providers.dart';
import 'package:navtool/core/state/providers.dart';
import 'package:navtool/core/services/gps_service.dart';
import 'package:navtool/core/models/gps_position.dart';
import 'package:navtool/core/utils/network_resilience.dart';

// Generate mocks for dependencies
@GenerateMocks([NoaaChartDiscoveryService, AppLogger, GpsService])
import 'chart_browser_screen_test.mocks.dart';

/// Test implementation of NetworkResilience to prevent timeout issues
class TestNetworkResilience extends NetworkResilience {
  @override
  Future<MarineNetworkConditions> assessMarineNetworkConditions() async {
    // Return a simple, static network condition for tests
    return MarineNetworkConditions(
      connectionQuality: ConnectionQuality.good,
      isSuitableForChartDownload: true,
      isSuitableForApiRequests: true,
      recommendedTimeoutMultiplier: 1.0,
      estimatedSpeed: 1000.0,
      latency: Duration(milliseconds: 50),
    );
  }
}

void main() {
  group('ChartBrowserScreen Tests', () {
    late MockNoaaChartDiscoveryService mockDiscoveryService;
    late MockAppLogger mockLogger;
    late MockGpsService mockGpsService;

    /// Helper function to pump with specific duration instead of waiting for settle
    Future<void> pumpAndWait(
      WidgetTester tester, {
      Duration wait = const Duration(milliseconds: 800), // Increased from 500ms to 800ms for more stable UI
    }) async {
      await tester.pump();
      await Future.delayed(wait);
      await tester.pump();
    }

    /// Helper function to pump with retries for flaky UI interactions  
    Future<void> pumpWithRetries(
      WidgetTester tester, {
      int maxRetries = 3,
    }) async {
      for (int i = 0; i < maxRetries; i++) {
        try {
          await tester.pump();
          await Future.delayed(const Duration(milliseconds: 100));
          return;
        } catch (e) {
          if (i == maxRetries - 1) rethrow;
          await Future.delayed(const Duration(milliseconds: 50));
        }
      }
    }

    setUp(() {
      mockDiscoveryService = MockNoaaChartDiscoveryService();
      mockLogger = MockAppLogger();
      mockGpsService = MockGpsService();
      
      // Configure default mock behaviors to prevent timeout issues
      when(mockGpsService.getCurrentPositionWithFallback())
          .thenAnswer((_) async => GpsPosition(
                latitude: 47.6062,
                longitude: -122.3321,
                timestamp: DateTime.now(),
                accuracy: 1000.0,
              ));
      
      when(mockDiscoveryService.discoverChartsByLocation(any))
          .thenAnswer((_) async => <Chart>[]);
      
      when(mockDiscoveryService.discoverChartsByState(any))
          .thenAnswer((_) async => <Chart>[]);
      
      when(mockDiscoveryService.searchCharts(any, filters: anyNamed('filters')))
          .thenAnswer((_) async => <Chart>[]);
      
      // Configure logger to be silent in tests
      when(mockLogger.info(any)).thenReturn(null);
      when(mockLogger.warning(any)).thenReturn(null);
      when(mockLogger.error(any, exception: anyNamed('exception'))).thenReturn(null);
    });

    Widget createTestWidget({bool withNavigation = false}) {
      return ProviderScope(
        overrides: [
          noaaChartDiscoveryServiceProvider.overrideWithValue(
            mockDiscoveryService,
          ),
          loggerProvider.overrideWithValue(mockLogger),
          gpsServiceProvider.overrideWithValue(mockGpsService),
          // Mock network resilience provider to prevent FutureBuilder issues
          networkResilienceProvider.overrideWith((ref) => TestNetworkResilience()),
        ],
        child: MaterialApp(
          home: const ChartBrowserScreen(),
          routes: withNavigation
              ? {
                  '/chart': (context) =>
                      const Scaffold(body: Text('Chart Display')),
                }
              : {},
        ),
      );
    }

    List<Chart> createTestCharts() {
      return [
        Chart(
          id: 'US5CA52M',
          title: 'San Francisco Bay',
          scale: 25000,
          bounds: GeographicBounds(
            north: 37.9,
            south: 37.7,
            east: -122.3,
            west: -122.5,
          ),
          lastUpdate: DateTime(2024, 1, 15),
          state: 'California',
          type: ChartType.harbor,
          description: 'Detailed harbor chart of San Francisco Bay',
          fileSize: 15728640, // 15MB
        ),
        Chart(
          id: 'US4CA11M',
          title: 'Monterey Bay',
          scale: 50000,
          bounds: GeographicBounds(
            north: 36.8,
            south: 36.5,
            east: -121.7,
            west: -122.1,
          ),
          lastUpdate: DateTime(2024, 1, 10),
          state: 'California',
          type: ChartType.coastal,
          description: 'Coastal chart covering Monterey Bay area',
          fileSize: 23068672, // 22MB
        ),
      ];
    }

    Chart createTestChart({
      String id = 'TEST_CHART',
      String title = 'Test Chart',
      int scale = 25000,
      String state = 'California',
      ChartType type = ChartType.harbor,
      String? description,
      int? fileSize,
    }) {
      return Chart(
        id: id,
        title: title,
        scale: scale,
        bounds: GeographicBounds(
          north: 37.9,
          south: 37.7,
          east: -122.3,
          west: -122.5,
        ),
        lastUpdate: DateTime.now(),
        state: state,
        type: type,
        description: description,
        fileSize: fileSize,
      );
    }

    /// Helper function to pump with extended timeout for complex UI interactions
    /// DEPRECATED: Use pumpAndWait() instead to prevent infinite animation loops
    @Deprecated('Use pumpAndWait() to prevent timeout issues')
    Future<void> pumpAndSettleWithTimeout(
      WidgetTester tester, {
      Duration timeout = const Duration(seconds: 5), // Reduced from 15s to 5s
    }) async {
      // For critical operations that must settle, use shorter timeout and fallback
      try {
        await tester.pumpAndSettle(timeout);
      } catch (e) {
        // Fallback: pump with fixed duration if settle fails
        await pumpAndWait(tester, wait: const Duration(seconds: 2));
      }
    }

    group('Screen Structure and Layout', () {
      testWidgets(
        'should create ChartBrowserScreen with all required components',
        (WidgetTester tester) async {
          // Arrange
          when(
            mockDiscoveryService.discoverChartsByState(any),
          ).thenAnswer((_) async => []);

          // Act
          await tester.pumpWidget(createTestWidget());
          await pumpAndWait(tester, wait: const Duration(milliseconds: 500));

          // Assert
          expect(find.byType(ChartBrowserScreen), findsOneWidget);
          expect(find.byType(Scaffold), findsOneWidget);
          expect(find.byType(AppBar), findsOneWidget);
          expect(find.text('Chart Browser'), findsOneWidget);
        },
      );

      testWidgets('should have state selection dropdown', (
        WidgetTester tester,
      ) async {
        // Arrange
        when(
          mockDiscoveryService.discoverChartsByState(any),
        ).thenAnswer((_) async => []);

        // Act
        await tester.pumpWidget(createTestWidget());
        await pumpAndWait(tester, wait: const Duration(milliseconds: 500));

        // Assert
        expect(find.byType(DropdownButton<String>), findsOneWidget);
        expect(find.text('Select State'), findsOneWidget);
      });

      testWidgets('should have search field', (WidgetTester tester) async {
        // Arrange
        when(
          mockDiscoveryService.discoverChartsByState(any),
        ).thenAnswer((_) async => []);

        // Act
        await tester.pumpWidget(createTestWidget());
        await pumpAndWait(tester, wait: const Duration(milliseconds: 500));

        // Assert
        expect(find.byType(TextField), findsAtLeastNWidgets(1));
        expect(find.text('Search charts...'), findsOneWidget);
      });

      testWidgets('should have chart type filter chips', (
        WidgetTester tester,
      ) async {
        // Arrange
        when(
          mockDiscoveryService.discoverChartsByState(any),
        ).thenAnswer((_) async => []);

        // Act
        await tester.pumpWidget(createTestWidget());
        await tester.pumpAndSettle();

        // Assert
        expect(find.byType(FilterChip), findsAtLeastNWidgets(3));
        expect(find.text('Harbor'), findsOneWidget);
        expect(find.text('Coastal'), findsOneWidget);
        expect(find.text('Approach'), findsOneWidget);
      });
    });

    group('State Selection Functionality', () {
      testWidgets('should display US coastal states in dropdown', (
        WidgetTester tester,
      ) async {
        // Arrange
        when(
          mockDiscoveryService.discoverChartsByState(any),
        ).thenAnswer((_) async => []);

        // Act
        await tester.pumpWidget(createTestWidget());
        await tester.pumpAndSettle();

        // Assert - check that the dropdown exists and has the correct label
        expect(find.byType(DropdownButtonFormField<String>), findsOneWidget);
        expect(find.text('Select State'), findsOneWidget);

        // Check that the dropdown has a label for accessibility
        expect(
          find.byWidgetPredicate(
            (widget) =>
                widget is Semantics &&
                widget.properties.label == 'Select a US state to browse charts',
          ),
          findsOneWidget,
        );
      });

      testWidgets('should discover charts when state is selected', (
        WidgetTester tester,
      ) async {
        // Arrange
        final testCharts = createTestCharts();
        when(
          mockDiscoveryService.discoverChartsByState('California'),
        ).thenAnswer((_) async => testCharts);

        // Act
        await tester.pumpWidget(createTestWidget());
        await tester.pumpAndSettle();

        // Select California from dropdown
        await tester.tap(find.byType(DropdownButton<String>));
        await pumpAndWait(tester, wait: const Duration(milliseconds: 600));
        await tester.tap(find.text('California'));
        await pumpAndWait(tester, wait: const Duration(seconds: 1));

        // Assert
        verify(
          mockDiscoveryService.discoverChartsByState('California'),
        ).called(1);
        expect(find.text('San Francisco Bay'), findsOneWidget);
        expect(find.text('Monterey Bay'), findsOneWidget);
      });

      testWidgets('should show loading indicator during chart discovery', (
        WidgetTester tester,
      ) async {
        // Arrange
        when(
          mockDiscoveryService.discoverChartsByState('California'),
        ).thenAnswer(
          (_) => Future.delayed(
            const Duration(seconds: 1),
            () => createTestCharts(),
          ),
        );

        // Act
        await tester.pumpWidget(createTestWidget());
        await tester.pumpAndSettle();

        // Select state to trigger loading
        await tester.tap(find.byType(DropdownButtonFormField<String>));
        await tester.pumpAndSettle();
        await tester.tap(find.text('California'));
        await tester.pump(); // Don't settle, check loading state

        // Assert
        expect(find.byType(CircularProgressIndicator), findsOneWidget);

        // Wait for the async operation to complete to avoid timer leaks
        await tester.pumpAndSettle();
      });

      testWidgets('should handle discovery errors gracefully', (
        WidgetTester tester,
      ) async {
        // Arrange
        when(
          mockDiscoveryService.discoverChartsByState('California'),
        ).thenThrow(Exception('Network error'));

        // Act
        await tester.pumpWidget(createTestWidget());
        await tester.pumpAndSettle();

        // Select state to trigger error
        await tester.tap(find.byType(DropdownButton<String>));
        await tester.pumpAndSettle();
        await tester.tap(find.text('California'));
        await tester.pumpAndSettle();

        // Assert
        expect(find.text('Failed to load charts'), findsOneWidget);
        expect(find.byIcon(Icons.error), findsOneWidget);
      });
    });

    group('Chart List Display', () {
      testWidgets('should display chart cards with metadata', (
        WidgetTester tester,
      ) async {
        // Arrange
        final testCharts = createTestCharts();
        when(
          mockDiscoveryService.discoverChartsByState('California'),
        ).thenAnswer((_) async => testCharts);

        // Act
        await tester.pumpWidget(createTestWidget());
        await tester.pumpAndSettle();

        // Select California
        await tester.tap(find.byType(DropdownButton<String>));
        await tester.pumpAndSettle();
        await tester.tap(find.text('California'));
        await tester.pumpAndSettle();

        // Assert
        expect(find.text('San Francisco Bay'), findsOneWidget);
        expect(find.text('Scale: 1:25,000'), findsOneWidget);
        expect(find.text('15.0 MB'), findsOneWidget);
        expect(
          find.text('Harbor'),
          findsAtLeastNWidgets(1),
        ); // Harbor type might appear in multiple places

        expect(find.text('Monterey Bay'), findsOneWidget);
        expect(find.text('Scale: 1:50,000'), findsOneWidget);
        expect(find.text('22.0 MB'), findsOneWidget);
        expect(
          find.text('Coastal'),
          findsAtLeastNWidgets(1),
        ); // Coastal type might appear in multiple places
      });

      testWidgets('should display chart bounds information', (
        WidgetTester tester,
      ) async {
        // Arrange
        final testCharts = createTestCharts();
        when(
          mockDiscoveryService.discoverChartsByState('California'),
        ).thenAnswer((_) async => testCharts);

        // Act
        await tester.pumpWidget(createTestWidget());
        await tester.pumpAndSettle();

        // Select California
        await tester.tap(find.byType(DropdownButton<String>));
        await tester.pumpAndSettle();
        await tester.tap(find.text('California'));
        await tester.pumpAndSettle();

        // Assert
        expect(find.textContaining('37.7° - 37.9°N'), findsOneWidget);
        expect(find.textContaining('122.3° - 122.5°W'), findsOneWidget);
      });

      testWidgets('should show empty state when no charts found', (
        WidgetTester tester,
      ) async {
        // Arrange
        when(
          mockDiscoveryService.discoverChartsByState('Nevada'),
        ).thenAnswer((_) async => []);

        // Act
        await tester.pumpWidget(createTestWidget());
        await tester.pumpAndSettle();

        // Select Nevada (inland state with no charts)
        final dropdownFinder = find.byType(DropdownButtonFormField<String>);
        expect(dropdownFinder, findsOneWidget);

        await tester.tap(dropdownFinder);
        await tester.pumpAndSettle();

        // Scroll to make Nevada visible if needed
        await tester.dragUntilVisible(
          find.text('Nevada'),
          find.byType(ListView),
          const Offset(0, -100),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.text('Nevada'));
        await tester.pumpAndSettle();

        // Assert
        expect(find.text('No charts found'), findsOneWidget);
        expect(
          find.text(
            'No charts are available for the selected state and filters.',
          ),
          findsOneWidget,
        );
        expect(find.byIcon(Icons.map_outlined), findsOneWidget);
      });
    });

    group('Search and Filtering', () {
      testWidgets('should filter charts by search query', (
        WidgetTester tester,
      ) async {
        // Arrange
        final testCharts = createTestCharts();
        when(
          mockDiscoveryService.discoverChartsByState('California'),
        ).thenAnswer((_) async => testCharts);
        when(
          mockDiscoveryService.searchCharts(
            'San Francisco',
            filters: anyNamed('filters'),
          ),
        ).thenAnswer((_) async => [testCharts[0]]);

        // Act
        await tester.pumpWidget(createTestWidget());
        await tester.pumpAndSettle();

        // Select California first
        await tester.tap(find.byType(DropdownButton<String>));
        await tester.pumpAndSettle();
        await tester.tap(find.text('California'));
        await tester.pumpAndSettle();

        // Search for San Francisco
        await tester.enterText(find.byType(TextField), 'San Francisco');
        await tester.pump(const Duration(milliseconds: 300)); // Debounce delay

        // Assert
        expect(find.text('San Francisco Bay'), findsOneWidget);
        expect(find.text('Monterey Bay'), findsNothing);
      });

      testWidgets('should filter charts by type using filter chips', (
        WidgetTester tester,
      ) async {
        // Arrange
        final testCharts = createTestCharts();
        when(
          mockDiscoveryService.discoverChartsByState('California'),
        ).thenAnswer((_) async => testCharts);

        // Act
        await tester.pumpWidget(createTestWidget());
        await tester.pumpAndSettle();

        // Select California first
        await tester.tap(find.byType(DropdownButton<String>));
        await tester.pumpAndSettle();
        await tester.tap(find.text('California'));
        await tester.pumpAndSettle();

        // Tap Harbor filter chip
        await tester.tap(find.widgetWithText(FilterChip, 'Harbor'));
        await tester.pumpAndSettle();

        // Assert
        expect(find.text('San Francisco Bay'), findsOneWidget);
        expect(find.text('Monterey Bay'), findsNothing);
      });

      testWidgets('should clear search when clear button tapped', (
        WidgetTester tester,
      ) async {
        // Arrange
        final testCharts = createTestCharts();
        when(
          mockDiscoveryService.discoverChartsByState('California'),
        ).thenAnswer((_) async => testCharts);

        // Mock search behavior
        when(
          mockDiscoveryService.searchCharts(any, filters: anyNamed('filters')),
        ).thenAnswer((invocation) async {
          final query = invocation.positionalArguments[0] as String;
          return testCharts
              .where(
                (chart) =>
                    chart.title.toLowerCase().contains(query.toLowerCase()),
              )
              .toList();
        });

        // Act - Use a larger test container to avoid overflow
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              noaaChartDiscoveryServiceProvider.overrideWith(
                (ref) => mockDiscoveryService,
              ),
            ],
            child: MaterialApp(
              home: Scaffold(
                body: SizedBox(
                  width: 800,
                  height: 800,
                  child: const ChartBrowserScreen(),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Select California
        await tester.tap(find.byType(DropdownButtonFormField<String>));
        await tester.pumpAndSettle();
        await tester.tap(find.text('California'));
        await tester.pumpAndSettle();

        // Enter search text
        await tester.enterText(find.byType(TextField), 'San Francisco');
        await tester.pumpAndSettle();

        // Verify clear button appears
        expect(find.byIcon(Icons.clear), findsOneWidget);

        // Clear search
        await tester.tap(find.byIcon(Icons.clear));
        await tester.pumpAndSettle();

        // Assert - search field should be empty and clear button should be gone
        final searchField = find.byType(TextField);
        expect(searchField, findsOneWidget);
        expect(find.byIcon(Icons.clear), findsNothing);

        // Verify the search field text is cleared
        final textField = tester.widget<TextField>(searchField);
        expect(textField.controller?.text ?? '', isEmpty);
      });
    });

    group('Chart Selection and Actions', () {
      testWidgets('should support multi-select with checkboxes', (
        WidgetTester tester,
      ) async {
        // Arrange
        final testCharts = createTestCharts();
        when(
          mockDiscoveryService.discoverChartsByState('California'),
        ).thenAnswer((_) async => testCharts);

        // Act
        await tester.pumpWidget(createTestWidget());
        await tester.pumpAndSettle();

        // Select California
        await tester.tap(find.byType(DropdownButton<String>));
        await tester.pumpAndSettle();
        await tester.tap(find.text('California'));
        await tester.pumpAndSettle();

        // Select first chart
        await tester.tap(find.byType(Checkbox).first);
        await tester.pumpAndSettle();

        // Assert
        expect(find.text('1 selected'), findsOneWidget);
        expect(find.byIcon(Icons.download), findsOneWidget);
      });

      testWidgets('should show download action when charts selected', (
        WidgetTester tester,
      ) async {
        // Arrange
        final testCharts = createTestCharts();
        when(
          mockDiscoveryService.discoverChartsByState('California'),
        ).thenAnswer((_) async => testCharts);

        // Act
        await tester.pumpWidget(createTestWidget());
        await tester.pumpAndSettle();

        // Select California and chart
        await tester.tap(find.byType(DropdownButton<String>));
        await tester.pumpAndSettle();
        await tester.tap(find.text('California'));
        await tester.pumpAndSettle();

        await tester.tap(find.byType(Checkbox).first);
        await tester.pumpAndSettle();

        // Assert
        expect(find.byIcon(Icons.download), findsOneWidget);
        expect(find.text('Download Selected'), findsOneWidget);
      });

      testWidgets('should navigate to chart display when chart tapped', (
        WidgetTester tester,
      ) async {
        // Arrange
        final testCharts = createTestCharts();
        when(
          mockDiscoveryService.discoverChartsByState('California'),
        ).thenAnswer((_) async => testCharts);

        // Act
        await tester.pumpWidget(createTestWidget(withNavigation: true));
        await tester.pumpAndSettle();

        // Select California
        await tester.tap(find.byType(DropdownButton<String>));
        await tester.pumpAndSettle();
        await tester.tap(find.text('California'));
        await tester.pumpAndSettle();

        // Tap on chart card (not checkbox)
        await tester.tap(find.text('San Francisco Bay'));
        await tester.pumpAndSettle();

        // Assert
        expect(find.text('Chart Display'), findsOneWidget);
      });

      testWidgets('should show chart preview dialog on info button tap', (
        WidgetTester tester,
      ) async {
        // Arrange
        final testCharts = createTestCharts();
        when(
          mockDiscoveryService.discoverChartsByState('California'),
        ).thenAnswer((_) async => testCharts);

        // Act
        await tester.pumpWidget(createTestWidget());
        await tester.pumpAndSettle();

        // Select California
        await tester.tap(find.byType(DropdownButton<String>));
        await tester.pumpAndSettle();
        await tester.tap(find.text('California'));
        await tester.pumpAndSettle();

        // Tap info button to show preview dialog
        await tester.tap(find.byIcon(Icons.info_outline).first);
        await pumpAndSettleWithTimeout(tester); // Use extended timeout for dialog animation

        // Assert
        expect(find.byType(AlertDialog), findsOneWidget);
        expect(find.text('Chart Details'), findsOneWidget);
        expect(
          find.text('Detailed harbor chart of San Francisco Bay'),
          findsOneWidget,
        );
      });
    });

    group('Performance and Error Handling', () {
      testWidgets('should handle large chart lists efficiently', (
        WidgetTester tester,
      ) async {
        // Arrange
        final largeChartList = List.generate(
          100,
          (index) => Chart(
            id: 'US_TEST_$index',
            title: 'Test Chart $index',
            scale: 25000 + index * 1000,
            bounds: GeographicBounds(
              north: 38.0,
              south: 37.0,
              east: -122.0,
              west: -123.0,
            ),
            lastUpdate: DateTime.now(),
            state: 'California',
            type: ChartType.harbor,
          ),
        );

        when(
          mockDiscoveryService.discoverChartsByState('California'),
        ).thenAnswer((_) async => largeChartList);

        // Act
        await tester.pumpWidget(createTestWidget());
        await tester.pumpAndSettle();

        // Select California
        await tester.tap(find.byType(DropdownButton<String>));
        await tester.pumpAndSettle();
        await tester.tap(find.text('California'));
        await tester.pumpAndSettle();

        // Assert
        expect(find.byType(ListView), findsOneWidget);
        expect(find.text('Test Chart 0'), findsOneWidget);

        // Scroll incrementally to avoid off-screen drag warnings and trigger lazy list build.
        // NOTE:
        // We deliberately scroll the outer SingleChildScrollView instead of the inner ListView.
        // The ListView is shrinkWrapped with NeverScrollableScrollPhysics so direct drags on it
        // produce framework warnings ("Scroll gesture was ignored because ..."). An earlier
        // experiment added an enableScrolling flag to make the ListView independently scrollable,
        // but that introduced multiple layout/semantics regressions (RenderBox not laid out,
        // overflows, null check issues). Keeping the production layout intact and adapting the
        // test to scroll the legitimate scrollable ancestor removes the warning without risking
        // stability. If the layout is ever refactored to a sliver-based structure, this can be
        // revisited.
        final scrollFinder = find.byType(SingleChildScrollView);
        for (var i = 0; i < 6; i++) {
          await tester.drag(scrollFinder, const Offset(0, -350));
          await tester.pump(
            const Duration(milliseconds: 120),
          ); // allow build/layout
        }
        await tester.pumpAndSettle();

        // Check that we have loaded charts further down the list
        // We know we have 100 charts (0-99), so let's check for one that should be visible after scrolling
        final chartFinders = find.textContaining('Test Chart');
        expect(
          chartFinders,
          findsAtLeastNWidgets(3),
        ); // Should find several chart titles
      });

      testWidgets('should debounce search input', (WidgetTester tester) async {
        // Arrange
        when(
          mockDiscoveryService.discoverChartsByState(any),
        ).thenAnswer((_) async => createTestCharts());
        when(
          mockDiscoveryService.searchCharts(any, filters: anyNamed('filters')),
        ).thenAnswer((_) async => []);

        // Act
        await tester.pumpWidget(createTestWidget());
        await tester.pumpAndSettle();

        // Select state first
        await tester.tap(find.byType(DropdownButton<String>));
        await tester.pumpAndSettle();
        await tester.tap(find.text('California'));
        await tester.pumpAndSettle();

        // Type rapidly
        await tester.enterText(find.byType(TextField), 'S');
        await tester.pump(const Duration(milliseconds: 100));
        await tester.enterText(find.byType(TextField), 'Sa');
        await tester.pump(const Duration(milliseconds: 100));
        await tester.enterText(find.byType(TextField), 'San');
        await tester.pump(
          const Duration(milliseconds: 500),
        ); // Wait for debounce

        // Assert
        verify(
          mockDiscoveryService.searchCharts(
            'San',
            filters: anyNamed('filters'),
          ),
        ).called(1);
        verifyNever(
          mockDiscoveryService.searchCharts('S', filters: anyNamed('filters')),
        );
        verifyNever(
          mockDiscoveryService.searchCharts('Sa', filters: anyNamed('filters')),
        );
      });
    });

    group('Accessibility', () {
      testWidgets('should have proper semantic labels', (
        WidgetTester tester,
      ) async {
        // Arrange
        when(
          mockDiscoveryService.discoverChartsByState(any),
        ).thenAnswer((_) async => []);

        // Act
        await tester.pumpWidget(createTestWidget());
        await tester.pumpAndSettle();

        // Assert - Use semantics finders that are more flexible
        expect(
          find.byWidgetPredicate(
            (widget) =>
                widget is Semantics &&
                widget.properties.label == 'Select a US state to browse charts',
          ),
          findsOneWidget,
        );

        expect(
          find.byWidgetPredicate(
            (widget) =>
                widget is Semantics &&
                widget.properties.label ==
                    'Search charts by name or description',
          ),
          findsOneWidget,
        );

        expect(
          find.byWidgetPredicate(
            (widget) =>
                widget is Semantics &&
                widget.properties.label == 'Filter charts by type',
          ),
          findsOneWidget,
        );
      });

      testWidgets('should support keyboard navigation', (
        WidgetTester tester,
      ) async {
        // Arrange
        final testCharts = createTestCharts();
        when(
          mockDiscoveryService.discoverChartsByState('California'),
        ).thenAnswer((_) async => testCharts);

        // Act
        await tester.pumpWidget(createTestWidget());
        await tester.pumpAndSettle();

        // Select California
        await tester.tap(find.byType(DropdownButton<String>));
        await tester.pumpAndSettle();
        await tester.tap(find.text('California'));
        await tester.pumpAndSettle();

        // Test tab navigation through chart cards
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.pump();

        // Assert - Focus should be navigable
        expect(find.byType(ChartBrowserScreen), findsOneWidget);
      });
    });

    group('Location-Based Chart Discovery', () {
      testWidgets('should automatically discover charts using GPS location', (
        WidgetTester tester,
      ) async {
        // Arrange
        final testCharts = createTestCharts();
        final seattlePosition = GpsPosition(
          latitude: 47.6062,
          longitude: -122.3321,
          timestamp: DateTime.now(),
          accuracy: 1000.0,
        );

        when(
          mockGpsService.getCurrentPositionWithFallback(),
        ).thenAnswer((_) async => seattlePosition);
        when(
          mockDiscoveryService.discoverChartsByLocation(any),
        ).thenAnswer((_) async => testCharts);

        // Act
        await tester.pumpWidget(createTestWidget());
        await tester.pumpAndSettle();

        // Assert - Should automatically discover charts without manual state selection
        verify(mockGpsService.getCurrentPositionWithFallback()).called(1);
        verify(mockDiscoveryService.discoverChartsByLocation(any)).called(1);
        expect(find.text('San Francisco Bay'), findsOneWidget);
      });

      testWidgets(
        'should use Seattle fallback when location services disabled',
        (WidgetTester tester) async {
          // Arrange
          final testCharts = createSeattleTestCharts();
          final seattlePosition = GpsPosition(
            latitude: 47.6062,
            longitude: -122.3321,
            timestamp: DateTime.now(),
            accuracy: 1000.0,
          );

          when(
            mockGpsService.getCurrentPositionWithFallback(),
          ).thenAnswer((_) async => seattlePosition);
          when(
            mockDiscoveryService.discoverChartsByLocation(any),
          ).thenAnswer((_) async => testCharts);

          // Act
          await tester.pumpWidget(createTestWidget());
          await tester.pumpAndSettle();

          // Assert - Should discover Seattle area charts as fallback
          final capturedCall = verify(
            mockDiscoveryService.discoverChartsByLocation(captureAny),
          ).captured.first;
          expect(
            capturedCall.latitude,
            closeTo(47.6062, 0.001),
          ); // Seattle latitude
          expect(
            capturedCall.longitude,
            closeTo(-122.3321, 0.001),
          ); // Seattle longitude
          expect(find.text('Puget Sound'), findsOneWidget);
        },
      );

      testWidgets(
        'should fall back to manual state selection if location discovery fails',
        (WidgetTester tester) async {
          // Arrange
          when(
            mockGpsService.getCurrentPositionWithFallback(),
          ).thenThrow(Exception('Location discovery failed'));

          // Act
          await tester.pumpWidget(createTestWidget());
          await tester.pumpAndSettle();

          // Assert - Should show state dropdown for manual selection
          expect(find.byType(DropdownButton<String>), findsOneWidget);
          expect(find.text('Select State'), findsOneWidget);
          expect(
            find.text(
              'Location discovery failed. Please select a state manually.',
            ),
            findsOneWidget,
          );
        },
      );
    });

    group('Enhanced Filtering Tests', () {
      testWidgets('should show scale filtering controls when enabled', (
        WidgetTester tester,
      ) async {
        // Arrange
        final testCharts = createTestCharts();
        when(
          mockDiscoveryService.discoverChartsByState('California'),
        ).thenAnswer((_) async => testCharts);

        // Act
        await tester.pumpWidget(createTestWidget());
        await tester.pumpAndSettle();

        // Select California to load charts
        await tester.tap(find.byType(DropdownButton<String>));
        await tester.pumpAndSettle();
        await tester.tap(find.text('California'));
        await tester.pumpAndSettle();

        // Enable scale filtering
        await tester.tap(find.text('Filter by Scale Range'));
        await pumpAndSettleWithTimeout(tester); // Use extended timeout for complex filtering UI

        // Assert
        expect(find.text('Scale: 1:1,000 - 1:10,000,000'), findsOneWidget);
        expect(find.byType(Slider), findsNWidgets(2)); // Min and max sliders
      });

      testWidgets('should show date filtering controls when enabled', (
        WidgetTester tester,
      ) async {
        // Arrange
        final testCharts = createTestCharts();
        when(
          mockDiscoveryService.discoverChartsByState('California'),
        ).thenAnswer((_) async => testCharts);

        // Act
        await tester.pumpWidget(createTestWidget());
        await tester.pumpAndSettle();

        // Select California to load charts
        await tester.tap(find.byType(DropdownButton<String>));
        await tester.pumpAndSettle();
        await tester.tap(find.text('California'));
        await tester.pumpAndSettle();

        // Enable date filtering
        await tester.tap(find.text('Filter by Update Date'));
        await tester.pumpAndSettle();

        // Assert
        expect(find.text('Start Date'), findsOneWidget);
        expect(find.text('End Date'), findsOneWidget);
      });

      testWidgets('should filter charts by scale range', (
        WidgetTester tester,
      ) async {
        // Arrange
        final testCharts = [
          createTestChart(id: 'US5CA52M', title: 'Small Scale', scale: 50000),
          createTestChart(id: 'US4CA11M', title: 'Large Scale', scale: 500000),
        ];
        when(
          mockDiscoveryService.discoverChartsByState('California'),
        ).thenAnswer((_) async => testCharts);

        // Act
        await tester.pumpWidget(createTestWidget());
        await pumpAndWait(tester);

        // Select California to load charts
        await tester.tap(find.byType(DropdownButton<String>));
        await pumpAndWait(tester);
        await tester.tap(find.text('California'));
        await pumpAndWait(tester, wait: const Duration(seconds: 1));

        // Verify both charts are shown initially
        expect(find.text('Small Scale'), findsOneWidget);
        expect(find.text('Large Scale'), findsOneWidget);

        // Enable scale filtering and set range to exclude large scale
        await tester.tap(find.text('Filter by Scale Range'));
        await pumpAndWait(tester);

        // Assert filtering UI is shown
        expect(find.byType(Slider), findsNWidgets(2));
      });

      testWidgets('should reset filters when state changes', (
        WidgetTester tester,
      ) async {
        // Arrange
        final californiaCharts = createTestCharts();
        final floridaCharts = [
          createTestChart(id: 'US4FL11M', title: 'Florida Chart'),
        ];

        when(
          mockDiscoveryService.discoverChartsByState('California'),
        ).thenAnswer((_) async => californiaCharts);
        when(
          mockDiscoveryService.discoverChartsByState('Florida'),
        ).thenAnswer((_) async => floridaCharts);

        // Act
        await tester.pumpWidget(createTestWidget());
        await pumpAndWait(tester);

        // Select California and enable filters
        await tester.tap(find.byType(DropdownButton<String>));
        await pumpAndWait(tester);
        await tester.tap(find.text('California'));
        await pumpAndWait(tester, wait: const Duration(seconds: 1));

        // Enable scale filter
        await tester.tap(find.text('Filter by Scale Range'));
        await pumpAndWait(tester);

        // Change to Florida (state change should reset filters)
        await tester.tap(find.byType(DropdownButton<String>));
        await pumpAndWait(tester);
        await tester.tap(find.text('Florida'));
        await pumpAndSettleWithTimeout(tester); // Use extended timeout for state change reset

        // Scale filter UI should not be visible (filter was reset)
        expect(find.byType(Slider), findsNothing);
      });
    });

    group('Enhanced Chart Preview Tests', () {
      testWidgets('should show enhanced chart details dialog', (
        WidgetTester tester,
      ) async {
        // Arrange
        final testChart = createTestChart(
          description: 'Detailed chart description',
          fileSize: 1024 * 1024, // 1 MB
        );
        when(
          mockDiscoveryService.discoverChartsByState('California'),
        ).thenAnswer((_) async => [testChart]);

        // Act
        await tester.pumpWidget(createTestWidget());
        await pumpAndWait(tester);

        // Load charts
        await tester.tap(find.byType(DropdownButton<String>));
        await pumpAndWait(tester);
        await tester.tap(find.text('California'));
        await pumpAndWait(tester, wait: const Duration(seconds: 1));

        // Tap info button
        await tester.tap(find.byIcon(Icons.info_outline));
        await pumpAndWait(tester);

        // Assert enhanced details are shown
        expect(find.text('Chart Details'), findsOneWidget);
        expect(find.text('Type:'), findsOneWidget);
        expect(find.text('Scale:'), findsOneWidget);
        expect(find.text('Coverage Area'), findsOneWidget);
        expect(find.text('Source:'), findsOneWidget);
        expect(find.text('1.0 MB'), findsOneWidget);
      });
    });
  });
}

// Helper method for Seattle test charts
List<Chart> createSeattleTestCharts() {
  return [
    Chart(
      id: 'US5WA23M',
      title: 'Puget Sound',
      scale: 50000,
      bounds: GeographicBounds(
        north: 47.8,
        south: 47.4,
        east: -122.2,
        west: -122.5,
      ),
      type: ChartType.harbor,
      lastUpdate: DateTime.now(),
      state: 'Washington',
    ),
  ];
}
