import 'package:flutter/material.dart';
import 'dart:io' show Platform;
import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/models/chart.dart';
import '../../core/providers/noaa_providers.dart';
import '../../core/state/providers.dart';
import '../../core/fixtures/washington_charts.dart';
import '../../core/services/noaa/progressive_chart_loader.dart';
import '../../core/error/network_error_classifier.dart';
import '../../core/utils/network_resilience.dart';
import '../../core/logging/app_logger.dart';
import 'widgets/chart_card.dart';
import 'widgets/download_manager_panel.dart';

/// Main screen for browsing and discovering NOAA charts by US state
class ChartBrowserScreen extends ConsumerStatefulWidget {
  const ChartBrowserScreen({super.key});

  @override
  ConsumerState<ChartBrowserScreen> createState() => _ChartBrowserScreenState();
}

class _ChartBrowserScreenState extends ConsumerState<ChartBrowserScreen> {
  String? _selectedState;
  String _searchQuery = '';
  Set<ChartType> _selectedChartTypes = {};
  Set<String> _selectedChartIds = {};
  bool _isLoading = false;
  bool _isRefreshing = false;
  bool _includeTestCharts = true; // Default to showing test charts
  String? _errorMessage;
  Timer? _searchDebouncer;

  // Enhanced refresh state
  ChartLoadProgress? _refreshProgress;
  String? _activeRefreshId;
  StreamSubscription<ChartLoadProgress>? _refreshSubscription;
  DateTime? _lastRefreshTime;

  // Scale filtering
  double _minScale = 1000;
  double _maxScale = 10000000;
  bool _scaleFilterEnabled = false;

  // Date filtering
  DateTime? _startDate;
  DateTime? _endDate;
  bool _dateFilterEnabled = false;

  // Logger for debugging
  AppLogger? _logger;

  // List of US coastal states that have NOAA charts
  static const List<String> _coastalStates = [
    'Alabama',
    'Alaska',
    'California',
    'Connecticut',
    'Delaware',
    'Florida',
    'Georgia',
    'Hawaii',
    'Illinois',
    'Indiana',
    'Louisiana',
    'Maine',
    'Maryland',
    'Massachusetts',
    'Michigan',
    'Minnesota',
    'Mississippi',
    'Nevada',
    'New Hampshire',
    'New Jersey',
    'New York',
    'North Carolina',
    'Ohio',
    'Oregon',
    'Pennsylvania',
    'Rhode Island',
    'South Carolina',
    'Texas',
    'Vermont',
    'Virginia',
    'Washington',
    'Wisconsin',
  ];

  List<Chart> _charts = [];
  List<Chart> _filteredCharts = [];

  @override
  void initState() {
    super.initState();
    
    // Initialize with test environment detection
    final isTestEnv = Platform.environment.containsKey('FLUTTER_TEST');
    
    // Load toggle state with timeout protection
    _loadToggleStateWithTimeout();
    
    // Automatically discover charts based on location when screen loads
    bool allowDiscovery = true;
    if (isTestEnv) {
      // In test environment, skip auto discovery unless a mock GPS service is provided.
      try {
        final gpsSvc = ref.read(gpsServiceProvider);
        final typeName = gpsSvc.runtimeType.toString();
        final isMock = typeName.contains('Mock');
        if (!isMock) {
          allowDiscovery =
              false; // Avoid real GPS in tests (causes pumpAndSettle hang)
        }
      } catch (_) {
        allowDiscovery = false;
      }
    }
    
    if (allowDiscovery) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _discoverChartsBasedOnLocationWithTimeout();
      });
    }
  }

  @override
  void dispose() {
    _searchDebouncer?.cancel();
    _refreshSubscription?.cancel();
    _cancelActiveRefresh();
    super.dispose();
  }

  /// Manually refresh the chart catalog with enhanced progress tracking
  Future<void> _refreshChartCatalog() async {
    if (_isRefreshing) return; // Prevent multiple concurrent refreshes

    setState(() {
      _isRefreshing = true;
      _refreshProgress = null;
      _errorMessage = null;
    });

    try {
      // Initialize logger if not done yet
      _logger ??= ref.read(loggerProvider);
      
      // PHASE 1: Manual refresh implementation
      // Use NOAA discovery service directly (without automatic bootstrap)
      final discoveryService = ref.read(noaaChartDiscoveryServiceProvider);
      
      // Show initial progress
      setState(() {
        _refreshProgress = ChartLoadProgress(
          stage: ChartLoadStage.initializing,
          currentItem: 0,
          currentItemName: 'Initializing',
          progress: 0.0,
          completedItems: 0,
          totalItems: 1,
          eta: null,
          loadedCharts: [],
        );
      });

      List<Chart> refreshedCharts = [];
      
      // Try to refresh charts for all coastal states or specific state
      final statesToRefresh = _selectedState != null 
          ? [_selectedState!] 
          : _coastalStates;
      
      int completedStates = 0;
      for (final state in statesToRefresh) {
        try {
          setState(() {
            _refreshProgress = ChartLoadProgress(
              stage: ChartLoadStage.fetchingCatalog,
              currentItem: completedStates + 1,
              currentItemName: 'Loading $state',
              progress: completedStates / statesToRefresh.length,
              completedItems: completedStates,
              totalItems: statesToRefresh.length,
              eta: null,
              loadedCharts: refreshedCharts,
            );
          });

          // Try to get charts from API for this state
          final stateCharts = await discoveryService.discoverChartsByState(state);
          refreshedCharts.addAll(stateCharts);
          
          completedStates++;
          
          _logger?.info('Refreshed ${stateCharts.length} charts for $state');
          
        } catch (error) {
          _logger?.warning('Failed to refresh charts for $state: $error');
          // Continue with other states
          completedStates++;
        }
      }

      // Update completion status
      setState(() {
        _refreshProgress = ChartLoadProgress(
          stage: ChartLoadStage.completed,
          currentItem: statesToRefresh.length,
          currentItemName: 'Completed',
          progress: 1.0,
          completedItems: statesToRefresh.length,
          totalItems: statesToRefresh.length,
          eta: null,
          loadedCharts: refreshedCharts,
        );
      });

      // Show success message
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Chart catalog updated: ${refreshedCharts.length} charts refreshed'),
            backgroundColor: Colors.green,
          ),
        );
        
        // Reload current state charts
        if (_selectedState != null) {
          _loadChartsForState(_selectedState!);
        }
      }

    } catch (error) {
      _logger?.error('Manual refresh failed', exception: error);
      
      final errorType = NetworkErrorClassifier.classifyError(error as Exception);
      final errorMessage = NetworkErrorClassifier.getUserFriendlyMessage(errorType);
      
      if (mounted) {
        setState(() {
          _errorMessage = errorMessage;
        });
        
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Refresh failed: $errorMessage'),
            backgroundColor: Colors.red,
            action: SnackBarAction(
              label: 'Retry',
              onPressed: _refreshChartCatalog,
            ),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isRefreshing = false;
          _lastRefreshTime = DateTime.now();
        });
      }
    }
  }

  /// Cancel active refresh operation
  Future<void> _cancelActiveRefresh() async {
    if (_activeRefreshId != null) {
      try {
        final progressiveLoader = ref.read(progressiveChartLoaderProvider);
        await progressiveLoader.cancelLoading(_activeRefreshId!);
        
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Chart refresh cancelled'),
              backgroundColor: Colors.orange,
            ),
          );
        }
      } catch (error) {
        // Ignore cancellation errors
      } finally {
        _cleanupRefreshState();
      }
    }
  }

  /// Clean up refresh state
  void _cleanupRefreshState() {
    if (!mounted) return;
    
    setState(() {
      _isRefreshing = false;
      _refreshProgress = null;
      _activeRefreshId = null;
    });
    
    _refreshSubscription?.cancel();
    _refreshSubscription = null;
  }

  /// Load toggle state from SharedPreferences with timeout protection
  Future<void> _loadToggleStateWithTimeout() async {
    final isTestEnv = Platform.environment.containsKey('FLUTTER_TEST');
    
    if (isTestEnv) {
      // In test environment, use default values to avoid SharedPreferences hangs
      _includeTestCharts = true;
      return;
    }
    
    try {
      // Apply timeout to prevent test hangs
      final timeoutFuture = Future.delayed(const Duration(seconds: 5), () {
        // Use default values if timeout
        _includeTestCharts = true;
      });
      
      final loadFuture = _loadToggleState();
      
      await Future.any([timeoutFuture, loadFuture]);
    } catch (e) {
      // If loading fails, use default value (true)
      _includeTestCharts = true;
    }
  }

  /// Load toggle state from SharedPreferences
  Future<void> _loadToggleState() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final includeTestCharts = prefs.getBool('include_test_charts') ?? true; // Default to true
      if (mounted) {
        setState(() {
          _includeTestCharts = includeTestCharts;
        });
      }
    } catch (e) {
      // If loading fails, use default value (true)
      _includeTestCharts = true;
    }
  }

  /// Save toggle state to SharedPreferences
  Future<void> _saveToggleState(bool include) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('include_test_charts', include);
    } catch (e) {
      // Silently fail if storage fails
    }
  }

  /// Handle menu actions from the app bar
  void _handleMenuAction(String action) {
    switch (action) {
      case 'toggle_test_charts':
        setState(() {
          _includeTestCharts = !_includeTestCharts;
        });
        _saveToggleState(_includeTestCharts);
        // Refresh chart list if state is selected
        if (_selectedState != null) {
          _loadChartsForState(_selectedState!);
        }
        break;
      case 'refresh':
        _refreshChartCatalog();
        break;
      case 'cancel_refresh':
        _cancelActiveRefresh();
        break;
    }
  }

  /// Get progress text for display
  String _getProgressText() {
    final progress = _refreshProgress;
    if (progress == null) return 'Initializing...';

    switch (progress.stage) {
      case ChartLoadStage.initializing:
        return 'Starting refresh...';
      case ChartLoadStage.fetchingCatalog:
        return 'Fetching chart catalog...';
      case ChartLoadStage.processingCharts:
        final percentage = (progress.progress * 100).round();
        final eta = progress.eta;
        final etaText = eta != null ? ' • ${_formatDuration(eta)} remaining' : '';
        return '$percentage% (${progress.completedItems}/${progress.totalItems})$etaText';
      case ChartLoadStage.finalizing:
        return 'Finalizing...';
      case ChartLoadStage.completed:
        return 'Completed!';
      case ChartLoadStage.cancelled:
        return 'Cancelled';
      case ChartLoadStage.failed:
        return 'Failed';
    }
  }

  /// Format duration for display
  String _formatDuration(Duration duration) {
    if (duration.inHours > 0) {
      return '${duration.inHours}h ${duration.inMinutes % 60}m';
    } else if (duration.inMinutes > 0) {
      return '${duration.inMinutes}m';
    } else {
      return '${duration.inSeconds}s';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Chart Browser'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        actions: [
          if (_selectedChartIds.isNotEmpty)
            TextButton.icon(
              onPressed: _downloadSelectedCharts,
              icon: const Icon(Icons.download),
              label: const Text('Download Selected'),
              style: TextButton.styleFrom(
                foregroundColor: Theme.of(context).colorScheme.onPrimary,
              ),
            ),
          // Settings menu with test chart toggle and refresh
          PopupMenuButton<String>(
            onSelected: _handleMenuAction,
            tooltip: 'Chart Browser Settings',
            itemBuilder: (context) => [
              PopupMenuItem(
                value: 'toggle_test_charts',
                child: Row(
                  children: [
                    Icon(_includeTestCharts ? Icons.visibility : Icons.visibility_off),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(_includeTestCharts ? 'Hide Elliott Bay Charts' : 'Show Elliott Bay Charts'),
                    ),
                  ],
                ),
              ),
              PopupMenuItem(
                value: 'refresh',
                enabled: !_isRefreshing,
                child: Row(
                  children: [
                    _isRefreshing 
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.refresh),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Text('Refresh Chart Catalog'),
                          if (_refreshProgress != null && _isRefreshing)
                            Text(
                              _getProgressText(),
                              style: const TextStyle(
                                fontSize: 11,
                                color: Colors.grey,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              if (_isRefreshing)
                PopupMenuItem(
                  value: 'cancel_refresh',
                  child: Row(
                    children: [
                      const Icon(Icons.cancel, color: Colors.red),
                      const SizedBox(width: 8),
                      const Expanded(child: Text('Cancel Refresh')),
                    ],
                  ),
                ),
            ],
          ),
          IconButton(
            tooltip: 'Open Download Manager',
            icon: const Icon(Icons.cloud_download),
            onPressed: _showDownloadManager,
          ),
        ],
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final controls = _buildControlsSection();
          final selectedCountBar = _selectedChartIds.isNotEmpty
              ? Container(
                  key: const ValueKey('selected-count-bar'),
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  color: Theme.of(context).colorScheme.primaryContainer,
                  child: Text(
                    '${_selectedChartIds.length} selected',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Theme.of(context).colorScheme.onPrimaryContainer,
                    ),
                  ),
                )
              : const SizedBox.shrink();

          final bool compact =
              constraints.maxHeight > 0 && constraints.maxHeight < 300;

          // Wrap everything in a SingleChildScrollView and force the inner content list to shrinkWrap
          return SafeArea(
            top: false,
            bottom: false,
            child: SingleChildScrollView(
              padding: EdgeInsets.zero,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  controls,
                  // Test charts status banner
                  if (_includeTestCharts)
                    Container(
                      width: double.infinity,
                      color: Colors.blue.shade50,
                      padding: const EdgeInsets.all(8),
                      child: Row(
                        children: [
                          Icon(Icons.info_outline, color: Colors.blue),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Including Elliott Bay test charts (US5WA50M, US3WA01M)',
                              style: TextStyle(color: Colors.blue.shade700),
                            ),
                          ),
                        ],
                      ),
                    ),
                  selectedCountBar,
                  _buildContentSection(
                    shrinkWrap: true,
                    allowCompactLoading: true,
                    compactEmpty: compact,
                  ),
                ],
              ),
            ),
          );
        },
      ),
      bottomNavigationBar: _buildStatusBar(),
    );
  }

  /// Build status bar showing network status and refresh info
  Widget _buildStatusBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border: Border(
          top: BorderSide(
            color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.2),
            width: 1,
          ),
        ),
      ),
      child: Row(
        children: [
          // Network status indicator
          _buildNetworkStatusIndicator(),
          const SizedBox(width: 16),
          // Last refresh info
          Expanded(
            child: _buildRefreshStatusInfo(),
          ),
        ],
      ),
    );
  }

  /// Build network status indicator
  Widget _buildNetworkStatusIndicator() {
    return Consumer(
      builder: (context, ref, child) {
        return FutureBuilder<MarineNetworkConditions>(
          future: ref.read(networkResilienceProvider).assessMarineNetworkConditions(),
          builder: (context, snapshot) {
            final conditions = snapshot.data;
            if (conditions == null) {
              return const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.help_outline, size: 16, color: Colors.grey),
                  SizedBox(width: 4),
                  Text('Network: Unknown', style: TextStyle(fontSize: 12)),
                ],
              );
            }

            final (icon, color, text) = _getNetworkStatusDisplay(conditions);
            return Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 16, color: color),
                const SizedBox(width: 4),
                Text(
                  'Network: $text',
                  style: TextStyle(fontSize: 12, color: color),
                ),
              ],
            );
          },
        );
      },
    );
  }

  /// Build refresh status info
  Widget _buildRefreshStatusInfo() {
    if (_isRefreshing && _refreshProgress != null) {
      return Row(
        children: [
          SizedBox(
            width: 12,
            height: 12,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              value: _refreshProgress!.progress,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              _getProgressText(),
              style: const TextStyle(fontSize: 12),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      );
    } else if (_lastRefreshTime != null) {
      final timeAgo = DateTime.now().difference(_lastRefreshTime!);
      return Text(
        'Last refresh: ${_formatTimeAgo(timeAgo)} ago',
        style: const TextStyle(fontSize: 12, color: Colors.grey),
      );
    } else {
      return const Text(
        'No recent refresh',
        style: TextStyle(fontSize: 12, color: Colors.grey),
      );
    }
  }

  /// Get network status display info
  (IconData, Color, String) _getNetworkStatusDisplay(MarineNetworkConditions conditions) {
    switch (conditions.connectionQuality) {
      case ConnectionQuality.excellent:
        return (Icons.wifi, Colors.green, 'Excellent');
      case ConnectionQuality.good:
        return (Icons.wifi, Colors.green, 'Good');
      case ConnectionQuality.fair:
        return (Icons.wifi_2_bar, Colors.orange, 'Fair');
      case ConnectionQuality.poor:
        return (Icons.wifi_1_bar, Colors.red, 'Poor');
      case ConnectionQuality.veryPoor:
        return (Icons.wifi_1_bar, Colors.red, 'Very Poor');
      case ConnectionQuality.offline:
        return (Icons.wifi_off, Colors.grey, 'Offline');
    }
  }

  /// Format time ago for display
  String _formatTimeAgo(Duration timeAgo) {
    if (timeAgo.inDays > 0) {
      return '${timeAgo.inDays}d';
    } else if (timeAgo.inHours > 0) {
      return '${timeAgo.inHours}h';
    } else if (timeAgo.inMinutes > 0) {
      return '${timeAgo.inMinutes}m';
    } else {
      return '${timeAgo.inSeconds}s';
    }
  }

  Widget _buildControlsSection() {
    return Container(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          // State selection dropdown
          Row(
            children: [
              Expanded(
                child: Semantics(
                  label: 'Select a US state to browse charts',
                  child: DropdownButtonFormField<String>(
                    value: _selectedState,
                    decoration: const InputDecoration(
                      labelText: 'Select State',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.map),
                    ),
                    items: _coastalStates.map((state) {
                      return DropdownMenuItem(value: state, child: Text(state));
                    }).toList(),
                    onChanged: _onStateSelected,
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 16),

          // Search field
          Semantics(
            label: 'Search charts by name or description',
            child: TextField(
              decoration: InputDecoration(
                labelText: 'Search charts...',
                border: const OutlineInputBorder(),
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _searchQuery.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: _clearSearch,
                      )
                    : null,
              ),
              onChanged: _onSearchChanged,
            ),
          ),

          const SizedBox(height: 16),

          // Chart type filter chips
          Semantics(
            label: 'Filter charts by type',
            child: Wrap(
              spacing: 8,
              children: ChartType.values.map((type) {
                final isSelected = _selectedChartTypes.contains(type);
                return FilterChip(
                  label: Text(type.displayName),
                  selected: isSelected,
                  onSelected: (selected) =>
                      _onChartTypeFilterChanged(type, selected),
                );
              }).toList(),
            ),
          ),

          const SizedBox(height: 16),

          // Scale filtering section
          _buildScaleFilterSection(),

          const SizedBox(height: 16),

          // Date filtering section
          _buildDateFilterSection(),
        ],
      ),
    );
  }

  Widget _buildContentSection({
    bool shrinkWrap = false,
    bool allowCompactLoading = false,
    bool compactEmpty = false,
  }) {
    // If no state explicitly selected but charts (e.g., via GPS discovery) are available, skip empty state.
    if (_selectedState == null &&
        _charts.isEmpty &&
        !_isLoading &&
        _errorMessage == null) {
      return _buildEmptyState(
        icon: Icons.map_outlined,
        title: 'Select a State',
        message:
            'Choose a US state from the dropdown above to browse available charts.',
        compact: compactEmpty,
      );
    }

    if (_isLoading) {
      // In extremely small viewports (test harness) we avoid a centered Column that can overflow.
      if (allowCompactLoading) {
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: const [
              SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              SizedBox(width: 12),
              Text('Loading charts...'),
            ],
          ),
        );
      }
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('Loading charts...'),
          ],
        ),
      );
    }

    if (_errorMessage != null) {
      return _buildErrorState();
    }

    if (_filteredCharts.isEmpty) {
      return _buildEmptyState(
        icon: Icons.map_outlined,
        title: 'No charts found',
        message: 'No charts are available for the selected state and filters.',
      );
    }

    return ListView.builder(
      key: const ValueKey('chart-list'),
      shrinkWrap: shrinkWrap,
      physics: shrinkWrap ? const NeverScrollableScrollPhysics() : null,
      itemCount: _filteredCharts.length,
      itemBuilder: (context, index) {
        final chart = _filteredCharts[index];
        return ChartCard(
          chart: chart,
          isSelected: _selectedChartIds.contains(chart.id),
          onSelectionChanged: (selected) =>
              _onChartSelectionChanged(chart.id, selected ?? false),
          onTap: () => _onChartTapped(chart),
          onInfoTap: () => _showChartDetails(chart),
        );
      },
    );
  }

  Widget _buildEmptyState({
    required IconData icon,
    required String title,
    required String message,
    bool compact = false,
  }) {
    final content = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Icon(
          icon,
          size: compact ? 32 : 64,
          color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.4),
        ),
        SizedBox(height: compact ? 8 : 16),
        Text(
          title,
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
            color: Theme.of(
              context,
            ).colorScheme.onSurface.withValues(alpha: 0.6),
          ),
          textAlign: TextAlign.center,
        ),
        SizedBox(height: compact ? 4 : 8),
        Text(
          message,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: Theme.of(
              context,
            ).colorScheme.onSurface.withValues(alpha: 0.6),
          ),
          textAlign: TextAlign.center,
        ),
      ],
    );

    if (compact) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: content,
      );
    }
    return Center(
      child: Padding(padding: const EdgeInsets.all(32), child: content),
    );
  }

  Widget _buildErrorState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error, size: 64, color: Colors.red),
            const SizedBox(height: 16),
            const Text(
              'Failed to load charts',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: Colors.red,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              _errorMessage ?? 'An unknown error occurred',
              style: Theme.of(context).textTheme.bodyMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _retryLoadCharts,
              child: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }

  void _onStateSelected(String? state) {
    if (state != null && state != _selectedState) {
      setState(() {
        _selectedState = state;
        _selectedChartIds.clear();
        _charts.clear();
        _filteredCharts.clear();
        _errorMessage = null;
        // Reset filters when changing state
        _selectedChartTypes.clear();
        _scaleFilterEnabled = false;
        _dateFilterEnabled = false;
        _startDate = null;
        _endDate = null;
      });
      _loadChartsForState(state);
    }
  }

  void _onSearchChanged(String query) {
    setState(() {
      _searchQuery = query;
    });

    // Debounce search
    _searchDebouncer?.cancel();
    _searchDebouncer = Timer(const Duration(milliseconds: 300), () {
      _performSearch();
    });
  }

  void _onChartTypeFilterChanged(ChartType type, bool selected) {
    setState(() {
      if (selected) {
        _selectedChartTypes.add(type);
      } else {
        _selectedChartTypes.remove(type);
      }
    });
    _filterCharts();
  }

  void _onChartSelectionChanged(String chartId, bool selected) {
    setState(() {
      if (selected) {
        _selectedChartIds.add(chartId);
      } else {
        _selectedChartIds.remove(chartId);
      }
      // Debug: ensure state change triggers rebuild of selected count bar.
    });
  }

  void _onChartTapped(Chart chart) {
    // Navigate to chart display
    Navigator.pushNamed(
      context,
      '/chart',
      arguments: {'chart': chart, 'chartTitle': chart.title},
    );
  }

  void _clearSearch() {
    setState(() {
      _searchQuery = '';
    });
    _filterCharts();
  }

  /// Automatically discovers charts based on current GPS location with timeout protection
  Future<void> _discoverChartsBasedOnLocationWithTimeout() async {
    final isTestEnv = Platform.environment.containsKey('FLUTTER_TEST');
    
    if (isTestEnv) {
      // In test environment, skip location discovery to prevent hangs
      return;
    }
    
    try {
      // Apply timeout to prevent test hangs
      final timeoutFuture = Future.delayed(const Duration(seconds: 10), () {
        if (mounted) {
          setState(() {
            _isLoading = false;
            _errorMessage = 'Location discovery timed out. Please select a state manually.';
          });
        }
      });
      
      final locationFuture = _discoverChartsBasedOnLocation();
      
      await Future.any([timeoutFuture, locationFuture]);
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = 'Location discovery failed. Please select a state manually.';
        });
      }
    }
  }

  /// Automatically discovers charts based on current GPS location with Seattle fallback
  Future<void> _discoverChartsBasedOnLocation() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      // Get GPS service and discovery service
      final gpsService = ref.read(gpsServiceProvider);
      final discoveryService = ref.read(noaaChartDiscoveryServiceProvider);

      // Get current position with Seattle fallback
      final position = await gpsService.getCurrentPositionWithFallback();

      if (position != null) {
        // Discover charts based on location
        final charts = await discoveryService.discoverChartsByLocation(
          position,
        );

        if (mounted) {
          setState(() {
            _charts = charts;
            _isLoading = false;
          });
          _filterCharts();
        }
      } else {
        // Fallback to manual state selection if location discovery fails
        if (mounted) {
          setState(() {
            _isLoading = false;
            _errorMessage =
                'Unable to determine location. Please select a state manually.';
          });
        }
      }
    } catch (error) {
      // Fallback to manual state selection on error
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage =
              'Location discovery failed. Please select a state manually.';
        });
      }
    }
  }

  Future<void> _loadChartsForState(String state) async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      // Initialize logger if not done yet
      _logger ??= ref.read(loggerProvider);

      // PHASE 1: Remove automatic bootstrap dependency - Offline-first approach
      // Start with test data immediately (no network dependency)
      final testCharts = _includeTestCharts 
          ? WashingtonTestCharts.getChartsForState(state)
          : <Chart>[];

      // Try to get cached charts from previous manual refresh (optional)
      List<Chart> cachedCharts = [];
      try {
        final catalogService = ref.read(chartCatalogServiceProvider);
        // Use cached charts without forcing bootstrap
        cachedCharts = await catalogService.searchChartsWithFilters(
          '', // Empty query to get all charts
          {'state': state},
        );
      } catch (error) {
        // Ignore cache errors, use test data only
        _logger?.debug('Failed to load cached charts, using test data only: $error');
      }

      // Combine and deduplicate charts (cached charts take precedence over test charts)
      final allCharts = <String, Chart>{};
      
      // Add test charts first
      for (final chart in testCharts) {
        allCharts[chart.id] = chart;
      }
      
      // Add cached charts (overwrites test charts with same ID)
      for (final chart in cachedCharts) {
        allCharts[chart.id] = chart;
      }
      
      // Sort by type priority (Harbor > Approach > Coastal > General > Overview)
      final sortedCharts = allCharts.values.toList()
        ..sort(_chartPriorityComparator);

      if (mounted) {
        setState(() {
          _charts = sortedCharts;
          _isLoading = false;
        });
        _filterCharts();
      }

      // Log success for debugging
      _logger?.info('Loaded ${sortedCharts.length} charts for $state (${cachedCharts.length} cached, ${testCharts.length} test)');
      
    } catch (error) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = 'Using offline charts for $state';
          
          // Fallback to test data only in case of any error
          final fallbackCharts = _includeTestCharts 
              ? WashingtonTestCharts.getChartsForState(state)
              : <Chart>[];
          _charts = fallbackCharts..sort(_chartPriorityComparator);
        });
        _filterCharts();
      }
      
      _logger?.error('Chart loading error (using offline mode)', exception: error);
    }
  }

  /// Comparator for sorting charts by type priority
  int _chartPriorityComparator(Chart a, Chart b) {
    final aPriority = a.typePriority;
    final bPriority = b.typePriority;
    
    return aPriority.compareTo(bPriority);
  }

  void _performSearch() {
    if (_searchQuery.isEmpty) {
      _filterCharts();
      return;
    }

    try {
      final discoveryService = ref.read(noaaChartDiscoveryServiceProvider);
      discoveryService
          .searchCharts(
            _searchQuery,
            filters: _selectedState != null ? {'state': _selectedState!} : null,
          )
          .then((searchResults) {
            if (mounted) {
              setState(() {
                _charts = searchResults;
              });
              _filterCharts();
            }
          })
          .catchError((error) {
            if (mounted) {
              setState(() {
                _errorMessage = error.toString();
              });
            }
          });
    } catch (error) {
      setState(() {
        _errorMessage = error.toString();
      });
    }
  }

  void _filterCharts() {
    // Debounce rapid filtering calls to improve test stability
    if (_searchDebouncer?.isActive ?? false) _searchDebouncer!.cancel();
    _searchDebouncer = Timer(const Duration(milliseconds: 100), () {
      if (mounted) {
        setState(() {
          _filteredCharts = _charts.where((chart) {
            // Filter by chart type
            if (_selectedChartTypes.isNotEmpty &&
                !_selectedChartTypes.contains(chart.type)) {
              return false;
            }

            // Filter by scale range
            if (_scaleFilterEnabled) {
              if (chart.scale < _minScale || chart.scale > _maxScale) {
                return false;
              }
            }

            // Filter by date range
            if (_dateFilterEnabled) {
              if (_startDate != null && chart.lastUpdate.isBefore(_startDate!)) {
                return false;
              }
              if (_endDate != null &&
                  chart.lastUpdate.isAfter(
                    _endDate!.add(const Duration(days: 1)),
                  )) {
                return false;
              }
            }

            // Filter by search query
            if (_searchQuery.isNotEmpty) {
              final query = _searchQuery.toLowerCase();
              return chart.title.toLowerCase().contains(query) ||
                  chart.id.toLowerCase().contains(query) ||
                  (chart.description?.toLowerCase().contains(query) ?? false);
            }

            return true;
          }).toList();
        });
      }
    });
  }

  void _retryLoadCharts() {
    if (_selectedState != null) {
      _loadChartsForState(_selectedState!);
    }
  }

  void _downloadSelectedCharts() async {
    if (_selectedChartIds.isEmpty) return;

    try {
      final downloadService = ref.read(downloadServiceProvider);
      final selectedCharts = _charts
          .where((chart) => _selectedChartIds.contains(chart.id))
          .toList();
      // Enqueue without awaiting sequentially
      for (final chart in selectedCharts) {
        final downloadUrl = 'https://charts.noaa.gov/ENCs/${chart.id}.zip';
        // Use queue to avoid blocking UI thread
        // ignore: discarded_futures
        downloadService.addToQueue(chart.id, downloadUrl);
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Queued ${selectedCharts.length} chart downloads'),
          duration: const Duration(seconds: 2),
        ),
      );
      setState(() => _selectedChartIds.clear());
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to start downloads: $error'),
            duration: const Duration(seconds: 5),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _showDownloadManager() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) {
        return const SizedBox(height: 500, child: DownloadManagerPanel());
      },
    );
  }

  void _showChartDetails(Chart chart) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.map, color: Theme.of(context).colorScheme.primary),
            const SizedBox(width: 8),
            const Expanded(child: Text('Chart Details')),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              // Chart title and ID
              Card(
                color: Theme.of(context).colorScheme.primaryContainer,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        chart.title,
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'ID: ${chart.id}',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context)
                              .colorScheme
                              .onPrimaryContainer
                              .withValues(alpha: 0.8),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),

              // Chart metadata
              _buildDetailRow('Type', chart.type.displayName),
              _buildDetailRow('Scale', chart.displayScale),
              _buildDetailRow('State', chart.state),
              _buildDetailRow('Source', chart.source.displayName),
              _buildDetailRow('Status', chart.status.displayName),
              _buildDetailRow('Edition', chart.edition.toString()),
              if (chart.updateNumber > 0)
                _buildDetailRow('Update', chart.updateNumber.toString()),

              const SizedBox(height: 12),

              // Geographic bounds
              Text(
                'Coverage Area',
                style: Theme.of(
                  context,
                ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 8),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    children: [
                      _buildDetailRow(
                        'North',
                        '${chart.bounds.north.toStringAsFixed(4)}°',
                      ),
                      _buildDetailRow(
                        'South',
                        '${chart.bounds.south.toStringAsFixed(4)}°',
                      ),
                      _buildDetailRow(
                        'East',
                        '${chart.bounds.east.toStringAsFixed(4)}°',
                      ),
                      _buildDetailRow(
                        'West',
                        '${chart.bounds.west.toStringAsFixed(4)}°',
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 12),

              // Additional information
              _buildDetailRow('Last Updated', _formatDate(chart.lastUpdate)),
              if (chart.fileSize != null)
                _buildDetailRow('File Size', _formatFileSize(chart.fileSize!)),
              _buildDetailRow('Downloaded', chart.isDownloaded ? 'Yes' : 'No'),

              if (chart.description != null) ...[
                const SizedBox(height: 12),
                Text(
                  'Description',
                  style: Theme.of(
                    context,
                  ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 8),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Text(
                      chart.description!,
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ),
                ),
              ],

              // Metadata
              if (chart.metadata.isNotEmpty) ...[
                const SizedBox(height: 12),
                Text(
                  'Additional Metadata',
                  style: Theme.of(
                    context,
                  ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 8),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: chart.metadata.entries
                          .map(
                            (entry) => _buildDetailRow(
                              entry.key,
                              entry.value.toString(),
                            ),
                          )
                          .toList(),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close'),
          ),
          if (!chart.isDownloaded)
            ElevatedButton(
              onPressed: () async {
                Navigator.of(context).pop();

                try {
                  final downloadService = ref.read(downloadServiceProvider);
                  final downloadUrl =
                      'https://charts.noaa.gov/ENCs/${chart.id}.zip';

                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Starting download of ${chart.title}...'),
                      duration: const Duration(seconds: 2),
                    ),
                  );

                  await downloadService.downloadChart(chart.id, downloadUrl);

                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          'Successfully started download of ${chart.title}',
                        ),
                        duration: const Duration(seconds: 3),
                        backgroundColor: Colors.green,
                      ),
                    );
                  }
                } catch (error) {
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          'Failed to download ${chart.title}: $error',
                        ),
                        duration: const Duration(seconds: 5),
                        backgroundColor: Colors.red,
                      ),
                    );
                  }
                }
              },
              child: const Text('Download'),
            ),
        ],
      ),
    );
  }

  Widget _buildScaleFilterSection() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            GestureDetector(
              onTap: () => setState(() {
                _scaleFilterEnabled = !_scaleFilterEnabled;
                // Filter will be called by debounced method automatically
              }),
              child: Row(
                children: [
                  Semantics(
                    label: 'Enable scale filtering',
                    child: Switch(
                      value: _scaleFilterEnabled,
                      onChanged: (value) => setState(() {
                        _scaleFilterEnabled = value;
                        _filterCharts(); // Only call once here
                      }),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Filter by Scale Range',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                ],
              ),
            ),
            if (_scaleFilterEnabled) ...[
              const SizedBox(height: 8),
              Text(
                'Scale: 1:${_formatScale(_minScale.round())} - 1:${_formatScale(_maxScale.round())}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 8),
              Semantics(
                label: 'Minimum scale slider',
                child: Slider(
                  value: _minScale,
                  min: 1000,
                  max: 10000000,
                  divisions: 100,
                  onChanged: (value) => setState(() {
                    _minScale = value;
                    if (_minScale > _maxScale) {
                      _maxScale = _minScale;
                    }
                    _filterCharts();
                  }),
                ),
              ),
              Semantics(
                label: 'Maximum scale slider',
                child: Slider(
                  value: _maxScale,
                  min: 1000,
                  max: 10000000,
                  divisions: 100,
                  onChanged: (value) => setState(() {
                    _maxScale = value;
                    if (_maxScale < _minScale) {
                      _minScale = _maxScale;
                    }
                    _filterCharts();
                  }),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildDateFilterSection() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            GestureDetector(
              onTap: () => setState(() {
                _dateFilterEnabled = !_dateFilterEnabled;
                // Filter will be called by debounced method automatically
              }),
              child: Row(
                children: [
                  Semantics(
                    label: 'Enable date filtering',
                    child: Switch(
                      value: _dateFilterEnabled,
                      onChanged: (value) => setState(() {
                        _dateFilterEnabled = value;
                        _filterCharts(); // Only call once here
                      }),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Filter by Update Date',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                ],
              ),
            ),
            if (_dateFilterEnabled) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => _selectStartDate(),
                      child: Text(
                        _startDate == null
                            ? 'Start Date'
                            : _formatDate(_startDate!),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => _selectEndDate(),
                      child: Text(
                        _endDate == null ? 'End Date' : _formatDate(_endDate!),
                      ),
                    ),
                  ),
                ],
              ),
              if (_startDate != null || _endDate != null) ...[
                const SizedBox(height: 8),
                TextButton(
                  onPressed: () => setState(() {
                    _startDate = null;
                    _endDate = null;
                    _filterCharts();
                  }),
                  child: const Text('Clear Date Filter'),
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _selectStartDate() async {
    final pickedDate = await showDatePicker(
      context: context,
      initialDate:
          _startDate ?? DateTime.now().subtract(const Duration(days: 365)),
      firstDate: DateTime(2000),
      lastDate: DateTime.now(),
    );
    if (pickedDate != null) {
      setState(() {
        _startDate = pickedDate;
        // Ensure start date is before end date
        if (_endDate != null && _startDate!.isAfter(_endDate!)) {
          _endDate = _startDate;
        }
        _filterCharts();
      });
    }
  }

  Future<void> _selectEndDate() async {
    final pickedDate = await showDatePicker(
      context: context,
      initialDate: _endDate ?? DateTime.now(),
      firstDate: _startDate ?? DateTime(2000),
      lastDate: DateTime.now(),
    );
    if (pickedDate != null) {
      setState(() {
        _endDate = pickedDate;
        // Ensure end date is after start date
        if (_startDate != null && _endDate!.isBefore(_startDate!)) {
          _startDate = _endDate;
        }
        _filterCharts();
      });
    }
  }

  String _formatScale(int scale) {
    return scale.toString().replaceAllMapped(
      RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
      (Match m) => '${m[1]},',
    );
  }

  String _formatDate(DateTime date) {
    return '${date.day}/${date.month}/${date.year}';
  }

  String _formatFileSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024)
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }

  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
            child: Text(
              '$label:',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                fontWeight: FontWeight.w600,
                color: Theme.of(
                  context,
                ).colorScheme.onSurface.withValues(alpha: 0.7),
              ),
            ),
          ),
          Expanded(
            child: Text(value, style: Theme.of(context).textTheme.bodyMedium),
          ),
        ],
      ),
    );
  }
}
