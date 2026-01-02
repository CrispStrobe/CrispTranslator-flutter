// lib/services/backends/python_nllb_onnx_backend.dart
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import '../translation_backend.dart';
import '../model_paths.dart';
import '../docx_translator.dart';
import '../../models/app_settings.dart';

class PythonNLLBONNXBackend extends TranslationBackend {
  final String scriptPath;
  final String modelDir;
  final String tokenizerDir;
  final String alignerDir; 
  String? _pythonCommand;
  Process? _serverProcess;
  StreamSubscription? _stdoutSubscription;
  final _responseController = StreamController<Map<String, dynamic>>.broadcast();
  bool _isServerReady = false;
  int _requestId = 0;
  AppSettings settings = AppSettings();

  // Store the BERT alignments from the most recent translation request
  List<Alignment>? _lastAlignments;
  
  PythonNLLBONNXBackend({
    this.scriptPath = 'scripts/translate_nllb_onnx.py',
    this.modelDir = ModelPaths.nllbModels,
    this.tokenizerDir = ModelPaths.nllbTokenizer,
    this.alignerDir = ModelPaths.awesomeAlignInt8,  
    super.verbose = false,
    super.debug = false,
  });

  /// Getter to allow DocxTranslator to access BERT alignments after a translate() call
  List<Alignment>? get lastAlignments => _lastAlignments;
  
  @override
  String get name => 'Python NLLB ONNX';
  
  @override
  String get description => 'ONNX Runtime INT8 (Unified Translate + Align)';
  
  Future<String?> _findWorkingPython() async {
    final candidates = ['python', 'python3', 'python3.11', 'python3.10'];
    
    for (final cmd in candidates) {
      try {
        final versionResult = await Process.run(cmd, ['--version']);
        if (versionResult.exitCode != 0) continue;
        
        final version = versionResult.stdout.toString().trim();
        logDebug('   Testing: $cmd ($version)');
        
        final testScript = '''
try:
    from optimum.onnxruntime import ORTModelForSeq2SeqLM
    from transformers import AutoTokenizer
    print("OK")
except ImportError:
    print("MISSING")
''';
        
        final testResult = await Process.run(
          cmd,
          ['-c', testScript],
          stdoutEncoding: utf8,
          stderrEncoding: utf8,
        );
        
        if (testResult.exitCode == 0 && testResult.stdout.trim() == 'OK') {
          logDebug('   ✓ Found working Python: $cmd');
          return cmd;
        } else {
          logDebug('   ✗ $cmd missing required packages');
        }
      } catch (e) {
        logDebug('   ✗ $cmd not found');
        continue;
      }
    }
    
    return null;
  }

  Future<void> updateSettings(AppSettings newSettings) async {
    settings = newSettings;
    
    if (_isServerReady && _serverProcess != null) {
      final settingsUpdate = {
        'command': 'update_settings',
        'beam_size': settings.beamSize,
        'repetition_penalty': settings.repetitionPenalty,
        'no_repeat_ngram_size': settings.noRepeatNgramSize,
        'max_length': settings.maxLength,
      };
      
      _serverProcess!.stdin.writeln(jsonEncode(settingsUpdate));
      await _serverProcess!.stdin.flush();
    }
  }
  
  @override
  Future<void> initialize() async {
    print('🔍 [BACKEND] Starting Python backend initialization...');
    
    final skipCheck = Platform.environment['SKIP_PYTHON_CHECK'] == '1';
    
    print('🔍 [BACKEND] Detecting Python interpreter...');
    
    if (skipCheck) {
      _pythonCommand = 'python';
      print('⚠️  [BACKEND] Skipping Python verification (SKIP_PYTHON_CHECK=1)');
    } else {
      print('🔍 [BACKEND] Searching for Python with required packages...');
      _pythonCommand = await _findWorkingPython();
      
      if (_pythonCommand == null) {
        print('❌ [BACKEND] No suitable Python found');
        throw Exception(
          'No Python installation found with required packages.\n\n'
          'Install with: python -m pip install optimum onnxruntime transformers'
        );
      }
      print('✅ [BACKEND] Found Python: $_pythonCommand');
    }
    
    // Check script
    print('🔍 [BACKEND] Checking script at: $scriptPath');
    final scriptFile = File(scriptPath);
    if (!scriptFile.existsSync()) {
      print('❌ [BACKEND] Script not found: $scriptPath');
      throw Exception('Script not found: $scriptPath');
    }
    print('✅ [BACKEND] Script found');
    
    // Check directories
    print('🔍 [BACKEND] Checking model directory: $modelDir');
    if (!Directory(modelDir).existsSync()) {
      print('❌ [BACKEND] Model directory not found: $modelDir');
      throw Exception('Model directory not found: $modelDir');
    }
    print('✅ [BACKEND] Model directory exists');
    
    print('🔍 [BACKEND] Checking tokenizer directory: $tokenizerDir');
    if (!Directory(tokenizerDir).existsSync()) {
      print('❌ [BACKEND] Tokenizer directory not found: $tokenizerDir');
      throw Exception('Tokenizer directory not found: $tokenizerDir');
    }
    print('✅ [BACKEND] Tokenizer directory exists');
    
    print('🔍 [BACKEND] Starting Python server...');
    await _startServer();
    
    print('✅ [BACKEND] Python backend fully initialized!');
  }
  
  Future<void> _startServer() async {
    logDebug('🔍 [DEBUG] Starting Unified Python translation/alignment server...');
    
    final readyCompleter = Completer<void>();

    _serverProcess = await Process.start(
      _pythonCommand!,
      [
        scriptPath, 
        '--server', 
        '--model-dir', modelDir,
        '--tokenizer-dir', tokenizerDir,
        '--aligner-dir', alignerDir, // Pass the aligner path
        if (debug) '--verbose',
      ],
      mode: ProcessStartMode.normal,
    );

    _stdoutSubscription = _serverProcess!.stdout
        .transform(utf8.decoder)
        .transform(LineSplitter())
        .listen((line) {
      logDebug('   [Python STDOUT] $line');
      try {
        final data = jsonDecode(line);
        
        if (data['status'] == 'init_failed') {
          if (!readyCompleter.isCompleted) {
            readyCompleter.completeError(Exception(data['error']));
          }
        }
        
        _responseController.add(data);
      } catch (e) {
        // Line is not JSON, likely just a status message or warning
      }
    });

    _serverProcess!.stderr
        .transform(utf8.decoder)
        .transform(LineSplitter())
        .listen((line) {
      if (line.trim().isNotEmpty) {
        logDebug('   [Python] $line');
      }
    });

    final subscription = _responseController.stream.listen((data) {
      if (data['status'] == 'ready') {
        _isServerReady = true;
        if (!readyCompleter.isCompleted) {
          readyCompleter.complete();
        }
      }
    });

    try {
      await readyCompleter.future.timeout(
        Duration(seconds: 90),
        onTimeout: () {
          throw Exception('Python server failed to start within 90 seconds');
        },
      );
    } finally {
      subscription.cancel();
    }

    logDebug('   ✓ Unified server ready');
  }
  
  @override
  Future<String> translate(
    String text,
    String targetLang,
    String sourceLang,
  ) async {
    if (text.trim().isEmpty) return text;
    
    if (!_isServerReady || _serverProcess == null) {
      throw StateError('Python server not ready');
    }

    // Reset alignments for this new segment to prevent stale data usage
    _lastAlignments = null;
    
    final isFirstTranslation = requestCount == 0;
    if (verbose && isFirstTranslation) {
      print('\n🔍 [VERBOSE] Testing first segment with BERT alignment:');
      print('   Source: "$text"');
      print('   $sourceLang → $targetLang');
    }
    
    try {
      final reqId = _requestId++;
      
      final request = {
        'text': text,
        'source': sourceLang,
        'target': targetLang,
        'request_id': reqId,
      };
      
      logDebug('🔍 [DEBUG] Sending Unified Request #$reqId: "${text.substring(0, text.length > 30 ? 30 : text.length)}..."');
      
      _serverProcess!.stdin.writeln(jsonEncode(request));
      await _serverProcess!.stdin.flush();
      
      final responseCompleter = Completer<Map<String, dynamic>>();
      late StreamSubscription subscription;
      
      subscription = _responseController.stream.listen((data) {
        if (data['request_id'] == reqId) {
          subscription.cancel();
          responseCompleter.complete(data);
        }
      });
      
      final data = await responseCompleter.future.timeout(
        Duration(seconds: 45),
        onTimeout: () {
          subscription.cancel();
          logError('❌ Unified task timeout for request #$reqId');
          return {'translation': text, 'alignments': []};
        },
      );
      
      if (data.containsKey('error')) {
        logError('❌ Python error: ${data['error']}');
        return text;
      }

      // 1. Capture the translation
      final translation = data['translation'] as String;

      // 2. Capture and parse the BERT alignments
      final List<dynamic>? alignJson = data['alignments'];
      if (alignJson != null && alignJson.isNotEmpty) {
        _lastAlignments = alignJson.map((a) {
          return Alignment(
            (a['s'] as num).toInt(), 
            (a['t'] as num).toInt()
          );
        }).toList();
        
        if (debug) {
          logDebug('   [DEBUG] Received ${_lastAlignments!.length} BERT alignment links');
        }
      }

      if (verbose && isFirstTranslation) {
        print('   Translated: "$translation"');
        print('   Links: $_lastAlignments\n');
      }
      
      logProgress();
      return translation;
      
    } catch (e, stack) {
      logError('❌ Unified translation/alignment failed: $e');
      if (debug) logDebug('Stack trace:\n$stack');
      return text;
    }
  }
  
  Future<void> shutdown() async {
    if (_serverProcess != null && _isServerReady) {
      try {
        _serverProcess!.stdin.writeln(jsonEncode({'command': 'shutdown'}));
        await _serverProcess!.stdin.flush();
        await _serverProcess!.exitCode.timeout(Duration(seconds: 5));
      } catch (e) {
        _serverProcess!.kill();
      }
      
      await _stdoutSubscription?.cancel();
      await _responseController.close();
      
      _serverProcess = null;
      _isServerReady = false;
    }
  }
}