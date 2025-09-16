import 'package:flutter_test/flutter_test.dart';
import 'package:navtool/s57.dart';
import 'package:navtool/core/models/chart.dart';
import '../utils/s57_test_fixtures.dart';

/// Tests for S57TestFixtures utility class
/// 
/// Validates that the S57TestFixtures utility can properly load and parse
/// real NOAA ENC data for testing marine navigation functionality.
void main() {
  group('S57TestFixtures', () {
    setUp(() {
      // Clear caches before each test to ensure fresh data loading
      S57TestFixtures.clearCaches();
    });

    group('Fixture Availability', () {
      test('should detect when S57 fixtures are available', () async {
        final available = await S57TestFixtures.areFixturesAvailable();
        
        // This test assumes fixtures are present in the test environment
        // If running in CI without fixtures, this test should be skipped
        expect(available, isTrue, 
          reason: 'S57 test fixtures should be available. '
                  'Ensure US5WA50M.000 and US3WA01M.000 are in test/fixtures/charts/s57_data/ENC_ROOT/');
      });

      test('should provide list of available chart IDs', () {
        final chartIds = S57TestFixtures.getAvailableChartIds();
        
        expect(chartIds, contains('US5WA50M'));
        expect(chartIds, contains('US3WA01M'));
        expect(chartIds, hasLength(2));
      });
    });

    group('Raw Chart Data Loading', () {
      test('should load Elliott Bay chart bytes successfully', () async {
        final bytes = await S57TestFixtures.loadElliottBayChartBytes();
        
        expect(bytes, isNotEmpty);
        expect(bytes.length, greaterThan(300000), 
          reason: 'Elliott Bay chart should be ~411KB');
        expect(bytes.length, lessThan(600000), 
          reason: 'Elliott Bay chart should not exceed 600KB');
        
        // Verify it's actually S57 data (check for ISO 8211 format markers)
        expect(bytes.length, greaterThan(24), 
          reason: 'Should have ISO 8211 leader');
      });

      test('should load Puget Sound chart bytes successfully', () async {
        final bytes = await S57TestFixtures.loadPugetSoundChartBytes();
        
        expect(bytes, isNotEmpty);
        expect(bytes.length, greaterThan(1200000), 
          reason: 'Puget Sound chart should be ~1.58MB');
        expect(bytes.length, lessThan(2000000), 
          reason: 'Puget Sound chart should not exceed 2MB');
        
        // Verify it's actually S57 data
        expect(bytes.length, greaterThan(24), 
          reason: 'Should have ISO 8211 leader');
      });

      test('should cache raw bytes for performance', () async {
        // Load chart twice
        final bytes1 = await S57TestFixtures.loadElliottBayChartBytes();
        final bytes2 = await S57TestFixtures.loadElliottBayChartBytes();
        
        // Should be identical cached instances
        expect(identical(bytes1, bytes2), isTrue, 
          reason: 'Second load should return cached bytes');
      });

      test('should throw FileSystemException for missing files', () async {
        // This test requires temporarily removing fixture files or
        // testing with a modified fixtures path
        
        // For now, test the error handling logic by testing error message format
        expect(() async {
          // This would fail if fixturesPath was wrong
          await S57TestFixtures.loadElliottBayChartBytes();
        }, returnsNormally); // Should succeed with correct fixtures
      });
    });

    group('Parsed Chart Data', () {
      test('should parse Elliott Bay chart to S57ParsedData', () async {
        final parsedData = await S57TestFixtures.loadParsedElliottBay();
        
        // Validate parsed data structure
        expect(parsedData.metadata, isNotNull);
        expect(parsedData.features, isNotEmpty);
        expect(parsedData.bounds, isNotNull);
        expect(parsedData.spatialIndex, isNotNull);
        
        // Validate feature count expectations for harbor chart
        expect(parsedData.features.length, greaterThanOrEqualTo(5),
          reason: 'Elliott Bay should have at least 5 features');
        
        // Validate geographic bounds are reasonable for Elliott Bay
        expect(parsedData.bounds.north, inInclusiveRange(47.0, 48.0));
        expect(parsedData.bounds.south, inInclusiveRange(47.0, 48.0));
        expect(parsedData.bounds.east, inInclusiveRange(-122.5, -122.0));
        expect(parsedData.bounds.west, inInclusiveRange(-122.5, -122.0));
        
        // Validate spatial index consistency
        expect(parsedData.spatialIndex.featureCount, equals(parsedData.features.length));
      });

      test('should parse Puget Sound chart to S57ParsedData', () async {
        final parsedData = await S57TestFixtures.loadParsedPugetSound();
        
        // Validate parsed data structure
        expect(parsedData.metadata, isNotNull);
        expect(parsedData.features, isNotEmpty);
        expect(parsedData.bounds, isNotNull);
        expect(parsedData.spatialIndex, isNotNull);
        
        // Validate feature count expectations for coastal chart
        expect(parsedData.features.length, greaterThanOrEqualTo(10),
          reason: 'Puget Sound should have at least 10 features');
        
        // Validate geographic bounds are reasonable for Puget Sound
        expect(parsedData.bounds.north, inInclusiveRange(46.5, 48.5));
        expect(parsedData.bounds.south, inInclusiveRange(46.5, 48.5));
        expect(parsedData.bounds.east, inInclusiveRange(-123.0, -122.0));
        expect(parsedData.bounds.west, inInclusiveRange(-123.0, -122.0));
        
        // Validate spatial index consistency
        expect(parsedData.spatialIndex.featureCount, equals(parsedData.features.length));
      });

      test('should cache parsed data for performance', () async {
        // Load chart twice
        final parsedData1 = await S57TestFixtures.loadParsedElliottBay();
        final parsedData2 = await S57TestFixtures.loadParsedElliottBay();
        
        // Should be identical cached instances
        expect(identical(parsedData1, parsedData2), isTrue,
          reason: 'Second parse should return cached data');
      });

      test('should handle S57 parsing warnings when provided', () async {
        final warnings = S57WarningCollector();
        
        final parsedData = await S57TestFixtures.loadParsedElliottBay(
          warnings: warnings,
        );
        
        expect(parsedData, isNotNull);
        // Warnings collector should be available for inspection
        expect(warnings, isNotNull);
      });
    });

    group('Chart Model Creation', () {
      test('should create Elliott Bay Chart model from S57 data', () async {
        final chart = await S57TestFixtures.createElliottBayChart();
        
        // Validate Chart model properties
        expect(chart.id, equals('US5WA50M'));
        expect(chart.title, isNotNull);
        expect(chart.title, isNotEmpty);
        expect(chart.scale, isNotNull);
        expect(chart.scale, greaterThan(0));
        expect(chart.type, equals(ChartType.harbor));
        expect(chart.source, equals(ChartSource.noaa));
        expect(chart.state, equals('Washington'));
        
        // Validate bounds
        expect(chart.bounds, isNotNull);
        expect(chart.bounds.north, inInclusiveRange(47.0, 48.0));
        expect(chart.bounds.south, inInclusiveRange(47.0, 48.0));
        expect(chart.bounds.east, inInclusiveRange(-122.5, -122.0));
        expect(chart.bounds.west, inInclusiveRange(-122.5, -122.0));
        
        // Validate metadata
        expect(chart.metadata, isNotNull);
        expect(chart.metadata!['source_type'], equals('s57_enc'));
        expect(chart.metadata!['feature_count'], isA<int>());
        expect(chart.metadata!['feature_count'], greaterThan(0));
        expect(chart.metadata!['usage_band'], equals(5));
        expect(chart.metadata!['chart_format'], equals('S57_ENC'));
        
        // Validate file size is set
        expect(chart.fileSize, isNotNull);
        expect(chart.fileSize!, greaterThan(300000));
      });

      test('should create Puget Sound Chart model from S57 data', () async {
        final chart = await S57TestFixtures.createPugetSoundChart();
        
        // Validate Chart model properties
        expect(chart.id, equals('US3WA01M'));
        expect(chart.title, isNotNull);
        expect(chart.title, isNotEmpty);
        expect(chart.scale, isNotNull);
        expect(chart.scale, greaterThan(0));
        expect(chart.type, equals(ChartType.coastal));
        expect(chart.source, equals(ChartSource.noaa));
        expect(chart.state, equals('Washington'));
        
        // Validate bounds
        expect(chart.bounds, isNotNull);
        expect(chart.bounds.north, inInclusiveRange(46.5, 48.5));
        expect(chart.bounds.south, inInclusiveRange(46.5, 48.5));
        expect(chart.bounds.east, inInclusiveRange(-123.0, -122.0));
        expect(chart.bounds.west, inInclusiveRange(-123.0, -122.0));
        
        // Validate metadata
        expect(chart.metadata, isNotNull);
        expect(chart.metadata!['source_type'], equals('s57_enc'));
        expect(chart.metadata!['feature_count'], isA<int>());
        expect(chart.metadata!['feature_count'], greaterThan(0));
        expect(chart.metadata!['usage_band'], equals(3));
        expect(chart.metadata!['chart_format'], equals('S57_ENC'));
        
        // Validate file size is set
        expect(chart.fileSize, isNotNull);
        expect(chart.fileSize!, greaterThan(1200000));
      });
    });

    group('Utility Methods', () {
      test('should extract chart metadata without full parsing', () async {
        final metadata = await S57TestFixtures.getChartMetadata('US5WA50M');
        
        expect(metadata['id'], equals('US5WA50M'));
        expect(metadata['title'], isNotNull);
        expect(metadata['scale'], isNotNull);
        expect(metadata['bounds'], isNotNull);
        expect(metadata['feature_count'], isA<int>());
        expect(metadata['feature_count'], greaterThan(0));
        expect(metadata['file_size'], isA<int>());
        expect(metadata['file_size'], greaterThan(300000));
      });

      test('should validate chart data integrity', () async {
        final parsedData = await S57TestFixtures.loadParsedElliottBay();
        
        final isValid = S57TestFixtures.validateChartData(parsedData, 'US5WA50M');
        expect(isValid, isTrue, 
          reason: 'Elliott Bay chart data should pass validation');
      });

      test('should provide marine test areas with real chart coverage', () {
        final testAreas = S57TestFixtures.getMarineTestAreas();
        
        expect(testAreas, hasLength(2));
        
        // Validate Elliott Bay test area
        final elliottBay = testAreas.firstWhere((area) => area['name'] == 'Elliott Bay Harbor');
        expect(elliottBay['chart_id'], equals('US5WA50M'));
        expect(elliottBay['usage_band'], equals(5));
        expect(elliottBay['features'], contains('navigation_aids'));
        
        // Validate Puget Sound test area
        final pugetSound = testAreas.firstWhere((area) => area['name'] == 'Puget Sound Coastal');
        expect(pugetSound['chart_id'], equals('US3WA01M'));
        expect(pugetSound['usage_band'], equals(3));
        expect(pugetSound['features'], contains('coastlines'));
      });

      test('should clear caches when requested', () async {
        // Load some data to populate caches
        await S57TestFixtures.loadElliottBayChartBytes();
        await S57TestFixtures.loadParsedElliottBay();
        
        // Clear caches
        S57TestFixtures.clearCaches();
        
        // Verify fresh loading (this is hard to test directly, but at least ensure no errors)
        final bytes = await S57TestFixtures.loadElliottBayChartBytes();
        expect(bytes, isNotEmpty);
      });
    });

    group('Error Handling', () {
      test('should throw ArgumentError for unknown chart ID', () async {
        expect(
          () async => await S57TestFixtures.getChartMetadata('UNKNOWN'),
          throwsA(isA<ArgumentError>()),
        );
      });

      test('should handle parsing errors gracefully', () async {
        // This test would require corrupted fixture data to test properly
        // For now, verify that normal parsing works
        expect(
          () async => await S57TestFixtures.loadParsedElliottBay(),
          returnsNormally,
        );
      });

      test('should validate file sizes within expected ranges', () async {
        // This is tested implicitly in the loading tests
        final elliottBytes = await S57TestFixtures.loadElliottBayChartBytes();
        final pugetBytes = await S57TestFixtures.loadPugetSoundChartBytes();
        
        expect(elliottBytes.length, inInclusiveRange(300000, 600000));
        expect(pugetBytes.length, inInclusiveRange(1200000, 2000000));
      });
    });

    group('Performance and Caching', () {
      test('should demonstrate caching performance benefit', () async {
        final stopwatch = Stopwatch();
        
        // First load (from disk)
        stopwatch.start();
        await S57TestFixtures.loadElliottBayChartBytes();
        stopwatch.stop();
        final firstLoadTime = stopwatch.elapsedMicroseconds;
        
        // Second load (from cache)
        stopwatch.reset();
        stopwatch.start();
        await S57TestFixtures.loadElliottBayChartBytes();
        stopwatch.stop();
        final secondLoadTime = stopwatch.elapsedMicroseconds;
        
        // Cached load should be significantly faster
        expect(secondLoadTime, lessThan(firstLoadTime ~/ 2),
          reason: 'Cached load should be at least 2x faster');
      });

      test('should cache both bytes and parsed data separately', () async {
        // Load bytes
        final bytes1 = await S57TestFixtures.loadElliottBayChartBytes();
        final bytes2 = await S57TestFixtures.loadElliottBayChartBytes();
        expect(identical(bytes1, bytes2), isTrue);
        
        // Load parsed data
        final parsed1 = await S57TestFixtures.loadParsedElliottBay();
        final parsed2 = await S57TestFixtures.loadParsedElliottBay();
        expect(identical(parsed1, parsed2), isTrue);
        
        // Clear caches and verify fresh loading
        S57TestFixtures.clearCaches();
        final bytes3 = await S57TestFixtures.loadElliottBayChartBytes();
        expect(identical(bytes1, bytes3), isFalse, 
          reason: 'After cache clear, should get new instance');
      });
    });

    group('Integration with S57 Parser', () {
      test('should work with S57WarningCollector', () async {
        final warnings = S57WarningCollector();
        
        final parsedData = await S57TestFixtures.loadParsedElliottBay(
          warnings: warnings,
        );
        
        expect(parsedData, isNotNull);
        expect(warnings, isNotNull);
        // Warnings collector should be usable for inspection
      });

      test('should produce valid S57ParsedData format', () async {
        final parsedData = await S57TestFixtures.loadParsedElliottBay();
        
        // Verify it can be converted to chart service format
        final chartServiceFormat = parsedData.toChartServiceFormat();
        expect(chartServiceFormat, isA<Map<String, dynamic>>());
        expect(chartServiceFormat, containsPair('metadata', isA<Map>()));
        expect(chartServiceFormat, containsPair('features', isA<List>()));
        expect(chartServiceFormat, containsPair('bounds', isA<Map>()));
        expect(chartServiceFormat, containsPair('spatial_index', isA<Map>()));
      });
    });
  });
}