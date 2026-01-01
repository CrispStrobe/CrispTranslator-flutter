// lib/services/python_nllb_service.dart
import 'dart:convert';
import 'dart:io';
import 'docx_translator.dart';

class PythonNLLBService implements TranslationService {
  final String scriptPath;
  final bool verbose;
  int _requestCount = 0;

  PythonNLLBService({
    this.scriptPath = 'scripts/translate_nllb.py',
    this.verbose = false,
  });

  @override
  Future<String> translate(
    String text,
    String targetLang,
    String sourceLang,
  ) async {
    if (text.trim().isEmpty) return text;

    _requestCount++;
    if (verbose && _requestCount == 1) {
      print('\n🔍 [DEBUG] First translation:');
      print('   Source text: "$text"');
      print('   $sourceLang → $targetLang');
    }

    try {
      final result = await Process.run(
        'python3',
        [scriptPath, text, sourceLang, targetLang],
        stdoutEncoding: utf8,
      );

      if (result.exitCode == 0) {
        final data = jsonDecode(result.stdout);
        final translation = data['translation'] as String;
        
        if (verbose && _requestCount == 1) {
          print('   Translated: "$translation"\n');
        }

        if (_requestCount % 10 == 0) {
          print('   [Translated ${_requestCount} segments...]');
        }

        return translation;
      } else {
        if (verbose) {
          print('❌ Python script error: ${result.stderr}');
        }
        return text;
      }
    } catch (e) {
      if (verbose) {
        print('❌ Subprocess failed: $e');
      }
      return text;
    }
  }
}