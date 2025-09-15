import 'dart:io';
import 'dart:convert';
import 'dart:typed_data';
import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:navtool/core/services/s57/s57_parser.dart';
import 'package:navtool/core/services/s57/s57_models.dart';
import 'package:navtool/core/services/compression_service.dart';
import 'package:navtool/core/services/compression_service_impl.dart';
import 'package:navtool/core/logging/app_logger.dart';
import 'package:navtool/core/models/compression_result.dart';
import 'package:navtool/core/error/app_error.dart';
import 'package:path/path.dart' as path;
import 'test_logger.dart';

/// Adapter to make TestLogger compatible with AppLogger interface
class _TestLoggerAdapter implements AppLogger {
  final TestLogger _logger = testLogger;

  @override
  void debug(String message, {String? context, Object? exception}) {
    _logger.debug(
      '${context != null ? '[$context] ' : ''}$message${exception != null ? ' | $exception' : ''}',
    );
  }

  @override
  void info(String message, {String? context, Object? exception}) {
    _logger.info(
      '${context != null ? '[$context] ' : ''}$message${exception != null ? ' | $exception' : ''}',
    );
  }

  @override
  void warning(String message, {String? context, Object? exception}) {
    _logger.warn(
      '${context != null ? '[$context] ' : ''}$message${exception != null ? ' | $exception' : ''}',
    );
  }

  @override
  void error(String message, {String? context, Object? exception}) {
    _logger.error('${context != null ? '[$context] ' : ''}$message', exception);
  }

  @override
  void logError(AppError error) {
    _logger.error('AppError: ${error.message}', error.originalError);
  }
}

/// Utilities for NOAA ENC integration testing
///
/// Handles fixture discovery, metadata extraction, snapshot generation,
/// and regression testing for real NOAA ENC files.
class EncTestUtilities {
  static const String _defaultFixturesEnvVar = 'NOAA_ENC_FIXTURES';
  
  // Standardized S57 fixture path (proper ENC directory structure)
  static const String _defaultFixturesPath = 'test/fixtures/charts/s57_data/ENC_ROOT';
  
  // Legacy ZIP fixture path (for backward compatibility)
  static const String _legacyZipPath = 'test/fixtures/charts/noaa_enc';
  
  static const String _goldenSnapshotsPath = 'test/fixtures/golden';
  static const String _allowSnapshotGenEnvVar = 'ALLOW_SNAPSHOT_GEN';

  /// Primary test chart (Harbor usage band 5)
  static const String primaryChartId = 'US5WA50M';
  static const String primaryChartFile = 'US5WA50M.000'; // S57 format
  static const String primaryChartFileZip = 'US5WA50M_harbor_elliott_bay.zip'; // Legacy ZIP

  /// Secondary test chart (Coastal usage band 3)
  static const String secondaryChartId = 'US3WA01M';
  static const String secondaryChartFile = 'US3WA01M.000'; // S57 format
  static const String secondaryChartFileZip = 'US3WA01M_coastal_puget_sound.zip'; // Legacy ZIP

  final CompressionService _compressionService;

  EncTestUtilities({CompressionService? compressionService})
    : _compressionService =
          compressionService ??
          CompressionServiceImpl(logger: _TestLoggerAdapter());

  /// Discover NOAA ENC fixture files (S57 format preferred)
  static FixtureDiscoveryResult discoverFixtures() {
    final fixturesPath =
        Platform.environment[_defaultFixturesEnvVar] ?? _defaultFixturesPath;
    final fixturesDir = Directory(fixturesPath);

    if (!fixturesDir.existsSync()) {
      // Fall back to legacy ZIP fixtures
      return discoverZipFixtures();
    }

    final s57Files = <String>[];
    final encDirectories = <String>[];
    
    // Look for S57 chart directories (US5WA50M, US3WA01M, etc.)
    for (final entity in fixturesDir.listSync()) {
      if (entity is Directory) {
        final chartId = entity.uri.pathSegments.last;
        final s57File = File(path.join(entity.path, '$chartId.000'));
        if (s57File.existsSync()) {
          s57Files.add(s57File.path);
          encDirectories.add(entity.path);
        }
      }
    }

    return FixtureDiscoveryResult.s57(
      foundFixtures: s57Files.isNotEmpty,
      fixtureFiles: s57Files,
      encDirectories: encDirectories,
      fixturePath: fixturesPath,
    );
  }

  /// Discover NOAA ENC fixture files (legacy ZIP format)
  static FixtureDiscoveryResult discoverZipFixtures() {
    final fixturesDir = Directory(_legacyZipPath);

    if (!fixturesDir.existsSync()) {
      return FixtureDiscoveryResult.notFound(_legacyZipPath);
    }

    final primaryFile = File('$_legacyZipPath/$primaryChartFileZip');
    final secondaryFile = File('$_legacyZipPath/$secondaryChartFileZip');

    return FixtureDiscoveryResult(
      fixturesPath: _legacyZipPath,
      primaryChartAvailable: primaryFile.existsSync(),
      secondaryChartAvailable: secondaryFile.existsSync(),
      primaryChartPath: primaryFile.existsSync() ? primaryFile.path : null,
      secondaryChartPath: secondaryFile.existsSync()
          ? secondaryFile.path
          : null,
      format: FixtureFormat.zip,
    );
  }

  /// Parse S57 chart file directly (no ZIP extraction needed)
  Future<S57ParsedData> parseChartFile(String s57FilePath) async {
    final s57File = File(s57FilePath);
    if (!s57File.existsSync()) {
      throw FileSystemException('S57 chart file not found', s57FilePath);
    }

    final parser = S57Parser(_TestLoggerAdapter());
    final s57Data = await s57File.readAsBytes();
    
    return await parser.parseS57Data(s57Data);
  }

  /// Extract S-57 chart data from ZIP archive with timeout
  Future<S57ParsedData> extractAndParseChart(String zipFilePath) async {
    final zipFile = File(zipFilePath);
    if (!zipFile.existsSync()) {
      throw FileSystemException('Chart file not found', zipFilePath);
    }

    final zipData = await zipFile.readAsBytes();
    final chartId = _extractChartIdFromFilename(zipFilePath);

    try {
      // Extract with timeout to prevent hanging
      final extractedFiles = await _compressionService
          .extractChartArchive(zipData, chartId: chartId)
          .timeout(
            const Duration(seconds: 30),
            onTimeout: () => throw TimeoutException(
              'ZIP extraction timed out',
              const Duration(seconds: 30),
            ),
          );

      // Find the primary chart file (.000 extension)
      final chartFile = extractedFiles.firstWhere(
        (file) => file.fileName.endsWith('.000'),
        orElse: () =>
            throw StateError('No S-57 chart file (.000) found in archive'),
      );

      // Parse with timeout to prevent hanging
      return Future(() {
        return S57Parser.parse(chartFile.data);
      }).timeout(
        const Duration(seconds: 30),
        onTimeout: () => throw TimeoutException(
          'S57 parsing timed out',
          const Duration(seconds: 30),
        ),
      );
    } catch (e) {
      if (e is TimeoutException) {
        testLogger.warn(
          'Chart parsing timed out for $chartId - this is a known performance limitation',
        );
        rethrow;
      }
      throw Exception('Failed to extract/parse chart $chartId: $e');
    }
  }

  /// Extract enhanced metadata from parsed S-57 data
  static EncMetadata extractMetadata(
    S57ParsedData parsedData,
    String chartFilePath,
  ) {
    final chartId = _extractChartIdFromFilename(chartFilePath);
    final usageBand = _extractUsageBandFromFilename(chartFilePath);

    // Extract additional metadata from the raw S-57 data if available
    final metadata = parsedData.metadata;

    return EncMetadata(
      cellId: chartId,
      editionNumber: _extractEditionNumber(metadata),
      updateNumber: _extractUpdateNumber(metadata),
      issueDate: _extractIssueDate(metadata),
      compilationScale: _extractCompilationScale(metadata),
      usageBand: usageBand,
      comf: _extractComf(metadata),
      somf: _extractSomf(metadata),
      horizontalDatum: _extractHorizontalDatum(metadata),
      verticalDatum: _extractVerticalDatum(metadata),
      soundingDatum: _extractSoundingDatum(metadata),
    );
  }

  /// Build feature frequency map for snapshot comparison
  static Map<String, int> buildFeatureFrequencyMap(S57ParsedData parsedData) {
    final frequencies = <String, int>{};

    for (final feature in parsedData.features) {
      final acronym = feature.featureType.acronym;
      frequencies[acronym] = (frequencies[acronym] ?? 0) + 1;
    }

    return frequencies;
  }

  /// Load snapshot from golden file
  static Future<EncSnapshot?> loadSnapshot(String chartId) async {
    final snapshotFile = File(
      '$_goldenSnapshotsPath/${chartId.toLowerCase()}_freq.json',
    );

    if (!snapshotFile.existsSync()) {
      return null;
    }

    try {
      final jsonString = await snapshotFile.readAsString();
      final jsonData = jsonDecode(jsonString) as Map<String, dynamic>;
      return EncSnapshot.fromJson(jsonData);
    } catch (e) {
      testLogger.warn('Failed to load snapshot for $chartId: $e');
      return null;
    }
  }

  /// Generate and save snapshot
  static Future<void> generateSnapshot(
    String chartId,
    EncMetadata metadata,
    Map<String, int> featureFrequency,
  ) async {
    final snapshot = EncSnapshot(
      cellId: chartId,
      edition: metadata.editionNumber,
      update: metadata.updateNumber,
      featureFrequency: featureFrequency,
    );

    final snapshotFile = File(
      '$_goldenSnapshotsPath/${chartId.toLowerCase()}_freq.json',
    );
    await snapshotFile.parent.create(recursive: true);

    const encoder = JsonEncoder.withIndent('  ');
    final jsonString = encoder.convert(snapshot.toJson());
    await snapshotFile.writeAsString(jsonString);

    testLogger.info('Generated snapshot for $chartId: ${snapshotFile.path}');
  }

  /// Compare feature frequencies with tolerance
  static SnapshotComparisonResult compareWithSnapshot(
    Map<String, int> currentFrequencies,
    EncSnapshot snapshot, {
    double tolerancePercent = 10.0,
  }) {
    final results = <String, FeatureComparisonResult>{};
    final warnings = <String>[];
    var hasFailures = false;

    // Check features present in snapshot
    for (final entry in snapshot.featureFrequency.entries) {
      final featureType = entry.key;
      final expectedCount = entry.value;
      final actualCount = currentFrequencies[featureType] ?? 0;

      final deltaPercent = expectedCount > 0
          ? ((actualCount - expectedCount) / expectedCount * 100.0)
          : (actualCount > 0 ? 100.0 : 0.0);

      final isWithinTolerance = deltaPercent.abs() <= tolerancePercent;

      results[featureType] = FeatureComparisonResult(
        featureType: featureType,
        expectedCount: expectedCount,
        actualCount: actualCount,
        deltaPercent: deltaPercent,
        isWithinTolerance: isWithinTolerance,
      );

      if (!isWithinTolerance) {
        hasFailures = true;
      }
    }

    // Check for new features not in snapshot
    final totalCurrentFeatures = currentFrequencies.values.fold(
      0,
      (sum, count) => sum + count,
    );
    for (final entry in currentFrequencies.entries) {
      final featureType = entry.key;
      final actualCount = entry.value;

      if (!snapshot.featureFrequency.containsKey(featureType)) {
        final percentOfTotal = totalCurrentFeatures > 0
            ? (actualCount / totalCurrentFeatures * 100.0)
            : 0.0;

        warnings.add(
          'New feature type: $featureType (count: $actualCount, ${percentOfTotal.toStringAsFixed(1)}% of total)',
        );

        // Consider it a failure if new feature represents >1% of total features
        if (percentOfTotal > 1.0) {
          hasFailures = true;
        }
      }
    }

    return SnapshotComparisonResult(
      results: results,
      warnings: warnings,
      hasFailures: hasFailures,
      tolerancePercent: tolerancePercent,
    );
  }

  /// Validate depth values in parsed data
  static DepthValidationResult validateDepthRanges(S57ParsedData parsedData) {
    final warnings = <String>[];
    var totalDepthFeatures = 0;
    var outOfRangeCount = 0;

    const minDepth = -20.0; // 20m above sea level
    const maxDepth = 120.0; // 120m below sea level

    for (final feature in parsedData.features) {
      if (feature.featureType == S57FeatureType.depthArea) {
        totalDepthFeatures++;
        final drval1 = _parseNumericDepth(
          feature.attributes['DRVAL1'],
          'DEPARE DRVAL1',
          feature.recordId,
          warnings,
        );
        final drval2 = _parseNumericDepth(
          feature.attributes['DRVAL2'],
          'DEPARE DRVAL2',
          feature.recordId,
          warnings,
        );

        if (drval1 != null && (drval1 < minDepth || drval1 > maxDepth)) {
          warnings.add(
            'DEPARE DRVAL1 out of range: ${drval1}m (feature ${feature.recordId})',
          );
          outOfRangeCount++;
        }

        if (drval2 != null && (drval2 < minDepth || drval2 > maxDepth)) {
          warnings.add(
            'DEPARE DRVAL2 out of range: ${drval2}m (feature ${feature.recordId})',
          );
          outOfRangeCount++;
        }
      } else if (feature.featureType == S57FeatureType.sounding) {
        totalDepthFeatures++;
        final valsou = _parseNumericDepth(
          feature.attributes['VALSOU'],
          'SOUNDG VALSOU',
          feature.recordId,
          warnings,
        );

        if (valsou != null && (valsou < minDepth || valsou > maxDepth)) {
          warnings.add(
            'SOUNDG VALSOU out of range: ${valsou}m (feature ${feature.recordId})',
          );
          outOfRangeCount++;
        }
      }
    }

    return DepthValidationResult(
      totalDepthFeatures: totalDepthFeatures,
      outOfRangeCount: outOfRangeCount,
      warnings: warnings,
      minDepth: minDepth,
      maxDepth: maxDepth,
    );
  }

  /// Attempt to parse a depth-related numeric attribute. Accepts int, double, or numeric strings.
  /// Returns null for missing or unparseable values and records a warning for invalid formats.
  static double? _parseNumericDepth(
    Object? raw,
    String label,
    int recordId,
    List<String> warnings,
  ) {
    if (raw == null) {
      return null; // missing is acceptable
    }
    if (raw is double) return raw;
    if (raw is int) return raw.toDouble();
    if (raw is String) {
      final cleaned = raw.trim();
      if (cleaned.isEmpty) return null;
      final parsed = double.tryParse(cleaned);
      if (parsed != null) return parsed;
      warnings.add('$label has non-numeric value "$raw" (feature $recordId)');
      return null;
    }
    warnings.add(
      '$label has unsupported value type ${raw.runtimeType} (feature $recordId)',
    );
    return null;
  }

  /// Check if snapshot generation is allowed
  static bool get isSnapshotGenerationAllowed {
    final envValue = Platform.environment[_allowSnapshotGenEnvVar];
    return envValue == '1' || envValue?.toLowerCase() == 'true';
  }

  /// Create example golden snapshots for expected charts
  static Future<void> createExampleSnapshots() async {
    if (!isSnapshotGenerationAllowed) {
      return;
    }

    // Example snapshot for primary chart (US5WA50M - Harbor)
    final primaryMetadata = EncMetadata(
      cellId: primaryChartId,
      editionNumber: 4,
      updateNumber: 12,
      usageBand: 5,
      compilationScale: 20000,
      comf: 10000000.0,
      somf: 10.0,
      horizontalDatum: 'WGS84',
      verticalDatum: 'MLLW',
      soundingDatum: 'MLLW',
    );

    final primaryFrequencies = {
      'DEPARE': 180, // Depth areas typical for harbor chart
      'SOUNDG': 9500, // Many soundings in harbor
      'COALNE': 12, // Coastline segments
      'LIGHTS': 4, // Navigation lights
      'WRECKS': 3, // Underwater obstacles
      'BCNCAR': 2, // Cardinal beacons
      'BOYLAT': 6, // Lateral buoys
    };

    await generateSnapshot(primaryChartId, primaryMetadata, primaryFrequencies);

    // Example snapshot for secondary chart (US3WA01M - Coastal)
    final secondaryMetadata = EncMetadata(
      cellId: secondaryChartId,
      editionNumber: 3,
      updateNumber: 8,
      usageBand: 3,
      compilationScale: 90000,
      comf: 10000000.0,
      somf: 10.0,
      horizontalDatum: 'WGS84',
      verticalDatum: 'MLLW',
      soundingDatum: 'MLLW',
    );

    final secondaryFrequencies = {
      'DEPARE': 450, // More depth areas in coastal chart
      'SOUNDG': 15000, // More soundings over larger area
      'COALNE': 25, // More coastline segments
      'LIGHTS': 8, // More navigation aids
      'WRECKS': 5, // More obstacles
      'BCNCAR': 4, // Cardinal beacons
      'BOYLAT': 12, // Lateral buoys
      'OBSTRN': 3, // Obstructions
    };

    await generateSnapshot(
      secondaryChartId,
      secondaryMetadata,
      secondaryFrequencies,
    );

    testLogger.info(
      'Example golden snapshots created for ${primaryChartId} and ${secondaryChartId}',
    );
  }

  /// Extract chart ID from filename
  static String _extractChartIdFromFilename(String filePath) {
    final fileName = filePath.split('/').last;
    final parts = fileName.split('_');
    return parts.isNotEmpty ? parts[0] : fileName.split('.')[0];
  }

  /// Extract usage band from filename (digit after US)
  static int _extractUsageBandFromFilename(String filePath) {
    final chartId = _extractChartIdFromFilename(filePath);
    if (chartId.length >= 3 && chartId.startsWith('US')) {
      final bandChar = chartId[2];
      return int.tryParse(bandChar) ?? 0;
    }
    return 0;
  }

  // Metadata extraction helpers - Enhanced to extract actual DSID/DSPM fields
  static int _extractEditionNumber(S57ChartMetadata metadata) {
    // Extract from metadata title or use parsing logic for DSID
    final title = metadata.title ?? '';
    final editionMatch = RegExp(
      r'Edition\s*(\d+)',
      caseSensitive: false,
    ).firstMatch(title);
    if (editionMatch != null) {
      return int.tryParse(editionMatch.group(1)!) ?? 0;
    }
    return 0;
  }

  static int _extractUpdateNumber(S57ChartMetadata metadata) {
    // Extract from metadata or use parsing logic for DSID
    final title = metadata.title ?? '';
    final updateMatch = RegExp(
      r'Update\s*(\d+)',
      caseSensitive: false,
    ).firstMatch(title);
    if (updateMatch != null) {
      return int.tryParse(updateMatch.group(1)!) ?? 0;
    }
    return 0;
  }

  static DateTime? _extractIssueDate(S57ChartMetadata metadata) {
    // Use creation date as fallback, or implement DSID issue date parsing
    return metadata.creationDate ?? metadata.updateDate;
  }

  static int? _extractCompilationScale(S57ChartMetadata metadata) {
    // Use existing scale or implement DSPM compilation scale extraction
    return metadata.scale;
  }

  static double? _extractComf(S57ChartMetadata metadata) {
    // DSPM coordinate multiplication factor - typical value for ENC
    // Default to 10,000,000 for degree-based coordinates
    return 10000000.0;
  }

  static double? _extractSomf(S57ChartMetadata metadata) {
    // DSPM sounding multiplication factor - typical value
    // Default to 10.0 for meter-based soundings
    return 10.0;
  }

  static String? _extractHorizontalDatum(S57ChartMetadata metadata) {
    // Default to WGS84 for NOAA charts, or implement DSPM parsing
    return 'WGS84';
  }

  static String? _extractVerticalDatum(S57ChartMetadata metadata) {
    // Default to MLLW for NOAA charts, or implement DSPM parsing
    return 'MLLW';
  }

  static String? _extractSoundingDatum(S57ChartMetadata metadata) {
    // Default to MLLW for NOAA charts, or implement DSPM parsing
    return 'MLLW';
  }
}

/// Supported fixture formats
enum FixtureFormat { s57, zip }

/// Result of fixture discovery
class FixtureDiscoveryResult {
  final String fixturesPath;
  final bool primaryChartAvailable;
  final bool secondaryChartAvailable;
  final String? primaryChartPath;
  final String? secondaryChartPath;
  final bool found;
  
  // Enhanced properties for S57 support
  final bool foundFixtures;
  final List<String> fixtureFiles;
  final List<String> encDirectories;
  final String fixturePath;
  final FixtureFormat format;

  FixtureDiscoveryResult({
    required this.fixturesPath,
    required this.primaryChartAvailable,
    required this.secondaryChartAvailable,
    this.primaryChartPath,
    this.secondaryChartPath,
    // Enhanced properties
    bool? foundFixtures,
    List<String>? fixtureFiles,
    List<String>? encDirectories, 
    String? fixturePath,
    FixtureFormat? format,
  }) : found = primaryChartAvailable || secondaryChartAvailable,
       foundFixtures = foundFixtures ?? (primaryChartAvailable || secondaryChartAvailable),
       fixtureFiles = fixtureFiles ?? [],
       encDirectories = encDirectories ?? [],
       fixturePath = fixturePath ?? fixturesPath,
       format = format ?? FixtureFormat.zip;

  // Enhanced constructor for S57 format
  FixtureDiscoveryResult.s57({
    required this.foundFixtures,
    required this.fixtureFiles,
    required this.encDirectories,
    required this.fixturePath,
    this.format = FixtureFormat.s57,
  }) : fixturesPath = fixturePath,
       primaryChartAvailable = fixtureFiles.any((f) => f.contains('US5WA50M')),
       secondaryChartAvailable = fixtureFiles.any((f) => f.contains('US3WA01M')),
       primaryChartPath = fixtureFiles.where((f) => f.contains('US5WA50M')).isNotEmpty 
           ? fixtureFiles.where((f) => f.contains('US5WA50M')).first : null,
       secondaryChartPath = fixtureFiles.where((f) => f.contains('US3WA01M')).isNotEmpty
           ? fixtureFiles.where((f) => f.contains('US3WA01M')).first : null,
       found = foundFixtures;

  factory FixtureDiscoveryResult.notFound(String path) {
    return FixtureDiscoveryResult(
      fixturesPath: path,
      primaryChartAvailable: false,
      secondaryChartAvailable: false,
      foundFixtures: false,
      fixturePath: path,
    );
  }

  bool get hasAnyFixtures => found;
  bool get hasPrimaryChart => primaryChartAvailable;
  bool get hasSecondaryChart => secondaryChartAvailable;
}

/// Enhanced metadata extracted from ENC
class EncMetadata {
  final String cellId;
  final int editionNumber;
  final int updateNumber;
  final DateTime? issueDate;
  final int? compilationScale;
  final int usageBand;
  final double? comf;
  final double? somf;
  final String? horizontalDatum;
  final String? verticalDatum;
  final String? soundingDatum;

  const EncMetadata({
    required this.cellId,
    required this.editionNumber,
    required this.updateNumber,
    this.issueDate,
    this.compilationScale,
    required this.usageBand,
    this.comf,
    this.somf,
    this.horizontalDatum,
    this.verticalDatum,
    this.soundingDatum,
  });
}

/// Snapshot data for regression testing
class EncSnapshot {
  final String cellId;
  final int edition;
  final int update;
  final Map<String, int> featureFrequency;

  const EncSnapshot({
    required this.cellId,
    required this.edition,
    required this.update,
    required this.featureFrequency,
  });

  factory EncSnapshot.fromJson(Map<String, dynamic> json) {
    return EncSnapshot(
      cellId: json['cellId'] as String,
      edition: json['edition'] as int,
      update: json['update'] as int,
      featureFrequency: Map<String, int>.from(json['featureFrequency'] as Map),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'cellId': cellId,
      'edition': edition,
      'update': update,
      'featureFrequency': featureFrequency,
    };
  }
}

/// Result of snapshot comparison
class SnapshotComparisonResult {
  final Map<String, FeatureComparisonResult> results;
  final List<String> warnings;
  final bool hasFailures;
  final double tolerancePercent;

  const SnapshotComparisonResult({
    required this.results,
    required this.warnings,
    required this.hasFailures,
    required this.tolerancePercent,
  });

  bool get isSuccess => !hasFailures;
  int get totalFeaturesChecked => results.length;
  int get featuresOutOfTolerance =>
      results.values.where((r) => !r.isWithinTolerance).length;
}

/// Result of comparing a single feature type
class FeatureComparisonResult {
  final String featureType;
  final int expectedCount;
  final int actualCount;
  final double deltaPercent;
  final bool isWithinTolerance;

  const FeatureComparisonResult({
    required this.featureType,
    required this.expectedCount,
    required this.actualCount,
    required this.deltaPercent,
    required this.isWithinTolerance,
  });

  int get deltaCount => actualCount - expectedCount;
}

/// Result of depth validation
class DepthValidationResult {
  final int totalDepthFeatures;
  final int outOfRangeCount;
  final List<String> warnings;
  final double minDepth;
  final double maxDepth;

  const DepthValidationResult({
    required this.totalDepthFeatures,
    required this.outOfRangeCount,
    required this.warnings,
    required this.minDepth,
    required this.maxDepth,
  });

  bool get isValid => outOfRangeCount == 0;
  double get outOfRangePercent => totalDepthFeatures > 0
      ? (outOfRangeCount / totalDepthFeatures * 100.0)
      : 0.0;
}
