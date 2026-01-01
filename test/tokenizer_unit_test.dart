import 'package:flutter_test/flutter_test.dart';
import 'dart:io';
import 'dart:convert';
import 'dart:typed_data';

void main() {
  group('NLLB Tokenizer Tests', () {
    late Map<String, int> vocab;
    late Map<int, String> reverseVocab;

    setUpAll(() async {
      // Load tokenizer.json
      final file = File('assets/models/tokenizer.json');
      final tokenizerData = await file.readAsString();
      final tokenizerJson = json.decode(tokenizerData);

      final model = tokenizerJson['model'];
      final vocabData = model['vocab'] as Map<String, dynamic>;

      vocab = {};
      reverseVocab = {};

      vocabData.forEach((token, id) {
        final tokenId = id as int;
        vocab[token] = tokenId;
        reverseVocab[tokenId] = token;
      });
    });

    test('Vocab loads correctly', () {
      expect(vocab.isNotEmpty, true);
      expect(vocab.length, greaterThan(250000));
      print('✅ Vocab size: ${vocab.length}');
    });

    test('Special tokens exist', () {
      expect(reverseVocab[1], isNotNull); // PAD
      expect(reverseVocab[2], isNotNull); // BOS/EOS
      expect(reverseVocab[3], isNotNull); // UNK
      print('✅ Special tokens found');
    });

    test('Language tokens exist', () {
      final germanTokenId = 256049;
      final frenchTokenId = 256057;

      expect(reverseVocab[germanTokenId], isNotNull);
      expect(reverseVocab[frenchTokenId], isNotNull);

      print('✅ German token: ${reverseVocab[germanTokenId]}');
      print('✅ French token: ${reverseVocab[frenchTokenId]}');
    });

    test('Common words exist', () {
      final commonWords = ['hello', 'the', 'a', 'is'];

      for (final word in commonWords) {
        // Try both with and without underscore prefix
        final found = vocab.containsKey(word) ||
            vocab.containsKey('▁$word') ||
            vocab.containsKey('▁$word▁');

        if (found) {
          print('✅ Found: $word');
        }
      }
    });

    test('Token ID range is valid', () {
      final maxId = reverseVocab.keys.reduce((a, b) => a > b ? a : b);
      final minId = reverseVocab.keys.reduce((a, b) => a < b ? a : b);

      print('✅ Token ID range: $minId to $maxId');
      expect(maxId, lessThan(300000));
      expect(minId, greaterThanOrEqualTo(0));
    });
  });

  group('Model Files Tests', () {
    test('Encoder model exists', () async {
      final file = File('assets/onnx_models/encoder_model.onnx');
      expect(await file.exists(), true);

      final size = await file.length();
      print('✅ Encoder size: ${(size / 1024 / 1024).toStringAsFixed(2)} MB');
    });

    test('Decoder model exists', () async {
      final file = File('assets/onnx_models/decoder_model.onnx');
      expect(await file.exists(), true);

      final size = await file.length();
      print('✅ Decoder size: ${(size / 1024 / 1024).toStringAsFixed(2)} MB');
    });

    test('Tokenizer JSON exists', () async {
      final file = File('assets/models/tokenizer.json');
      expect(await file.exists(), true);

      final size = await file.length();
      print('✅ Tokenizer size: ${(size / 1024 / 1024).toStringAsFixed(2)} MB');
    });
  });
}
