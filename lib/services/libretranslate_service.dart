// lib/services/libretranslate_service.dart
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'docx_translator.dart';

class LibreTranslateService implements TranslationService {
  final String baseUrl;
  final String? apiKey;
  final Map<String, int> _rateLimitTracker = {};
  
  // Language code mapping
  static const Map<String, String> languageCodes = {
    'English': 'en',
    'German': 'de',
    'Spanish': 'es',
    'French': 'fr',
    'Italian': 'it',
    'Portuguese': 'pt',
    'Russian': 'ru',
    'Chinese': 'zh',
    'Japanese': 'ja',
    'Korean': 'ko',
    'Arabic': 'ar',
    'Dutch': 'nl',
    'Polish': 'pl',
    'Turkish': 'tr',
    'Czech': 'cs',
    'Ukrainian': 'uk',
    'Vietnamese': 'vi',
    'Hindi': 'hi',
  };

  LibreTranslateService({
    this.baseUrl = 'https://libretranslate.com',
    this.apiKey,
  });

  @override
  Future<String> translate(
    String text,
    String targetLang,
    String sourceLang,
  ) async {
    if (text.trim().isEmpty) return text;

    // Respect rate limits (simple client-side throttling)
    await _respectRateLimit();

    final sourceCode = languageCodes[sourceLang] ?? sourceLang.toLowerCase();
    final targetCode = languageCodes[targetLang] ?? targetLang.toLowerCase();

    try {
      final response = await http.post(
        Uri.parse('$baseUrl/translate'),
        headers: {
          'Content-Type': 'application/json',
          if (apiKey != null) 'Authorization': 'Bearer $apiKey',
        },
        body: jsonEncode({
          'q': text,
          'source': sourceCode,
          'target': targetCode,
          'format': 'text',
        }),
      ).timeout(Duration(seconds: 30));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data['translatedText'] as String;
      } else if (response.statusCode == 429) {
        // Rate limited - wait and retry once
        print('⚠️  Rate limited, waiting 2 seconds...');
        await Future.delayed(Duration(seconds: 2));
        return translate(text, targetLang, sourceLang);
      } else {
        print('❌ Translation API error: ${response.statusCode}');
        print('   Response: ${response.body}');
        return text; // Return original on error
      }
    } catch (e) {
      print('❌ Translation request failed: $e');
      return text; // Return original on error
    }
  }

  Future<void> _respectRateLimit() async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final key = (now ~/ 1000).toString(); // Group by second
    
    _rateLimitTracker[key] = (_rateLimitTracker[key] ?? 0) + 1;
    
    // Clean old entries
    _rateLimitTracker.removeWhere((k, v) => 
      int.parse(k) < (now ~/ 1000) - 10
    );
    
    // If more than 5 requests in current second, wait
    if ((_rateLimitTracker[key] ?? 0) > 5) {
      await Future.delayed(Duration(milliseconds: 200));
    }
  }

  // Helper to get supported languages
  Future<List<Map<String, String>>> getSupportedLanguages() async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/languages'),
        headers: {
          if (apiKey != null) 'Authorization': 'Bearer $apiKey',
        },
      );

      if (response.statusCode == 200) {
        final List languages = jsonDecode(response.body);
        return languages.map((lang) => {
          'code': lang['code'] as String,
          'name': lang['name'] as String,
        }).toList();
      }
    } catch (e) {
      print('Failed to get languages: $e');
    }
    return [];
  }
}