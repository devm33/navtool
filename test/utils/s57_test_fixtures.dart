/// S57 Test Fixtures Utility for Real NOAA ENC Data Usage
/// 
/// This utility provides methods to load and parse real NOAA Electronic 
/// Navigational Chart (ENC) data for testing marine navigation functionality.
/// It replaces synthetic test data with actual S57 chart files for higher
/// test validity and maritime safety compliance.
library;

import 'dart:io';
import 'dart:typed_data';
import 'package:path/path.dart' as path;
import 'package:navtool/s57.dart';
import 'package:navtool/core/models/chart.dart';
import 'package:navtool/core/models/geographic_bounds.dart';

/// Test fixtures for real NOAA S57 ENC data
/// 
/// Provides standardized access to real NOAA Electronic Navigational Chart
/// data for testing marine navigation features with actual chart data instead
/// of synthetic fixtures.
class S57TestFixtures {
  /// Base path to S57 test fixtures
  static const String fixturesPath = 'test/fixtures/charts/s57_data/ENC_ROOT';
  
  /// Cache for parsed chart data to improve test performance
  static final Map<String, S57ParsedData> _parseCache = {};
  
  /// Cache for raw chart bytes to improve test performance
  static final Map<String, Uint8List> _bytesCache = {};

  // ============================================================================
  // Raw Chart Data Loading Methods
  // ============================================================================

  /// Load Elliott Bay harbor chart raw bytes (US5WA50M.000)
  /// 
  /// This is a harbor-scale chart (1:20,000) covering Elliott Bay and 
  /// Seattle Harbor area, containing navigation aids, depth contours,
  /// and harbor facilities.
  /// 
  /// Expected file size: ~411KB
  /// Usage band: 5 (harbor/approach)
  static Future<Uint8List> loadElliottBayChartBytes() async {
    const cacheKey = 'US5WA50M_bytes';
    if (_bytesCache.containsKey(cacheKey)) {
      return _bytesCache[cacheKey]!;
    }

    final chartPath = path.join(fixturesPath, 'US5WA50M', 'US5WA50M.000');
    final file = File(chartPath);
    
    if (!await file.exists()) {
      throw FileSystemException(
        'Elliott Bay chart fixture not found. Expected at: $chartPath',
        chartPath,
      );
    }

    final bytes = await file.readAsBytes();
    
    // Validate expected file size (approximately 411KB)
    if (bytes.length < 300000 || bytes.length > 600000) {
      throw StateError(
        'Elliott Bay chart size unexpected: ${bytes.length} bytes. '
        'Expected ~411KB (300-600KB range).',
      );
    }

    final uint8bytes = Uint8List.fromList(bytes);
    _bytesCache[cacheKey] = uint8bytes;
    return uint8bytes;
  }

  /// Load Puget Sound coastal chart raw bytes (US3WA01M.000)
  /// 
  /// This is a coastal-scale chart (1:90,000) covering broader Puget Sound
  /// region, containing coastlines, depth areas, and major navigation routes.
  /// 
  /// Expected file size: ~1.58MB
  /// Usage band: 3 (coastal)
  static Future<Uint8List> loadPugetSoundChartBytes() async {
    const cacheKey = 'US3WA01M_bytes';
    if (_bytesCache.containsKey(cacheKey)) {
      return _bytesCache[cacheKey]!;
    }

    final chartPath = path.join(fixturesPath, 'US3WA01M', 'US3WA01M.000');
    final file = File(chartPath);
    
    if (!await file.exists()) {
      throw FileSystemException(
        'Puget Sound chart fixture not found. Expected at: $chartPath',
        chartPath,
      );
    }

    final bytes = await file.readAsBytes();
    
    // Validate expected file size (approximately 1.58MB)
    if (bytes.length < 1200000 || bytes.length > 2000000) {
      throw StateError(
        'Puget Sound chart size unexpected: ${bytes.length} bytes. '
        'Expected ~1.58MB (1.2-2.0MB range).',
      );
    }

    final uint8bytes = Uint8List.fromList(bytes);
    _bytesCache[cacheKey] = uint8bytes;
    return uint8bytes;
  }

  // ============================================================================
  // Parsed Chart Data Methods
  // ============================================================================

  /// Load and parse Elliott Bay chart to S57ParsedData
  /// 
  /// Returns parsed S57 data with features, metadata, bounds, and spatial index.
  /// Results are cached for performance in subsequent test runs.
  /// 
  /// Throws [AppError] if parsing fails
  /// Throws [FileSystemException] if chart file not found
  static Future<S57ParsedData> loadParsedElliottBay({
    S57WarningCollector? warnings,
  }) async {
    const cacheKey = 'US5WA50M_parsed';
    if (_parseCache.containsKey(cacheKey)) {
      return _parseCache[cacheKey]!;
    }

    final bytes = await loadElliottBayChartBytes();
    
    try {
      final parsedData = S57Parser.parse(bytes.toList(), warnings: warnings);
      
      // Validate parsed data contains expected features
      if (parsedData.features.isEmpty) {
        throw StateError('Elliott Bay chart parsing produced no features');
      }

      // Expected to have navigation aids, depth contours, etc.
      if (parsedData.features.length < 5) {
        throw StateError(
          'Elliott Bay chart has unexpectedly few features: ${parsedData.features.length}. '
          'Expected at least 5 features for a harbor chart.',
        );
      }

      _parseCache[cacheKey] = parsedData;
      return parsedData;
    } catch (e) {
      throw Exception('Failed to parse Elliott Bay chart: $e');
    }
  }

  /// Load and parse Puget Sound chart to S57ParsedData
  /// 
  /// Returns parsed S57 data with features, metadata, bounds, and spatial index.
  /// Results are cached for performance in subsequent test runs.
  /// 
  /// Throws [AppError] if parsing fails
  /// Throws [FileSystemException] if chart file not found
  static Future<S57ParsedData> loadParsedPugetSound({
    S57WarningCollector? warnings,
  }) async {
    const cacheKey = 'US3WA01M_parsed';
    if (_parseCache.containsKey(cacheKey)) {
      return _parseCache[cacheKey]!;
    }

    final bytes = await loadPugetSoundChartBytes();
    
    try {
      final parsedData = S57Parser.parse(bytes.toList(), warnings: warnings);
      
      // Validate parsed data contains expected features
      if (parsedData.features.isEmpty) {
        throw StateError('Puget Sound chart parsing produced no features');
      }

      // Expected to have many features for a coastal chart
      if (parsedData.features.length < 10) {
        throw StateError(
          'Puget Sound chart has unexpectedly few features: ${parsedData.features.length}. '
          'Expected at least 10 features for a coastal chart.',
        );
      }

      _parseCache[cacheKey] = parsedData;
      return parsedData;
    } catch (e) {
      throw Exception('Failed to parse Puget Sound chart: $e');
    }
  }

  // ============================================================================
  // Chart Model Creation Methods
  // ============================================================================

  /// Create Chart model from Elliott Bay S57 data
  /// 
  /// Converts parsed S57 data into NavTool Chart model format for use in
  /// tests that expect Chart objects rather than raw S57 data.
  static Future<Chart> createElliottBayChart({
    S57WarningCollector? warnings,
  }) async {
    final parsedData = await loadParsedElliottBay(warnings: warnings);
    
    return Chart(
      id: 'US5WA50M',
      title: parsedData.metadata.title ?? 'Elliott Bay Harbor (US5WA50M)',
      scale: parsedData.metadata.scale ?? 20000,
      bounds: GeographicBounds(
        north: parsedData.bounds.north,
        south: parsedData.bounds.south,
        east: parsedData.bounds.east,
        west: parsedData.bounds.west,
      ),
      lastUpdate: parsedData.metadata.issueDate ?? DateTime.now(),
      state: 'Washington',
      type: ChartType.harbor,
      source: ChartSource.noaa,
      status: ChartStatus.current,
      edition: parsedData.metadata.editionNumber ?? 1,
      updateNumber: parsedData.metadata.updateNumber ?? 0,
      description: 'Real NOAA ENC harbor chart for Elliott Bay, Seattle',
      fileSize: (await loadElliottBayChartBytes()).length,
      metadata: {
        'source_type': 's57_enc',
        'feature_count': parsedData.features.length,
        'usage_band': 5,
        'chart_format': 'S57_ENC',
        'datum': parsedData.metadata.horizontalDatum ?? 'WGS84',
      },
    );
  }

  /// Create Chart model from Puget Sound S57 data
  /// 
  /// Converts parsed S57 data into NavTool Chart model format for use in
  /// tests that expect Chart objects rather than raw S57 data.
  static Future<Chart> createPugetSoundChart({
    S57WarningCollector? warnings,
  }) async {
    final parsedData = await loadParsedPugetSound(warnings: warnings);
    
    return Chart(
      id: 'US3WA01M',
      title: parsedData.metadata.title ?? 'Puget Sound (US3WA01M)',
      scale: parsedData.metadata.scale ?? 90000,
      bounds: GeographicBounds(
        north: parsedData.bounds.north,
        south: parsedData.bounds.south,
        east: parsedData.bounds.east,
        west: parsedData.bounds.west,
      ),
      lastUpdate: parsedData.metadata.issueDate ?? DateTime.now(),
      state: 'Washington',
      type: ChartType.coastal,
      source: ChartSource.noaa,
      status: ChartStatus.current,
      edition: parsedData.metadata.editionNumber ?? 1,
      updateNumber: parsedData.metadata.updateNumber ?? 0,
      description: 'Real NOAA ENC coastal chart for Puget Sound region',
      fileSize: (await loadPugetSoundChartBytes()).length,
      metadata: {
        'source_type': 's57_enc',
        'feature_count': parsedData.features.length,
        'usage_band': 3,
        'chart_format': 'S57_ENC',
        'datum': parsedData.metadata.horizontalDatum ?? 'WGS84',
      },
    );
  }

  // ============================================================================
  // Utility and Validation Methods
  // ============================================================================

  /// Check if S57 test fixtures are available
  /// 
  /// Returns true if both Elliott Bay and Puget Sound chart files exist
  /// and are readable. Useful for skipping tests when fixtures are missing.
  static Future<bool> areFixturesAvailable() async {
    try {
      final elliottBayPath = path.join(fixturesPath, 'US5WA50M', 'US5WA50M.000');
      final pugetSoundPath = path.join(fixturesPath, 'US3WA01M', 'US3WA01M.000');
      
      final elliottFile = File(elliottBayPath);
      final pugetFile = File(pugetSoundPath);
      
      return await elliottFile.exists() && await pugetFile.exists();
    } catch (e) {
      return false;
    }
  }

  /// Get chart metadata without full parsing
  /// 
  /// Extracts basic metadata from chart file header for quick validation
  /// without performing full feature parsing.
  static Future<Map<String, dynamic>> getChartMetadata(String chartId) async {
    Uint8List bytes;
    
    switch (chartId.toUpperCase()) {
      case 'US5WA50M':
        bytes = await loadElliottBayChartBytes();
        break;
      case 'US3WA01M':
        bytes = await loadPugetSoundChartBytes();
        break;
      default:
        throw ArgumentError('Unknown chart ID: $chartId');
    }

    try {
      // Parse just enough to get metadata
      final parsedData = S57Parser.parse(bytes.toList());
      return {
        'id': chartId,
        'title': parsedData.metadata.title,
        'scale': parsedData.metadata.scale,
        'edition': parsedData.metadata.editionNumber,
        'issue_date': parsedData.metadata.issueDate?.toIso8601String(),
        'bounds': {
          'north': parsedData.bounds.north,
          'south': parsedData.bounds.south,
          'east': parsedData.bounds.east,
          'west': parsedData.bounds.west,
        },
        'feature_count': parsedData.features.length,
        'file_size': bytes.length,
      };
    } catch (e) {
      throw Exception('Failed to extract metadata from chart $chartId: $e');
    }
  }

  /// Clear all caches
  /// 
  /// Useful for testing cache functionality or ensuring fresh data loads
  static void clearCaches() {
    _parseCache.clear();
    _bytesCache.clear();
  }

  /// Get available chart IDs
  /// 
  /// Returns list of chart IDs that have fixtures available
  static List<String> getAvailableChartIds() {
    return ['US5WA50M', 'US3WA01M'];
  }

  // ============================================================================
  // Marine Navigation Test Utilities
  // ============================================================================

  /// Get marine test areas with real chart coverage
  /// 
  /// Returns test-friendly coordinate ranges within actual chart coverage
  /// for testing navigation calculations with real data.
  static List<Map<String, dynamic>> getMarineTestAreas() {
    return [
      {
        'name': 'Elliott Bay Harbor',
        'chart_id': 'US5WA50M',
        'center_lat': 47.600,
        'center_lon': -122.340,
        'bounds': {
          'north': 47.650,
          'south': 47.550,
          'east': -122.300,
          'west': -122.380,
        },
        'scale': 20000,
        'usage_band': 5,
        'features': ['navigation_aids', 'depth_contours', 'harbor_facilities'],
      },
      {
        'name': 'Puget Sound Coastal',
        'chart_id': 'US3WA01M',
        'center_lat': 47.500,
        'center_lon': -122.500,
        'bounds': {
          'north': 48.000,
          'south': 47.000,
          'east': -122.200,
          'west': -122.800,
        },
        'scale': 90000,
        'usage_band': 3,
        'features': ['coastlines', 'depth_areas', 'major_navigation_routes'],
      },
    ];
  }

  /// Validate chart data integrity
  /// 
  /// Performs basic validation on parsed chart data to ensure it meets
  /// expectations for marine navigation testing.
  static bool validateChartData(S57ParsedData parsedData, String expectedChartId) {
    // Check metadata exists
    if (parsedData.metadata.title?.isEmpty ?? true) {
      return false;
    }

    // Check features exist
    if (parsedData.features.isEmpty) {
      return false;
    }

    // Check bounds are reasonable for Puget Sound area
    final bounds = parsedData.bounds;
    if (bounds.north < 46.0 || bounds.north > 49.0 ||
        bounds.south < 46.0 || bounds.south > 49.0 ||
        bounds.east > -120.0 || bounds.east < -125.0 ||
        bounds.west > -120.0 || bounds.west < -125.0) {
      return false;
    }

    // Check spatial index was created
    if (parsedData.spatialIndex.featureCount != parsedData.features.length) {
      return false;
    }

    return true;
  }
}