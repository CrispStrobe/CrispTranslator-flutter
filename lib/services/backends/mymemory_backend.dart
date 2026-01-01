// lib/services/backends/mymemory_backend.dart
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../translation_backend.dart';

class MyMemoryBackend extends TranslationBackend {
  static const String apiUrl = 'https://api.mymemory.translated.net/get';
  
  static const Map<String, String> languageCodes = {
    'English': 'en', 'German': 'de', 'Spanish': 'es', 'French': 'fr',
    'Italian': 'it', 'Portuguese': 'pt', 'Russian': 'ru', 'Chinese': 'zh',
    'Japanese': 'ja', 'Korean': 'ko', 'Arabic': 'ar', 'Dutch': 'nl',
    'Polish': 'pl', 'Turkish': 'tr', 'Czech': 'cs', 'Ukrainian': 'uk',
    'Vietnamese': 'vi', 'Hindi': 'hi', 'Greek': 'el', 'Hebrew': 'he',
  };
  
  DateTime _lastRequest = DateTime.now();
  
  MyMemoryBackend({super.verbose = false, super.debug = false});
  
  @override
  String get name => 'MyMemory API';
  
  @override
  String get description => 'Free cloud translation API';
  
  @override
  Future<void> initialize() async {
    logDebug('🔍 [DEBUG] Testing internet connection...');
    try {
      final response = await http.get(Uri.parse('https://api.mymemory.translated.net'))
          .timeout(Duration(seconds: 5));
      logDebug('   ✓ API reachable (status: ${response.statusCode})');
    } catch (e) {
      throw Exception('Cannot reach MyMemory API: $e');
    }
    logInfo('✅ MyMemory backend initialized');
  }
  
  @override
  Future<String> translate(
    String text,
    String targetLang,
    String sourceLang,
  ) async {
    if (text.trim().isEmpty) return text;
    
    // Rate limiting
    final now = DateTime.now();
    final elapsed = now.difference(_lastRequest).inMilliseconds;
    if (elapsed < 100) {
      await Future.delayed(Duration(milliseconds: 100 - elapsed));
    }
    _lastRequest = DateTime.now();
    
    final srcCode = languageCodes[sourceLang] ?? sourceLang.toLowerCase();
    final tgtCode = languageCodes[targetLang] ?? targetLang.toLowerCase();
    
    final isFirstTranslation = requestCount == 0;
    
    if (verbose && isFirstTranslation) {
      print('\n🔍 [VERBOSE] First translation:');
      print('   Source text: "$text"');
      print('   Language pair: $srcCode|$tgtCode');
    }
    
    try {
      final uri = Uri.parse(apiUrl).replace(queryParameters: {
        'q': text,
        'langpair': '$srcCode|$tgtCode',
      });
      
      logDebug('🔍 [DEBUG] GET $uri');
      
      final response = await http.get(uri).timeout(Duration(seconds: 10));
      
      logDebug('🔍 [DEBUG] Response status: ${response.statusCode}');
      
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        
        logDebug('🔍 [DEBUG] Response data: $data');
        
        final translation = data['responseData']['translatedText'] as String;
        
        if (verbose && isFirstTranslation) {
          print('   Translated: "$translation"');
          print('   Quality: ${data['responseData']['match']}\n');
        }
        
        logProgress();
        return translation;
      } else {
        logError('❌ API error: ${response.statusCode}');
        logError('   Response: ${response.body}');
        return text;
      }
    } catch (e, stack) {
      logError('❌ Request failed: $e');
      if (debug) {
        logDebug('Stack trace:\n$stack');
      }
      return text;
    }
  }
}