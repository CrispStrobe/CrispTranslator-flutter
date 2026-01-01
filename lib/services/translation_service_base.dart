// lib/services/translation_service_base.dart:

import 'dart:typed_data';

abstract class ModelLoader {
  Future<Uint8List> loadModel(String modelName);
}

// This will be implemented differently for CLI vs Flutter