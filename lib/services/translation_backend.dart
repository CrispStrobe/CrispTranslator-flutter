// lib/services/translation_backend.dart
import 'docx_translator.dart';

abstract class TranslationBackend implements TranslationService {
  final bool verbose;
  final bool debug;
  int requestCount = 0;
  
  TranslationBackend({this.verbose = false, this.debug = false});
  
  Future<void> initialize() async {}
  
  Future<bool> test() async {
    try {
      logInfo('🧪 Testing backend: $name');
      logInfo('   Running comprehensive test suite...\n');
      
      // Test cases: various lengths and complexities
      final testCases = [
        // Simple greeting
        TestCase('Hello, how are you today?', 'English', 'German'),
        
        // Medium sentence
        TestCase(
          'The quick brown fox jumps over the lazy dog.',
          'English', 
          'Spanish'
        ),
        
        // Complex sentence
        TestCase(
          'Machine learning has revolutionized the way we process and analyze large datasets in modern computing.',
          'English',
          'French'
        ),
        
        // Technical content
        TestCase(
          'The application uses neural networks to perform real-time translation with high accuracy.',
          'English',
          'German'
        ),
        
        // Conversational
        TestCase(
          'I would like to schedule a meeting for next Tuesday afternoon if that works for everyone.',
          'English',
          'Spanish'
        ),
        
        // Short and punchy
        TestCase('This is amazing!', 'English', 'German'),
        
        // Question
        TestCase(
          'What are the main differences between these two approaches?',
          'English',
          'French'
        ),
        
        // Multiple clauses
        TestCase(
          'When the sun rises tomorrow, we will begin our journey to the mountains, where we plan to spend the entire weekend hiking and camping.',
          'English',
          'German'
        ),
      ];
      
      logInfo('📝 Test Suite: ${testCases.length} sentences');
      logInfo('   Languages: English → German, Spanish, French');
      logInfo('   Testing batch processing speed...\n');
      
      final startTime = DateTime.now();
      int passed = 0;
      int failed = 0;
      
      for (int i = 0; i < testCases.length; i++) {
        final test = testCases[i];
        final testNum = i + 1;
        
        logInfo('[$testNum/${testCases.length}] "${_truncate(test.text, 50)}"');
        logInfo('   ${test.source} → ${test.target}');
        
        final translationStart = DateTime.now();
        final result = await translate(test.text, test.target, test.source);
        final duration = DateTime.now().difference(translationStart);
        
        // Check if translation occurred
        if (result.isEmpty) {
          logError('   ❌ FAILED: Empty result');
          failed++;
        } else if (result == test.text) {
          logError('   ❌ FAILED: Translation unchanged');
          failed++;
        } else {
          logInfo('   ✅ "${_truncate(result, 50)}"');
          logInfo('   ⏱️  ${duration.inMilliseconds}ms');
          passed++;
        }
        
        logInfo('');
      }
      
      final totalDuration = DateTime.now().difference(startTime);
      
      // Summary
      logInfo('═' * 60);
      logInfo('📊 Test Results');
      logInfo('═' * 60);
      logInfo('Total tests:    ${testCases.length}');
      logInfo('Passed:         $passed ✅');
      logInfo('Failed:         $failed ❌');
      logInfo('Success rate:   ${((passed / testCases.length) * 100).toStringAsFixed(1)}%');
      logInfo('Total time:     ${_formatDuration(totalDuration)}');
      logInfo('Average time:   ${(totalDuration.inMilliseconds / testCases.length).toStringAsFixed(0)}ms per sentence');
      
      if (testCases.length > 1) {
        final throughput = testCases.length / totalDuration.inSeconds;
        logInfo('Throughput:     ${throughput.toStringAsFixed(2)} sentences/sec');
      }
      
      logInfo('═' * 60);
      
      return failed == 0;
      
    } catch (e, stack) {
      logError('❌ Test failed with exception: $e');
      if (debug) {
        logDebug('Stack trace:\n$stack');
      }
      return false;
    }
  }
  
  String get name;
  String get description;
  
  void logInfo(String message) {
    print(message);
  }
  
  void logVerbose(String message) {
    if (verbose || debug) print(message);
  }
  
  void logDebug(String message) {
    if (debug) print(message);
  }
  
  void logError(String message) {
    print(message);
  }
  
  void logProgress() {
    requestCount++;
    if (requestCount % 10 == 0) {
      print('   [Translated $requestCount segments...]');
    }
  }
  
  String _truncate(String text, int maxLength) {
    if (text.length <= maxLength) return text;
    return '${text.substring(0, maxLength)}...';
  }
  
  String _formatDuration(Duration d) {
    if (d.inSeconds < 60) {
      return '${d.inSeconds}.${(d.inMilliseconds % 1000).toString().padLeft(3, '0')}s';
    } else {
      final min = d.inMinutes;
      final sec = d.inSeconds % 60;
      return '${min}m ${sec}s';
    }
  }
}

class TestCase {
  final String text;
  final String source;
  final String target;
  
  TestCase(this.text, this.source, this.target);
}