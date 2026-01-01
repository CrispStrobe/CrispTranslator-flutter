// model_loader_io.dart
import 'dart:io';
import 'dart:typed_data';
import 'translation_service_base.dart';

class ModelLoaderIO implements ModelLoader {
  final String modelsPath;
  
  ModelLoaderIO(this.modelsPath);
  
  @override
  Future<Uint8List> loadModel(String modelName) async {
    final file = File('$modelsPath/$modelName');
    if (!file.existsSync()) {
      throw Exception('Model file not found: ${file.path}');
    }
    return await file.readAsBytes();
  }
}