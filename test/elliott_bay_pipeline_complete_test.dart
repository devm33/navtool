/// Test to verify the complete Elliott Bay S57 → Maritime feature pipeline
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/services.dart';
import 'dart:io';

import 'package:navtool/core/services/s57/s57_parser.dart';
import 'package:navtool/core/adapters/s57_to_maritime_adapter.dart';
import 'package:navtool/core/utils/zip_extractor.dart';
import 'package:navtool/core/models/chart.dart';
import 'package:navtool/core/models/geographic_bounds.dart';
import 'package:navtool/core/fixtures/washington_charts.dart';

void main() {
  group('Elliott Bay Complete Pipeline Tests', () {
    test('Elliott Bay S57 complete pipeline produces rich maritime features', () async {
      print('=== Elliott Bay Complete Pipeline Test ===');
      
      // Test Chart: Elliott Bay Harbor (US5WA50M)
      final elliottBayChart = Chart(
        id: 'US5WA50M',
        title: 'APPROACHES TO EVERETT - Elliott Bay Harbor',
        scale: 20000,
        bounds: GeographicBounds(
          north: 47.7,
          south: 47.5,  
          east: -122.2,
          west: -122.4,
        ),
        state: 'Washington',
        type: ChartType.harbor,
        description: 'Harbor-scale chart covering Elliott Bay and Seattle Harbor',
        isDownloaded: true,
        fileSize: 147361,
        edition: 1,
        updateNumber: 0,
        source: ChartSource.noaa,
        status: ChartStatus.current,
        lastUpdate: DateTime.now(),
      );
      
      print('Testing chart: ${elliottBayChart.id} - ${elliottBayChart.title}');
      
      // Phase 1: Load S57 chart data with multiple fallback strategies
      List<int>? s57Data;
      
      // Strategy 1: Direct S57 file (highest priority)
      final s57DirectPath = 'test/fixtures/charts/s57_data/ENC_ROOT/US5WA50M/US5WA50M.000';
      final directFile = File(s57DirectPath);
      
      if (await directFile.exists()) {
        s57Data = await directFile.readAsBytes();
        print('SUCCESS: Loaded ${s57Data.length} bytes from direct S57 file');
      } else {
        print('Direct S57 file not found: $s57DirectPath');
        
        // Strategy 2: Extract from ZIP file (fallback)
        final zipPath = 'test/fixtures/charts/noaa_enc/US5WA50M_harbor_elliott_bay.zip';
        final zipFile = File(zipPath);
        
        if (await zipFile.exists()) {
          final zipBytes = await zipFile.readAsBytes();
          print('Loaded ${zipBytes.length} byte ZIP file, extracting S57 data...');
          
          s57Data = await ZipExtractor.extractS57FromZip(zipBytes, 'US5WA50M');
          if (s57Data != null) {
            print('SUCCESS: Extracted ${s57Data.length} bytes of S57 data from ZIP');
          } else {
            print('FAILED to extract S57 data from ZIP');
          }
        } else {
          print('ZIP file not found: $zipPath');
        }
      }
      
      expect(s57Data, isNotNull, reason: 'Should load S57 chart data from either direct file or ZIP');
      expect(s57Data!.length, greaterThan(1000), reason: 'S57 data should be substantial');
      
      // Phase 2: Parse S57 data
      print('\n=== S57 Parsing Phase ===');
      final parsedData = S57Parser.parse(s57Data);
      
      print('S57 parsing results:');
      print('  Features found: ${parsedData.features.length}');
      print('  Chart bounds: ${parsedData.bounds.toMap()}');
      print('  Chart metadata: ${parsedData.metadata.toMap()}');
      
      // Analysis of S57 feature types
      final s57FeatureTypeCounts = <String, int>{};
      for (final feature in parsedData.features) {
        final acronym = feature.featureType.acronym;
        s57FeatureTypeCounts[acronym] = (s57FeatureTypeCounts[acronym] ?? 0) + 1;
      }
      print('  S57 feature breakdown: $s57FeatureTypeCounts');
      
      expect(parsedData.features.length, greaterThan(3), 
             reason: 'Elliott Bay should have more than 3 S57 features');
      
      // Phase 3: Convert S57 features to Maritime features
      print('\n=== Maritime Feature Conversion Phase ===');
      final maritimeFeatures = S57ToMaritimeAdapter.convertFeatures(parsedData.features);
      
      print('Maritime conversion results:');
      print('  Maritime features generated: ${maritimeFeatures.length}');
      
      // Analysis of maritime feature types
      final maritimeTypeCounts = <String, int>{};
      final realConversions = <String, int>{};
      for (final feature in maritimeFeatures) {
        final typeName = feature.type.name;
        maritimeTypeCounts[typeName] = (maritimeTypeCounts[typeName] ?? 0) + 1;
        
        // Track features with S57 origin data
        if (feature.attributes.containsKey('original_s57_acronym')) {
          final s57Acronym = feature.attributes['original_s57_acronym'] as String;
          realConversions[s57Acronym] = (realConversions[s57Acronym] ?? 0) + 1;
        }
      }
      print('  Maritime feature breakdown: $maritimeTypeCounts');
      print('  Real S57 conversions: $realConversions');
      
      final conversionRate = (maritimeFeatures.length / parsedData.features.length * 100).toStringAsFixed(1);
      print('  Conversion rate: $conversionRate% (${maritimeFeatures.length}/${parsedData.features.length})');
      
      expect(maritimeFeatures.length, greaterThan(10), 
             reason: 'Elliott Bay should produce many maritime features (current issue: only 3 synthetic features)');
      expect(maritimeFeatures.length / parsedData.features.length, greaterThan(0.5), 
             reason: 'Should successfully convert most S57 features to maritime features');
      
      // Phase 4: Validate maritime features have real S57 origin data
      final featuresWithOrigin = maritimeFeatures.where((f) => 
        f.attributes.containsKey('original_s57_code')).length;
      
      print('  Features with S57 origin data: $featuresWithOrigin/${maritimeFeatures.length}');
      
      expect(featuresWithOrigin, greaterThan(5), 
             reason: 'Most features should have S57 origin data, indicating real chart parsing');
      
      // Phase 5: Validate feature coordinates are in Elliott Bay region
      var validCoordinates = 0;
      for (final feature in maritimeFeatures) {
        final lat = feature.position.latitude;
        final lng = feature.position.longitude;
        
        // Elliott Bay approximate bounds: 47.5-47.7°N, 122.2-122.4°W
        if (lat >= 47.5 && lat <= 47.7 && lng >= -122.4 && lng <= -122.2) {
          validCoordinates++;
        }
      }
      
      print('  Features in Elliott Bay region: $validCoordinates/${maritimeFeatures.length}');
      
      expect(validCoordinates / maritimeFeatures.length, greaterThan(0.8), 
             reason: 'Most features should be located in Elliott Bay geographic region');
      
      // Success Summary
      print('\n=== SUCCESS SUMMARY ===');
      print('✅ S57 parsing: ${parsedData.features.length} features');
      print('✅ Maritime conversion: ${maritimeFeatures.length} features ($conversionRate% rate)');
      print('✅ Real S57 data: $featuresWithOrigin features with origin data');
      print('✅ Geographic validation: $validCoordinates features in Elliott Bay region');
      print('✅ COMPLETE PIPELINE WORKING - Elliott Bay should display rich maritime chart data');
      
      // The issue is likely in the chart loading/navigation flow, not the S57 parsing pipeline
    });
    
    test('Chart data loading matches pipeline test results', () async {
      // This test simulates the exact same loading logic as ChartScreen._loadChartData
      final chart = WashingtonTestCharts.getElliottBayCharts().first;
      
      // Test Strategy 1: Direct S-57 files  
      final s57DirectPath = 'test/fixtures/charts/s57_data/ENC_ROOT/${chart.id}/${chart.id}.000';
      var s57Data = await _tryLoadFromFile(s57DirectPath);
      
      if (s57Data == null) {
        // Test Strategy 2: ZIP extraction (fallback)
        final zipPath = 'test/fixtures/charts/noaa_enc/${chart.id}_harbor_elliott_bay.zip';
        final zipFile = File(zipPath);
        
        if (await zipFile.exists()) {
          final zipBytes = await zipFile.readAsBytes();
          s57Data = await ZipExtractor.extractS57FromZip(zipBytes, chart.id);
        }
      }
      
      expect(s57Data, isNotNull, reason: 'Chart data loading should work with same strategies as ChartScreen');
      
      if (s57Data != null) {
        final parsedData = S57Parser.parse(s57Data);
        final maritimeFeatures = S57ToMaritimeAdapter.convertFeatures(parsedData.features);
        
        expect(maritimeFeatures.length, greaterThan(10), 
               reason: 'Chart loading pipeline should produce rich maritime features');
        
        print('Chart loading test: ${maritimeFeatures.length} maritime features generated');
        print('This confirms the pipeline works - issue must be in app runtime chart access');
      }
    });
  });
}

Future<List<int>?> _tryLoadFromFile(String path) async {
  try {
    final file = File(path);
    if (await file.exists()) {
      return await file.readAsBytes();
    }
  } catch (e) {
    print('Error loading file $path: $e');
  }
  return null;
}