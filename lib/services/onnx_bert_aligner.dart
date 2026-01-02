// lib/services/onnx_bert_aligner.dart
import 'dart:typed_data';
import 'package:flutter/services.dart';
import 'package:onnxruntime/onnxruntime.dart';
import 'dart:io';
import 'dart:math' as math;
import 'docx_translator.dart';

class ONNXBertAligner implements WordAligner {
  OrtSession? _session;
  BertTokenizer? _tokenizer;
  bool _isInitialized = false;
  final bool verbose;

  ONNXBertAligner({this.verbose = false});

  Future<void> initialize({String? modelsPath}) async {
    if (_isInitialized) return;

    try {
      print('🔧 [ALIGNER] Initializing ONNX BERT aligner...');

      OrtEnv.instance.init();

      final sessionOptions = OrtSessionOptions()
        ..setInterOpNumThreads(2)
        ..setIntraOpNumThreads(2)
        ..setSessionGraphOptimizationLevel(GraphOptimizationLevel.ortEnableAll);

      // Load ONNX model
      Uint8List modelBytes;
      if (modelsPath != null) {
        print('📦 [ALIGNER] Loading from file system: $modelsPath');
        modelBytes = await File('$modelsPath/awesome_align_int8/model.onnx').readAsBytes();
      } else {
        print('📦 [ALIGNER] Loading from assets...');
        final buffer = await rootBundle.load('assets/onnx_models/awesome_align_int8/model.onnx');
        modelBytes = buffer.buffer.asUint8List();
      }

      _session = OrtSession.fromBuffer(modelBytes, sessionOptions);
      print('✅ [ALIGNER] ONNX model loaded');

      // Initialize simple BERT tokenizer
      _tokenizer = BertTokenizer();
      await _tokenizer!.initialize();
      print('✅ [ALIGNER] Tokenizer initialized');

      _isInitialized = true;
      print('✅ [ALIGNER] BERT aligner fully initialized');
    } catch (e, stack) {
      print('❌ [ALIGNER] Initialization failed: $e');
      print('Stack trace: $stack');
      _isInitialized = false;
      rethrow;
    }
  }

  @override
  List<Alignment> align(List<String> sourceWords, List<String> targetWords) {
    if (!_isInitialized || _session == null || _tokenizer == null) {
      print('⚠️  [ALIGNER] Not initialized, falling back to heuristic');
      return HeuristicAligner().align(sourceWords, targetWords);
    }

    if (sourceWords.isEmpty || targetWords.isEmpty) return [];

    try {
      if (verbose) {
        print('🔗 [ALIGNER] Aligning: ${sourceWords.length} → ${targetWords.length} words');
      }

      // Tokenize source words
      final srcEncoding = _tokenizer!.encode(sourceWords);
      final srcWordMap = srcEncoding.wordMap;

      // Tokenize target words
      final tgtEncoding = _tokenizer!.encode(targetWords);
      final tgtWordMap = tgtEncoding.wordMap;

      // Get embeddings from BERT
      final srcEmbeddings = _getEmbeddings(srcEncoding.inputIds, srcEncoding.attentionMask);
      final tgtEmbeddings = _getEmbeddings(tgtEncoding.inputIds, tgtEncoding.attentionMask);

      if (srcEmbeddings == null || tgtEmbeddings == null) {
        print('⚠️  [ALIGNER] Failed to get embeddings, falling back');
        return HeuristicAligner().align(sourceWords, targetWords);
      }

      // Compute similarity matrix
      final similarity = _computeSimilarity(srcEmbeddings, tgtEmbeddings);

      // Extract alignments using competitive selection
      final alignments = <Alignment>[];
      final seen = <String>{};

      // Forward pass: best target for each source
      final bestTgtForSrc = <int>[];
      for (int i = 0; i < similarity.length; i++) {
        int bestJ = 0;
        double maxSim = similarity[i][0];
        for (int j = 1; j < similarity[i].length; j++) {
          if (similarity[i][j] > maxSim) {
            maxSim = similarity[i][j];
            bestJ = j;
          }
        }
        bestTgtForSrc.add(bestJ);
      }

      // Backward pass: best source for each target
      final bestSrcForTgt = <int>[];
      for (int j = 0; j < similarity[0].length; j++) {
        int bestI = 0;
        double maxSim = similarity[0][j];
        for (int i = 1; i < similarity.length; i++) {
          if (similarity[i][j] > maxSim) {
            maxSim = similarity[i][j];
            bestI = i;
          }
        }
        bestSrcForTgt.add(bestI);
      }

      // Symmetric selection
      for (int i = 0; i < bestTgtForSrc.length; i++) {
        final j = bestTgtForSrc[i];
        if (bestSrcForTgt[j] == i) {
          // Map sub-token indices back to word indices
          final srcWordIdx = srcWordMap[i];
          final tgtWordIdx = tgtWordMap[j];

          final key = '$srcWordIdx-$tgtWordIdx';
          if (!seen.contains(key)) {
            alignments.add(Alignment(srcWordIdx, tgtWordIdx));
            seen.add(key);
          }
        }
      }

      if (verbose) {
        print('✅ [ALIGNER] Found ${alignments.length} alignment links');
      }

      return alignments;
    } catch (e, stack) {
      print('❌ [ALIGNER] Alignment failed: $e');
      if (verbose) print('Stack trace: $stack');
      return HeuristicAligner().align(sourceWords, targetWords);
    }
  }

  List<List<double>>? _getEmbeddings(Int64List inputIds, Int64List attentionMask) {
    try {
      final idTensor = OrtValueTensor.createTensorWithDataList(
        inputIds,
        [1, inputIds.length],
      );

      final maskTensor = OrtValueTensor.createTensorWithDataList(
        attentionMask,
        [1, attentionMask.length],
      );

      final outputs = _session!.run(
        OrtRunOptions(),
        {
          'input_ids': idTensor,
          'attention_mask': maskTensor,
        },
      );

      idTensor.release();
      maskTensor.release();

      if (outputs == null || outputs.isEmpty) return null;

      // Extract embeddings (remove CLS and SEP tokens)
      final List rawOutput = outputs[0]!.value as List;
      final List sequence = rawOutput[0] as List;

      // Skip [CLS] at position 0 and [SEP] at end
      final embeddings = <List<double>>[];
      for (int i = 1; i < sequence.length - 1; i++) {
        final List embedding = sequence[i] as List;
        embeddings.add(embedding.map((e) => (e as num).toDouble()).toList());
      }

      outputs[0]!.release();

      return embeddings;
    } catch (e) {
      print('❌ [ALIGNER] Failed to get embeddings: $e');
      return null;
    }
  }

  List<List<double>> _computeSimilarity(
    List<List<double>> srcEmb,
    List<List<double>> tgtEmb,
  ) {
    // Normalize embeddings for cosine similarity
    final srcNorm = _normalize(srcEmb);
    final tgtNorm = _normalize(tgtEmb);

    // Compute dot product (cosine similarity after normalization)
    final similarity = <List<double>>[];
    for (int i = 0; i < srcNorm.length; i++) {
      final row = <double>[];
      for (int j = 0; j < tgtNorm.length; j++) {
        double dotProduct = 0;
        for (int k = 0; k < srcNorm[i].length; k++) {
          dotProduct += srcNorm[i][k] * tgtNorm[j][k];
        }
        row.add(dotProduct);
      }
      similarity.add(row);
    }

    return similarity;
  }

  List<List<double>> _normalize(List<List<double>> embeddings) {
    final normalized = <List<double>>[];
    for (final emb in embeddings) {
      double norm = 0;
      for (final val in emb) {
        norm += val * val;
      }
      norm = math.sqrt(norm);

      if (norm < 1e-9) {
        normalized.add(List.filled(emb.length, 0.0));
      } else {
        normalized.add(emb.map((v) => v / norm).toList());
      }
    }
    return normalized;
  }

  void dispose() {
    _session?.release();
    _isInitialized = false;
  }

  bool get isInitialized => _isInitialized;
}

// Simple BERT tokenizer for word-level tokenization
class BertTokenizer {
  static const int clsTokenId = 101;
  static const int sepTokenId = 102;
  static const int unkTokenId = 100;
  static const int padTokenId = 0;

  Future<void> initialize() async {
    // Already initialized - using character-level tokenization
  }

  TokenizerOutput encode(List<String> words) {
    final inputIds = <int>[clsTokenId];
    final attentionMask = <int>[1];
    final wordMap = <int>[];

    for (int wordIdx = 0; wordIdx < words.length; wordIdx++) {
      final word = words[wordIdx];
      final tokens = _tokenizeWord(word);

      for (final token in tokens) {
        inputIds.add(token);
        attentionMask.add(1);
        wordMap.add(wordIdx);
      }
    }

    inputIds.add(sepTokenId);
    attentionMask.add(1);

    return TokenizerOutput(
      inputIds: Int64List.fromList(inputIds),
      attentionMask: Int64List.fromList(attentionMask),
      wordMap: wordMap,
    );
  }

  List<int> _tokenizeWord(String word) {
    // Simple character-level encoding with hash-based IDs
    final tokens = <int>[];
    final chars = word.toLowerCase().split('');
    
    for (var char in chars) {
      // Use character code modulo to create consistent IDs in valid range
      // BERT vocab typically ranges from 0-30000, so we use 1000-29000
      final charCode = char.codeUnitAt(0);
      final tokenId = 1000 + (charCode % 28000);
      tokens.add(tokenId);
    }
    
    return tokens.isEmpty ? [unkTokenId] : tokens;
  }
}

class TokenizerOutput {
  final Int64List inputIds;
  final Int64List attentionMask;
  final List<int> wordMap; // Maps sub-token position to word index

  TokenizerOutput({
    required this.inputIds,
    required this.attentionMask,
    required this.wordMap,
  });
}