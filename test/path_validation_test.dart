import 'package:flutter_test/flutter_test.dart';
import 'dart:io';
import 'fixtures/charts/test_chart_data.dart';
import 'utils/enc_test_utilities.dart';

void main() {
  group('Path Validation Tests (Issue #212)', () {
    test('should validate S57 ENC directory structure exists', () {
      final encRoot = Directory(TestChartData.s57FixturesPath);
      
      expect(encRoot.existsSync(), isTrue, 
             reason: 'S57 ENC_ROOT directory should exist: ${TestChartData.s57FixturesPath}');
      
      // Check for catalog file
      final catalogFile = File('${TestChartData.s57FixturesPath}/CATALOG.031');
      expect(catalogFile.existsSync(), isTrue,
             reason: 'ENC catalog file should exist');
             
      print('✅ S57 ENC directory structure validated: ${TestChartData.s57FixturesPath}');
    });

    test('should confirm S57 base files are present (.000 format)', () {
      // Check Elliott Bay chart
      final elliottBayFile = File(TestChartData.elliottBayHarborChart);
      expect(elliottBayFile.existsSync(), isTrue,
             reason: 'Elliott Bay S57 chart should exist: ${TestChartData.elliottBayHarborChart}');
             
      // Check Puget Sound chart  
      final pugetSoundFile = File(TestChartData.pugetSoundCoastalChart);
      expect(pugetSoundFile.existsSync(), isTrue,
             reason: 'Puget Sound S57 chart should exist: ${TestChartData.pugetSoundCoastalChart}');
             
      print('✅ US5WA50M available in S57 format: ${TestChartData.elliottBayHarborChart}');
      print('✅ US3WA01M available in S57 format: ${TestChartData.pugetSoundCoastalChart}');
    });

    test('should test helper method behavior', () {
      // Test S57 directory path helper
      final us5wa50mDir = TestChartData.getS57ChartDirectory('US5WA50M');
      expect(us5wa50mDir, contains('ENC_ROOT/US5WA50M'));
      
      final us3wa01mDir = TestChartData.getS57ChartDirectory('US3WA01M'); 
      expect(us3wa01mDir, contains('ENC_ROOT/US3WA01M'));
      
      // Test absolute path helper
      final absolutePath = TestChartData.getAbsolutePath('test/sample.txt');
      expect(absolutePath, isA<String>());
      expect(absolutePath, contains('test/sample.txt'));
      
      print('✅ Helper methods working correctly');
    });

    test('should ensure at least one format is available per chart', () {
      final discoveryResult = EncTestUtilities.discoverFixtures();
      
      expect(discoveryResult.foundFixtures, isTrue,
             reason: 'At least one fixture format should be available');
      
      if (discoveryResult.format == FixtureFormat.s57) {
        expect(discoveryResult.fixtureFiles, isNotEmpty,
               reason: 'S57 fixture files should be available');
        print('✅ Using S57 format fixtures: ${discoveryResult.fixtureFiles.length} files');
      } else {
        expect(discoveryResult.hasAnyFixtures, isTrue,
               reason: 'ZIP fixture files should be available as fallback');
        print('✅ Using ZIP format fixtures as fallback');
      }
    });

    test('should validate no references to incorrect paths exist', () {
      // This test ensures we don't regress back to incorrect paths
      
      // Should use standardized S57 paths
      expect(TestChartData.s57FixturesPath, equals('test/fixtures/charts/s57_data/ENC_ROOT'));
      expect(TestChartData.zipFixturesPath, equals('test/fixtures/charts/noaa_enc'));
      
      // Charts should point to S57 format by default
      expect(TestChartData.elliottBayHarborChart, endsWith('.000'));
      expect(TestChartData.pugetSoundCoastalChart, endsWith('.000'));
      expect(TestChartData.elliottBayHarborChart, contains('s57_data/ENC_ROOT'));
      expect(TestChartData.pugetSoundCoastalChart, contains('s57_data/ENC_ROOT'));
      
      // ZIP versions should be clearly marked as legacy
      expect(TestChartData.elliottBayHarborChartZip, endsWith('.zip'));
      expect(TestChartData.pugetSoundCoastalChartZip, endsWith('.zip'));
      expect(TestChartData.elliottBayHarborChartZip, contains('noaa_enc'));
      expect(TestChartData.pugetSoundCoastalChartZip, contains('noaa_enc'));
      
      print('✅ Path validation complete - no incorrect path references found');
    });
  });
}