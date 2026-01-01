// lib/services/backends/python_nllb_onnx_backend.dart
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import '../translation_backend.dart';
import '../model_paths.dart';

class PythonNLLBONNXBackend extends TranslationBackend {
  final String scriptPath;
  final String modelDir;
  final String tokenizerDir;
  final String alignerDir;  // ADD THIS for future word alignment
  String? _pythonCommand;
  Process? _serverProcess;
  StreamSubscription? _stdoutSubscription;
  final _responseController = StreamController<Map<String, dynamic>>.broadcast();
  bool _isServerReady = false;
  int _requestId = 0;
  
  PythonNLLBONNXBackend({
    this.scriptPath = 'scripts/translate_nllb_onnx.py',
    this.modelDir = ModelPaths.nllbModels,
    this.tokenizerDir = ModelPaths.nllbTokenizer,
    this.alignerDir = ModelPaths.awesomeAlignInt8,  // ADD THIS - default to INT8 (smaller, faster)
    super.verbose = false,
    super.debug = false,
  });
  
  @override
  String get name => 'Python NLLB ONNX';
  
  @override
  String get description => 'ONNX Runtime INT8 (via Python bridge)';
  
  // ... _findWorkingPython stays the same ...
  
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

Install with: python -m pip install optimum onnxruntime transformers
'''
        );
      }
    }
    
    // Check script
    final scriptFile = File(scriptPath);
    if (!scriptFile.existsSync()) {
      throw Exception('Script not found: $scriptPath');
    }
    logDebug('   ✓ Script: $scriptPath');
    
    // Check directories
    if (!Directory(modelDir).existsSync()) {
      throw Exception('Model directory not found: $modelDir');
    }
    logDebug('   ✓ Model dir: $modelDir');
    
    if (!Directory(tokenizerDir).existsSync()) {
      throw Exception('Tokenizer directory not found: $tokenizerDir');
    }
    logDebug('   ✓ Tokenizer dir: $tokenizerDir');
    
    // Check NLLB ONNX files
    for (final file in ModelPaths.nllbOnnxFiles) {
      if (!File(file).existsSync()) {
        throw Exception('Required ONNX model file not found: $file');
      }
    }
    logDebug('   ✓ All ONNX model files present (${ModelPaths.nllbOnnxFiles.length})');
    
    // Check NLLB config/tokenizer files
    for (final file in ModelPaths.nllbConfigFiles) {
      if (!File(file).existsSync()) {
        throw Exception('Required config/tokenizer file not found: $file');
      }
    }
    logDebug('   ✓ All config/tokenizer files present (${ModelPaths.nllbConfigFiles.length})');
    
    // Check aligner directory (optional but configured)
    if (Directory(alignerDir).existsSync()) {
      final alignerModel = '$alignerDir/model.onnx';
      if (File(alignerModel).existsSync()) {
        logDebug('   ✓ Word aligner available: $alignerDir');
      } else {
        logDebug('   ⚠ Aligner directory exists but model.onnx missing: $alignerDir');
      }
    } else {
      logDebug('   ℹ Word aligner not found: $alignerDir (optional)');
    }
    
    // Check optional Awesome Align variants
    if (ModelPaths.checkAwesomeAlignInt8()) {
      logDebug('   ✓ Awesome Align INT8 available');
    }
    
    if (ModelPaths.checkAwesomeAlignFp32()) {
      logDebug('   ✓ Awesome Align FP32 available');
    }
    
    // Start server
    await _startServer();
    
    logInfo('✅ Python NLLB ONNX backend initialized (using: $_pythonCommand)');
  }
  
  Future<void> _startServer() async {
    logDebug('🔍 [DEBUG] Starting Python translation server...');
    
    // 1. DECLARE AT THE VERY TOP to ensure scoping within the listener closures
    final readyCompleter = Completer<void>();

    // 2. Start the process
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

    // 3. Setup the Stdout listener (readyCompleter is now in scope)
    _stdoutSubscription = _serverProcess!.stdout
        .transform(utf8.decoder)
        .transform(LineSplitter())
        .listen((line) {
      logDebug('   [Python STDOUT] $line');
      try {
        final data = jsonDecode(line);
        
        // Immediate failure handling
        if (data['status'] == 'init_failed') {
          if (!readyCompleter.isCompleted) {
            readyCompleter.completeError(Exception(data['error']));
          }
        }
        
        _responseController.add(data);
      } catch (e) {
        // Log is likely just a text message from Python
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

    // 4. Setup the Ready Signal listener
    final subscription = _responseController.stream.listen((data) {
      if (data['status'] == 'ready') {
        _isServerReady = true;
        if (!readyCompleter.isCompleted) {
          readyCompleter.complete();
        }
      }
    });

    try {
      // 5. Wait for the signal
      await readyCompleter.future.timeout(
        Duration(seconds: 90),
        onTimeout: () {
          throw Exception('Python server failed to start within 90 seconds');
        },
      );
    } finally {
      subscription.cancel();
    }

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