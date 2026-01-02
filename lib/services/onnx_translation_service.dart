// lib/services/onnx_translation_service.dart:

import 'dart:typed_data';
import 'package:flutter/services.dart';
import 'package:onnxruntime/onnxruntime.dart';
import 'nllb_tokenizer.dart';
import 'dart:io';
import 'dart:math' as math;

/// Represents a single candidate path in the Beam Search tree.
class BeamHypothesis {
  final List<int> tokens;
  final double score;
  final Map<String, OrtValue> decoderKVs;
  bool isFinished;

  BeamHypothesis({
    required this.tokens,
    required this.score,
    required this.decoderKVs,
    this.isFinished = false,
  });

  /// Safely releases all ONNX tensors associated with this branch.
  void dispose() {
    decoderKVs.forEach((_, value) => value.release());
    decoderKVs.clear();
  }
}

class ONNXTranslationService {
  OrtSession? _encoderSession;
  OrtSession? _decoderSession;
  OrtSession? _decoderWithPastSession;
  NLLBTokenizer? _tokenizer;
  bool _isInitialized = false;

  // final int maxTokens = 256;
  static const int hiddenSize = 1024;
  static const int numLayers = 12;
  static const int numHeads = 16;
  static const int headDim = 64; // 1024 / 16

  Future<void> initialize({String? modelsPath}) async {
    try {
      print('🔧 Initializing ONNX Translation Service...');

      OrtEnv.instance.init();

      final sessionOptions = OrtSessionOptions()
        ..setInterOpNumThreads(4)
        ..setIntraOpNumThreads(4)
        ..setSessionGraphOptimizationLevel(
          GraphOptimizationLevel.ortEnableAll,
        );

      // Load from file system if path provided, otherwise from assets
      Uint8List encoderBytes, decoderBytes, decoderWithPastBytes;

      if (modelsPath != null) {
        // Load from file system
        print('📦 Loading encoder from file system...');
        encoderBytes =
            await File('$modelsPath/encoder_model.onnx').readAsBytes();

        print('📦 Loading decoder from file system...');
        decoderBytes =
            await File('$modelsPath/decoder_model.onnx').readAsBytes();

        print('📦 Loading decoder with KV cache from file system...');
        decoderWithPastBytes =
            await File('$modelsPath/decoder_with_past_model.onnx')
                .readAsBytes();
      } else {
        // Load from assets
        print('📦 Loading encoder from assets...');
        final encoderBuffer =
            await rootBundle.load('assets/onnx_models/encoder_model.onnx');
        encoderBytes = encoderBuffer.buffer.asUint8List();

        print('📦 Loading decoder from assets...');
        final decoderBuffer =
            await rootBundle.load('assets/onnx_models/decoder_model.onnx');
        decoderBytes = decoderBuffer.buffer.asUint8List();

        print('📦 Loading decoder with KV cache from assets...');
        final decoderWithPastBuffer = await rootBundle
            .load('assets/onnx_models/decoder_with_past_model.onnx');
        decoderWithPastBytes = decoderWithPastBuffer.buffer.asUint8List();
      }

      _encoderSession = OrtSession.fromBuffer(encoderBytes, sessionOptions);
      _decoderSession = OrtSession.fromBuffer(decoderBytes, sessionOptions);
      _decoderWithPastSession =
          OrtSession.fromBuffer(decoderWithPastBytes, sessionOptions);

      print(
          'DEBUG: [Decoder] Regular decoder input names: ${_decoderSession!.inputNames}');
      print(
          'DEBUG: [Decoder] With-past decoder input names: ${_decoderWithPastSession!.inputNames}');

      // Initialize tokenizer
      _tokenizer = NLLBTokenizer();
      await _tokenizer!.initialize(modelsPath: modelsPath);

      _isInitialized = true;
      print('✅ Service fully initialized!');
    } catch (e, stack) {
      print('❌ Initialization failed: $e');
      print(stack);
      rethrow;
    }
  }

  /// CORE BEAM SEARCH DECODER
  Future<List<int>> _runDecoderBeamSearch(
    OrtValue encoderOutput,
    TokenizerOutput encoding,
    String targetLanguage, {
    int beamSize = 4,
    int maxLength = 128,
  }) async {
    final targetLangId = _tokenizer!.getLanguageTokenId(targetLanguage);
    final int encoderSeqLen = (encoderOutput.value as List)[0].length;
    final fullEncoderMask = Int64List.fromList(encoding.attentionMask.map((e) => e.toInt()).toList());

    // Initialize with Lang ID (BOS + Language Tag)
    List<BeamHypothesis> beams = [
      BeamHypothesis(
        tokens: [2, targetLangId],
        score: 0.0,
        decoderKVs: {},
      )
    ];

    for (int step = 0; step < maxLength; step++) {
      List<BeamHypothesis> candidates = [];

      for (var beam in beams) {
        if (beam.isFinished) {
          candidates.add(beam);
          continue;
        }

        final bool isStep0 = step == 0;
        final session = isStep0 ? _decoderSession! : _decoderWithPastSession!;
        final currentInputIds = isStep0 ? beam.tokens : [beam.tokens.last];

        final idTensor = OrtValueTensor.createTensorWithDataList(
            Int64List.fromList(currentInputIds), [1, currentInputIds.length]);
        final maskTensor = OrtValueTensor.createTensorWithDataList(fullEncoderMask, [1, encoderSeqLen]);

        final inputs = <String, OrtValue>{
          'input_ids': idTensor,
          'encoder_attention_mask': maskTensor,
        };

        if (isStep0) {
          inputs['encoder_hidden_states'] = encoderOutput;
        } else {
          inputs.addAll(beam.decoderKVs);
          // Note: encoder KVs are typically static and handled within the session
        }

        final outputs = await session.runAsync(OrtRunOptions(), inputs);
        if (outputs == null) continue;

        final logitsValue = outputs[0]!;
        final List logits = (logitsValue.value as List)[0][currentInputIds.length - 1];

        // 🛡️ Log-Softmax for numerical stability
        final logProbs = _computeLogSoftmax(logits);
        final topKIndices = _getTopK(logProbs, beamSize);

        for (int nextToken in topKIndices) {
          final nextScore = beam.score + logProbs[nextToken];
          final nextTokens = List<int>.from(beam.tokens)..add(nextToken);
          
          // Map present KVs to past KVs for the next step
          final nextKVs = _extractKVs(outputs, session.outputNames);

          candidates.add(BeamHypothesis(
            tokens: nextTokens,
            score: nextScore,
            decoderKVs: nextKVs,
            isFinished: nextToken == 2, // EOS
          ));
        }

        // Cleanup temporary tensors for this specific branch step
        idTensor.release();
        maskTensor.release();
        logitsValue.release();
        // If we were using past KVs, we can't release them until we know which beam won
      }

      // Sort candidates by score (best first)
      candidates.sort((a, b) => b.score.compareTo(a.score));

      // 🧹 Pruning: Keep only top beams and dispose of the others
      final oldBeams = beams;
      beams = candidates.take(beamSize).toList();

      // Dispose only of hypotheses that didn't make the cut
      for (var cand in candidates.skip(beamSize)) {
        cand.dispose();
      }
      // Dispose of old beam KVs as they've been cycled into new candidate KVs
      for (var oldBeam in oldBeams) {
        if (!beams.contains(oldBeam)) oldBeam.dispose();
      }

      if (beams.every((b) => b.isFinished)) break;
    }

    final bestBeam = beams.first;
    final result = List<int>.from(bestBeam.tokens.sublist(2));

    // Final Memory Cleanup
    for (var b in beams) {
      b.dispose();
    }

    return result;
  }

  /// Numerically stable Log-Softmax implementation
  List<double> _computeLogSoftmax(List logits) {
    double maxLogit = logits.map((e) => (e as num).toDouble()).reduce((a, b) => a > b ? a : b);
    double sumExp = logits.map((e) => math.exp((e as num).toDouble() - maxLogit)).reduce((a, b) => a + b);
    double logSumExp = maxLogit + math.log(sumExp);
    return logits.map((e) => (e as num).toDouble() - logSumExp).toList();
  }

  List<int> _getTopK(List<double> probs, int k) {
    final indexed = probs.asMap().entries.toList();
    indexed.sort((a, b) => b.value.compareTo(a.value));
    return indexed.take(k).map((e) => e.key).toList();
  }

  Map<String, OrtValue> _extractKVs(List<OrtValue?> outputs, List<String> names) {
    final kvs = <String, OrtValue>{};
    for (int i = 1; i < outputs.length; i++) {
      final name = names[i].replaceFirst('present', 'past_key_values');
      kvs[name] = outputs[i]!; 
    }
    return kvs;
  }

  /// Public translation entry point with beam search logic branching.
  Future<String> translate(
    String text,
    String targetLanguage, {
    String sourceLanguage = 'English',
    int beamSize = 1, // ✅ Passed from AppSettings
    int? maxLength,   // If null, will be dynamically calculated
  }) async {
    if (!_isInitialized) throw StateError('Service not initialized');

    final startTime = DateTime.now();
    print('\n' + '=' * 70);
    print('🔤 Translation: "$text"');
    print('   $sourceLanguage → $targetLanguage (Beams: $beamSize)'); 
    print('=' * 70);

    try {
      // 1. Tokenize with source language
      final tokStart = DateTime.now();
      final encoding = _tokenizer!.encode(text, sourceLanguage: sourceLanguage);

      print('\n--- CROSS-CHECK LOG (DART vs PYTHON) ---');
      print('DART Encoder IDs:   ${encoding.inputIds.take(15).toList()}');
      final targetLangId = _tokenizer!.getLanguageTokenId(targetLanguage);
      print('DART Source Lang: $sourceLanguage');
      print('DART Target Lang ID: $targetLangId');

      final actualLength = encoding.attentionMask.where((m) => m == 1).length;
      print('📝 Tokens: $actualLength (${DateTime.now().difference(tokStart).inMilliseconds}ms)');

      // ✅ Calculate dynamic max length based on input
      final dynamicMaxLength = maxLength ?? _calculateMaxLength(actualLength);
      print('📏 [DECODER] Dynamic max_length: $dynamicMaxLength (input: $actualLength)');

      // 2. Run encoder
      final encStart = DateTime.now();
      final encoderOutput = await _runEncoder(encoding);
      print('🔄 Encoder: ${DateTime.now().difference(encStart).inMilliseconds}ms');

      // 3. Logic Branching: Beam Search vs. Greedy with Cache
      final decStart = DateTime.now();
      List<int> outputIds;

      if (beamSize > 1) {
        print('🚀 [DECODER] Running Full Beam Search (Size: $beamSize)...');
        outputIds = await _runDecoderBeamSearch(
          encoderOutput!,
          encoding,
          targetLanguage,
          beamSize: beamSize,
          maxLength: dynamicMaxLength,
        );
      } else {
        print('⚡ [DECODER] Running Greedy Search with KV Cache...');
        outputIds = await _runDecoderWithCache(
          encoderOutput,
          encoding,
          targetLanguage,
          maxLength: dynamicMaxLength,
        );
      }
      print('🔄 Decoder: ${DateTime.now().difference(decStart).inMilliseconds}ms');

      // 4. Detokenize
      final detokStart = DateTime.now();
      final translation = _tokenizer!.decode(outputIds);
      print('📝 Detokenize: ${DateTime.now().difference(detokStart).inMilliseconds}ms');

      final totalTime = DateTime.now().difference(startTime).inMilliseconds;
      print('✅ Total: ${totalTime}ms');
      print('   Result: "$translation"');
      print('=' * 70 + '\n');

      return translation;
    } catch (e, stack) {
      print('❌ Translation failed: $e');
      print(stack);
      rethrow;
    }
  }

// Calculate appropriate max length
int _calculateMaxLength(int inputLength) {
  // Rule: output can be 2-3x longer than input for most language pairs
  // Min: 64 tokens, Max: 512 tokens
  final calculated = (inputLength * 2.5).toInt();
  return calculated.clamp(64, 512);
}

  Future<OrtValue?> _runEncoder(TokenizerOutput encoding) async {
    print('\n🔧 [Encoder] Running encoder...');
    final ids = encoding.inputIds.toList();
    final mask = encoding.attentionMask.toList();

    // ✅ Use actual length instead of fixed maxTokens
    final int actualLength = ids.length;

    print('DEBUG [Encoder] Input IDs: $ids');
    print('DEBUG [Encoder] Attention Mask: $mask');
    print(
        'DEBUG [Encoder] Input shape: [1, $actualLength] (dynamic, matching Python!)');

    final idTensor = OrtValueTensor.createTensorWithDataList(
        Int64List.fromList(ids), [1, actualLength] // ✅ Dynamic length!
        );
    final maskTensor = OrtValueTensor.createTensorWithDataList(
        Int64List.fromList(mask), [1, actualLength] // ✅ Dynamic length!
        );

    try {
      print('DEBUG [Encoder] Running ONNX encoder session...');
      final outputs = await _encoderSession!.runAsync(OrtRunOptions(), {
        'input_ids': idTensor,
        'attention_mask': maskTensor,
      });

      final encoderOutput = outputs?[0];

      if (encoderOutput != null) {
        final List outer = encoderOutput.value as List;
        final List seq0 = outer[0] as List;
        final List hidden0 = seq0[0] as List;
        print(
            'DEBUG [Encoder] Output shape: [${outer.length}, ${seq0.length}, ${hidden0.length}]');
        print(
            'DEBUG [Encoder] Hidden States (Position 0, First 20): ${hidden0.take(20).toList()}');
        print(
            'DEBUG [Encoder] Hidden States (Position 1, First 20): ${(seq0[1] as List).take(20).toList()}');
      }

      return encoderOutput;
    } finally {
      idTensor.release();
      maskTensor.release();
    }
  }

  Future<List<int>> _runDecoderWithCache(
  OrtValue? encoderOutput,
  TokenizerOutput encoding,
  String targetLanguage, {
  int maxLength = 128, // ✅ Accept as parameter with default
}) async {
  print('\n🔧 [Decoder] Starting decoder with KV cache...');
  print('📏 [Decoder] Max length: $maxLength');

  final targetLangId = _tokenizer!.getLanguageTokenId(targetLanguage);
  final decoderTokens = <int>[2, targetLangId];
  final int encoderSeqLen = (encoderOutput!.value as List)[0].length;

  print('DEBUG [Decoder] Starting sequence: $decoderTokens');
  print('DEBUG [Decoder] Encoder sequence length: $encoderSeqLen');

  final fullEncoderMask = Int64List.fromList(
      encoding.attentionMask.map((e) => e.toInt()).toList());

  Map<String, OrtValue> decoderKVs = {};
  Map<String, OrtValue> encoderKVs = {};

  int inputTensorsCreated = 0;
  int inputTensorsReleased = 0;

  try {
    for (int step = 0; step < maxLength; step++) { // ✅ Use maxLength parameter
      final DateTime stepStart = DateTime.now();
      final bool isStep0 = step == 0;
      final session = isStep0 ? _decoderSession! : _decoderWithPastSession!;

      print('\n${"=" * 70}');
      print('DEBUG [Decoder] --- STEP $step ---');
      print('${"=" * 70}');

      final currentInputIds = isStep0 ? decoderTokens : [decoderTokens.last];
      print('DEBUG [Decoder] Input IDs: $currentInputIds');

      // Create input tensors
      final idTensor = OrtValueTensor.createTensorWithDataList(
          Int64List.fromList(currentInputIds), [1, currentInputIds.length]);
      inputTensorsCreated++;

      final maskTensor = OrtValueTensor.createTensorWithDataList(
          fullEncoderMask, [1, encoderSeqLen]);
      inputTensorsCreated++;

      final inputs = <String, OrtValue>{
        'input_ids': idTensor,
        'encoder_attention_mask': maskTensor,
      };

      if (isStep0) {
        inputs['encoder_hidden_states'] = encoderOutput;
        print('DEBUG [Decoder] Step 0: Using regular decoder');
      } else {
        inputs.addAll(decoderKVs);
        inputs.addAll(encoderKVs);
        print(
            'DEBUG [Decoder] Step $step: Using decoder_with_past (${decoderKVs.length} decoder + ${encoderKVs.length} encoder KVs)');
      }

      final runOptions = OrtRunOptions();
      final outputs = await session.runAsync(runOptions, inputs);

      if (outputs == null || outputs.isEmpty) {
        throw Exception('Step $step failed');
      }

      // Extract next token
      final logitsValue = outputs[0]!;
      final List logits = logitsValue.value as List;
      final List stepLogits = logits[0][currentInputIds.length - 1] as List;

      int nextToken = 0;
      double maxVal = double.negativeInfinity;
      for (int i = 0; i < stepLogits.length; i++) {
        double val = (stepLogits[i] as num).toDouble();
        if (val > maxVal) {
          maxVal = val;
          nextToken = i;
        }
      }

      logitsValue.release();

      final word = _tokenizer!.decode([nextToken]);
      final elapsed = DateTime.now().difference(stepStart).inMilliseconds;
      print(
          '✅ [Decoder] Step $step: Token $nextToken -> "$word" | Logit: ${maxVal.toStringAsFixed(3)} | ${elapsed}ms');

      // Manage KV Tensors
      if (isStep0) {
        final names = session.outputNames;
        int decoderCount = 0, encoderCount = 0;

        for (int i = 1; i < outputs.length; i++) {
          final pastName =
              names[i].replaceFirst('present', 'past_key_values');
          if (pastName.contains('.decoder.')) {
            decoderKVs[pastName] = outputs[i]!;
            decoderCount++;
          } else if (pastName.contains('.encoder.')) {
            encoderKVs[pastName] = outputs[i]!;
            encoderCount++;
          }
        }

        print(
            '💾 [Memory] Received $decoderCount decoder + $encoderCount encoder KVs from ONNX');
      } else {
        final oldCount = decoderKVs.length;
        decoderKVs.forEach((k, v) => v.release());
        decoderKVs.clear();

        final names = session.outputNames;
        for (int i = 1; i < outputs.length; i++) {
          final pastName =
              names[i].replaceFirst('present', 'past_key_values');
          decoderKVs[pastName] = outputs[i]!;
        }
        print(
            '💾 [Memory] Cycled ${decoderKVs.length} decoder KVs (released $oldCount old)');
      }

      // Release input tensors
      idTensor.release();
      maskTensor.release();
      runOptions.release();
      inputTensorsReleased += 2;

      // Add token FIRST, then check for EOS
      decoderTokens.add(nextToken);
      
      if (nextToken == 2) {
        print('⚠️  [Decoder] EOS token reached at step $step');
        break;
      }
    }
    
    // Only warn if we exited loop without hitting EOS
    if (decoderTokens.last != 2) {
      print('⚠️  [Decoder] Reached max_length=$maxLength without EOS - translation may be incomplete');
    }
    
  } finally {
    print('\n${"=" * 70}');
    print('💾 [Memory] FINAL CLEANUP');
    print('${"=" * 70}');

    final decoderCount = decoderKVs.length;
    decoderKVs.forEach((k, v) => v.release());
    print('💾 [Memory] Released $decoderCount final decoder KVs');

    final encoderCount = encoderKVs.length;
    encoderKVs.forEach((k, v) => v.release());
    print('💾 [Memory] Released $encoderCount final encoder KVs');

    print('\n💾 [Memory] INPUT TENSOR TRACKING:');
    print('   Created: $inputTensorsCreated input tensors');
    print('   Released: $inputTensorsReleased input tensors');
    if (inputTensorsCreated == inputTensorsReleased) {
      print('   ✅ Perfect - all input tensors released!');
    } else {
      print(
          '   ⚠️  Leak: ${inputTensorsCreated - inputTensorsReleased} input tensors not released!');
    }
    print('\n💾 [Memory] KV TENSORS:');
    print('   KVs are created by ONNX and released by us');
    print('   ✅ All KVs properly released in finally block');
    print('${"=" * 70}');
  }

  print('\n📊 [Decoder] Final sequence: $decoderTokens');
  return decoderTokens.sublist(2);
}

  int _argmax(List logits) {
    int maxIdx = 0;
    double maxVal = double.negativeInfinity;
    for (int i = 0; i < logits.length; i++) {
      final val = (logits[i] as num).toDouble();
      if (val > maxVal) {
        maxVal = val;
        maxIdx = i;
      }
    }
    return maxIdx;
  }

  void dispose() {
    _encoderSession?.release();
    _decoderSession?.release(); // ✅ Release both decoders
    _decoderWithPastSession?.release();
    OrtEnv.instance.release();
    _isInitialized = false;
  }

  bool get isInitialized => _isInitialized;
}
