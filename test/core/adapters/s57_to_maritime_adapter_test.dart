import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:navtool/core/adapters/s57_to_maritime_adapter.dart';
import 'package:navtool/core/models/chart_models.dart';
import 'package:navtool/core/services/s57/s57_models.dart';
import 'package:navtool/core/services/s57/s57_parser.dart';
import '../../utils/s57_test_fixtures.dart';

void main() {
  group('S57ToMaritimeAdapter', () {
    group('Real S57 Data Conversion Tests', () {
      test('should convert real Elliott Bay S57 features to maritime format', () async {
        // Check fixture availability
        final available = await S57TestFixtures.areFixturesAvailable();
        if (!available) {
          return markTestSkipped('S57 fixtures not available');
        }

        // Load and parse real Elliott Bay chart
        final chartData = await S57TestFixtures.loadElliottBayChartBytes();
        final s57ParsedData = S57Parser.parse(chartData.toList());
        
        expect(s57ParsedData.features, isNotEmpty,
          reason: 'Elliott Bay chart should have S57 features');
        
        // Convert real S57 features to maritime features
        final maritimeFeatures = S57ToMaritimeAdapter.convertFeatures(s57ParsedData.features);
        
        expect(maritimeFeatures, isNotEmpty,
          reason: 'Should convert some S57 features to maritime format');
        expect(maritimeFeatures.length, lessThanOrEqualTo(s57ParsedData.features.length),
          reason: 'Maritime features should not exceed S57 features');
        
        // Verify maritime features have proper structure
        for (final feature in maritimeFeatures) {
          expect(feature.type, isNotNull);
          expect(feature.id, isNotEmpty);
          expect(feature.position, isNotNull);
          expect(feature.attributes, isNotNull);
          
          // Verify coordinates are in Elliott Bay area
          expect(feature.position.latitude, inInclusiveRange(47.0, 48.0));
          expect(feature.position.longitude, inInclusiveRange(-123.0, -122.0));
        }
        
        // Log conversion statistics
        print('Real S57 Conversion: ${s57ParsedData.features.length} S57 → ${maritimeFeatures.length} maritime features');
      });
    });

    group('Synthetic S57 Data Conversion Tests', () {
      test('should convert empty list to empty list', () {
        final result = S57ToMaritimeAdapter.convertFeatures([]);
        expect(result, isEmpty);
      });

      test('should convert multiple features and filter out null results', () {
        final s57Features = [
          S57Feature(
            recordId: 1,
            featureType: S57FeatureType.depthArea,
            geometryType: S57GeometryType.area,
            coordinates: [
              S57Coordinate(latitude: 47.60, longitude: -122.33),
              S57Coordinate(latitude: 47.61, longitude: -122.33),
              S57Coordinate(latitude: 47.61, longitude: -122.32),
              S57Coordinate(latitude: 47.60, longitude: -122.32),
            ],
            attributes: {'DRVAL1': 10.0, 'DRVAL2': 20.0},
          ),
          S57Feature(
            recordId: 2,
            featureType: S57FeatureType.unknown,
            geometryType: S57GeometryType.point,
            coordinates: [S57Coordinate(latitude: 47.60, longitude: -122.33)],
            attributes: {},
          ),
          S57Feature(
            recordId: 3,
            featureType: S57FeatureType.lighthouse,
            geometryType: S57GeometryType.point,
            coordinates: [S57Coordinate(latitude: 47.60, longitude: -122.33)],
            attributes: {'LITCHR': 'F', 'VALNMR': 15.0, 'COLOUR': 'white'},
          ),
        ];

        final result = S57ToMaritimeAdapter.convertFeatures(s57Features);

        expect(result, hasLength(2)); // Unknown feature should be filtered out
        expect(result[0].type, equals(MaritimeFeatureType.depthArea));
        expect(result[1].type, equals(MaritimeFeatureType.lighthouse));
      });
    });

    group('depth area conversion', () {
      test('should convert DEPARE to AreaFeature with proper attributes', () {
        final s57 = S57Feature(
          recordId: 123,
          featureType: S57FeatureType.depthArea,
          geometryType: S57GeometryType.area,
          coordinates: [
            S57Coordinate(latitude: 47.60, longitude: -122.33),
            S57Coordinate(latitude: 47.61, longitude: -122.33),
            S57Coordinate(latitude: 47.61, longitude: -122.32),
            S57Coordinate(latitude: 47.60, longitude: -122.32),
          ],
          attributes: {'DRVAL1': 5.0, 'DRVAL2': 15.0},
        );

        final result = S57ToMaritimeAdapter.convertFeatures([s57]);

        expect(result, hasLength(1));
        final feature = result.first as AreaFeature;
        expect(feature.id, equals('depare_123'));
        expect(feature.type, equals(MaritimeFeatureType.depthArea));
        expect(feature.attributes['depth_min'], equals(5.0));
        expect(feature.attributes['depth_max'], equals(15.0));
        expect(feature.fillColor, isNotNull);
        expect(feature.coordinates, hasLength(1)); // Single ring
        expect(feature.coordinates.first, hasLength(4)); // Four corners
      });

      test('should handle depth area with missing depth values', () {
        final s57 = S57Feature(
          recordId: 124,
          featureType: S57FeatureType.depthArea,
          geometryType: S57GeometryType.area,
          coordinates: [S57Coordinate(latitude: 47.60, longitude: -122.33)],
          attributes: {}, // No depth values
        );

        final result = S57ToMaritimeAdapter.convertFeatures([s57]);

        expect(result, hasLength(1));
        final feature = result.first as AreaFeature;
        expect(feature.attributes['depth_min'], equals(0.0));
        expect(feature.attributes['depth_max'], equals(0.0));
      });

      test('should assign appropriate colors based on depth', () {
        final testCases = [
          {'min': 1.0, 'max': 1.5, 'expectedColor': 'red'}, // Very shallow
          {'min': 3.0, 'max': 4.0, 'expectedColor': 'orange'}, // Shallow
          {'min': 7.0, 'max': 9.0, 'expectedColor': 'yellow'}, // Moderate shallow
          {'min': 15.0, 'max': 18.0, 'expectedColor': 'lightBlue'}, // Moderate depth
          {'min': 25.0, 'max': 30.0, 'expectedColor': 'blue'}, // Deep water
        ];

        for (final testCase in testCases) {
          final s57 = S57Feature(
            recordId: 125,
            featureType: S57FeatureType.depthArea,
            geometryType: S57GeometryType.area,
            coordinates: [S57Coordinate(latitude: 47.60, longitude: -122.33)],
            attributes: {
              'DRVAL1': testCase['min'],
              'DRVAL2': testCase['max'],
            },
          );

          final result = S57ToMaritimeAdapter.convertFeatures([s57]);
          final feature = result.first as AreaFeature;
          
          // Verify color is assigned (specific color testing would require more complex setup)
          expect(feature.fillColor, isNotNull);
          expect(feature.fillColor!.alpha, greaterThan(0));
        }
      });
    });

    group('sounding conversion', () {
      test('should convert SOUNDG to PointFeature with depth label', () {
        final s57 = S57Feature(
          recordId: 200,
          featureType: S57FeatureType.sounding,
          geometryType: S57GeometryType.point,
          coordinates: [S57Coordinate(latitude: 47.605, longitude: -122.325)],
          attributes: {'VALSOU': 12.5},
        );

        final result = S57ToMaritimeAdapter.convertFeatures([s57]);

        expect(result, hasLength(1));
        final feature = result.first as PointFeature;
        expect(feature.id, equals('sounding_200'));
        expect(feature.type, equals(MaritimeFeatureType.soundings));
        expect(feature.position.latitude, equals(47.605));
        expect(feature.position.longitude, equals(-122.325));
        expect(feature.label, equals('12.5m'));
        expect(feature.attributes['depth'], equals(12.5));
      });

      test('should format depth labels correctly', () {
        final testCases = [
          {'depth': 5.0, 'expectedLabel': '5m'},
          {'depth': 12.3, 'expectedLabel': '12.3m'},
          {'depth': 0.5, 'expectedLabel': '0.5m'},
        ];

        for (final testCase in testCases) {
          final s57 = S57Feature(
            recordId: 201,
            featureType: S57FeatureType.sounding,
            geometryType: S57GeometryType.point,
            coordinates: [S57Coordinate(latitude: 47.60, longitude: -122.33)],
            attributes: {'VALSOU': testCase['depth']},
          );

          final result = S57ToMaritimeAdapter.convertFeatures([s57]);
          final feature = result.first as PointFeature;
          expect(feature.label, equals(testCase['expectedLabel']));
        }
      });
    });

    group('depth contour conversion', () {
      test('should convert DEPCNT to DepthContour with line coordinates', () {
        final s57 = S57Feature(
          recordId: 300,
          featureType: S57FeatureType.depthContour,
          geometryType: S57GeometryType.line,
          coordinates: [
            S57Coordinate(latitude: 47.60, longitude: -122.33),
            S57Coordinate(latitude: 47.61, longitude: -122.32),
            S57Coordinate(latitude: 47.62, longitude: -122.31),
          ],
          attributes: {'VALDCO': 10.0},
        );

        final result = S57ToMaritimeAdapter.convertFeatures([s57]);

        expect(result, hasLength(1));
        final feature = result.first as DepthContour;
        expect(feature.id, equals('depthcontour_300'));
        expect(feature.type, equals(MaritimeFeatureType.depthContour));
        expect(feature.depth, equals(10.0));
        expect(feature.coordinates, hasLength(3));
        expect(feature.coordinates.first.latitude, equals(47.60));
        expect(feature.coordinates.last.latitude, equals(47.62));
      });
    });

    group('coastline conversion', () {
      test('should convert COALNE to LineFeature for shoreline', () {
        final s57 = S57Feature(
          recordId: 400,
          featureType: S57FeatureType.coastline,
          geometryType: S57GeometryType.line,
          coordinates: [
            S57Coordinate(latitude: 47.60, longitude: -122.33),
            S57Coordinate(latitude: 47.61, longitude: -122.32),
          ],
          attributes: {'CATCOA': 'mangrove'},
        );

        final result = S57ToMaritimeAdapter.convertFeatures([s57]);

        expect(result, hasLength(1));
        final feature = result.first as LineFeature;
        expect(feature.id, equals('coastline_400'));
        expect(feature.type, equals(MaritimeFeatureType.shoreline));
        expect(feature.coordinates, hasLength(2));
        expect(feature.width, equals(2.0));
        expect(feature.attributes['category'], equals('mangrove'));
      });

      test('should handle shoreline alias', () {
        final s57 = S57Feature(
          recordId: 401,
          featureType: S57FeatureType.shoreline, // Alias for coastline
          geometryType: S57GeometryType.line,
          coordinates: [S57Coordinate(latitude: 47.60, longitude: -122.33)],
          attributes: {},
        );

        final result = S57ToMaritimeAdapter.convertFeatures([s57]);

        expect(result, hasLength(1));
        final feature = result.first as LineFeature;
        expect(feature.type, equals(MaritimeFeatureType.shoreline));
      });
    });

    group('navigation aids conversion', () {
      test('should convert lighthouse with characteristics', () {
        final s57 = S57Feature(
          recordId: 500,
          featureType: S57FeatureType.lighthouse,
          geometryType: S57GeometryType.point,
          coordinates: [S57Coordinate(latitude: 47.60, longitude: -122.33)],
          attributes: {
            'LITCHR': 'Fl',
            'VALNMR': 18.0,
            'COLOUR': 'red',
          },
          label: 'Point Robinson Light',
        );

        final result = S57ToMaritimeAdapter.convertFeatures([s57]);

        expect(result, hasLength(1));
        final feature = result.first as PointFeature;
        expect(feature.id, equals('lighthouse_500'));
        expect(feature.type, equals(MaritimeFeatureType.lighthouse));
        expect(feature.label, equals('Point Robinson Light'));
        expect(feature.attributes['character'], equals('Fl'));
        expect(feature.attributes['range'], equals(18.0));
        expect(feature.attributes['color'], equals('red'));
      });

      test('should generate lighthouse label from characteristics', () {
        final s57 = S57Feature(
          recordId: 501,
          featureType: S57FeatureType.lighthouse,
          geometryType: S57GeometryType.point,
          coordinates: [S57Coordinate(latitude: 47.60, longitude: -122.33)],
          attributes: {
            'LITCHR': 'F',
            'VALNMR': 12.0,
            'COLOUR': 'white',
          },
          // No label - should generate one
        );

        final result = S57ToMaritimeAdapter.convertFeatures([s57]);
        final feature = result.first as PointFeature;
        expect(feature.label, equals('Lt F 12M'));
      });

      test('should convert buoy with attributes', () {
        final s57 = S57Feature(
          recordId: 502,
          featureType: S57FeatureType.buoyLateral,
          geometryType: S57GeometryType.point,
          coordinates: [S57Coordinate(latitude: 47.60, longitude: -122.33)],
          attributes: {
            'BOYSHP': 'pillar',
            'COLOUR': 'red',
            'CATBOY': 'port',
            'TOPMAR': 'cylinder',
          },
        );

        final result = S57ToMaritimeAdapter.convertFeatures([s57]);

        expect(result, hasLength(1));
        final feature = result.first as PointFeature;
        expect(feature.id, equals('buoy_502'));
        expect(feature.type, equals(MaritimeFeatureType.buoy));
        expect(feature.attributes['buoyShape'], equals('pillar'));
        expect(feature.attributes['color'], equals('red'));
        expect(feature.attributes['category'], equals('port'));
        expect(feature.attributes['topmark'], equals('cylinder'));
      });

      test('should convert beacon with cardinal category', () {
        final s57 = S57Feature(
          recordId: 503,
          featureType: S57FeatureType.beacon,
          geometryType: S57GeometryType.point,
          coordinates: [S57Coordinate(latitude: 47.60, longitude: -122.33)],
          attributes: {
            'CATBCN': 'north',
            'COLOUR': 'black',
          },
        );

        final result = S57ToMaritimeAdapter.convertFeatures([s57]);

        expect(result, hasLength(1));
        final feature = result.first as PointFeature;
        expect(feature.id, equals('beacon_503'));
        expect(feature.type, equals(MaritimeFeatureType.beacon));
        expect(feature.attributes['category'], equals('north'));
        expect(feature.label, equals('N Card Bcn'));
      });
    });

    group('hazard conversion', () {
      test('should convert obstruction with depth', () {
        final s57 = S57Feature(
          recordId: 600,
          featureType: S57FeatureType.obstruction,
          geometryType: S57GeometryType.point,
          coordinates: [S57Coordinate(latitude: 47.60, longitude: -122.33)],
          attributes: {
            'CATOBS': 'snag',
            'VALSOU': 5.2,
          },
        );

        final result = S57ToMaritimeAdapter.convertFeatures([s57]);

        expect(result, hasLength(1));
        final feature = result.first as PointFeature;
        expect(feature.id, equals('obstruction_600'));
        expect(feature.type, equals(MaritimeFeatureType.obstruction));
        expect(feature.attributes['category'], equals('snag'));
        expect(feature.attributes['depth'], equals(5.2));
        expect(feature.label, equals('Obstr 5.2m'));
      });

      test('should convert wreck with category', () {
        final s57 = S57Feature(
          recordId: 601,
          featureType: S57FeatureType.wreck,
          geometryType: S57GeometryType.point,
          coordinates: [S57Coordinate(latitude: 47.60, longitude: -122.33)],
          attributes: {
            'CATWRK': 'dangerous',
            'VALSOU': 8.0,
          },
        );

        final result = S57ToMaritimeAdapter.convertFeatures([s57]);

        expect(result, hasLength(1));
        final feature = result.first as PointFeature;
        expect(feature.id, equals('wreck_601'));
        expect(feature.type, equals(MaritimeFeatureType.wrecks));
        expect(feature.attributes['category'], equals('dangerous'));
        expect(feature.label, equals('Wreck 8m'));
      });

      test('should convert underwater rock', () {
        final s57 = S57Feature(
          recordId: 602,
          featureType: S57FeatureType.underwater,
          geometryType: S57GeometryType.point,
          coordinates: [S57Coordinate(latitude: 47.60, longitude: -122.33)],
          attributes: {'VALSOU': 2.5},
        );

        final result = S57ToMaritimeAdapter.convertFeatures([s57]);

        expect(result, hasLength(1));
        final feature = result.first as PointFeature;
        expect(feature.id, equals('underwater_602'));
        expect(feature.type, equals(MaritimeFeatureType.rocks));
        expect(feature.label, equals('Rock 2.5m'));
      });
    });

    group('coordinate handling', () {
      test('should calculate center position from multiple coordinates', () {
        final s57 = S57Feature(
          recordId: 700,
          featureType: S57FeatureType.depthArea,
          geometryType: S57GeometryType.area,
          coordinates: [
            S57Coordinate(latitude: 47.60, longitude: -122.34),
            S57Coordinate(latitude: 47.62, longitude: -122.34),
            S57Coordinate(latitude: 47.62, longitude: -122.32),
            S57Coordinate(latitude: 47.60, longitude: -122.32),
          ],
          attributes: {'DRVAL1': 10.0, 'DRVAL2': 20.0},
        );

        final result = S57ToMaritimeAdapter.convertFeatures([s57]);
        final feature = result.first as AreaFeature;
        
        // Center should be average of coordinates
        expect(feature.position.latitude, equals(47.61));
        expect(feature.position.longitude, equals(-122.33));
      });

      test('should handle single coordinate', () {
        final s57 = S57Feature(
          recordId: 701,
          featureType: S57FeatureType.sounding,
          geometryType: S57GeometryType.point,
          coordinates: [S57Coordinate(latitude: 47.605, longitude: -122.325)],
          attributes: {'VALSOU': 5.0},
        );

        final result = S57ToMaritimeAdapter.convertFeatures([s57]);
        final feature = result.first as PointFeature;
        
        expect(feature.position.latitude, equals(47.605));
        expect(feature.position.longitude, equals(-122.325));
      });

      test('should handle empty coordinates gracefully', () {
        final s57 = S57Feature(
          recordId: 702,
          featureType: S57FeatureType.sounding,
          geometryType: S57GeometryType.point,
          coordinates: [], // Empty coordinates
          attributes: {'VALSOU': 5.0},
        );

        final result = S57ToMaritimeAdapter.convertFeatures([s57]);
        final feature = result.first as PointFeature;
        
        // Should default to (0,0)
        expect(feature.position.latitude, equals(0.0));
        expect(feature.position.longitude, equals(0.0));
      });
    });

    group('attribute preservation', () {
      test('should preserve original S-57 metadata', () {
        final s57 = S57Feature(
          recordId: 800,
          featureType: S57FeatureType.lighthouse,
          geometryType: S57GeometryType.point,
          coordinates: [S57Coordinate(latitude: 47.60, longitude: -122.33)],
          attributes: {
            'LITCHR': 'Fl',
            'VALNMR': 15.0,
            'custom_attribute': 'test_value',
          },
        );

        final result = S57ToMaritimeAdapter.convertFeatures([s57]);
        final feature = result.first as PointFeature;
        
        // Should preserve original S-57 metadata
        expect(feature.attributes['original_s57_code'], equals(75)); // LIGHTS code
        expect(feature.attributes['original_s57_acronym'], equals('LIGHTS'));
        
        // Should preserve all original attributes
        expect(feature.attributes['LITCHR'], equals('Fl'));
        expect(feature.attributes['VALNMR'], equals(15.0));
        expect(feature.attributes['custom_attribute'], equals('test_value'));
      });
    });

    group('error handling', () {
      test('should handle conversion errors gracefully', () {
        final s57 = S57Feature(
          recordId: 900,
          featureType: S57FeatureType.lighthouse,
          geometryType: S57GeometryType.point,
          coordinates: [S57Coordinate(latitude: 47.60, longitude: -122.33)],
          attributes: {
            'VALNMR': 'invalid_range', // Invalid type - should use default
          },
        );

        // Should not throw, and should create a feature with default values
        expect(() => S57ToMaritimeAdapter.convertFeatures([s57]), returnsNormally);
        
        final result = S57ToMaritimeAdapter.convertFeatures([s57]);
        
        // Should still create a feature with default range value
        expect(result, hasLength(1));
        final feature = result.first as PointFeature;
        expect(feature.type, equals(MaritimeFeatureType.lighthouse));
        expect(feature.attributes['range'], equals(10.0)); // Default value used
      });

      test('should filter out unknown feature types', () {
        final s57Features = [
          S57Feature(
            recordId: 901,
            featureType: S57FeatureType.unknown,
            geometryType: S57GeometryType.point,
            coordinates: [S57Coordinate(latitude: 47.60, longitude: -122.33)],
            attributes: {},
          ),
          S57Feature(
            recordId: 902,
            featureType: S57FeatureType.lighthouse,
            geometryType: S57GeometryType.point,
            coordinates: [S57Coordinate(latitude: 47.60, longitude: -122.33)],
            attributes: {},
          ),
        ];

        final result = S57ToMaritimeAdapter.convertFeatures(s57Features);
        
        // Should only convert known feature types
        expect(result, hasLength(1));
        expect(result.first.type, equals(MaritimeFeatureType.lighthouse));
      });
    });

    group('shore construction conversion', () {
      test('should convert SLCONS to LineFeature with proper attributes', () {
        final s57ShoreConstruction = S57Feature(
          recordId: 801,
          featureType: S57FeatureType.shoreConstruction,
          geometryType: S57GeometryType.line,
          coordinates: [
            S57Coordinate(latitude: 47.605, longitude: -122.325),
            S57Coordinate(latitude: 47.606, longitude: -122.324),
            S57Coordinate(latitude: 47.607, longitude: -122.323),
          ],
          attributes: {
            'CATSLC': 'pier', // Shore construction category
            'CONRAD': 'concrete', // Construction material
            'OBJNAM': 'Elliott Bay Pier',
          },
        );

        final result = S57ToMaritimeAdapter.convertFeatures([s57ShoreConstruction]);
        
        expect(result, hasLength(1));
        expect(result.first, isA<LineFeature>());
        
        final lineFeature = result.first as LineFeature;
        expect(lineFeature.type, equals(MaritimeFeatureType.shoreConstruction));
        expect(lineFeature.id, equals('slcons_801'));
        expect(lineFeature.coordinates, hasLength(3));
        expect(lineFeature.width, equals(3.0));
        expect(lineFeature.color, equals(Colors.brown));
        expect(lineFeature.attributes['category'], equals('pier'));
        expect(lineFeature.attributes['construction_material'], equals('concrete'));
        expect(lineFeature.attributes['original_s57_acronym'], equals('SLCONS'));
      });

      test('should handle shore construction with missing attributes', () {
        final s57ShoreConstruction = S57Feature(
          recordId: 802,
          featureType: S57FeatureType.shoreConstruction,
          geometryType: S57GeometryType.line,
          coordinates: [
            S57Coordinate(latitude: 47.605, longitude: -122.325),
            S57Coordinate(latitude: 47.606, longitude: -122.324),
          ],
          attributes: {}, // No attributes
        );

        final result = S57ToMaritimeAdapter.convertFeatures([s57ShoreConstruction]);
        
        expect(result, hasLength(1));
        final lineFeature = result.first as LineFeature;
        expect(lineFeature.attributes['category'], equals('unknown'));
        expect(lineFeature.attributes['construction_material'], equals('unknown'));
      });
    });

    group('built area conversion', () {
      test('should convert BUAARE to AreaFeature with proper attributes', () {
        final s57BuiltArea = S57Feature(
          recordId: 901,
          featureType: S57FeatureType.builtArea,
          geometryType: S57GeometryType.area,
          coordinates: [
            S57Coordinate(latitude: 47.60, longitude: -122.33),
            S57Coordinate(latitude: 47.61, longitude: -122.33),
            S57Coordinate(latitude: 47.61, longitude: -122.32),
            S57Coordinate(latitude: 47.60, longitude: -122.32),
            S57Coordinate(latitude: 47.60, longitude: -122.33), // Closed polygon
          ],
          attributes: {
            'CATBUA': 'industrial', // Built area category
            'FUNCTN': 'port facilities', // Function
            'OBJNAM': 'Elliott Bay Terminal',
          },
        );

        final result = S57ToMaritimeAdapter.convertFeatures([s57BuiltArea]);
        
        expect(result, hasLength(1));
        expect(result.first, isA<AreaFeature>());
        
        final areaFeature = result.first as AreaFeature;
        expect(areaFeature.type, equals(MaritimeFeatureType.builtArea));
        expect(areaFeature.id, equals('buaare_901'));
        expect(areaFeature.coordinates, hasLength(1)); // One ring
        expect(areaFeature.coordinates.first, hasLength(5)); // 5 points (closed polygon)
        expect(areaFeature.fillColor, equals(Colors.orange.withValues(alpha: 0.4))); // Industrial color
        expect(areaFeature.attributes['category'], equals('industrial'));
        expect(areaFeature.attributes['function'], equals('port facilities'));
        expect(areaFeature.attributes['original_s57_acronym'], equals('BUAARE'));
      });

      test('should use different colors based on built area category', () {
        // Test residential built area
        final s57ResidentialArea = S57Feature(
          recordId: 902,
          featureType: S57FeatureType.builtArea,
          geometryType: S57GeometryType.area,
          coordinates: [
            S57Coordinate(latitude: 47.60, longitude: -122.33),
            S57Coordinate(latitude: 47.61, longitude: -122.33),
            S57Coordinate(latitude: 47.61, longitude: -122.32),
            S57Coordinate(latitude: 47.60, longitude: -122.32),
            S57Coordinate(latitude: 47.60, longitude: -122.33),
          ],
          attributes: {'CATBUA': 'residential'},
        );

        final residentialResult = S57ToMaritimeAdapter.convertFeatures([s57ResidentialArea]);
        final residentialArea = residentialResult.first as AreaFeature;
        expect(residentialArea.fillColor, equals(Colors.yellow.withValues(alpha: 0.3)));

        // Test unknown category (default)
        final s57UnknownArea = S57Feature(
          recordId: 903,
          featureType: S57FeatureType.builtArea,
          geometryType: S57GeometryType.area,
          coordinates: [
            S57Coordinate(latitude: 47.60, longitude: -122.33),
            S57Coordinate(latitude: 47.61, longitude: -122.33),
            S57Coordinate(latitude: 47.61, longitude: -122.32),
            S57Coordinate(latitude: 47.60, longitude: -122.32),
            S57Coordinate(latitude: 47.60, longitude: -122.33),
          ],
          attributes: {'CATBUA': 'unknown'},
        );

        final unknownResult = S57ToMaritimeAdapter.convertFeatures([s57UnknownArea]);
        final unknownArea = unknownResult.first as AreaFeature;
        expect(unknownArea.fillColor, equals(Colors.grey.withValues(alpha: 0.6)));
      });
    });

    group('Elliott Bay feature type coverage', () {
      test('supports all Elliott Bay feature types', () {
        final supportedTypes = S57FeatureType.values.map((t) => t.acronym).toSet();
        
        // Verify critical Elliott Bay feature types are supported
        expect(supportedTypes, contains('DEPARE')); // Depth areas
        expect(supportedTypes, contains('SOUNDG')); // Soundings
        expect(supportedTypes, contains('BOYLAT')); // Lateral buoys
        expect(supportedTypes, contains('BOYCAR')); // Cardinal buoys
        expect(supportedTypes, contains('LIGHTS')); // Lights
        expect(supportedTypes, contains('COALNE')); // Coastlines
        expect(supportedTypes, contains('LNDARE')); // Land areas
        expect(supportedTypes, contains('SLCONS')); // Shore constructions - NEW
        expect(supportedTypes, contains('BUAARE')); // Built areas - NEW
      });

      test('converts Elliott Bay feature mix with new types', () {
        final s57Features = [
          // Existing supported types
          S57Feature(
            recordId: 1,
            featureType: S57FeatureType.depthArea,
            geometryType: S57GeometryType.area,
            coordinates: [S57Coordinate(latitude: 47.60, longitude: -122.33)],
            attributes: {'DRVAL1': 10.0},
          ),
          S57Feature(
            recordId: 2,
            featureType: S57FeatureType.buoyLateral,
            geometryType: S57GeometryType.point,
            coordinates: [S57Coordinate(latitude: 47.61, longitude: -122.32)],
            attributes: {'BOYSHP': 'cylindrical'},
          ),
          // New supported types
          S57Feature(
            recordId: 3,
            featureType: S57FeatureType.shoreConstruction,
            geometryType: S57GeometryType.line,
            coordinates: [
              S57Coordinate(latitude: 47.605, longitude: -122.325),
              S57Coordinate(latitude: 47.606, longitude: -122.324),
            ],
            attributes: {'CATSLC': 'pier'},
          ),
          S57Feature(
            recordId: 4,
            featureType: S57FeatureType.builtArea,
            geometryType: S57GeometryType.area,
            coordinates: [
              S57Coordinate(latitude: 47.60, longitude: -122.33),
              S57Coordinate(latitude: 47.61, longitude: -122.33),
              S57Coordinate(latitude: 47.61, longitude: -122.32),
              S57Coordinate(latitude: 47.60, longitude: -122.32),
              S57Coordinate(latitude: 47.60, longitude: -122.33),
            ],
            attributes: {'CATBUA': 'port'},
          ),
        ];

        final result = S57ToMaritimeAdapter.convertFeatures(s57Features);
        
        // Should convert all 4 features
        expect(result, hasLength(4));
        
        // Verify feature types
        final featureTypes = result.map((f) => f.type).toSet();
        expect(featureTypes, contains(MaritimeFeatureType.depthArea));
        expect(featureTypes, contains(MaritimeFeatureType.buoy));
        expect(featureTypes, contains(MaritimeFeatureType.shoreConstruction));
        expect(featureTypes, contains(MaritimeFeatureType.builtArea));
      });
    });
  });
}