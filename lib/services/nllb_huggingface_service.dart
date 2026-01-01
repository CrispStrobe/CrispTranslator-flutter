// lib/services/nllb_huggingface_service.dart
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'docx_translator.dart';

class NLLBHuggingFaceService implements TranslationService {
  static const String apiUrl = 'https://unesco-nllb.hf.space/call/translate';
  static const String statusUrl = 'https://unesco-nllb.hf.space/call/translate';
  
  // Language name mapping - NLLB uses full language names
  static const Map<String, String> languageNames = {
    'English': 'English',
    'German': 'German',
    'Spanish': 'Spanish',
    'French': 'French',
    'Italian': 'Italian',
    'Portuguese': 'Portuguese',
    'Russian': 'Russian',
    'Chinese': 'Chinese (Simplified)',
    'Japanese': 'Japanese',
    'Korean': 'Korean',
    'Arabic': 'Modern Standard Arabic',
    'Dutch': 'Dutch',
    'Polish': 'Polish',
    'Turkish': 'Turkish',
    'Czech': 'Czech',
    'Ukrainian': 'Ukrainian',
    'Vietnamese': 'Vietnamese',
    'Hindi': 'Hindi',
    'Greek': 'Greek',
    'Hebrew': 'Hebrew',
    'Swedish': 'Swedish',
    'Danish': 'Danish',
    'Finnish': 'Finnish',
    'Norwegian': 'Norwegian Bokmål',
    'Romanian': 'Romanian',
    'Bulgarian': 'Bulgarian',
    'Croatian': 'Croatian',
    'Serbian': 'Serbian',
    'Slovak': 'Slovak',
    'Slovenian': 'Slovenian',
    'Bengali': 'Bengali',
    'Tamil': 'Tamil',
    'Telugu': 'Telugu',
    'Urdu': 'Urdu',
    'Thai': 'Thai',
    'Indonesian': 'Indonesian',
    'Malay': 'Standard Malay',
    'Tagalog': 'Tagalog',
    'Swahili': 'Swahili',
    'Hungarian': 'Hungarian',
    'Estonian': 'Estonian',
    'Latvian': 'Standard Latvian',
    'Lithuanian': 'Lithuanian',
    'Catalan': 'Catalan',
    'Basque': 'Basque',
    'Galician': 'Galician',
    'Icelandic': 'Icelandic',
    'Irish': 'Irish',
    'Welsh': 'Welsh',
  };

  int _requestCount = 0;

  @override
  Future<String> translate(
    String text,
    String targetLang,
    String sourceLang,
  ) async {
    if (text.trim().isEmpty) return text;

    final srcLangName = languageNames[sourceLang] ?? sourceLang;
    final tgtLangName = languageNames[targetLang] ?? targetLang;

    _requestCount++;
    if (_requestCount % 10 == 0) {
      print('   [Translated ${_requestCount} segments via HuggingFace...]');
    }

    try {
      // Step 1: Submit translation request
      final submitResponse = await http.post(
        Uri.parse(apiUrl),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'data': [text, srcLangName, tgtLangName]
        }),
      ).timeout(Duration(seconds: 60));

      if (submitResponse.statusCode != 200) {
        print('❌ HuggingFace API error: ${submitResponse.statusCode}');
        print('   Response: ${submitResponse.body}');
        return text;
      }

      final submitData = jsonDecode(submitResponse.body);
      final eventId = submitData['event_id'];

      if (eventId == null) {
        print('❌ No event_id received');
        return text;
      }

      // Step 2: Poll for result
      final resultUrl = 'https://unesco-nllb.hf.space/call/translate/$eventId';
      
      for (int attempt = 0; attempt < 30; attempt++) {
        await Future.delayed(Duration(milliseconds: 500));
        
        final resultResponse = await http.get(Uri.parse(resultUrl))
            .timeout(Duration(seconds: 10));

        if (resultResponse.statusCode == 200) {
          // Parse SSE stream
          final lines = resultResponse.body.split('\n');
          for (final line in lines) {
            if (line.startsWith('data: ')) {
              final jsonStr = line.substring(6);
              try {
                final data = jsonDecode(jsonStr);
                if (data is List && data.isNotEmpty) {
                  final translatedText = data[0] as String;
                  return translatedText;
                }
              } catch (e) {
                // Continue if JSON parsing fails
                continue;
              }
            }
          }
        }
      }

      print('⚠️  Translation timeout for: ${text.substring(0, text.length > 30 ? 30 : text.length)}...');
      return text;

    } catch (e) {
      print('❌ Translation request failed: $e');
      return text;
    }
  }

  static void printSupportedLanguages() {
    print('\n📋 Supported Languages:');
    final sorted = languageNames.keys.toList()..sort();
    for (int i = 0; i < sorted.length; i += 3) {
      final line = sorted.skip(i).take(3).map((l) => l.padRight(20)).join();
      print('   $line');
    }
    print('');
  }
}