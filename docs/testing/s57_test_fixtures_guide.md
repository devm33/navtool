# S57TestFixtures Utility Guide

## Overview

The `S57TestFixtures` utility provides standardized access to real NOAA Electronic Navigational Chart (ENC) data for testing marine navigation features. It replaces synthetic test data with actual S57 chart files for higher test validity and maritime safety compliance.

## Purpose

- **Safety-Critical Testing**: Use real NOAA ENC data instead of synthetic data for marine navigation testing
- **Test Validity**: Ensure tests reflect actual chart data characteristics and complexity
- **Performance Optimization**: Caching system for efficient test execution
- **Standardization**: Consistent API for accessing S57 test data across all test suites

## Available Charts

### Elliott Bay Harbor Chart (US5WA50M)
- **Scale**: 1:20,000 (Harbor/Approach)
- **Coverage**: Elliott Bay and Seattle Harbor area
- **File Size**: ~411KB
- **Usage Band**: 5 (Harbor)
- **Features**: Navigation aids, depth contours, harbor facilities
- **File**: `test/fixtures/charts/s57_data/ENC_ROOT/US5WA50M/US5WA50M.000`

### Puget Sound Coastal Chart (US3WA01M)
- **Scale**: 1:90,000 (Coastal)
- **Coverage**: Broader Puget Sound region
- **File Size**: ~1.58MB
- **Usage Band**: 3 (Coastal)
- **Features**: Coastlines, depth areas, major navigation routes
- **File**: `test/fixtures/charts/s57_data/ENC_ROOT/US3WA01M/US3WA01M.000`

## Usage Examples

### Basic Chart Loading

```dart
import 'package:flutter_test/flutter_test.dart';
import '../utils/s57_test_fixtures.dart';

void main() {
  group('Marine Navigation Tests', () {
    test('should load real Elliott Bay chart data', () async {
      // Load raw chart bytes
      final chartBytes = await S57TestFixtures.loadElliottBayChartBytes();
      expect(chartBytes, isNotEmpty);
      
      // Load parsed S57 data
      final parsedData = await S57TestFixtures.loadParsedElliottBay();
      expect(parsedData.features, isNotEmpty);
      
      // Create Chart model
      final chart = await S57TestFixtures.createElliottBayChart();
      expect(chart.type, equals(ChartType.harbor));
    });
  });
}
```

### Replacing Synthetic Data

```dart
// BEFORE: Using synthetic data
final testChart = TestFixtures.createTestChart(
  id: 'SYNTHETIC_001',
  title: 'Fake Test Chart',
  // ... synthetic properties
);

// AFTER: Using real S57 data
final realChart = await S57TestFixtures.createElliottBayChart();
// Now testing with actual NOAA ENC data!
```

### Performance-Optimized Testing

```dart
void main() {
  group('S57 Performance Tests', () {
    setUpAll(() async {
      // Pre-load and cache charts for all tests in this group
      await S57TestFixtures.loadParsedElliottBay();
      await S57TestFixtures.loadParsedPugetSound();
    });
    
    test('chart processing performance', () async {
      // Uses cached data for fast test execution
      final parsedData = await S57TestFixtures.loadParsedElliottBay();
      // Test chart processing logic...
    });
  });
}
```

### Working with S57 Features

```dart
test('should validate S57 feature types', () async {
  final parsedData = await S57TestFixtures.loadParsedElliottBay();
  
  // Find navigation aids
  final navigationAids = parsedData.features.where(
    (feature) => feature.featureType == S57FeatureType.buoyLateral ||
                 feature.featureType == S57FeatureType.lighthouse,
  ).toList();
  
  expect(navigationAids, isNotEmpty, 
    reason: 'Elliott Bay should contain navigation aids');
  
  // Validate geographic coordinates are within expected bounds
  for (final feature in navigationAids) {
    expect(feature.geometry?.coordinates, isNotEmpty);
    // Validate coordinates are within Elliott Bay area
  }
});
```

### Error Handling and Validation

```dart
test('should handle missing fixtures gracefully', () async {
  final available = await S57TestFixtures.areFixturesAvailable();
  
  if (!available) {
    // Skip test if fixtures not available
    return markTestSkipped('S57 test fixtures not available');
  }
  
  // Proceed with test using real data
  final chart = await S57TestFixtures.createElliottBayChart();
  expect(chart, isNotNull);
});
```

## API Reference

### Raw Data Loading

- `loadElliottBayChartBytes()` → `Future<Uint8List>`
- `loadPugetSoundChartBytes()` → `Future<Uint8List>`

### Parsed Data Loading

- `loadParsedElliottBay({warnings})` → `Future<S57ParsedData>`
- `loadParsedPugetSound({warnings})` → `Future<S57ParsedData>`

### Chart Model Creation

- `createElliottBayChart({warnings})` → `Future<Chart>`
- `createPugetSoundChart({warnings})` → `Future<Chart>`

### Utility Methods

- `areFixturesAvailable()` → `Future<bool>`
- `getAvailableChartIds()` → `List<String>`
- `getChartMetadata(chartId)` → `Future<Map<String, dynamic>>`
- `getMarineTestAreas()` → `List<Map<String, dynamic>>`
- `validateChartData(parsedData, expectedChartId)` → `bool`
- `clearCaches()` → `void`

## Best Practices

### 1. Check Fixture Availability

```dart
test('marine navigation feature', () async {
  final available = await S57TestFixtures.areFixturesAvailable();
  if (!available) {
    return markTestSkipped('S57 fixtures not available');
  }
  
  // Test with real data
});
```

### 2. Use Appropriate Chart Scale

```dart
// For harbor-scale testing (detailed navigation)
final harborChart = await S57TestFixtures.createElliottBayChart();

// For coastal-scale testing (broader area coverage)
final coastalChart = await S57TestFixtures.createPugetSoundChart();
```

### 3. Cache Management for Performance

```dart
setUpAll(() async {
  // Pre-load data for test suite
  await S57TestFixtures.loadParsedElliottBay();
});

tearDownAll(() {
  // Clear caches after test suite
  S57TestFixtures.clearCaches();
});
```

### 4. Validate Real Data Characteristics

```dart
test('depth contour validation', () async {
  final parsedData = await S57TestFixtures.loadParsedElliottBay();
  
  final depthContours = parsedData.features.where(
    (feature) => feature.featureType == S57FeatureType.depthContour,
  ).toList();
  
  // Real harbor chart should have depth contours
  expect(depthContours, isNotEmpty);
  
  // Validate depth values are reasonable for harbor
  for (final contour in depthContours) {
    final depth = contour.attributes['VALDCO'];
    if (depth != null) {
      expect(depth, inInclusiveRange(0.0, 100.0),
        reason: 'Harbor depth contours should be 0-100 meters');
    }
  }
});
```

## Test Migration Guide

### Step 1: Identify Synthetic Data Usage

```bash
# Find tests using synthetic data
grep -r "TestFixtures.createTestChart" test/
grep -r "_createTestChart" test/
```

### Step 2: Replace with Real Data

```dart
// BEFORE
final testChart = TestFixtures.createTestChart(id: 'TEST001');

// AFTER
final realChart = await S57TestFixtures.createElliottBayChart();
```

### Step 3: Update Test Assertions

```dart
// BEFORE: Synthetic data has predictable values
expect(testChart.scale, equals(25000));
expect(testChart.features.length, equals(3));

// AFTER: Real data has actual NOAA values
expect(realChart.scale, equals(20000)); // Actual Elliott Bay scale
expect(realChart.features.length, greaterThanOrEqualTo(5)); // Real feature count
```

### Step 4: Handle Real Data Variability

```dart
// Use ranges instead of exact values for real data
expect(parsedData.features.length, inInclusiveRange(5, 100));
expect(chart.bounds.north, inInclusiveRange(47.5, 47.7));
```

## Performance Considerations

### Caching Strategy

The utility implements two-level caching:

1. **Bytes Cache**: Raw file data cached to avoid disk I/O
2. **Parse Cache**: Parsed S57 data cached to avoid re-parsing

### Cache Lifecycle

```dart
// Cache populated on first access
final data1 = await S57TestFixtures.loadParsedElliottBay(); // Disk + Parse
final data2 = await S57TestFixtures.loadParsedElliottBay(); // Cache hit

// Cache cleared when requested
S57TestFixtures.clearCaches();
final data3 = await S57TestFixtures.loadParsedElliottBay(); // Disk + Parse again
```

### Test Suite Performance

```dart
// Efficient: Pre-load in setUpAll
setUpAll(() async {
  await S57TestFixtures.loadParsedElliottBay();
  await S57TestFixtures.loadParsedPugetSound();
});

// Individual tests run fast using cached data
```

## Troubleshooting

### Missing Fixtures

**Error**: `FileSystemException: Elliott Bay chart fixture not found`

**Solution**: Ensure S57 test fixtures are present:
```bash
ls test/fixtures/charts/s57_data/ENC_ROOT/US5WA50M/US5WA50M.000
ls test/fixtures/charts/s57_data/ENC_ROOT/US3WA01M/US3WA01M.000
```

### Unexpected File Sizes

**Error**: `StateError: Elliott Bay chart size unexpected: X bytes`

**Solution**: Verify fixture integrity:
```bash
# Elliott Bay should be ~411KB
wc -c test/fixtures/charts/s57_data/ENC_ROOT/US5WA50M/US5WA50M.000

# Puget Sound should be ~1.58MB
wc -c test/fixtures/charts/s57_data/ENC_ROOT/US3WA01M/US3WA01M.000
```

### Parsing Failures

**Error**: `Failed to parse Elliott Bay chart`

**Solution**: 
1. Verify S57 parser is working: `flutter test test/core/services/s57/s57_parser_test.dart`
2. Check fixture file integrity
3. Review S57 parser configuration for real data vs test data differences

## Integration Examples

### Chart Browser Tests

```dart
test('should display real Elliott Bay chart in browser', () async {
  final chart = await S57TestFixtures.createElliottBayChart();
  
  // Test chart browser with real chart data
  await tester.pumpWidget(ChartBrowserScreen(initialChart: chart));
  
  // Verify real chart metadata is displayed
  expect(find.text(chart.title), findsOneWidget);
  expect(find.text('Harbor'), findsOneWidget); // Real chart type
});
```

### S57 Parser Integration Tests

```dart
test('should parse real NOAA ENC data correctly', () async {
  final bytes = await S57TestFixtures.loadElliottBayChartBytes();
  final warnings = S57WarningCollector();
  
  final parsedData = S57Parser.parse(bytes.toList(), warnings: warnings);
  
  // Validate parsing results with real data
  expect(parsedData.features, isNotEmpty);
  expect(parsedData.metadata.title, isNotEmpty);
  expect(S57TestFixtures.validateChartData(parsedData, 'US5WA50M'), isTrue);
});
```

---

**This utility is essential for migrating NavTool tests from synthetic data to real NOAA ENC data, ensuring marine navigation safety through accurate testing with actual chart data.**