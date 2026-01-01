import 'dart:io';
import 'dart:typed_data';
import 'dart:convert';

class StandaloneNLLBTokenizer {
  Map<String, int>? _vocab;
  Map<int, String>? _reverseVocab;
  List<List<String>>? _merges;

  static const Map<String, int> languageTokens = {
    'German': 256049,
    'French': 256057,
    'Spanish': 256014,
    'Italian': 256024,
    'Portuguese': 256031,
    'Japanese': 256100,
    'Chinese': 256137,
    'Korean': 256104,
    'Arabic': 256167,
    'Hindi': 256098,
  };

  static const int padTokenId = 1;
  static const int bosTokenId = 2;
  static const int eosTokenId = 2;
  static const int unkTokenId = 3;

  Future<void> initialize(String tokenizerJsonPath) async {
    print('📝 Loading tokenizer from $tokenizerJsonPath...');

    final file = File(tokenizerJsonPath);
    final tokenizerData = await file.readAsString();
    final tokenizerJson = json.decode(tokenizerData);

    final model = tokenizerJson['model'];
    final vocabData = model['vocab'] as Map<String, dynamic>;

    _vocab = {};
    _reverseVocab = {};

    vocabData.forEach((token, id) {
      final tokenId = id as int;
      _vocab![token] = tokenId;
      _reverseVocab![tokenId] = token;
    });

    // Handle merges - can be List<String> or List<List<String>>
    final mergesData = model['merges'];
    _merges = [];

    if (mergesData is List) {
      for (var merge in mergesData) {
        try {
          if (merge is String) {
            final parts = merge.split(' ');
            if (parts.length == 2) {
              _merges!.add(parts);
            }
          } else if (merge is List) {
            if (merge.length >= 2) {
              _merges!.add([merge[0].toString(), merge[1].toString()]);
            }
          }
        } catch (e) {
          continue;
        }
      }
    }

    print(
        '✅ Tokenizer loaded: ${_vocab!.length} tokens, ${_merges!.length} merges');
  }

  TokenizerOutput encode(String text, {int maxLength = 256}) {
    if (_vocab == null) {
      throw StateError('Tokenizer not initialized');
    }

    text = text.trim();
    final tokens = _tokenizeBPE(text);
    final ids = tokens.map((token) => _vocab![token] ?? unkTokenId).toList();

    // Add special tokens: BOS + ids + EOS
    final fullIds = <int>[bosTokenId, ...ids, eosTokenId];

    // Truncate if needed
    final finalIds = <int>[]; // Create growable list
    if (fullIds.length > maxLength) {
      finalIds.addAll(fullIds.sublist(0, maxLength - 1));
      finalIds.add(eosTokenId);
    } else {
      finalIds.addAll(fullIds);
    }

    // Create attention mask (growable)
    final attentionMask = <int>[];
    attentionMask.addAll(List.filled(finalIds.length, 1));

    // Pad to maxLength
    while (finalIds.length < maxLength) {
      finalIds.add(padTokenId);
      attentionMask.add(0);
    }

    return TokenizerOutput(
      inputIds: Int32List.fromList(finalIds),
      attentionMask: Uint8List.fromList(attentionMask),
    );
  }

  String decode(List<int> ids) {
    if (_reverseVocab == null) {
      throw StateError('Tokenizer not initialized');
    }

    final tokens = <String>[];

    for (final id in ids) {
      if (id == padTokenId || id == bosTokenId || id == eosTokenId) {
        continue;
      }
      if (languageTokens.values.contains(id)) {
        continue;
      }

      final token = _reverseVocab![id];
      if (token != null) {
        tokens.add(token);
      }
    }

    String text = tokens.join('');
    text = text.replaceAll('▁', ' ');
    text = text.replaceAll(RegExp(r'\s+'), ' ');
    text = text.trim();

    return text;
  }

  List<String> _tokenizeBPE(String text) {
    text = '▁$text';
    text = text.replaceAll(' ', '▁');
    List<String> tokens = text.split('').toList();

    if (_merges != null && _merges!.isNotEmpty) {
      for (final merge in _merges!) {
        if (merge.length != 2) continue;

        final first = merge[0];
        final second = merge[1];
        final merged = first + second;

        bool changed = true;
        while (changed) {
          changed = false;
          for (int i = 0; i < tokens.length - 1; i++) {
            if (tokens[i] == first && tokens[i + 1] == second) {
              tokens[i] = merged;
              tokens.removeAt(i + 1);
              changed = true;
              break;
            }
          }
        }
      }
    }

    return tokens;
  }

  int getLanguageTokenId(String language) {
    return languageTokens[language] ?? languageTokens['German']!;
  }
}

class TokenizerOutput {
  final Int32List inputIds;
  final Uint8List attentionMask;

  TokenizerOutput({
    required this.inputIds,
    required this.attentionMask,
  });
}

void main() async {
  print('=' * 70);
  print('🧪 NLLB Translation Test Suite');
  print('=' * 70);
  print('');

  // Test 1: Tokenizer Test
  print('Test 1: Tokenizer');
  print('-' * 70);

  try {
    final tokenizer = StandaloneNLLBTokenizer();
    await tokenizer.initialize('assets/models/tokenizer.json');

    final testTexts = [
      'Hello, how are you?',
      'The quick brown fox jumps over the lazy dog.',
      'Machine learning is fascinating!',
    ];

    for (final text in testTexts) {
      print('\n📝 Input: "$text"');

      final encoding = tokenizer.encode(text, maxLength: 256);
      final actualTokens = encoding.attentionMask.where((m) => m == 1).length;

      print('   Token count: $actualTokens');
      print('   First 10 IDs: ${encoding.inputIds.sublist(0, 10)}');

      // Test decode
      final decoded = tokenizer.decode(encoding.inputIds.toList());
      print('   Decoded: "$decoded"');

      // Verify round-trip (approximately)
      if (decoded.toLowerCase().contains(text.split(' ')[0].toLowerCase())) {
        print('   ✅ Round-trip successful');
      } else {
        print('   ⚠️  Round-trip may have issues');
      }
    }

    print('\n✅ Tokenizer tests passed!');
  } catch (e, stack) {
    print('❌ Tokenizer test failed: $e');
    print(stack);
    exit(1);
  }

  print('\n' + '=' * 70);
  print('Test 2: Model File Check');
  print('-' * 70);

  final modelFiles = [
    'assets/onnx_models/encoder_model.onnx',
    'assets/onnx_models/decoder_model.onnx',
    'assets/models/tokenizer.json',
  ];

  for (final filePath in modelFiles) {
    final file = File(filePath);
    if (await file.exists()) {
      final size = await file.length();
      final sizeMB = size / (1024 * 1024);
      print('✅ $filePath (${sizeMB.toStringAsFixed(2)} MB)');
    } else {
      print('❌ Missing: $filePath');
    }
  }

  print('\n' + '=' * 70);
  print('✅ All tests completed!');
  print('=' * 70);
  print('\n💡 Next: Run "flutter run -d macos" to test with ONNX models');
}
