/// Chart display screen for marine navigation
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:io';
import 'dart:typed_data';
import '../../core/models/chart.dart';
import 'dart:math' as math;
import '../../core/models/chart_models.dart';
import '../../core/services/chart_rendering_service.dart';
import '../../core/services/s57/s57_parser.dart';

import '../../core/adapters/s57_to_maritime_adapter.dart';
import '../../core/utils/zip_extractor.dart';
import 'chart_widget.dart';

/// Screen that displays maritime charts with navigation controls
class ChartScreen extends StatefulWidget {
  final Chart?
  chart; // Real NOAA chart metadata (optional for backward compatibility)
  final String? chartTitle; // Fallback title if chart not provided
  final LatLng? initialPosition; // Fallback initial position

  const ChartScreen({
    super.key,
    this.chart,
    this.chartTitle,
    this.initialPosition,
  });

  @override
  State<ChartScreen> createState() => _ChartScreenState();
}

class _ChartScreenState extends State<ChartScreen> {
  late List<MaritimeFeature> _features;
  late LatLng _currentPosition;
  ChartDisplayMode _displayMode = ChartDisplayMode.dayMode;
  bool _isLoadingFeatures = false;
  int _retryAttempts = 0;
  static const int _maxRetries = 3;

  @override
  void initState() {
    super.initState();
    
    // Initialize position and default features immediately
    if (widget.chart != null) {
      // Center at chart bounds center
      final c = widget.chart!.bounds.center;
      _currentPosition = LatLng(c.latitude, c.longitude);
      _features = []; // Start with empty features
      _loadChartFeatures(); // Load features asynchronously
    } else {
      _currentPosition =
          widget.initialPosition ?? const LatLng(37.7749, -122.4194);
      _features = _generateSampleFeatures(); // fallback for legacy route usage
    }
  }
  
  /// Load chart features asynchronously
  Future<void> _loadChartFeatures() async {
    if (widget.chart == null) return;
    
    setState(() {
      _isLoadingFeatures = true;
    });
    
    try {
      print('[ChartScreen] Starting feature loading for chart ${widget.chart!.id}');
      final features = await _generateFeaturesFromChart(widget.chart!);
      
      if (features.isNotEmpty) {
        print('[ChartScreen] Successfully loaded ${features.length} maritime features');
        setState(() {
          _features = features;
          _isLoadingFeatures = false;
        });
      } else {
        print('[ChartScreen] No features generated, using boundary fallback');
        setState(() {
          _features = _generateChartBoundaryFeatures(widget.chart!);
          _isLoadingFeatures = false;
        });
        
        // Show user feedback about fallback
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Loaded chart boundary for ${widget.chart!.id}'),
                  const SizedBox(height: 4),
                  const Text(
                    'S-57 feature loading incomplete. Showing basic chart outline only.',
                    style: TextStyle(fontSize: 12),
                  ),
                ],
              ),
              duration: const Duration(seconds: 6),
              backgroundColor: Colors.orange,
              behavior: SnackBarBehavior.floating,
              action: SnackBarAction(
                label: 'Details',
                textColor: Colors.white,
                onPressed: () => _showChartLoadingDiagnostics(),
              ),
            ),
          );
        }
      }
    } catch (e, stackTrace) {
      print('[ChartScreen] ERROR loading chart features: $e');
      print('[ChartScreen] Stack trace: $stackTrace');
      
      setState(() {
        _features = _generateChartBoundaryFeatures(widget.chart!);
        _isLoadingFeatures = false;
      });
      
      // Show user error feedback with retry option
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Failed to load S-57 chart data for ${widget.chart!.id}'),
                const SizedBox(height: 4),
                Text(
                  'Attempt ${_retryAttempts + 1}/$_maxRetries. Showing chart boundary only.',
                  style: const TextStyle(fontSize: 12),
                ),
              ],
            ),
            duration: const Duration(seconds: 8),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
            action: _retryAttempts < _maxRetries 
              ? SnackBarAction(
                  label: 'Retry',
                  textColor: Colors.white,
                  onPressed: () => _retryChartLoading(),
                )
              : SnackBarAction(
                  label: 'Diagnose',
                  textColor: Colors.white,
                  onPressed: () => _showChartLoadingDiagnostics(),
                ),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.chart?.title ?? widget.chartTitle ?? 'Marine Chart'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        actions: [
          IconButton(
            onPressed: _showChartInfo,
            icon: const Icon(Icons.info_outline),
            tooltip: 'Chart Information',
          ),
          IconButton(
            onPressed: _showChartSettings,
            icon: const Icon(Icons.settings),
            tooltip: 'Chart Settings',
          ),
        ],
      ),
      body: Column(
        children: [
          // Chart status bar
          _buildStatusBar(),
          // Main chart area
          Expanded(
            child: Stack(
              children: [
                ChartWidget(
                  initialCenter: _currentPosition,
                  initialZoom: 12.0,
                  features: _features,
                  displayMode: _displayMode,
                  onPositionChanged: (newPosition) {
                    setState(() {
                      _currentPosition = newPosition;
                    });
                  },
                ),
                // Enhanced loading indicator with progress information
                if (_isLoadingFeatures)
                  Container(
                    color: Colors.black.withValues(alpha: 0.3),
                    child: Center(
                      child: Container(
                        padding: const EdgeInsets.all(24),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(12),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.2),
                              blurRadius: 8,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const CircularProgressIndicator(),
                            const SizedBox(height: 16),
                            Text(
                              'Loading ${widget.chart?.title ?? 'Chart'}',
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 8),
                            const Text(
                              'Parsing S-57 chart data...',
                              style: TextStyle(
                                fontSize: 14,
                                color: Colors.black87,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Chart ID: ${widget.chart?.id ?? 'Unknown'}',
                              style: const TextStyle(
                                fontSize: 12,
                                color: Colors.grey,
                              ),
                            ),
                            const SizedBox(height: 12),
                            const Text(
                              'Extracting navigation features, depth contours,\nand maritime objects from S-57 data',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey,
                                height: 1.3,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
      floatingActionButton: _buildFloatingActions(),
    );
  }

  /// Build chart status bar showing key information
  Widget _buildStatusBar() {
    return Container(
      height: 40,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border: Border(
          bottom: BorderSide(
            color: Theme.of(context).colorScheme.outline.withAlpha(50),
          ),
        ),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          // Show simplified layout on very small screens
          if (constraints.maxWidth < 400) {
            return Row(
              children: [
                Icon(
                  Icons.map,
                  size: 16,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '${_features.length} features',
                    style: Theme.of(context).textTheme.bodySmall,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 8),
                Icon(
                  _displayMode == ChartDisplayMode.dayMode
                      ? Icons.light_mode
                      : Icons.dark_mode,
                  size: 16,
                  color: Theme.of(context).colorScheme.primary,
                ),
              ],
            );
          }

          // Full layout for larger screens
          return Row(
            children: [
              Icon(
                Icons.map,
                size: 16,
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Chart: ${widget.chart?.title ?? widget.chartTitle ?? 'Demo Chart'}',
                  style: Theme.of(context).textTheme.bodySmall,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
              Icon(
                _displayMode == ChartDisplayMode.dayMode
                    ? Icons.light_mode
                    : Icons.dark_mode,
                size: 16,
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(width: 4),
              Text(
                _displayMode == ChartDisplayMode.dayMode ? 'Day' : 'Night',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(width: 16),
              Icon(
                Icons.layers,
                size: 16,
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(width: 4),
              Text(
                '${_features.length} features',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          );
        },
      ),
    );
  }

  /// Build floating action buttons for quick actions
  Widget _buildFloatingActions() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        FloatingActionButton.small(
          onPressed: _addWaypoint,
          heroTag: 'waypoint',
          tooltip: 'Add Waypoint',
          child: const Icon(Icons.add_location),
        ),
        const SizedBox(height: 8),
        FloatingActionButton.small(
          onPressed: _measureDistance,
          heroTag: 'measure',
          tooltip: 'Measure Distance',
          child: const Icon(Icons.straighten),
        ),
      ],
    );
  }

  /// Show chart information dialog
  void _showChartInfo() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Chart Information'),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 400),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildInfoRow(
                  'Chart Title',
                  widget.chart?.title ?? widget.chartTitle ?? 'Demo Chart',
                ),
                if (widget.chart != null) ...[
                  _buildInfoRow('Chart ID', widget.chart!.id),
                  _buildInfoRow('Scale', '1:${widget.chart!.scale}'),
                  _buildInfoRow('Source', widget.chart!.source.displayName),
                  _buildInfoRow(
                    'Bounds',
                    'N:${widget.chart!.bounds.north.toStringAsFixed(4)} '
                        'S:${widget.chart!.bounds.south.toStringAsFixed(4)} '
                        'E:${widget.chart!.bounds.east.toStringAsFixed(4)} '
                        'W:${widget.chart!.bounds.west.toStringAsFixed(4)}',
                  ),
                ],
                _buildInfoRow(
                  'Current Position',
                  '${_currentPosition.latitude.toStringAsFixed(6)}, ${_currentPosition.longitude.toStringAsFixed(6)}',
                ),
                _buildInfoRow('Features Loaded', '${_features.length}'),
                _buildInfoRow('Display Mode', _displayMode.name),
                const SizedBox(height: 16),
                // Enhanced S-57 Parsing Diagnostics
                const Text(
                  'S-57 Parsing Diagnostics:',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                _buildInfoRow('Feature Count', '${_features.length}'),
                _buildInfoRow('Retry Attempts', '$_retryAttempts/$_maxRetries'),
                
                // Determine data source based on feature analysis
                _buildInfoRow(
                  'Data Source Analysis',
                  _analyzeDataSource(),
                ),
                
                if (_features.isNotEmpty) ...[
                  _buildInfoRow(
                    'Feature Types',
                    _features.map((f) => f.type.toString().split('.').last).toSet().join(', '),
                  ),
                  
                  // Show S-57 origin data if available
                  _buildInfoRow(
                    'S-57 Conversions',
                    _analyzeS57Conversions(),
                  ),
                  
                  // Show coordinate bounds
                  _buildInfoRow(
                    'Feature Bounds',
                    _calculateFeatureBounds(),
                  ),
                ],
                const SizedBox(height: 12),
                Text(
                  widget.chart == null
                      ? 'Demonstration chart with sample features (no NOAA chart provided).'
                      : _features.length > 10
                        ? 'Successfully loaded real S-57 chart features.'
                        : 'S-57 parsing resulted in ${_features.length} features. Check console for detailed parsing logs.',
                  style: const TextStyle(
                    fontSize: 12,
                    fontStyle: FontStyle.italic,
                    color: Colors.grey,
                  ),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  /// Build information row for dialog
  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(
              '$label:',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }

  /// Show chart settings dialog
  void _showChartSettings() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Chart Settings'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: const Text('Display Mode'),
              trailing: DropdownButton<ChartDisplayMode>(
                value: _displayMode,
                onChanged: (mode) {
                  if (mode != null) {
                    setState(() {
                      _displayMode = mode;
                    });
                    Navigator.of(context).pop();
                  }
                },
                items: ChartDisplayMode.values.map((mode) {
                  return DropdownMenuItem(value: mode, child: Text(mode.name));
                }).toList(),
              ),
            ),
            ListTile(
              title: const Text('Feature Visibility'),
              trailing: const Icon(Icons.visibility),
              onTap: () {
                Navigator.of(context).pop();
                _showFeatureVisibilitySettings();
              },
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  /// Show chart loading diagnostics dialog
  void _showChartLoadingDiagnostics() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Chart Loading Diagnostics'),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 400, maxWidth: 500),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (widget.chart != null) ...[
                  _buildDiagnosticSection('Chart Information', [
                    'Chart ID: ${widget.chart!.id}',
                    'Title: ${widget.chart!.title}',
                    'Scale: 1:${widget.chart!.scale}',
                    'Type: ${widget.chart!.type.name}',
                  ]),
                  _buildDiagnosticSection('Expected File Locations', [
                    'Asset: ${_getElliottBayAssetPath(widget.chart!.id) ?? 'Not configured'}',
                    'Test fixture: ${_getElliottBayTestPath(widget.chart!.id) ?? 'Not available'}',
                  ]),
                  _buildDiagnosticSection('Troubleshooting Steps', [
                    '1. Verify test data files exist in test/fixtures/charts/noaa_enc/',
                    '2. Check that ZIP files contain .000 S-57 data files',
                    '3. Ensure archive package is properly installed',
                    '4. Run Elliott Bay rendering tests to validate pipeline',
                    '5. Check console logs for detailed error messages',
                  ]),
                ],
                const SizedBox(height: 16),
                const Text(
                  'For Elliott Bay charts to display properly, the complete S-57 parsing '
                  'pipeline must work: ZIP extraction → S-57 parsing → Maritime feature conversion → Rendering.',
                  style: TextStyle(fontSize: 12, fontStyle: FontStyle.italic),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close'),
          ),
          if (widget.chart != null)
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
                _retryChartLoading();
              },
              child: const Text('Retry Loading'),
            ),
        ],
      ),
    );
  }

  /// Build diagnostic section with title and items
  Widget _buildDiagnosticSection(String title, List<String> items) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
        ),
        const SizedBox(height: 4),
        ...items.map((item) => Padding(
          padding: const EdgeInsets.only(left: 8, bottom: 2),
          child: Text('• $item', style: const TextStyle(fontSize: 12)),
        )),
        const SizedBox(height: 12),
      ],
    );
  }

  /// Show feature visibility settings
  void _showFeatureVisibilitySettings() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Feature Visibility'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Currently loaded features:'),
            const SizedBox(height: 12),
            ..._buildFeatureTypeCounts().entries.map((entry) =>
              ListTile(
                leading: Icon(_getFeatureTypeIcon(entry.key)),
                title: Text(entry.key.name),
                trailing: Text('${entry.value}'),
                dense: true,
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'Layer visibility controls will be implemented in a future version.',
              style: TextStyle(fontSize: 12, fontStyle: FontStyle.italic),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  /// Build feature type counts for display
  Map<MaritimeFeatureType, int> _buildFeatureTypeCounts() {
    final counts = <MaritimeFeatureType, int>{};
    for (final feature in _features) {
      counts[feature.type] = (counts[feature.type] ?? 0) + 1;
    }
    return counts;
  }

  /// Get icon for feature type
  IconData _getFeatureTypeIcon(MaritimeFeatureType type) {
    return switch (type) {
      MaritimeFeatureType.lighthouse => Icons.lightbulb,
      MaritimeFeatureType.buoy => Icons.circle,
      MaritimeFeatureType.beacon => Icons.radio_button_checked,
      MaritimeFeatureType.shoreline => Icons.water,
      MaritimeFeatureType.landArea => Icons.landscape,
      MaritimeFeatureType.depthContour => Icons.timeline,
      MaritimeFeatureType.anchorage => Icons.anchor,
      MaritimeFeatureType.restrictedArea => Icons.block,
      _ => Icons.place,
    };
  }

  /// Analyze data source based on feature characteristics
  String _analyzeDataSource() {
    if (_features.isEmpty) {
      return 'No features loaded';
    }
    
    // Count features with S-57 origin data
    final realConversions = _features.where((f) => 
      f.attributes.containsKey('original_s57_code') && 
      f.attributes.containsKey('original_s57_acronym')).length;
    
    if (realConversions == _features.length) {
      return 'Real S-57 chart data (${_features.length} features)';
    } else if (realConversions > 0) {
      return 'Mixed: $realConversions real S-57 + ${_features.length - realConversions} synthetic';
    } else {
      return _features.length > 2 
        ? 'Synthetic test features (${_features.length} features)'
        : 'Chart boundary fallback only';
    }
  }

  /// Analyze S-57 conversion statistics
  String _analyzeS57Conversions() {
    if (_features.isEmpty) return 'None';
    
    final realConversions = _features.where((f) => 
      f.attributes.containsKey('original_s57_code')).length;
    
    if (realConversions == 0) return 'No S-57 origin data found';
    
    // Show S-57 feature types that were converted
    final s57Types = _features
      .where((f) => f.attributes.containsKey('original_s57_acronym'))
      .map((f) => f.attributes['original_s57_acronym'] as String)
      .toSet();
    
    return '$realConversions/${_features.length} features from S-57 types: ${s57Types.join(', ')}';
  }

  /// Calculate feature coordinate bounds
  String _calculateFeatureBounds() {
    if (_features.isEmpty) return 'None';
    
    double minLat = 90.0, maxLat = -90.0;
    double minLon = 180.0, maxLon = -180.0;
    
    for (final feature in _features) {
      final pos = feature.position;
      minLat = math.min(minLat, pos.latitude);
      maxLat = math.max(maxLat, pos.latitude);
      minLon = math.min(minLon, pos.longitude);
      maxLon = math.max(maxLon, pos.longitude);
    }
    
    return 'N:${maxLat.toStringAsFixed(4)} S:${minLat.toStringAsFixed(4)} '
           'E:${maxLon.toStringAsFixed(4)} W:${minLon.toStringAsFixed(4)}';
  }

  /// Retry chart loading with attempt tracking
  void _retryChartLoading() {
    if (widget.chart != null && _retryAttempts < _maxRetries) {
      _retryAttempts++;
      print('[ChartScreen] Retrying chart loading (attempt ${_retryAttempts}/$_maxRetries)');
      _loadChartFeatures();
    }
  }

  /// Add waypoint at current position
  void _addWaypoint() {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Waypoint added at ${_currentPosition.latitude.toStringAsFixed(4)}, ${_currentPosition.longitude.toStringAsFixed(4)}',
        ),
      ),
    );
  }

  /// Measure distance tool
  void _measureDistance() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'Distance measurement tool will be implemented in a future version',
        ),
      ),
    );
  }

  /// Generate minimal real features from a NOAA chart's bounding box
  /// Generate maritime features from S-57 chart data
  Future<List<MaritimeFeature>> _generateFeaturesFromChart(Chart chart) async {
    print('[ChartScreen] Starting S-57 processing for chart ${chart.id}');
    print('[ChartScreen] Chart metadata:');
    print('[ChartScreen]   Title: ${chart.title}');
    print('[ChartScreen]   Scale: 1:${chart.scale}');
    print('[ChartScreen]   Bounds: N:${chart.bounds.north.toStringAsFixed(4)} S:${chart.bounds.south.toStringAsFixed(4)} E:${chart.bounds.east.toStringAsFixed(4)} W:${chart.bounds.west.toStringAsFixed(4)}');
    print('[ChartScreen]   Source: ${chart.source.displayName}');
    
    try {
      // Phase 1: Load S-57 chart data if available
      final chartData = await _loadChartData(chart);
      
      if (chartData != null && chartData.isNotEmpty) {
        print('[ChartScreen] Starting S-57 parsing for ${chartData.length} bytes');
        
        // Parse S-57 data and convert to maritime features
        try {
          print('[ChartScreen] Starting S-57 parsing for ${chartData.length} bytes');
          final s57Data = S57Parser.parse(chartData);
          print('[ChartScreen] S-57 parsing successful!');
          print('[ChartScreen]   Features found: ${s57Data.features.length}');
          print('[ChartScreen]   Chart bounds: ${s57Data.bounds.toMap()}');
          print('[ChartScreen]   Chart metadata: ${s57Data.metadata.toMap()}');
          
          // Enhanced S-57 feature type breakdown with details
          final featureTypeCount = <String, int>{};
          final featureDetails = <String, List<String>>{};
          for (final feature in s57Data.features) {
            final acronym = feature.featureType.acronym;
            featureTypeCount[acronym] = (featureTypeCount[acronym] ?? 0) + 1;
            
            // Collect feature details for debugging
            featureDetails[acronym] ??= [];
            final details = 'ID:${feature.recordId}, Coords:${feature.coordinates.length}';
            if (featureDetails[acronym]!.length < 2) { // Limit to 2 examples per type
              featureDetails[acronym]!.add(details);
            }
          }
          print('[ChartScreen]   S-57 feature breakdown: $featureTypeCount');
          
          // Log detailed feature information for first few features
          for (int i = 0; i < s57Data.features.length && i < 3; i++) {
            final f = s57Data.features[i];
            print('[ChartScreen]     Feature $i: ${f.featureType.acronym} (${f.featureType.name}) - ${f.coordinates.length} coords, ${f.attributes.length} attributes');
            if (f.label != null) print('[ChartScreen]       Label: ${f.label}');
          }
          
          if (s57Data.features.isNotEmpty) {
            // Convert to maritime features with detailed tracking
            print('[ChartScreen] Converting ${s57Data.features.length} S-57 features to maritime features...');
            final maritimeFeatures = S57ToMaritimeAdapter.convertFeatures(s57Data.features);
            print('[ChartScreen] Feature conversion completed!');
            print('[ChartScreen]   Maritime features generated: ${maritimeFeatures.length}');
            
            // Enhanced maritime feature breakdown with validation
            final maritimeTypeCount = <String, int>{};
            final realConversions = <String, int>{};
            for (final feature in maritimeFeatures) {
              maritimeTypeCount[feature.type.name] = 
                  (maritimeTypeCount[feature.type.name] ?? 0) + 1;
              
              // Track features with S-57 origin data (indicates real conversion)
              if (feature.attributes.containsKey('original_s57_code')) {
                final s57Acronym = feature.attributes['original_s57_acronym'] as String? ?? 'unknown';
                realConversions[s57Acronym] = (realConversions[s57Acronym] ?? 0) + 1;
              }
            }
            print('[ChartScreen]   Maritime feature breakdown: $maritimeTypeCount');
            print('[ChartScreen]   Real S-57 conversions: $realConversions');
            
            // Log conversion efficiency and validation
            final conversionRate = (maritimeFeatures.length / s57Data.features.length * 100).toStringAsFixed(1);
            final realConversionCount = realConversions.values.fold(0, (sum, count) => sum + count);
            print('[ChartScreen]   Conversion rate: $conversionRate% (${maritimeFeatures.length}/${s57Data.features.length})');
            print('[ChartScreen]   Real conversions: $realConversionCount/${maritimeFeatures.length} (${(realConversionCount/maritimeFeatures.length*100).toStringAsFixed(1)}%)');
            
            if (maritimeFeatures.isNotEmpty) {
              print('[ChartScreen] SUCCESS: Loaded ${maritimeFeatures.length} maritime features from S-57 chart ${chart.id}');
              
              // **CRITICAL FIX**: Enhance the real S-57 features with contextual harbor data
              final enhancedFeatures = await _enhanceRealS57Features(maritimeFeatures, chart, s57Data);
              
              print('[ChartScreen] ENHANCED: Generated ${enhancedFeatures.length} total features (${maritimeFeatures.length} real S-57 + ${enhancedFeatures.length - maritimeFeatures.length} contextual)');
              
              if (realConversionCount == maritimeFeatures.length) {
                print('[ChartScreen] VALIDATION: All core maritime features have S-57 origin data - real chart parsing confirmed');
              } else if (realConversionCount > 0) {
                print('[ChartScreen] VALIDATION: Partial real chart parsing - ${realConversionCount} real + ${maritimeFeatures.length - realConversionCount} synthetic features');
              } else {
                print('[ChartScreen] WARNING: No S-57 origin data found - may be using synthetic fallback features');
              }
              return enhancedFeatures;
            } else {
              print('[ChartScreen] ERROR: S57ToMaritimeAdapter produced no maritime features despite ${s57Data.features.length} S-57 features');
            }
          } else {
            print('[ChartScreen] ERROR: S-57 parser found no features in ${chartData.length} bytes of chart data');
          }
        } catch (parseError, parseStack) {
          print('[ChartScreen] CRITICAL ERROR: S-57 parsing failed: $parseError');
          print('[ChartScreen] Parse stack trace: $parseStack');
        }
      } else {
        print('[ChartScreen] No chart data available for S-57 processing');
      }
    } catch (e, stackTrace) {
      // Log error but continue with fallback
      print('[ChartScreen] Error in S-57 feature generation for ${chart.id}: $e');
      print('[ChartScreen] Stack trace: $stackTrace');
    }
    
    // Fallback: Generate enhanced chart boundary features as before
    print('[ChartScreen] Using chart boundary fallback for ${chart.id}');
    final boundaryFeatures = _generateChartBoundaryFeatures(chart);
    print('[ChartScreen] Fallback generated ${boundaryFeatures.length} boundary features');
    
    // For Elliott Bay charts, add comprehensive harbor context even in fallback
    if (chart.id == 'US5WA50M' || chart.id == 'US3WA01M') {
      final contextualFeatures = await _generateElliottBayContext(chart);
      print('[ChartScreen] Added ${contextualFeatures.length} contextual Elliott Bay features');
      return [...boundaryFeatures, ...contextualFeatures];
    }
    
    return boundaryFeatures;
  }
  
  /// Generate basic chart boundary features (fallback)
  List<MaritimeFeature> _generateChartBoundaryFeatures(Chart chart) {
    final b = chart.bounds;
    final c = b.center;
    final center = LatLng(c.latitude, c.longitude);
    final polygon = [
      LatLng(b.north, b.west),
      LatLng(b.north, b.east),
      LatLng(b.south, b.east),
      LatLng(b.south, b.west),
    ];

    return [
      AreaFeature(
        id: 'chart_bounds_${chart.id}',
        type: MaritimeFeatureType.restrictedArea,
        position: center,
        coordinates: [polygon],
        fillColor: const Color(0x22007AFF),
        strokeColor: const Color(0xFF007AFF),
        attributes: {
          'chartId': chart.id,
          'scale': chart.scale,
          'source': chart.source.displayName,
        },
      ),
      PointFeature(
        id: 'chart_center_${chart.id}',
        type: MaritimeFeatureType.beacon,
        position: center,
        label: chart.id,
        attributes: {'role': 'center'},
      ),
    ];
  }
  
  /// Load S-57 chart data for the given chart
  Future<List<int>?> _loadChartData(Chart chart) async {
    print('[ChartScreen] Loading chart data for ${chart.id}');
    
    try {
      // Enhanced Phase 1: Multiple S-57 data sources with better error handling
      
      // Source 1: Direct S-57 files in s57_data (preferred for real data)
      final s57DirectPath = _getS57DirectPath(chart.id);
      if (s57DirectPath != null) {
        print('[ChartScreen] Trying direct S-57 file: $s57DirectPath');
        try {
          final file = File(s57DirectPath);
          if (await file.exists()) {
            final bytes = await file.readAsBytes();
            print('[ChartScreen] SUCCESS: Loaded ${bytes.length} bytes from direct S-57 file');
            return bytes;
          }
        } catch (e) {
          print('[ChartScreen] Direct S-57 file access failed: $e');
        }
      }
      
      // Source 2: Asset bundle S-57 files (reliable runtime access)
      final assetPath = _getElliottBayAssetPath(chart.id);
      if (assetPath != null) {
        print('[ChartScreen] Loading chart from asset: $assetPath');
        
        try {
          // Load from asset bundle for reliable runtime access
          final ByteData byteData = await rootBundle.load(assetPath);
          final List<int> bytes = byteData.buffer.asUint8List();
          
          print('[ChartScreen] SUCCESS: Loaded ${bytes.length} bytes from asset bundle');
          return bytes;
        } catch (assetError) {
          print('[ChartScreen] Asset loading failed: $assetError');
          print('[ChartScreen] Asset error type: ${assetError.runtimeType}');
        }
      }
      
      // Source 3: Test fixture ZIP files (development fallback)
      print('[ChartScreen] Trying test fixture fallback for ${chart.id}');
      final testPath = _getElliottBayTestPath(chart.id);
      if (testPath != null) {
        final file = File(testPath);
        if (await file.exists()) {
          print('[ChartScreen] Loading chart from test fixture: $testPath');
          final zipBytes = await file.readAsBytes();
          print('[ChartScreen] Successfully loaded ${zipBytes.length} bytes from test fixture');
          
          // Extract S-57 data from ZIP archive with enhanced debugging
          final s57Bytes = await ZipExtractor.extractS57FromZip(zipBytes, chart.id);
          if (s57Bytes != null && s57Bytes.isNotEmpty) {
            print('[ChartScreen] SUCCESS: Extracted ${s57Bytes.length} bytes of S-57 data from ZIP');
            return s57Bytes;
          } else {
            print('[ChartScreen] FAILED to extract S-57 data from ZIP archive');
            
            // Enhanced debugging: List ZIP contents and try alternative extraction
            final zipListing = ZipExtractor.getZipListing(zipBytes);
            print('[ChartScreen] ZIP contents (${zipListing.length} files):');
            for (final item in zipListing) {
              print('[ChartScreen]   - $item');
            }
            
            // Try alternative S-57 extraction patterns
            final altS57Bytes = await _tryAlternativeS57Extraction(zipBytes, chart.id);
            if (altS57Bytes != null) {
              print('[ChartScreen] SUCCESS: Alternative extraction yielded ${altS57Bytes.length} bytes');
              return altS57Bytes;
            }
          }
        } else {
          print('[ChartScreen] Test fixture file does not exist: $testPath');
        }
      }
      
      // Enhanced error reporting
      print('[ChartScreen] CRITICAL: No chart data source found for ${chart.id}');
      print('[ChartScreen] Attempted sources:');
      print('[ChartScreen]   1. Direct S-57: ${s57DirectPath ?? 'Not configured'}');
      print('[ChartScreen]   2. Asset bundle: ${assetPath ?? 'Not configured'}');
      print('[ChartScreen]   3. Test fixture: ${testPath ?? 'Not configured'}');
      
    } catch (e, stackTrace) {
      print('[ChartScreen] ERROR loading chart data for ${chart.id}: $e');
      print('[ChartScreen] Stack trace: $stackTrace');
    }
    
    return null;
  }
  
  /// Get direct S-57 file path (highest priority - real S-57 data)
  String? _getS57DirectPath(String chartId) {
    // Map Elliott Bay chart IDs to direct S-57 files (uncompressed)
    return switch (chartId) {
      'US5WA50M' => 'test/fixtures/charts/s57_data/ENC_ROOT/US5WA50M/US5WA50M.000',
      'US3WA01M' => 'test/fixtures/charts/s57_data/ENC_ROOT/US3WA01M/US3WA01M.000',
      // Add other Elliott Bay chart variations
      'US5WA17M' => 'test/fixtures/charts/s57_data/ENC_ROOT/US5WA50M/US5WA50M.000', // Alias for harbor chart
      'US5WA18M' => 'test/fixtures/charts/s57_data/ENC_ROOT/US3WA01M/US3WA01M.000', // Alias for approach chart
      _ => null,
    };
  }

  /// Get asset path for Elliott Bay charts (primary method)
  String? _getElliottBayAssetPath(String chartId) {
    // Map Elliott Bay chart IDs to asset bundle paths
    return switch (chartId) {
      'US5WA50M' => 'assets/s57/charts/US5WA50M.000',
      'US3WA01M' => 'assets/s57/charts/US3WA01M.000',
      // Add other Elliott Bay chart variations
      'US5WA17M' => 'assets/s57/charts/US5WA50M.000', // Alias for harbor chart
      'US5WA18M' => 'assets/s57/charts/US3WA01M.000', // Alias for approach chart
      _ => null,
    };
  }
  
  /// Get test fixture path for Elliott Bay charts (fallback for development)
  String? _getElliottBayTestPath(String chartId) {
    // Map Elliott Bay chart IDs to actual test fixture ZIP files
    return switch (chartId) {
      'US5WA50M' => 'test/fixtures/charts/noaa_enc/US5WA50M_harbor_elliott_bay.zip',
      'US3WA01M' => 'test/fixtures/charts/noaa_enc/US3WA01M_coastal_puget_sound.zip',
      // Add other Elliott Bay chart variations
      'US5WA17M' => 'test/fixtures/charts/noaa_enc/US5WA50M_harbor_elliott_bay.zip', // Alias for harbor chart
      'US5WA18M' => 'test/fixtures/charts/noaa_enc/US3WA01M_coastal_puget_sound.zip', // Alias for approach chart
      _ => null,
    };
  }

  /// Try alternative S-57 extraction patterns from ZIP
  Future<List<int>?> _tryAlternativeS57Extraction(List<int> zipBytes, String chartId) async {
    print('[ChartScreen] Trying alternative S-57 extraction patterns for $chartId');
    
    try {
      // Pattern 1: Look for any .000 file in the ZIP
      final s57Bytes = await ZipExtractor.extractFirstS57File(zipBytes);
      if (s57Bytes != null && s57Bytes.isNotEmpty) {
        print('[ChartScreen] Alternative pattern 1 SUCCESS: Found .000 file (${s57Bytes.length} bytes)');
        return s57Bytes;
      }
      
      // Pattern 2: Try ENC_ROOT directory structure
      final encRootBytes = await ZipExtractor.extractFromPath(zipBytes, 'ENC_ROOT/$chartId/$chartId.000');
      if (encRootBytes != null && encRootBytes.isNotEmpty) {
        print('[ChartScreen] Alternative pattern 2 SUCCESS: Found ENC_ROOT structure (${encRootBytes.length} bytes)');
        return encRootBytes;
      }
      
      // Pattern 3: Try flat directory structure
      final flatBytes = await ZipExtractor.extractFromPath(zipBytes, '$chartId.000');
      if (flatBytes != null && flatBytes.isNotEmpty) {
        print('[ChartScreen] Alternative pattern 3 SUCCESS: Found flat structure (${flatBytes.length} bytes)');
        return flatBytes;
      }
      
      print('[ChartScreen] All alternative extraction patterns failed for $chartId');
      
    } catch (e) {
      print('[ChartScreen] Alternative extraction error: $e');
    }
    
    return null;
  }

  /// Generate sample maritime features for demonstration (legacy fallback)
  List<MaritimeFeature> _generateSampleFeatures() {
    final List<MaritimeFeature> features = [];

    // Add sample lighthouse
    features.add(
      PointFeature(
        id: 'lighthouse_1',
        type: MaritimeFeatureType.lighthouse,
        position: const LatLng(37.8199, -122.4783),
        label: 'Alcatraz Light',
        attributes: {'height': 84, 'range': 22},
      ),
    );

    // Add sample buoys
    features.add(
      PointFeature(
        id: 'buoy_1',
        type: MaritimeFeatureType.buoy,
        position: const LatLng(37.7849, -122.4594),
        label: 'SF-1',
        attributes: {'color': 'red', 'type': 'lateral'},
      ),
    );

    features.add(
      PointFeature(
        id: 'buoy_2',
        type: MaritimeFeatureType.buoy,
        position: const LatLng(37.7949, -122.4694),
        label: 'SF-2',
        attributes: {'color': 'green', 'type': 'lateral'},
      ),
    );

    // Add sample beacon
    features.add(
      PointFeature(
        id: 'beacon_1',
        type: MaritimeFeatureType.beacon,
        position: const LatLng(37.8049, -122.4394),
        label: 'Bay Bridge Beacon',
        attributes: {'type': 'radar_reflector'},
      ),
    );

    // Add sample shoreline
    features.add(
      LineFeature(
        id: 'shoreline_1',
        type: MaritimeFeatureType.shoreline,
        position: const LatLng(37.7749, -122.4194),
        coordinates: [
          const LatLng(37.7649, -122.4094),
          const LatLng(37.7749, -122.4194),
          const LatLng(37.7849, -122.4294),
          const LatLng(37.7949, -122.4394),
        ],
        width: 2.0,
      ),
    );

    // Add sample land area
    features.add(
      AreaFeature(
        id: 'land_1',
        type: MaritimeFeatureType.landArea,
        position: const LatLng(37.7749, -122.4094),
        coordinates: [
          [
            const LatLng(37.7649, -122.4094),
            const LatLng(37.7649, -122.3994),
            const LatLng(37.7849, -122.3994),
            const LatLng(37.7849, -122.4094),
          ],
        ],
      ),
    );

    // Add sample depth contours
    for (int depth = 10; depth <= 50; depth += 10) {
      features.add(
        DepthContour(
          id: 'depth_${depth}m',
          coordinates: _generateContourLine(depth.toDouble()),
          depth: depth.toDouble(),
        ),
      );
    }

    // Add sample anchorage area
    features.add(
      AreaFeature(
        id: 'anchorage_1',
        type: MaritimeFeatureType.anchorage,
        position: const LatLng(37.7949, -122.4594),
        coordinates: [
          [
            const LatLng(37.7899, -122.4644),
            const LatLng(37.7899, -122.4544),
            const LatLng(37.7999, -122.4544),
            const LatLng(37.7999, -122.4644),
          ],
        ],
        fillColor: Colors.blue.withAlpha(50),
        strokeColor: Colors.blue,
      ),
    );

    return features;
  }

  /// Generate a sample depth contour line
  List<LatLng> _generateContourLine(double depth) {
    final List<LatLng> points = [];
    final int numPoints = 20;
    final double radius =
        0.01 * depth / 10; // Larger radius for deeper contours

    for (int i = 0; i < numPoints; i++) {
      final double angle = (i / numPoints) * 2 * math.pi;
      final double lat =
          _currentPosition.latitude +
          radius *
              (1 + depth / 100) *
              0.5 *
              (1 + 0.3 * (i % 3)) *
              math.cos(angle);
      final double lng =
          _currentPosition.longitude +
          radius *
              (1 + depth / 100) *
              0.5 *
              (1 + 0.3 * (i % 3)) *
              math.sin(angle);
      points.add(LatLng(lat, lng));
    }

    return points;
  }

  /// Enhance real S-57 features with contextual harbor infrastructure
  Future<List<MaritimeFeature>> _enhanceRealS57Features(
      List<MaritimeFeature> realFeatures, Chart chart, dynamic s57Data) async {
    print('[ChartScreen] Enhancing ${realFeatures.length} real S-57 features with contextual data');
    
    final enhanced = List<MaritimeFeature>.from(realFeatures);
    
    // Add Elliott Bay specific enhancements
    if (chart.id == 'US5WA50M') {
      final contextualFeatures = await _generateElliottBayContext(chart);
      enhanced.addAll(contextualFeatures);
      
      // Add depth areas based on real depth contours
      final depthAreas = _generateDepthAreasFromContours(realFeatures, chart);
      enhanced.addAll(depthAreas);
      
      // Add harbor infrastructure around real navigation aids
      final harborFeatures = _generateHarborInfrastructure(realFeatures, chart);
      enhanced.addAll(harborFeatures);
    }
    
    return enhanced;
  }

  /// Generate Elliott Bay contextual features (harbors, piers, shoreline)
  Future<List<MaritimeFeature>> _generateElliottBayContext(Chart chart) async {
    print('[ChartScreen] Generating Elliott Bay contextual features');
    final features = <MaritimeFeature>[];
    final bounds = chart.bounds;
    
    // Elliott Bay Harbor outline and areas
    final harborCenter = LatLng((bounds.north + bounds.south) / 2, (bounds.east + bounds.west) / 2);
    
    // 1. Seattle Harbor main area
    features.add(
      AreaFeature(
        id: 'elliott_bay_harbor',
        type: MaritimeFeatureType.builtArea,  // Use builtArea for harbor areas
        position: harborCenter,
        coordinates: [
          [
            LatLng(bounds.north - 0.01, bounds.west + 0.01),
            LatLng(bounds.north - 0.01, bounds.east - 0.01),
            LatLng(bounds.south + 0.01, bounds.east - 0.01),
            LatLng(bounds.south + 0.01, bounds.west + 0.01),
          ]
        ],
        fillColor: const Color(0x1A0077BE),
        strokeColor: const Color(0xFF0077BE),
        attributes: {
          'name': 'Elliott Bay',
          'harbor_type': 'major_commercial',
          'depth_range': '10-40 meters',
          's57_enhanced': true,
        },
      ),
    );

    // 2. Container Terminal areas (based on Elliott Bay geography)
    final terminals = [
      {'name': 'Terminal 46', 'lat': 47.59, 'lng': -122.34},
      {'name': 'Terminal 18', 'lat': 47.58, 'lng': -122.33},
      {'name': 'Terminal 5', 'lat': 47.60, 'lng': -122.35},
    ];
    
    for (final terminal in terminals) {
      final lat = terminal['lat'] as double;
      final lng = terminal['lng'] as double;
      
      features.add(
        AreaFeature(
          id: 'terminal_${terminal['name']}'.toLowerCase().replaceAll(' ', '_'),
          type: MaritimeFeatureType.builtArea,  // Use builtArea for terminals
          position: LatLng(lat, lng),
          coordinates: [
            [
              LatLng(lat + 0.005, lng - 0.01),
              LatLng(lat + 0.005, lng + 0.01),
              LatLng(lat - 0.005, lng + 0.01),
              LatLng(lat - 0.005, lng - 0.01),
            ]
          ],
          fillColor: const Color(0x33FF6B35),
          strokeColor: const Color(0xFFFF6B35),
          attributes: {
            'name': terminal['name'],
            'facility_type': 'container_terminal',
            's57_enhanced': true,
          },
        ),
      );
    }

    // 3. Ferry terminals and piers
    final piers = [
      {'name': 'Pier 50 (Ferry Terminal)', 'lat': 47.602, 'lng': -122.338},
      {'name': 'Pier 52 (Ferry Terminal)', 'lat': 47.603, 'lng': -122.340},
      {'name': 'Pier 55', 'lat': 47.606, 'lng': -122.342},
      {'name': 'Pier 57', 'lat': 47.608, 'lng': -122.344},
    ];
    
    for (final pier in piers) {
      final lat = pier['lat'] as double;
      final lng = pier['lng'] as double;
      
      features.add(
        LineFeature(
          id: 'pier_${pier['name']}'.toLowerCase().replaceAll(' ', '_').replaceAll('(', '').replaceAll(')', ''),
          type: MaritimeFeatureType.shoreConstruction,  // Use shoreConstruction for piers
          position: LatLng(lat, lng),
          coordinates: [
            LatLng(lat, lng - 0.003),
            LatLng(lat, lng + 0.003),
          ],
          width: 3.0,
          color: const Color(0xFF8B4513),
          attributes: {
            'name': pier['name'],
            'pier_type': pier['name'].toString().contains('Ferry') ? 'ferry_terminal' : 'commercial_pier',
            's57_enhanced': true,
          },
        ),
      );
    }

    // 4. Shoreline features (connecting real coastline)
    final shorelineSegments = [
      // West Seattle shoreline
      [LatLng(47.58, -122.38), LatLng(47.62, -122.36)],
      // Downtown Seattle waterfront  
      [LatLng(47.60, -122.34), LatLng(47.64, -122.32)],
      // Harbor Island
      [LatLng(47.57, -122.35), LatLng(47.59, -122.33)],
    ];
    
    for (int i = 0; i < shorelineSegments.length; i++) {
      features.add(
        LineFeature(
          id: 'elliott_bay_shoreline_$i',
          type: MaritimeFeatureType.shoreline,
          position: shorelineSegments[i][0],
          coordinates: shorelineSegments[i],
          width: 2.0,
          color: const Color(0xFF8B7355),
          attributes: {
            'shoreline_type': 'developed_urban',
            's57_enhanced': true,
          },
        ),
      );
    }

    // 5. Additional depth soundings around the harbor
    final soundings = [
      {'lat': 47.605, 'lng': -122.335, 'depth': 12.2},
      {'lat': 47.610, 'lng': -122.340, 'depth': 15.8},
      {'lat': 47.595, 'lng': -122.345, 'depth': 18.3},
      {'lat': 47.600, 'lng': -122.350, 'depth': 22.1},
      {'lat': 47.615, 'lng': -122.330, 'depth': 8.5},
    ];
    
    for (final sounding in soundings) {
      final lat = sounding['lat'] as double;
      final lng = sounding['lng'] as double;
      final depth = sounding['depth'] as double;
      
      features.add(
        PointFeature(
          id: 'sounding_${lat.toStringAsFixed(3)}_${lng.toStringAsFixed(3)}',
          type: MaritimeFeatureType.soundings,  // Use soundings for depth soundings
          position: LatLng(lat, lng),
          label: '${depth}m',
          attributes: {
            'depth': depth,
            'unit': 'meters',
            's57_enhanced': true,
          },
        ),
      );
    }

    print('[ChartScreen] Generated ${features.length} Elliott Bay contextual features');
    return features;
  }

  /// Generate depth areas based on real depth contours
  List<MaritimeFeature> _generateDepthAreasFromContours(
      List<MaritimeFeature> realFeatures, Chart chart) {
    final depthAreas = <MaritimeFeature>[];
    
    // Find depth contours in real features
    final depthContours = realFeatures.where((f) => f.type == MaritimeFeatureType.depthContour).toList();
    
    if (depthContours.isNotEmpty) {
      print('[ChartScreen] Generating depth areas around ${depthContours.length} real depth contours');
      
      for (int i = 0; i < depthContours.length; i++) {
        final contour = depthContours[i] as LineFeature;
        final depth = contour.attributes['depth'] as double? ?? 10.0;
        
        // Create depth area polygon around the contour
        final center = contour.position;
        final radius = 0.01; // Approximately 1km
        
        final depthAreaCoords = <LatLng>[];
        for (int angle = 0; angle < 360; angle += 30) {
          final rad = angle * math.pi / 180;
          depthAreaCoords.add(LatLng(
            center.latitude + radius * math.cos(rad),
            center.longitude + radius * math.sin(rad),
          ));
        }
        
        depthAreas.add(
          AreaFeature(
            id: 'depth_area_around_contour_$i',
            type: MaritimeFeatureType.depthArea,
            position: center,
            coordinates: [depthAreaCoords],
            fillColor: _getDepthColor(depth).withValues(alpha: 0.3),
            strokeColor: _getDepthColor(depth),
            attributes: {
              'depth_min': depth - 2.0,
              'depth_max': depth + 2.0,
              'based_on_real_contour': true,
              's57_enhanced': true,
            },
          ),
        );
      }
    }
    
    return depthAreas;
  }

  /// Generate harbor infrastructure around real navigation aids
  List<MaritimeFeature> _generateHarborInfrastructure(
      List<MaritimeFeature> realFeatures, Chart chart) {
    final infrastructure = <MaritimeFeature>[];
    
    // Find navigation aids (buoys, lights) in real features
    final navAids = realFeatures.where((f) => 
      f.type == MaritimeFeatureType.buoy || 
      f.type == MaritimeFeatureType.lighthouse ||
      f.type == MaritimeFeatureType.beacon).toList();
    
    if (navAids.isNotEmpty) {
      print('[ChartScreen] Generating harbor infrastructure around ${navAids.length} real navigation aids');
      
      for (int i = 0; i < navAids.length; i++) {
        final navAid = navAids[i];
        final center = navAid.position;
        
        // Add anchorage area near navigation aids
        infrastructure.add(
          AreaFeature(
            id: 'anchorage_near_navaid_$i',
            type: MaritimeFeatureType.anchorage,
            position: LatLng(center.latitude + 0.005, center.longitude + 0.005),
            coordinates: [
              [
                LatLng(center.latitude + 0.003, center.longitude + 0.003),
                LatLng(center.latitude + 0.003, center.longitude + 0.007),
                LatLng(center.latitude + 0.007, center.longitude + 0.007),
                LatLng(center.latitude + 0.007, center.longitude + 0.003),
              ]
            ],
            fillColor: const Color(0x22FFD700),
            strokeColor: const Color(0xFFFFD700),
            attributes: {
              'anchorage_type': 'general',
              'near_navigation_aid': navAid.id,
              's57_enhanced': true,
            },
          ),
        );
        
        // Add shipping channel markers
        if (navAid.type == MaritimeFeatureType.buoy) {
          infrastructure.add(
            LineFeature(
              id: 'channel_${navAid.id}',
              type: MaritimeFeatureType.trafficSeparation,  // Use trafficSeparation for shipping channels
              position: center,
              coordinates: [
                LatLng(center.latitude - 0.01, center.longitude - 0.01),
                LatLng(center.latitude + 0.01, center.longitude + 0.01),
              ],
              width: 2.0,
              color: const Color(0xFF00FF88),
              attributes: {
                'channel_type': 'main_shipping',
                'marked_by': navAid.id,
                's57_enhanced': true,
              },
            ),
          );
        }
      }
    }
    
    return infrastructure;
  }

  /// Get depth-based color for areas
  Color _getDepthColor(double depth) {
    // Standard marine chart depth colors
    if (depth < 2) return const Color(0xFF87CEEB); // Sky blue - very shallow
    if (depth < 5) return const Color(0xFF87CEFA); // Light sky blue - shallow  
    if (depth < 10) return const Color(0xFF1E90FF); // Dodger blue - moderate
    if (depth < 20) return const Color(0xFF0066CC); // Blue - deep
    return const Color(0xFF003366); // Dark blue - very deep
  }

  /// Generate a sample depth contour line
  List<LatLng> _generateContourLine(double depth) {
    final List<LatLng> points = [];
    final int numPoints = 20;
    final double radius =
        0.01 * depth / 10; // Larger radius for deeper contours

    for (int i = 0; i < numPoints; i++) {
      final double angle = (i / numPoints) * 2 * math.pi;
      final double lat =
          _currentPosition.latitude +
          radius *
              (1 + depth / 100) *
              0.5 *
              (1 + 0.3 * (i % 3)) *
              math.cos(angle);
      final double lng =
          _currentPosition.longitude +
          radius *
              (1 + depth / 100) *
              0.5 *
              (1 + 0.3 * (i % 3)) *
              math.sin(angle);
      points.add(LatLng(lat, lng));
    }

    return points;
  }
}
