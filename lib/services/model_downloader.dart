import 'dart:io';
import 'package:dio/dio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:flutter/services.dart';
import 'dart:convert';

class ModelDownloader {
  static const String huggingFaceRepo = 'cstr/nllb_600m_int8_onnx';
  static const String baseUrl =
      'https://huggingface.co/$huggingFaceRepo/resolve/main';

  static const List<String> requiredFiles = [
    'encoder_model.onnx',
    'decoder_model.onnx',
    'decoder_with_past_model.onnx',
    'tokenizer.json',
  ];

  Future<bool> areModelsInAssets() async {
    try {
      print('🔍 Checking for models in assets via manifest...');

      // Load the asset manifest
      final manifestContent = await rootBundle.loadString('AssetManifest.json');
      final Map<String, dynamic> manifestMap = json.decode(manifestContent);

      print(
          '📋 Asset manifest loaded. Total assets: ${manifestMap.keys.length}');

      // Check each required file
      final onnxFiles = [
        'encoder_model.onnx',
        'decoder_model.onnx',
        'decoder_with_past_model.onnx'
      ];

      for (final file in onnxFiles) {
        final assetKey = 'assets/onnx_models/$file';
        if (manifestMap.containsKey(assetKey)) {
          print('  ✅ Found in manifest: $assetKey');
        } else {
          print('  ❌ NOT in manifest: $assetKey');
          print(
              '  Available ONNX assets: ${manifestMap.keys.where((k) => k.contains('onnx')).toList()}');
          return false;
        }
      }

      // Check tokenizer
      final tokenizerKey = 'assets/models/tokenizer.json';
      if (manifestMap.containsKey(tokenizerKey)) {
        print('  ✅ Found in manifest: $tokenizerKey');
      } else {
        print('  ❌ NOT in manifest: $tokenizerKey');
        print(
            '  Available model assets: ${manifestMap.keys.where((k) => k.contains('models')).toList()}');
        return false;
      }

      print('✅ All required assets found in manifest!');
      return true;
    } catch (e, stack) {
      print('❌ Error checking asset manifest: $e');
      print('Stack trace: $stack');
      return false;
    }
  }

  static const Map<String, int> fileSizes = {
    'encoder_model.onnx': 419 * 1024 * 1024, // ~419 MB
    'decoder_model.onnx': 734 * 1024 * 1024, // ~734 MB
    'decoder_with_past_model.onnx': 709 * 1024 * 1024, // ~709 MB
    'tokenizer.json': 32 * 1024 * 1024, // ~32 MB
  };

  final Dio _dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 30),
    receiveTimeout: const Duration(minutes: 10),
  ));

  Future<String> getModelsDirectory() async {
    final appDir = await getApplicationDocumentsDirectory();
    final modelsDir = Directory('${appDir.path}/nllb_models');

    if (!await modelsDir.exists()) {
      await modelsDir.create(recursive: true);
    }

    return modelsDir.path;
  }

  Future<bool> areModelsDownloaded() async {
    try {
      final modelsPath = await getModelsDirectory();

      for (final file in requiredFiles) {
        final filePath = '$modelsPath/$file';
        final fileExists = await File(filePath).exists();

        if (!fileExists) {
          print('Model file missing: $file');
          return false;
        }

        // Verify file size
        final fileSize = await File(filePath).length();
        final expectedSize = fileSizes[file] ?? 0;

        if (fileSize < expectedSize * 0.95) {
          // Allow 5% tolerance
          print(
              'Model file incomplete: $file (${fileSize} bytes, expected ~${expectedSize} bytes)');
          return false;
        }
      }

      print('✅ All models verified');
      return true;
    } catch (e) {
      print('❌ Error checking models: $e');
      return false;
    }
  }

  Future<void> downloadModels({
    required Function(String fileName, double progress) onProgress,
    required Function(String message) onStatusUpdate,
  }) async {
    try {
      final modelsPath = await getModelsDirectory();
      onStatusUpdate('Preparing to download models...');

      int totalFiles = requiredFiles.length;
      int completedFiles = 0;

      for (final fileName in requiredFiles) {
        final filePath = '$modelsPath/$fileName';
        final file = File(filePath);

        // Skip if already exists and is complete
        if (await file.exists()) {
          final fileSize = await file.length();
          final expectedSize = fileSizes[fileName] ?? 0;

          if (fileSize >= expectedSize * 0.95) {
            completedFiles++;
            onProgress(fileName, 1.0);
            onStatusUpdate(
                '✅ $fileName already downloaded ($completedFiles/$totalFiles)');
            continue;
          } else {
            // Delete incomplete file
            await file.delete();
            onStatusUpdate('Removing incomplete file: $fileName');
          }
        }

        // Download file
        onStatusUpdate(
            'Downloading $fileName... ($completedFiles/$totalFiles)');

        final url = '$baseUrl/$fileName';
        print('Downloading from: $url');

        await _dio.download(
          url,
          filePath,
          onReceiveProgress: (received, total) {
            if (total != -1) {
              final progress = received / total;
              onProgress(fileName, progress);

              if (received % (10 * 1024 * 1024) == 0 || progress == 1.0) {
                final receivedMB =
                    (received / (1024 * 1024)).toStringAsFixed(1);
                final totalMB = (total / (1024 * 1024)).toStringAsFixed(1);
                onStatusUpdate(
                    '$fileName: ${receivedMB}MB / ${totalMB}MB (${(progress * 100).toStringAsFixed(0)}%)');
              }
            }
          },
          options: Options(
            headers: {
              'User-Agent': 'CrispTranslator/1.0',
            },
          ),
        );

        // Verify download
        final downloadedSize = await file.length();
        final expectedSize = fileSizes[fileName] ?? 0;

        if (downloadedSize < expectedSize * 0.95) {
          throw Exception(
              'Download incomplete: $fileName (${downloadedSize} bytes)');
        }

        completedFiles++;
        onProgress(fileName, 1.0);
        onStatusUpdate('✅ $fileName downloaded ($completedFiles/$totalFiles)');
      }

      onStatusUpdate('✅ All models downloaded successfully!');
    } catch (e) {
      throw Exception('Failed to download models: $e');
    }
  }

  Future<void> deleteModels() async {
    try {
      final modelsPath = await getModelsDirectory();
      final dir = Directory(modelsPath);

      if (await dir.exists()) {
        await dir.delete(recursive: true);
        print('Models deleted');
      }
    } catch (e) {
      print('Error deleting models: $e');
    }
  }

  Future<Map<String, int>> getModelsSizeInfo() async {
    try {
      final modelsPath = await getModelsDirectory();
      final info = <String, int>{};
      int totalSize = 0;

      for (final file in requiredFiles) {
        final filePath = '$modelsPath/$file';
        final fileExists = await File(filePath).exists();

        if (fileExists) {
          final size = await File(filePath).length();
          info[file] = size;
          totalSize += size;
        }
      }

      info['total'] = totalSize;
      return info;
    } catch (e) {
      return {};
    }
  }
}
