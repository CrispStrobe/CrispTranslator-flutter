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
      print('🔗 [ALIGNER] ==================== ALIGNMENT START ====================');
      print('🔗 [ALIGNER] Source words (${sourceWords.length}): $sourceWords');
      print('🔗 [ALIGNER] Target words (${targetWords.length}): $targetWords');

      // 1. TOKENIZE WITH WORDMAP (Python equivalent: get_tokens_and_map)
      final srcEncoding = _tokenizeWords(sourceWords);
      final tgtEncoding = _tokenizeWords(targetWords);
      
      print('🔗 [ALIGNER] Source: ${srcEncoding.subtokens.length} subtokens → ${srcEncoding.wordMap.length} mapped');
      print('🔗 [ALIGNER] Target: ${tgtEncoding.subtokens.length} subtokens → ${tgtEncoding.wordMap.length} mapped');

      // 2. GET EMBEDDINGS
      final srcEmbeddings = _getEmbeddings(srcEncoding.inputIds, srcEncoding.attentionMask);
      final tgtEmbeddings = _getEmbeddings(tgtEncoding.inputIds, tgtEncoding.attentionMask);

      if (srcEmbeddings == null || tgtEmbeddings == null) {
        print('⚠️  [ALIGNER] Failed to get embeddings');
        return HeuristicAligner().align(sourceWords, targetWords);
      }

      print('🔗 [ALIGNER] Embeddings: src=${srcEmbeddings.length}, tgt=${tgtEmbeddings.length}');

      // Verify dimensions match
      if (srcEmbeddings.length != srcEncoding.wordMap.length ||
          tgtEmbeddings.length != tgtEncoding.wordMap.length) {
        print('❌ [ALIGNER] Dimension mismatch! Src: ${srcEmbeddings.length} vs ${srcEncoding.wordMap.length}, Tgt: ${tgtEmbeddings.length} vs ${tgtEncoding.wordMap.length}');
        return HeuristicAligner().align(sourceWords, targetWords);
      }

      // 3. NORMALIZE EMBEDDINGS (Python: src_out / np.linalg.norm)
      final srcNorm = _normalizeEmbeddings(srcEmbeddings);
      final tgtNorm = _normalizeEmbeddings(tgtEmbeddings);

      // 4. COMPUTE SIMILARITY MATRIX (Python: np.dot(src_norm, tgt_norm.T))
      final similarity = _computeSimilarity(srcNorm, tgtNorm);
      final srcLen = similarity.length;
      final tgtLen = similarity[0].length;
      
      print('🔗 [ALIGNER] Similarity matrix: ${srcLen}x$tgtLen');

      // 5. FORWARD PASS: For each source token, find best target token
      final forwardMatches = List<int>.filled(srcLen, -1);
      
      for (int i = 0; i < srcLen; i++) {
        int bestJ = 0;
        double maxSim = similarity[i][0];
        
        for (int j = 1; j < tgtLen; j++) {
          if (similarity[i][j] > maxSim) {
            maxSim = similarity[i][j];
            bestJ = j;
          }
        }
        
        forwardMatches[i] = bestJ;
      }

      // 6. BACKWARD PASS: For each target token, find best source token
      final backwardMatches = List<int>.filled(tgtLen, -1);
      
      for (int j = 0; j < tgtLen; j++) {
        int bestI = 0;
        double maxSim = similarity[0][j];
        
        for (int i = 1; i < srcLen; i++) {
          if (similarity[i][j] > maxSim) {
            maxSim = similarity[i][j];
            bestI = i;
          }
        }
        
        backwardMatches[j] = bestI;
      }

      // 7. MUTUAL ARGMAX INTERSECTION (Python: if best_src_for_tgt[j] == i)
      final alignments = <Alignment>[];
      final seen = <String>{};
      const threshold = 0.001; // Python: 1e-3

      for (int i = 0; i < srcLen; i++) {
        final j = forwardMatches[i];
        
        // MUTUAL AGREEMENT: src i picked tgt j AND tgt j picked src i
        if (backwardMatches[j] == i && similarity[i][j] > threshold) {
          // Map subword indices to word indices
          final srcWordIdx = srcEncoding.wordMap[i];
          final tgtWordIdx = tgtEncoding.wordMap[j];

          final key = '$srcWordIdx-$tgtWordIdx';
          if (!seen.contains(key)) {
            alignments.add(Alignment(srcWordIdx, tgtWordIdx));
            seen.add(key);
            
            if (verbose) {
              print('🔗 [ALIGNER] ✓ Align: src[$srcWordIdx]"${sourceWords[srcWordIdx]}" ↔ tgt[$tgtWordIdx]"${targetWords[tgtWordIdx]}" (sim=${similarity[i][j].toStringAsFixed(3)})');
            }
          }
        }
      }
      
      print('🔗 [ALIGNER] ==================== FOUND ${alignments.length} ALIGNMENTS ====================');
      for (final a in alignments) {
        print('   ${a.sourceIndex} ↔ ${a.targetIndex}');
      }
      
      return alignments;
    } catch (e, stack) {
      print('❌ [ALIGNER] Alignment failed: $e');
      if (verbose) print('Stack trace: $stack');
      return HeuristicAligner().align(sourceWords, targetWords);
    }
  }

  // CRITICAL: Tokenize per-word with wordMap (matches Python's get_tokens_and_map)
  _TokenizationResult _tokenizeWords(List<String> words) {
    final subtokens = <String>[];
    final wordMap = <int>[];
    
    print('🔍 [TOKENIZER] Tokenizing ${words.length} words...');
    
    // Process each word individually
    for (int wordIdx = 0; wordIdx < words.length; wordIdx++) {
        final word = words[wordIdx];
        
        // Tokenize this word
        final tokens = _tokenizer!.tokenizeWord(word);
        
        if (tokens.isEmpty) {
        // If tokenization failed, use [UNK]
        subtokens.add('[UNK]');
        wordMap.add(wordIdx);
        } else {
        // Add all subtokens for this word
        subtokens.addAll(tokens);
        // Map each subtoken back to the original word index
        wordMap.addAll(List.filled(tokens.length, wordIdx));
        }
    }
    
    print('🔍 [TOKENIZER] Result: ${subtokens.length} subtokens for ${words.length} words');
    print('🔍 [TOKENIZER] First 10 subtokens: ${subtokens.take(10).toList()}');
    
    // Build input IDs with [CLS] and [SEP]
    final inputIds = <int>[101]; // [CLS]
    final attentionMask = <int>[1];
    
    for (final token in subtokens) {
        final id = _tokenizer!._vocab[token] ?? 100; // [UNK] if not found
        inputIds.add(id);
        attentionMask.add(1);
    }
    
    inputIds.add(102); // [SEP]
    attentionMask.add(1);
    
    print('🔍 [TOKENIZER] Final sequence: ${inputIds.length} tokens (including CLS/SEP)');
    
    return _TokenizationResult(
        subtokens: subtokens,
        inputIds: Int64List.fromList(inputIds),
        attentionMask: Int64List.fromList(attentionMask),
        wordMap: wordMap,
    );
    }

  // Normalize embeddings (Python: emb / np.linalg.norm(emb, axis=-1, keepdims=True))
  List<List<double>> _normalizeEmbeddings(List<List<double>> embeddings) {
    return embeddings.map((emb) {
      double sumSq = 0.0;
      for (final val in emb) {
        sumSq += val * val;
      }
      final norm = math.sqrt(sumSq);
      
      if (norm < 1e-9) {
        return List<double>.filled(emb.length, 0.0);
      }
      
      return emb.map((v) => v / norm).toList();
    }).toList();
  }

  List<List<double>>? _getEmbeddings(Int64List inputIds, Int64List attentionMask) {
    OrtValueTensor? idTensor;
    OrtValueTensor? maskTensor;
    OrtRunOptions? runOptions;
    List<OrtValue?>? outputs;

    try {
      idTensor = OrtValueTensor.createTensorWithDataList(inputIds, [1, inputIds.length]);
      maskTensor = OrtValueTensor.createTensorWithDataList(attentionMask, [1, attentionMask.length]);
      runOptions = OrtRunOptions();
      
      // Run ONNX model
      outputs = _session!.run(runOptions, {
        'input_ids': idTensor,
        'attention_mask': maskTensor
      });

      if (outputs == null || outputs.isEmpty || outputs[0] == null) {
        print('❌ [ALIGNER] No output from ONNX model');
        return null;
      }

      // Extract last_hidden_state [1, seq_len, 768]
      final List rawValue = outputs[0]!.value as List;
      final List sequence = rawValue[0] as List;
      
      final embeddings = <List<double>>[];
      
      // Python: [0, 1:-1] - skip CLS (index 0) and SEP (last index)
      for (int i = 1; i < sequence.length - 1; i++) {
        final List embedding = sequence[i] as List;
        embeddings.add(embedding.map((e) => (e as num).toDouble()).toList());
      }

      print('🔗 [ALIGNER] Extracted ${embeddings.length} embeddings (excluding CLS/SEP)');
      return embeddings;
      
    } catch (e) {
      print('❌ [ALIGNER] Inference Error: $e');
      return null;
    } finally {
      // Release memory
      idTensor?.release();
      maskTensor?.release();
      runOptions?.release();
      if (outputs != null) {
        for (var element in outputs) {
          element?.release();
        }
      }
    }
  }

  // Compute cosine similarity matrix (Python: np.dot(src_norm, tgt_norm.T))
  List<List<double>> _computeSimilarity(List<List<double>> srcNorm, List<List<double>> tgtNorm) {
    final similarity = List.generate(
      srcNorm.length,
      (_) => List<double>.filled(tgtNorm.length, 0.0)
    );
    
    for (int i = 0; i < srcNorm.length; i++) {
      for (int j = 0; j < tgtNorm.length; j++) {
        double dotProduct = 0.0;
        for (int k = 0; k < srcNorm[i].length; k++) {
          dotProduct += srcNorm[i][k] * tgtNorm[j][k];
        }
        similarity[i][j] = dotProduct;
      }
    }
    
    return similarity;
  }

  void dispose() {
    _session?.release();
    _isInitialized = false;
  }

  bool get isInitialized => _isInitialized;
}

// Helper class for tokenization result
class _TokenizationResult {
  final List<String> subtokens;
  final Int64List inputIds;
  final Int64List attentionMask;
  final List<int> wordMap;
  
  _TokenizationResult({
    required this.subtokens,
    required this.inputIds,
    required this.attentionMask,
    required this.wordMap,
  });
}

// Simple BERT tokenizer
class BertTokenizer {
  Map<String, int> _vocab = {};
  bool _isLoaded = false;

  Future<void> initialize() async {
    if (_isLoaded) return;
    try {
      final data = await rootBundle.loadString('assets/onnx_models/vocab.txt');
      final lines = data.split('\n');
      for (int i = 0; i < lines.length; i++) {
        final token = lines[i].trim();
        if (token.isNotEmpty) {
          _vocab[token] = i;
        }
      }
      _isLoaded = true;
      print('✅ [TOKENIZER] Loaded ${_vocab.length} vocab entries');
      
      // DEBUG: Check if common tokens exist
      print('🔍 [TOKENIZER] Vocab check: [CLS]=${_vocab['[CLS]']}, ##ical=${_vocab['##ical']}, theology=${_vocab['theology']}');
    } catch (e) {
      print('❌ [TOKENIZER] Failed to load vocab.txt: $e');
    }
  }

  // CRITICAL FIX: Proper WordPiece tokenization
  List<String> tokenizeWord(String word) {
    final tokens = <String>[];
    String remaining = word; // DON'T lowercase - BERT is case-sensitive!
    bool isFirstToken = true;
    
    while (remaining.isNotEmpty) {
      String? foundToken;
      int foundLen = 0;
      
      // Try to find the longest matching subtoken (greedy)
      for (int len = remaining.length; len > 0; len--) {
        final substr = remaining.substring(0, len);
        // Add ## prefix for continuation tokens
        final candidate = isFirstToken ? substr : '##$substr';
        
        if (_vocab.containsKey(candidate)) {
          foundToken = candidate;
          foundLen = len;
          break;
        }
      }
      
      if (foundToken == null) {
        // Can't tokenize this character - use [UNK] for the whole remaining word
        print('⚠️  [TOKENIZER] Unknown token: "$remaining" in word "$word"');
        return tokens.isEmpty ? ['[UNK]'] : [...tokens, '[UNK]'];
      }
      
      tokens.add(foundToken);
      remaining = remaining.substring(foundLen);
      isFirstToken = false;
    }
    
    // DEBUG: Show multi-token words
    if (tokens.length > 1) {
      print('🔍 [TOKENIZER] "$word" → $tokens');
    }
    
    return tokens;
  }
}