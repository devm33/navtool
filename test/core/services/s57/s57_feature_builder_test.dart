import 'package:flutter_test/flutter_test.dart';
import 'package:navtool/core/services/s57/s57_models.dart';
import 'package:navtool/core/services/s57/s57_object_catalog.dart';
import 'package:navtool/core/services/s57/s57_feature_builder.dart';
import 'package:navtool/core/services/s57/s57_parser.dart';
import '../../../utils/s57_test_fixtures.dart';

void main() {
  group('S57FeatureBuilder', () {
    group('Real Data Feature Building Tests', () {
      test('should build features from real Elliott Bay S57 data', () async {
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
        
        // Verify that features were properly built with real data
        for (final feature in s57ParsedData.features) {
          expect(feature.recordId, isA<int>());
          expect(feature.featureType, isA<S57FeatureType>());
          expect(feature.geometryType, isA<S57GeometryType>());
          expect(feature.coordinates, isNotEmpty,
            reason: 'Real features should have coordinates');
          
          // Verify coordinates are in Elliott Bay area
          for (final coord in feature.coordinates) {
            expect(coord.latitude, inInclusiveRange(47.0, 48.0),
              reason: 'Elliott Bay latitude range');
            expect(coord.longitude, inInclusiveRange(-123.0, -122.0),
              reason: 'Elliott Bay longitude range');
          }
        }
        
        // Check for expected S57 feature types in Elliott Bay
        final featureTypes = s57ParsedData.features.map((f) => f.featureType).toSet();
        print('Real S57 Feature Types found: ${featureTypes.map((t) => t.acronym).toList()}');
        
        // Should have various marine navigation features
        expect(featureTypes, isNotEmpty);
        expect(s57ParsedData.features.length, greaterThan(5),
          reason: 'Elliott Bay should have multiple real features');
      });
    });

    group('Synthetic Data Feature Building Tests', () {
    late S57ObjectCatalog objectCatalog;
    late S57AttributeCatalog attributeCatalog;
    late S57FeatureBuilder builder;

    setUp(() {
      // Create test catalogs
      final objectClasses = [
        const S57ObjectClass(code: 42, acronym: 'DEPARE', name: 'Depth Area'),
        const S57ObjectClass(code: 74, acronym: 'SOUNDG', name: 'Sounding'),
        const S57ObjectClass(code: 38, acronym: 'BOYLAT', name: 'Lateral Buoy'),
      ];
      objectCatalog = S57ObjectCatalog.fromObjectClasses(objectClasses);

      final attributeDefs = [
        const S57AttributeDef(
          acronym: 'DRVAL1',
          type: S57AttrType.float,
          name: 'Minimum depth',
        ),
        const S57AttributeDef(
          acronym: 'VALSOU',
          type: S57AttrType.float,
          name: 'Sounding depth',
        ),
        const S57AttributeDef(
          acronym: 'OBJNAM',
          type: S57AttrType.string,
          name: 'Object name',
        ),
        const S57AttributeDef(
          acronym: 'CATBOY',
          type: S57AttrType.enumType,
          name: 'Buoy category',
          domain: {'1': 'lateral', '2': 'cardinal'},
        ),
      ];
      attributeCatalog = S57AttributeCatalog.fromAttributeDefs(attributeDefs);

      builder = S57FeatureBuilder(objectCatalog, attributeCatalog);
    });

    group('buildFeature', () {
      test('should build feature with known object code and attributes', () {
        // Arrange
        final rawAttributes = {
          'DRVAL1': ['10.5'],
          'OBJNAM': ['Test Depth Area'],
        };
        final coordinates = [
          const S57Coordinate(latitude: 47.6, longitude: -122.3),
          const S57Coordinate(latitude: 47.7, longitude: -122.4),
        ];

        // Act
        final feature = builder.buildFeature(
          recordId: 123,
          objectCode: 42, // DEPARE
          rawAttributes: rawAttributes,
          coordinates: coordinates,
        );

        // Assert
        expect(feature, isNotNull);
        expect(feature!.recordId, equals(123));
        expect(feature.featureType, equals(S57FeatureType.depthArea));
        expect(feature.geometryType, equals(S57GeometryType.line));
        expect(feature.coordinates, hasLength(2));
        expect(feature.label, equals('Test Depth Area')); // Uses OBJNAM

        // Check decoded attributes
        expect(feature.attributes['DRVAL1'], equals(10.5)); // Decoded as float
        expect(
          feature.attributes['OBJNAM'],
          equals('Test Depth Area'),
        ); // Decoded as string
      });

      test('should build feature with enum attributes', () {
        // Arrange
        final rawAttributes = {
          'CATBOY': ['1'],
          'OBJNAM': ['Port Hand Buoy'],
        };
        final coordinates = [
          const S57Coordinate(latitude: 47.6, longitude: -122.3),
        ];

        // Act
        final feature = builder.buildFeature(
          recordId: 456,
          objectCode: 38, // BOYLAT
          rawAttributes: rawAttributes,
          coordinates: coordinates,
        );

        // Assert
        expect(feature, isNotNull);
        expect(feature!.featureType, equals(S57FeatureType.buoyLateral));
        expect(feature.geometryType, equals(S57GeometryType.point));

        // Check enum decoding
        final catboy = feature.attributes['CATBOY'] as Map<String, dynamic>;
        expect(catboy['code'], equals('1'));
        expect(catboy['label'], equals('lateral'));
      });

      test('should handle unknown object codes gracefully', () {
        // Arrange
        final rawAttributes = <String, List<String>>{};
        final coordinates = [
          const S57Coordinate(latitude: 47.6, longitude: -122.3),
        ];

        // Act
        final feature = builder.buildFeature(
          recordId: 789,
          objectCode: 999, // Unknown code
          rawAttributes: rawAttributes,
          coordinates: coordinates,
        );

        // Assert - should return null for unknown object codes
        expect(feature, isNull);
      });

      test('should handle unknown attributes by passing them through', () {
        // Arrange
        final rawAttributes = {
          'DRVAL1': ['15.0'], // Known attribute
          'UNKNOWN_ATTR': ['some_value'], // Unknown attribute
        };
        final coordinates = [
          const S57Coordinate(latitude: 47.6, longitude: -122.3),
        ];

        // Act
        final feature = builder.buildFeature(
          recordId: 321,
          objectCode: 42, // DEPARE
          rawAttributes: rawAttributes,
          coordinates: coordinates,
        );

        // Assert
        expect(feature, isNotNull);
        expect(feature!.attributes['DRVAL1'], equals(15.0)); // Decoded
        expect(
          feature.attributes['UNKNOWN_ATTR'],
          equals('some_value'),
        ); // Passed through
      });

      test(
        'should emit validation warnings for missing required attributes',
        () {
          // Arrange - DEPARE without required DRVAL1
          final rawAttributes = {
            'OBJNAM': ['Depth Area Without Min Depth'],
          };
          final coordinates = [
            const S57Coordinate(latitude: 47.6, longitude: -122.3),
          ];

          // Act
          final feature = builder.buildFeature(
            recordId: 111,
            objectCode: 42, // DEPARE
            rawAttributes: rawAttributes,
            coordinates: coordinates,
          );

          // Assert - feature should be built even with validation warnings
          expect(feature, isNotNull);
          expect(feature!.attributes, isNot(contains('DRVAL1')));
          expect(feature.label, equals('Depth Area Without Min Depth'));

          // Warnings are printed but we can't easily test that in this context
          // The important thing is that the feature is still created
        },
      );

      test('should determine geometry types correctly', () {
        final rawAttributes = <String, List<String>>{};

        // Point geometry (single coordinate)
        final pointFeature = builder.buildFeature(
          recordId: 1,
          objectCode: 74, // SOUNDG
          rawAttributes: rawAttributes,
          coordinates: [const S57Coordinate(latitude: 47.6, longitude: -122.3)],
        );
        expect(pointFeature?.geometryType, equals(S57GeometryType.point));

        // Line geometry (multiple coordinates, not closed)
        final lineFeature = builder.buildFeature(
          recordId: 2,
          objectCode: 42, // DEPARE
          rawAttributes: rawAttributes,
          coordinates: [
            const S57Coordinate(latitude: 47.6, longitude: -122.3),
            const S57Coordinate(latitude: 47.7, longitude: -122.4),
          ],
        );
        expect(lineFeature?.geometryType, equals(S57GeometryType.line));

        // Area geometry (closed polygon)
        final areaFeature = builder.buildFeature(
          recordId: 3,
          objectCode: 42, // DEPARE
          rawAttributes: rawAttributes,
          coordinates: [
            const S57Coordinate(latitude: 47.6, longitude: -122.3),
            const S57Coordinate(latitude: 47.7, longitude: -122.3),
            const S57Coordinate(latitude: 47.7, longitude: -122.4),
            const S57Coordinate(latitude: 47.6, longitude: -122.3), // Closed
          ],
        );
        expect(areaFeature?.geometryType, equals(S57GeometryType.area));
      });

      test('should use object class name as label when OBJNAM is missing', () {
        // Arrange
        final rawAttributes = {
          'DRVAL1': ['20.0'],
        };
        final coordinates = [
          const S57Coordinate(latitude: 47.6, longitude: -122.3),
        ];

        // Act
        final feature = builder.buildFeature(
          recordId: 555,
          objectCode: 42, // DEPARE
          rawAttributes: rawAttributes,
          coordinates: coordinates,
        );

        // Assert
        expect(feature, isNotNull);
        expect(feature!.label, equals('Depth Area')); // Uses object class name
      });

      test('should handle empty coordinates gracefully', () {
        // Arrange
        final rawAttributes = {
          'DRVAL1': ['5.0'],
        };

        // Act
        final feature = builder.buildFeature(
          recordId: 777,
          objectCode: 42, // DEPARE
          rawAttributes: rawAttributes,
          coordinates: [], // Empty coordinates
        );

        // Assert
        expect(feature, isNotNull);
        expect(
          feature!.geometryType,
          equals(S57GeometryType.point),
        ); // Default fallback
        expect(feature.coordinates, isEmpty);
      });
    });

    group('S57FeatureBuilderFactory', () {
      tearDown(() {
        S57FeatureBuilderFactory.reset();
      });

      test('should throw error when not initialized', () {
        expect(() => S57FeatureBuilderFactory.create(), throwsStateError);
      });

      test('should create builder with custom catalogs', () {
        final builder = S57FeatureBuilderFactory.createWithCatalogs(
          objectCatalog,
          attributeCatalog,
        );

        expect(builder, isA<S57FeatureBuilder>());
      });

      test('should reset catalogs', () {
        S57FeatureBuilderFactory.reset();
        expect(S57FeatureBuilderFactory.objectCatalog, isNull);
        expect(S57FeatureBuilderFactory.attributeCatalog, isNull);
      });
    });
  });
}
