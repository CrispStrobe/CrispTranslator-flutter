// lib/services/translate_docx.dart
import 'dart:io';
import 'dart:typed_data';
import 'package:args/args.dart';
import 'docx_translator.dart';
import 'translation_backend.dart';
import 'backend_factory.dart';
import 'backends/python_nllb_onnx_backend.dart'; 

void main(List<String> args) async {
  final parser = ArgParser()
    ..addFlag('help', abbr: 'h', help: 'Show help message', negatable: false)
    ..addFlag('verbose', abbr: 'v', help: 'Verbose output (shows first translation)', negatable: false)
    ..addFlag('debug', abbr: 'd', help: 'Debug mode (maximum verbosity)', negatable: false)
    ..addOption('backend', abbr: 'b', help: 'Translation backend', defaultsTo: 'onnx')
    ..addFlag('list-backends', help: 'List available backends', negatable: false)
    ..addFlag('test', abbr: 't', help: 'Test backend connection', negatable: false);
  
  ArgResults parsed;
  try {
    parsed = parser.parse(args);
  } catch (e) {
    print('❌ Error: $e\n');
    _printUsage(parser);
    exit(1);
  }
  
  if (parsed['help'] as bool) {
    _printUsage(parser);
    exit(0);
  }
  
  if (parsed['list-backends'] as bool) {
    print(BackendFactory.getAvailableBackends());
    exit(0);
  }
  
  final verbose = parsed['verbose'] as bool;
  final debug = parsed['debug'] as bool;
  final backendName = parsed['backend'] as String;
  final testOnly = parsed['test'] as bool;
  final positional = parsed.rest;
  
  print('╔════════════════════════════════════════════════════════════════╗');
  print('║        DOCX TRANSLATOR - CLI Tool                              ║');
  print('║        Multi-Backend Translation System                        ║');
  print('╚════════════════════════════════════════════════════════════════╝\n');
  
  if (debug) {
    print('🐛 Debug mode enabled (maximum verbosity)\n');
  }
  
  // Create backend
  TranslationBackend backend;
  try {
    final backendType = BackendFactory.fromString(backendName);
    backend = BackendFactory.create(backendType, verbose: verbose, debug: debug);
    print('🔧 Backend: ${backend.name} - ${backend.description}\n');
  } catch (e) {
    print('❌ Invalid backend: $backendName');
    print(BackendFactory.getAvailableBackends());
    exit(1);
  }
  
  // Initialize backend
  try {
    print('⚙️  Initializing backend...');
    await backend.initialize();
  } catch (e, stack) {
    print('\n❌ Backend initialization failed: $e');
    if (debug) {
      print('\nStack trace:');
      print(stack);
    }
    print('\n💡 Troubleshooting tips:');
    if (backendName.toLowerCase().contains('onnx')) {
      print('   • Make sure Python 3 is installed: python3 --version');
      print('   • Install required packages: pip install optimum onnxruntime transformers');
      print('   • Check that ONNX models exist in: assets/onnx_models/');
      print('   • Verify script exists: scripts/translate_nllb_onnx.py');
      print('   • Current directory: ${Directory.current.path}');
    } else if (backendName.toLowerCase().contains('mymemory')) {
      print('   • Check internet connection');
      print('   • Try: curl https://api.mymemory.translated.net');
    }
    exit(1);
  }
  
  // Test mode
  if (testOnly) {
    print('═' * 68);
    print('🧪 BACKEND TEST MODE');
    print('═' * 68);
    print('');
    
    try {
      final works = await backend.test();
      
      print('');
      if (works) {
        print('╔════════════════════════════════════════════════════════════════╗');
        print('║  ✅ ALL TESTS PASSED - Backend is ready for production!        ║');
        print('╚════════════════════════════════════════════════════════════════╝');
        
        // Cleanup
        if (backend is PythonNLLBONNXBackend) {
          await (backend as PythonNLLBONNXBackend).shutdown();
        }
        
        exit(0);
      } else {
        print('╔════════════════════════════════════════════════════════════════╗');
        print('║  ❌ SOME TESTS FAILED - Please check the logs above            ║');
        print('╚════════════════════════════════════════════════════════════════╝');
        
        // Cleanup
        if (backend is PythonNLLBONNXBackend) {
          await (backend as PythonNLLBONNXBackend).shutdown();
        }
        
        exit(1);
      }
    } catch (e, stack) {
      print('\n❌ Backend error: $e');
      if (debug) {
        print('\nStack trace:');
        print(stack);
      }
      
      // Cleanup
      if (backend is PythonNLLBONNXBackend) {
        await (backend as PythonNLLBONNXBackend).shutdown();
      }
      
      exit(1);
    }
  }
  
  // Validate arguments for translation
  if (positional.length < 3) {
    print('❌ Error: Missing required arguments\n');
    _printUsage(parser);
    exit(1);
  }
  
  String inputPath = positional[0];
  String sourceLang = positional[1];
  String targetLang = positional[2];
  String? outputPath = positional.length > 3 ? positional[3] : null;
  
  // Expand ~
  if (inputPath.startsWith('~')) {
    final home = Platform.environment['HOME'] ?? Platform.environment['USERPROFILE'];
    if (home != null) inputPath = inputPath.replaceFirst('~', home);
  }
  
  if (outputPath == null) {
    final inputFile = File(inputPath);
    final dir = inputFile.parent.path;
    final name = inputFile.uri.pathSegments.last.replaceAll('.docx', '');
    outputPath = '$dir/${name}_${targetLang.toLowerCase()}.docx';
  } else if (outputPath.startsWith('~')) {
    final home = Platform.environment['HOME'] ?? Platform.environment['USERPROFILE'];
    if (home != null) outputPath = outputPath.replaceFirst('~', home);
  }
  
  print('📄 Input:   $inputPath');
  print('📄 Output:  $outputPath');
  print('🌍 Translation: $sourceLang → $targetLang');
  if (verbose) print('🔍 Verbose mode enabled');
  print('');
  
  final inputFile = File(inputPath);
  if (!inputFile.existsSync()) {
    print('❌ Error: Input file not found: $inputPath');
    exit(1);
  }
  
  try {
    // Test connection
    print('🔌 Testing connection...');
    final testResult = await backend.translate('Hello', targetLang, sourceLang);
    print('✅ Connection OK (test: "$testResult")\n');
    
    // Read file
    print('📖 Reading input file...');
    final Uint8List inputBytes = await inputFile.readAsBytes();
    print('✅ Read ${(inputBytes.length / 1024).toStringAsFixed(1)} KB');
    
    // Create translator
    final translator = DocxTranslator(
      translationService: backend,
      aligner: HeuristicAligner(),
      verbose: verbose || debug,
    );
    
    // Translate
    print('\n🔄 Starting translation...\n');
    final startTime = DateTime.now();
    
    final Uint8List outputBytes = await translator.translateDocument(
      docxBytes: inputBytes,
      targetLanguage: targetLang,
      sourceLanguage: sourceLang,
    );
    
    final duration = DateTime.now().difference(startTime);
    
    // Save
    print('\n💾 Writing output file...');
    await File(outputPath).writeAsBytes(outputBytes);
    print('✅ Saved to: $outputPath');
    
    // Statistics
    print('\n📊 Statistics:');
    print('   Input:     ${(inputBytes.length / 1024).toStringAsFixed(1)} KB');
    print('   Output:    ${(outputBytes.length / 1024).toStringAsFixed(1)} KB');
    print('   Time:      ${_formatDuration(duration)}');
    print('   Segments:  ${backend.requestCount}');
    if (duration.inSeconds > 0) {
      print('   Speed:     ${(backend.requestCount / duration.inSeconds).toStringAsFixed(1)} segments/sec');
    }
    
    print('\n╔════════════════════════════════════════════════════════════════╗');
    print('║  ✅ SUCCESS! Document translated successfully.                  ║');
    print('╚════════════════════════════════════════════════════════════════╝');
  } catch (e, stackTrace) {
    print('\n❌ Error: $e');
    if (verbose || debug) {
      print('\nStack trace:');
      print(stackTrace);
    }
    
    // Cleanup
    if (backend is PythonNLLBONNXBackend) {
      await (backend as PythonNLLBONNXBackend).shutdown();
    }
    
    exit(1);
  } finally {
    // Cleanup
    if (backend is PythonNLLBONNXBackend) {
      await (backend as PythonNLLBONNXBackend).shutdown();
    }
  }
}

void _printUsage(ArgParser parser) {
  print('''
Usage: dart run lib/services/translate_docx.dart [options] <input.docx> <source> <target> [output.docx]

Options:
${parser.usage}

Examples:
  # Test backend
  dart run lib/services/translate_docx.dart --test -b onnx
  dart run lib/services/translate_docx.dart --test --debug -b onnx

  # Translate with default backend
  dart run lib/services/translate_docx.dart input.docx German English

  # Verbose mode (shows first translation)
  dart run lib/services/translate_docx.dart -v input.docx German English

  # Debug mode (maximum verbosity)
  dart run lib/services/translate_docx.dart -d input.docx Spanish French

  # Different backend
  dart run lib/services/translate_docx.dart -b mymemory input.docx German English
''');
}

String _formatDuration(Duration d) {
  if (d.inSeconds < 60) {
    return '${d.inSeconds}s';
  } else {
    final min = d.inMinutes;
    final sec = d.inSeconds % 60;
    return '${min}m ${sec}s';
  }
}