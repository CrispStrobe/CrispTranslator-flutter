// lib/services/backends/python_nllb_onnx_backend.dart
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import '../translation_backend.dart';

class PythonNLLBONNXBackend extends TranslationBackend {
  final String scriptPath;
  final String modelDir;
  final String tokenizerDir;  // ADD THIS
  String? _pythonCommand;
  Process? _serverProcess;
  StreamSubscription? _stdoutSubscription;
  final _responseController = StreamController<Map<String, dynamic>>.broadcast();
  bool _isServerReady = false;
  int _requestId = 0;
  
  PythonNLLBONNXBackend({
    this.scriptPath = 'scripts/translate_nllb_onnx.py',
    this.modelDir = 'assets/onnx_models',
    this.tokenizerDir = 'assets/models',
    super.verbose = false,
    super.debug = false,
  });
  
  @override
  String get name => 'Python NLLB ONNX';
  
  @override
  String get description => 'ONNX Runtime INT8 (via Python bridge)';
  
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
  
  @override
  Future<void> initialize() async {
    final skipCheck = Platform.environment['SKIP_PYTHON_CHECK'] == '1';
    
    logDebug('🔍 [DEBUG] Detecting Python interpreter with required packages...');
    
    if (skipCheck) {
      _pythonCommand = 'python';
      logDebug('⚠️  Skipping Python verification (SKIP_PYTHON_CHECK=1)');
      logDebug('   Using: $_pythonCommand');
    } else {
      _pythonCommand = await _findWorkingPython();
      
      if (_pythonCommand == null) {
        throw Exception(
          '''
No Python installation found with required packages.

You have multiple Python installations. Please:
1. Find which Python has the packages:
   python --version && python -c "import optimum; print('OK')"
   python3 --version && python3 -c "import optimum; print('OK')"

2. Install packages to the correct Python:
   python -m pip install optimum onnxruntime transformers
   OR
   python3 -m pip install optimum onnxruntime transformers

Or skip the check (if you know packages are installed):
   SKIP_PYTHON_CHECK=1 dart run lib/services/translate_docx.dart ...
'''
        );
      }
    }
    
    // Check files
    final scriptFile = File(scriptPath);
    if (!scriptFile.existsSync()) {
      throw Exception('Script not found: $scriptPath');
    }
    logDebug('   ✓ Script: $scriptPath');
    
    final modelDirPath = Directory(modelDir);
    if (!modelDirPath.existsSync()) {
      throw Exception('Model directory not found: $modelDir');
    }
    logDebug('   ✓ Model dir: $modelDir');

    final tokenizerDirPath = Directory(tokenizerDir);
    if (!tokenizerDirPath.existsSync()) {
      throw Exception('Tokenizer directory not found: $tokenizerDir');
    }
    logDebug('   ✓ Tokenizer dir: $tokenizerDir');
    
    final requiredFiles = [
      '$modelDir/encoder_model.onnx',
      '$modelDir/decoder_model.onnx',
      '$modelDir/decoder_with_past_model.onnx',
      '$modelDir/config.json',
    ];
    
    for (final file in requiredFiles) {
      if (!File(file).existsSync()) {
        throw Exception('Required model file not found: $file');
      }
    }
    logDebug('   ✓ All model files present');
    
    final requiredTokenizerFiles = [
      '$tokenizerDir/tokenizer.json',
      '$tokenizerDir/tokenizer_config.json',
      '$tokenizerDir/sentencepiece.bpe.model',
    ];
    
    for (final file in requiredTokenizerFiles) {
      if (!File(file).existsSync()) {
        throw Exception('Required tokenizer file not found: $file');
      }
    }
    logDebug('   ✓ All tokenizer files present');
    
    // Start server process
    await _startServer();
    
    logInfo('✅ Python NLLB ONNX backend initialized (using: $_pythonCommand)');
  }
  
  Future<void> _startServer() async {
    logDebug('🔍 [DEBUG] Starting Python translation server...');
    
    _serverProcess = await Process.start(
      _pythonCommand!,
      [
        scriptPath, 
        '--server', 
        '--model-dir', modelDir,
        '--tokenizer-dir', tokenizerDir,  
      ],
      mode: ProcessStartMode.normal,
    );
    
    // Listen to stdout
    _stdoutSubscription = _serverProcess!.stdout
        .transform(utf8.decoder)
        .transform(LineSplitter())
        .listen((line) {
      try {
        final data = jsonDecode(line);
        _responseController.add(data);
      } catch (e) {
        logDebug('Failed to parse server response: $line');
      }
    });
    
    // Listen to stderr for warnings (but don't fail)
    _serverProcess!.stderr
        .transform(utf8.decoder)
        .transform(LineSplitter())
        .listen((line) {
      if (debug && line.trim().isNotEmpty) {
        logDebug('   [Python] $line');
      }
    });
    
    // Wait for ready signal
    final readyCompleter = Completer<void>();
    final subscription = _responseController.stream.listen((data) {
      if (data['status'] == 'ready') {
        _isServerReady = true;
        if (!readyCompleter.isCompleted) {
          readyCompleter.complete();
        }
      }
    });
    
    await readyCompleter.future.timeout(
      Duration(seconds: 30),
      onTimeout: () {
        throw Exception('Python server failed to start within 30 seconds');
      },
    );
    
    subscription.cancel();
    logDebug('   ✓ Python server ready');
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
    
    final isFirstTranslation = requestCount == 0;
    
    if (verbose && isFirstTranslation) {
      print('\n🔍 [VERBOSE] First translation:');
      print('   Source text: "$text"');
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
      
      logDebug('🔍 [DEBUG] Sending request #$reqId: "${text.substring(0, text.length > 30 ? 30 : text.length)}..."');
      
      // Send request
      _serverProcess!.stdin.writeln(jsonEncode(request));
      await _serverProcess!.stdin.flush();
      
      // Wait for response with matching request_id
      final responseCompleter = Completer<String>();
      late StreamSubscription subscription;
      
      subscription = _responseController.stream.listen((data) {
        if (data['request_id'] == reqId) {
          subscription.cancel();
          
          if (data.containsKey('error')) {
            logError('❌ Python error: ${data['error']}');
            responseCompleter.complete(text);
          } else {
            final translation = data['translation'] as String;
            
            if (verbose && isFirstTranslation) {
              print('   Translated: "$translation"\n');
            }
            
            responseCompleter.complete(translation);
          }
        }
      });
      
      final translation = await responseCompleter.future.timeout(
        Duration(seconds: 30),
        onTimeout: () {
          subscription.cancel();
          logError('❌ Translation timeout for request #$reqId');
          return text;
        },
      );
      
      logProgress();
      return translation;
      
    } catch (e, stack) {
      logError('❌ Translation failed: $e');
      if (debug) {
        logDebug('Stack trace:\n$stack');
      }
      return text;
    }
  }
  
  Future<void> shutdown() async {
    if (_serverProcess != null && _isServerReady) {
      try {
        // Send shutdown command
        _serverProcess!.stdin.writeln(jsonEncode({'command': 'shutdown'}));
        await _serverProcess!.stdin.flush();
        
        // Wait for process to exit
        await _serverProcess!.exitCode.timeout(Duration(seconds: 5));
      } catch (e) {
        // Force kill if graceful shutdown fails
        _serverProcess!.kill();
      }
      
      await _stdoutSubscription?.cancel();
      await _responseController.close();
      
      _serverProcess = null;
      _isServerReady = false;
    }
  }
}