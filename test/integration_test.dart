import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/services.dart';
import 'package:onnxruntime/onnxruntime.dart';
import '../lib/services/nllb_tokenizer.dart';
import '../lib/services/onnx_translation_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('NLLB Translation Integration Tests', () {
    late ONNXTranslationService service;

    setUpAll(() async {
      print('\n' + '=' * 70);
      print('🚀 Initializing Translation Service...');
      print('=' * 70);

      service = ONNXTranslationService();
      await service.initialize();

      print('✅ Service initialized successfully!\n');
    });

    tearDownAll(() {
      print('\n🧹 Cleaning up...');
      service.dispose();
    });

    test('Service is initialized', () {
      expect(service.isInitialized, true);
      print('✅ Service is ready');
    });

    test('Translate simple English to German', () async {
      print('\n' + '-' * 70);
      print('Test: English → German');
      print('-' * 70);

      final input = 'Hello, how are you?';
      print('📝 Input: "$input"');

      final startTime = DateTime.now();
      final translation = await service.translate(input, 'German');
      final elapsed = DateTime.now().difference(startTime);

      print('🇩🇪 Translation: "$translation"');
      print('⏱️  Time: ${elapsed.inMilliseconds}ms');

      expect(translation.isNotEmpty, true);
      expect(translation.length, greaterThan(5));

      print('✅ Translation completed successfully\n');
    });

    test('Translate English to French', () async {
      print('\n' + '-' * 70);
      print('Test: English → French');
      print('-' * 70);

      final input = 'Good morning!';
      print('📝 Input: "$input"');

      final startTime = DateTime.now();
      final translation = await service.translate(input, 'French');
      final elapsed = DateTime.now().difference(startTime);

      print('🇫🇷 Translation: "$translation"');
      print('⏱️  Time: ${elapsed.inMilliseconds}ms');

      expect(translation.isNotEmpty, true);

      print('✅ Translation completed successfully\n');
    });

    test('Translate English to Spanish', () async {
      print('\n' + '-' * 70);
      print('Test: English → Spanish');
      print('-' * 70);

      final input = 'Thank you very much!';
      print('📝 Input: "$input"');

      final startTime = DateTime.now();
      final translation = await service.translate(input, 'Spanish');
      final elapsed = DateTime.now().difference(startTime);

      print('🇪🇸 Translation: "$translation"');
      print('⏱️  Time: ${elapsed.inMilliseconds}ms');

      expect(translation.isNotEmpty, true);

      print('✅ Translation completed successfully\n');
    });

    test('Translate longer sentence', () async {
      print('\n' + '-' * 70);
      print('Test: Longer sentence');
      print('-' * 70);

      final input =
          'Machine learning is a fascinating field of artificial intelligence.';
      print('📝 Input: "$input"');

      final startTime = DateTime.now();
      final translation = await service.translate(input, 'German');
      final elapsed = DateTime.now().difference(startTime);

      print('🇩🇪 Translation: "$translation"');
      print('⏱️  Time: ${elapsed.inMilliseconds}ms');

      expect(translation.isNotEmpty, true);
      expect(translation.length, greaterThan(20));

      print('✅ Translation completed successfully\n');
    });

    test('Multiple translations (performance test)', () async {
      print('\n' + '-' * 70);
      print('Test: Multiple Translations Performance');
      print('-' * 70);

      final testCases = [
        ('Hello', 'German'),
        ('Goodbye', 'French'),
        ('Thank you', 'Spanish'),
        ('Good morning', 'Italian'),
      ];

      final times = <int>[];

      for (final (text, lang) in testCases) {
        print('\n📝 "$text" → $lang');

        final startTime = DateTime.now();
        final translation = await service.translate(text, lang);
        final elapsed = DateTime.now().difference(startTime);

        times.add(elapsed.inMilliseconds);

        print('   Result: "$translation"');
        print('   Time: ${elapsed.inMilliseconds}ms');

        expect(translation.isNotEmpty, true);
      }

      final avgTime = times.reduce((a, b) => a + b) / times.length;
      final minTime = times.reduce((a, b) => a < b ? a : b);
      final maxTime = times.reduce((a, b) => a > b ? a : b);

      print('\n📊 Performance Summary:');
      print('   Average: ${avgTime.toStringAsFixed(0)}ms');
      print('   Min: ${minTime}ms');
      print('   Max: ${maxTime}ms');

      print('✅ All translations completed successfully\n');
    });
  });
}
