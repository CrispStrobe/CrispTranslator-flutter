// lib/services/mymemory_service.dart
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'docx_translator.dart';

class MyMemoryService implements TranslationService {
  static const String apiUrl = 'https://api.mymemory.translated.net/get';
  
  // ISO 639-1 language codes
  static const Map<String, String> languageCodes = {
    'English': 'en', 'German': 'de', 'Spanish': 'es', 'French': 'fr',
    'Italian': 'it', 'Portuguese': 'pt', 'Russian': 'ru', 'Chinese': 'zh',
    'Japanese': 'ja', 'Korean': 'ko', 'Arabic': 'ar', 'Dutch': 'nl',
    'Polish': 'pl', 'Turkish': 'tr', 'Czech': 'cs', 'Ukrainian': 'uk',
    'Vietnamese': 'vi', 'Hindi': 'hi', 'Greek': 'el', 'Hebrew': 'he',
    'Swedish': 'sv', 'Danish': 'da', 'Finnish': 'fi', 'Norwegian': 'no',
    'Romanian': 'ro', 'Bulgarian': 'bg', 'Croatian': 'hr', 'Serbian': 'sr',
    'Slovak': 'sk', 'Slovenian': 'sl', 'Bengali': 'bn', 'Tamil': 'ta',
    'Telugu': 'te', 'Urdu': 'ur', 'Thai': 'th', 'Indonesian': 'id',
    'Malay': 'ms', 'Tagalog': 'tl', 'Swahili': 'sw', 'Hungarian': 'hu',
    'Estonian': 'et', 'Latvian': 'lv', 'Lithuanian': 'lt', 'Catalan': 'ca',
    'Icelandic': 'is', 'Irish': 'ga', 'Welsh': 'cy',
  };

  final bool verbose;
  int _requestCount = 0;
  DateTime _lastRequest = DateTime.now();

  MyMemoryService({this.verbose = false});

  @override
  Future<String> translate(
    String text,
    String targetLang,
    String sourceLang,
  ) async {
    if (text.trim().isEmpty) return text;

    // Rate limiting: 1 request per 100ms to be polite
    final now = DateTime.now();
    final elapsed = now.difference(_lastRequest).inMilliseconds;
    if (elapsed < 100) {
      await Future.delayed(Duration(milliseconds: 100 - elapsed));
    }
    _lastRequest = DateTime.now();

    final srcCode = languageCodes[sourceLang] ?? sourceLang.toLowerCase();
    final tgtCode = languageCodes[targetLang] ?? targetLang.toLowerCase();
    final langPair = '$srcCode|$tgtCode';

    _requestCount++;
    if (verbose && _requestCount == 1) {
      print('\n🔍 [DEBUG] First translation:');
      print('   Source text: "$text"');
      print('   Language pair: $langPair');
    }

    try {
      final uri = Uri.parse(apiUrl).replace(queryParameters: {
        'q': text,
        'langpair': langPair,
      });

      final response = await http.get(uri).timeout(Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final translatedText = data['responseData']['translatedText'] as String;
        
        if (verbose && _requestCount == 1) {
          print('   Translated text: "$translatedText"');
          print('   Match quality: ${data['responseData']['match']}');
          print('');
        }

        if (_requestCount % 10 == 0) {
          print('   [Translated ${_requestCount} segments...]');
        }

        return translatedText;
      } else {
        if (verbose) {
          print('❌ API error: ${response.statusCode}');
          print('   Response: ${response.body}');
        }
        return text;
      }
    } catch (e) {
      if (verbose) {
        print('❌ Translation failed: $e');
      }
      return text;
    }
  }
}