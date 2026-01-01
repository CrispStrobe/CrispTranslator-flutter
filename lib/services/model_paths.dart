// lib/services/model_paths.dart
import 'dart:io';  // ADD THIS

/// Central configuration for all model paths
/// Everything is now under assets/ for consistency
class ModelPaths {
  // Base paths
  static const String assetsBase = 'assets';
  
  // NLLB Translation models
  static const String nllbModels = '$assetsBase/onnx_models';
  static const String nllbTokenizer = '$assetsBase/models';
  
  // Awesome Align models (for word alignment)
  static const String awesomeAlignFp32 = '$assetsBase/onnx_models/awesome_align';
  static const String awesomeAlignInt8 = '$assetsBase/onnx_models/awesome_align_int8';
  
  // NLLB ONNX model files (in onnx_models/)
  static const nllbOnnxFiles = [
    '$nllbModels/encoder_model.onnx',
    '$nllbModels/decoder_model.onnx',
    '$nllbModels/decoder_with_past_model.onnx',
  ];
  
  // NLLB config/tokenizer files (in models/)
  static const nllbConfigFiles = [
    '$nllbTokenizer/config.json',
    '$nllbTokenizer/generation_config.json',
    '$nllbTokenizer/tokenizer.json',
    '$nllbTokenizer/tokenizer_config.json',
    '$nllbTokenizer/sentencepiece.bpe.model',
    '$nllbTokenizer/special_tokens_map.json',
  ];
  
  // Awesome Align files (optional, for alignment)
  static const awesomeAlignInt8Files = [
    '$awesomeAlignInt8/model.onnx',
  ];
  
  static const awesomeAlignFp32Files = [
    '$awesomeAlignFp32/model.onnx',
  ];
  
  /// Check if all required NLLB files exist
  static bool checkNllbFiles() {
    for (final file in [...nllbOnnxFiles, ...nllbConfigFiles]) {
      if (!File(file).existsSync()) {
        return false;
      }
    }
    return true;
  }
  
  /// Check if awesome align INT8 is available
  static bool checkAwesomeAlignInt8() {
    return awesomeAlignInt8Files.every((f) => File(f).existsSync());
  }
  
  /// Check if awesome align FP32 is available
  static bool checkAwesomeAlignFp32() {
    return awesomeAlignFp32Files.every((f) => File(f).existsSync());
  }
  
  /// Get a readable list of what's missing
  static List<String> getMissingFiles() {
    final missing = <String>[];
    
    for (final file in [...nllbOnnxFiles, ...nllbConfigFiles]) {
      if (!File(file).existsSync()) {
        missing.add(file);
      }
    }
    
    return missing;
  }
}