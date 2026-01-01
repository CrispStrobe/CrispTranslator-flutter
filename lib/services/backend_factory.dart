// lib/services/backend_factory.dart
import 'translation_backend.dart';
import 'backends/python_nllb_onnx_backend.dart';
import 'backends/mymemory_backend.dart';

enum BackendType {
  pythonNllbOnnx,
  myMemory,
}

class BackendFactory {
  static TranslationBackend create(
    BackendType type, {
    bool verbose = false,
    bool debug = false,
  }) {
    switch (type) {
      case BackendType.pythonNllbOnnx:
        return PythonNLLBONNXBackend(verbose: verbose, debug: debug);
      case BackendType.myMemory:
        return MyMemoryBackend(verbose: verbose, debug: debug);
    }
  }
  
  static BackendType fromString(String name) {
    switch (name.toLowerCase()) {
      case 'onnx':
      case 'nllb-onnx':
      case 'python-onnx':
        return BackendType.pythonNllbOnnx;
      case 'mymemory':
      case 'api':
        return BackendType.myMemory;
      default:
        throw ArgumentError('Unknown backend: $name');
    }
  }
  
  static String getAvailableBackends() {
    return '''
Available backends:
  onnx          Python NLLB ONNX (default, local, fast)
  mymemory      MyMemory API (cloud, free, slower)
''';
  }
}