import 'dart:typed_data';
import 'package:CrispTranslator/services/docx_translator.dart';

void main() async {
  print('🧪 Testing DocxTranslator with mock translation...\n');

  // Create a simple test
  final translator = DocxTranslator(
    translationService: TestTranslationService(),
    aligner: HeuristicAligner(),
    verbose: true,
  );

  print('✅ Translator created successfully!');
  print('   Translation: ${translator.translationService.runtimeType}');
  print('   Aligner: ${translator.aligner.runtimeType}');

  // Test the alignment
  final testWords = ['Hello', 'world', 'how', 'are', 'you'];
  final testTranslated = ['HELLO', 'WORLD', 'HOW', 'ARE', 'YOU'];

  final alignments = translator.aligner?.align(testWords, testTranslated) ?? [];
  print('\n🔗 Alignment test:');
  print('   Source: $testWords');
  print('   Target: $testTranslated');
  print('   Alignments: ${alignments.length} found');
  for (final a in alignments) {
    print(
        '      ${testWords[a.sourceIndex]} ↔ ${testTranslated[a.targetIndex]}');
  }

  print('\n✅ All systems operational!');
  print('   Use bin/translate_docx.dart for actual file translation');
}

class TestTranslationService implements TranslationService {
  @override
  Future<String> translate(
      String text, String targetLang, String sourceLang) async {
    return text.toUpperCase();
  }
}
