/// ZIP file extraction utilities for S-57 chart data
library;

import 'dart:io';
import 'dart:typed_data';
import 'package:archive/archive.dart';

/// Utility class for extracting S-57 chart data from ZIP archives
class ZipExtractor {
  /// Extract S-57 .000 file from NOAA ENC ZIP archive
  /// 
  /// NOAA ENC charts are distributed as ZIP files containing:
  /// - ENC_ROOT/CATALOG.031 (catalog file)
  /// - ENC_ROOT/[CHART_ID]/[CHART_ID].000 (main S-57 file)
  /// - ENC_ROOT/[CHART_ID]/[CHART_ID].txt (readme)
  /// 
  /// Returns the bytes of the .000 file if found, null otherwise
  static Future<List<int>?> extractS57FromZip(
    List<int> zipBytes,
    String chartId, [
    String? expectedFileName,
  ]) async {
    try {
      print('[ZipExtractor] Extracting S-57 data from ${zipBytes.length} byte ZIP for chart $chartId');
      
      // Decode ZIP archive
      final archive = ZipDecoder().decodeBytes(zipBytes);
      print('[ZipExtractor] ZIP contains ${archive.files.length} files');
      
      // List all files for debugging
      for (final file in archive.files) {
        print('[ZipExtractor] Found file: ${file.name} (${file.size} bytes)');
      }
      
      // Try multiple extraction strategies
      List<int>? s57Data;
      
      // Strategy 1: Look for specific expected filename
      if (expectedFileName != null) {
        s57Data = _findFileByName(archive, expectedFileName);
        if (s57Data != null) {
          print('[ZipExtractor] Found S-57 data using expected filename: $expectedFileName');
          return s57Data;
        }
      }
      
      // Strategy 2: Standard NOAA ENC structure
      s57Data = _findS57InStandardStructure(archive, chartId);
      if (s57Data != null) {
        print('[ZipExtractor] Found S-57 data in standard ENC_ROOT structure');
        return s57Data;
      }
      
      // Strategy 3: Flat ZIP structure
      s57Data = _findS57InFlatStructure(archive, chartId);
      if (s57Data != null) {
        print('[ZipExtractor] Found S-57 data in flat ZIP structure');
        return s57Data;
      }
      
      // Strategy 4: Find any .000 file
      s57Data = _findAnyS57File(archive);
      if (s57Data != null) {
        print('[ZipExtractor] Found S-57 data by .000 extension match');
        return s57Data;
      }
      
      print('[ZipExtractor] No S-57 .000 file found in ZIP archive');
      return null;
      
    } catch (e, stackTrace) {
      print('[ZipExtractor] ERROR extracting S-57 from ZIP: $e');
      print('[ZipExtractor] Stack trace: $stackTrace');
      return null;
    }
  }
  
  /// Find file by exact name match
  static List<int>? _findFileByName(Archive archive, String fileName) {
    for (final file in archive.files) {
      if (!file.isFile) continue;
      
      if (file.name == fileName) {
        return file.content as List<int>;
      }
    }
    return null;
  }
  
  /// Find S-57 file in standard NOAA ENC structure: ENC_ROOT/[CHART_ID]/[CHART_ID].000
  static List<int>? _findS57InStandardStructure(Archive archive, String chartId) {
    final expectedPath = 'ENC_ROOT/$chartId/$chartId.000';
    
    for (final file in archive.files) {
      if (!file.isFile) continue;
      
      if (file.name == expectedPath) {
        print('[ZipExtractor] Found standard structure S-57 file: ${file.name}');
        return file.content as List<int>;
      }
    }
    
    // Also try variations
    final variations = [
      'ENC_ROOT/$chartId/${chartId.toUpperCase()}.000',
      'ENC_ROOT/${chartId.toUpperCase()}/$chartId.000',
      'ENC_ROOT/${chartId.toUpperCase()}/${chartId.toUpperCase()}.000',
    ];
    
    for (final variation in variations) {
      for (final file in archive.files) {
        if (!file.isFile) continue;
        if (file.name == variation) {
          print('[ZipExtractor] Found S-57 file with variation: ${file.name}');
          return file.content as List<int>;
        }
      }
    }
    
    return null;
  }
  
  /// Find S-57 file in flat ZIP structure: [CHART_ID].000
  static List<int>? _findS57InFlatStructure(Archive archive, String chartId) {
    final expectedName = '$chartId.000';
    
    for (final file in archive.files) {
      if (!file.isFile) continue;
      
      // Check exact match
      if (file.name == expectedName) {
        print('[ZipExtractor] Found flat structure S-57 file: ${file.name}');
        return file.content as List<int>;
      }
      
      // Check case variations
      if (file.name.toLowerCase() == expectedName.toLowerCase()) {
        print('[ZipExtractor] Found S-57 file with case variation: ${file.name}');
        return file.content as List<int>;
      }
    }
    
    return null;
  }
  
  /// Find any .000 file (fallback strategy)
  static List<int>? _findAnyS57File(Archive archive) {
    for (final file in archive.files) {
      if (!file.isFile) continue;
      
      if (file.name.toLowerCase().endsWith('.000')) {
        print('[ZipExtractor] Found .000 file: ${file.name}');
        return file.content as List<int>;
      }
    }
    
    return null;
  }
  
  /// Extract all files from ZIP (for debugging)
  static Map<String, List<int>> extractAllFiles(List<int> zipBytes) {
    final result = <String, List<int>>{};
    
    try {
      final archive = ZipDecoder().decodeBytes(zipBytes);
      
      for (final file in archive.files) {
        if (file.isFile) {
          result[file.name] = file.content as List<int>;
        }
      }
    } catch (e) {
      print('[ZipExtractor] ERROR extracting all files: $e');
    }
    
    return result;
  }
  
  /// Get ZIP file listing (for debugging)
  static List<String> getZipListing(List<int> zipBytes) {
    final listing = <String>[];
    
    try {
      final archive = ZipDecoder().decodeBytes(zipBytes);
      
      for (final file in archive.files) {
        final type = file.isFile ? 'FILE' : 'DIR';
        final size = file.isFile ? '${file.size} bytes' : '';
        listing.add('$type: ${file.name} $size');
      }
    } catch (e) {
      listing.add('ERROR: $e');
    }
    
    return listing;
  }

  /// Extract first S-57 file found (alternative extraction method)
  static Future<List<int>?> extractFirstS57File(List<int> zipBytes) async {
    try {
      final archive = ZipDecoder().decodeBytes(zipBytes);
      return _findAnyS57File(archive);
    } catch (e) {
      print('[ZipExtractor] ERROR in extractFirstS57File: $e');
      return null;
    }
  }

  /// Extract file from specific path (alternative extraction method)
  static Future<List<int>?> extractFromPath(List<int> zipBytes, String path) async {
    try {
      final archive = ZipDecoder().decodeBytes(zipBytes);
      return _findFileByName(archive, path);
    } catch (e) {
      print('[ZipExtractor] ERROR in extractFromPath: $e');
      return null;
    }
  }
}