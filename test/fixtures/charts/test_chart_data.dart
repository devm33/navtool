import 'dart:io';
import 'package:path/path.dart' as path;

/// Test chart data paths and utilities for accessing NOAA ENC test fixtures
class TestChartData {
  // Standardized S57 fixture path (proper ENC directory structure)
  static const String _baseFixturesPath = 'test/fixtures/charts/s57_data/ENC_ROOT';
  
  // Legacy ZIP fixture path (for backward compatibility)
  static const String _legacyZipPath = 'test/fixtures/charts/noaa_enc';

  /// Elliott Bay harbor-scale chart (US5WA50M)
  /// Uses proper S57 directory structure: US5WA50M/US5WA50M.000
  static String get elliottBayHarborChart =>
      path.join(_baseFixturesPath, 'US5WA50M', 'US5WA50M.000');

  /// Elliott Bay harbor chart (legacy ZIP format for backward compatibility)
  static String get elliottBayHarborChartZip =>
      path.join(_legacyZipPath, 'US5WA50M_harbor_elliott_bay.zip');

  /// Puget Sound coastal-scale chart (US3WA01M)  
  /// Uses proper S57 directory structure: US3WA01M/US3WA01M.000
  static String get pugetSoundCoastalChart =>
      path.join(_baseFixturesPath, 'US3WA01M', 'US3WA01M.000');

  /// Puget Sound coastal chart (legacy ZIP format for backward compatibility)
  static String get pugetSoundCoastalChartZip =>
      path.join(_legacyZipPath, 'US3WA01M_coastal_puget_sound.zip');

  /// Get S57 chart directory path (contains .000, .001, etc. files)
  static String getS57ChartDirectory(String chartId) {
    return path.join(_baseFixturesPath, chartId);
  }

  /// Get the base S57 fixture path  
  static String get s57FixturesPath => _baseFixturesPath;

  /// Get the legacy ZIP fixture path
  static String get zipFixturesPath => _legacyZipPath;

  /// Get absolute path to chart fixture
  static String getAbsolutePath(String relativePath) {
    return path.join(Directory.current.path, relativePath);
  }

  /// Verify chart fixture exists (checks S57 format first, then ZIP fallback)
  static bool chartExists(String chartPath) {
    // Try S57 format first
    if (File(getAbsolutePath(chartPath)).existsSync()) {
      return true;
    }
    
    // Try ZIP fallback for legacy tests
    final zipPath = chartPath
        .replaceAll(_baseFixturesPath, _legacyZipPath)
        .replaceAll('.000', '.zip');
    return File(getAbsolutePath(zipPath)).existsSync();
  }

  /// Get all available test chart paths
  static List<String> getAllTestCharts() {
    return [elliottBayHarborChart, pugetSoundCoastalChart];
  }

  /// Get all available test charts (legacy ZIP format)
  static List<String> getAllTestChartsZip() {
    return [elliottBayHarborChartZip, pugetSoundCoastalChartZip];
  }

  /// Chart metadata for test validation
  static const Map<String, ChartTestMetadata> chartMetadata = {
    'US5WA50M': ChartTestMetadata(
      cellId: 'US5WA50M',
      title: 'APPROACHES TO EVERETT',
      usageBand: 5,
      scale: '1:20,000',
      region: 'Elliott Bay, Seattle Harbor',
      expectedSizeBytes: 147361,
      sha256:
          'B5C5C72CB867F045EB08AFA0E007D74E97D0E57D6C137349FA0056DB8E816FAE',
    ),
    'US3WA01M': ChartTestMetadata(
      cellId: 'US3WA01M',
      title: 'Puget Sound Coastal',
      usageBand: 3,
      scale: '1:90,000',
      region: 'Puget Sound region',
      expectedSizeBytes: 640268,
      sha256: '', // To be filled when available
    ),
  };
}

/// Metadata for test chart validation
class ChartTestMetadata {
  final String cellId;
  final String title;
  final int usageBand;
  final String scale;
  final String region;
  final int expectedSizeBytes;
  final String sha256;

  const ChartTestMetadata({
    required this.cellId,
    required this.title,
    required this.usageBand,
    required this.scale,
    required this.region,
    required this.expectedSizeBytes,
    required this.sha256,
  });
}
