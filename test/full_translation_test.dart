import 'dart:io';
import '../lib/services/onnx_translation_service.dart';

// Mock rootBundle for testing
import 'package:flutter/services.dart' show rootBundle, ByteData;
import 'dart:typed_data';

class MockAssetBundle {
  static Future<ByteData> load(String key) async {
    final file = File(key);
    final bytes = await file.readAsBytes();
    return ByteData.sublistView(Uint8List.fromList(bytes));
  }

  static Future<String> loadString(String key) async {
    final file = File(key);
    return await file.readAsString();
  }
}

void main() async {
  print('=' * 70);
  print('🧪 Full NLLB Translation Test');
  print('=' * 70);
  print('');

  try {
    // Note: This requires running with Flutter's dart VM
    // Use: flutter run test/full_translation_test.dart

    print('This test requires Flutter runtime.');
    print('Please use: flutter test test/integration_test.dart');
    print('');
    print('Or run the app: flutter run -d macos');
  } catch (e, stack) {
    print('❌ Error: $e');
    print(stack);
    exit(1);
  }
}
