// model_loader_flutter.dart
import 'dart:typed_data';
import 'package:flutter/services.dart';
import 'translation_service_base.dart';
import 'dart:io';

class ModelLoaderFlutter implements ModelLoader {
  final String? assetsPath;
  final String? filesystemPath;
  
  ModelLoaderFlutter({this.assetsPath, this.filesystemPath});
  
  @override
  Future<Uint8List> loadModel(String modelName) async {
    // Try filesystem first (for downloaded models)
    if (filesystemPath != null) {
      try {
        final file = File('$filesystemPath/$modelName');
        if (file.existsSync()) {
          print('📦 Loading $modelName from filesystem: $filesystemPath');
          return await file.readAsBytes();
        }
      } catch (e) {
        print('⚠️  Failed to load from filesystem: $e');
      }
    }
    
    // Fallback to assets
    final assetPath = assetsPath ?? 'assets/onnx_models';
    print('📦 Loading $modelName from assets: $assetPath');
    final buffer = await rootBundle.load('$assetPath/$modelName');
    return buffer.buffer.asUint8List();
  }
}