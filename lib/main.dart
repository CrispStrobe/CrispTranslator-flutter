// lib/main.dart
import 'package:flutter/material.dart';
import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
import 'services/onnx_translation_service.dart';
import 'services/nllb_tokenizer.dart';
import 'services/model_downloader.dart';
import 'services/backends/python_nllb_onnx_backend.dart';

import 'services/docx_translator.dart' as docx;
import 'models/app_settings.dart';
import 'pages/settings_page.dart';
import 'widgets/alignment_visualizer.dart';
import 'dart:io';
import 'services/docx_translation_service.dart' as python_docx;
import 'services/flutter_docx_translation_service.dart' as flutter_docx;

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'CrispTranslator',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
        useMaterial3: true,
      ),
      debugShowCheckedModeBanner: false,
      home: const TranslatorPage(),
    );
  }
}

class TranslatorPage extends StatefulWidget {
  const TranslatorPage({super.key});

  @override
  State<TranslatorPage> createState() => _TranslatorPageState();
}

class _TranslatorPageState extends State<TranslatorPage> with SingleTickerProviderStateMixin {
  
  late TabController _tabController;
  final _textController = TextEditingController();
  final _service = ONNXTranslationService();
  final _downloader = ModelDownloader();

  bool _useFlutterDocx = true; // TRUE = Flutter ONNX, FALSE = Python backend

  bool _isCheckingModels = true;
  bool _needsDownload = false;
  bool _isDownloading = false;
  bool _isInitializing = false;
  bool _isTranslating = false;

  String? _translation;
  String? _error;
  String _downloadStatus = '';
  Map<String, double> _downloadProgress = {};

  String _sourceLanguage = 'English';
  String _targetLanguage = 'German';

  List<String> _languages = [
    'English',
    'German',
    'French',
    'Spanish',
    'Italian',
    'Portuguese',
    'Japanese',
    'Chinese',
    'Korean',
    'Arabic',
    'Hindi',
  ];

  // ========== NEW FEATURES ==========
  PythonNLLBONNXBackend? _docxBackend;
  AppSettings _settings = AppSettings.balanced();
  
  bool _isProcessingDocx = false;
  String? _docxFileName;
  Uint8List? _docxBytes;
  Uint8List? _translatedDocxBytes;
  List<_SegmentTranslation> _segmentTranslations = [];
  Object? _docxProgress;
  List<docx.Alignment>? _lastAlignments;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _checkModels();
  }

  // ========== ORIGINAL METHODS (UNCHANGED) ==========
  
  void _populateLanguageList() {
    setState(() {
      _languages = NLLBTokenizer.languageTokens.keys.toList();
      _languages.sort();
    });
  }

  Future<void> _checkModels() async {
    print('🔍 [MAIN] Starting model check...');
    setState(() {
      _isCheckingModels = true;
      _error = null;
    });

    try {
      print('🔍 [MAIN] Step 1: Checking if models are bundled in assets...');
      final inAssets = await _downloader.areModelsInAssets();
      print('🔍 [MAIN] Assets check result: $inAssets');

      if (inAssets) {
        print('✅ [MAIN] Models found in assets! Will use bundled models.');
        if (mounted) {
          print('🔧 [MAIN] Initializing service with assets...');
          _initializeService();
        }
        return;
      }

      print('⚠️  [MAIN] Models not in assets. Checking downloaded models...');
      final modelsExist = await _downloader.areModelsDownloaded();
      print('🔍 [MAIN] Downloaded models check result: $modelsExist');

      if (mounted) {
        if (modelsExist) {
          print('✅ [MAIN] Downloaded models found! Will use downloaded models.');
          _initializeServiceWithDownloadedModels();
        } else {
          print('❌ [MAIN] No models found. Will prompt for download.');
          setState(() {
            _isCheckingModels = false;
            _needsDownload = true;
          });
        }
      }
    } catch (e, stack) {
      print('❌ [MAIN] Error during model check: $e');
      print('Stack trace: $stack');
      if (mounted) {
        setState(() {
          _isCheckingModels = false;
          _error = 'Failed to check models: $e';
        });
      }
    }
  }

  Future<void> _initializeServiceWithDownloadedModels() async {
    print('🔧 [MAIN] Initializing with downloaded models...');
    setState(() {
      _isInitializing = true;
      _isCheckingModels = false;
      _error = null;
    });

    try {
      final modelsPath = await _downloader.getModelsDirectory();
      print('📁 [MAIN] Models directory: $modelsPath');
      await _service.initialize(modelsPath: modelsPath);

      print('✅ [MAIN] Service initialized successfully with downloaded models!');
      if (mounted) {
        _populateLanguageList();
        setState(() {
          _isInitializing = false;
        });
      }
    } catch (e, stack) {
      print('❌ [MAIN] Initialization failed: $e');
      print('Stack trace: $stack');
      if (mounted) {
        setState(() {
          _isInitializing = false;
          _error = 'Initialization failed: $e';
        });
      }
    }
  }

  Future<void> _downloadModels() async {
    print('📥 [MAIN] Starting model download...');
    setState(() {
      _isDownloading = true;
      _downloadStatus = 'Starting download...';
      _downloadProgress = {};
      _error = null;
    });

    try {
      await _downloader.downloadModels(
        onProgress: (fileName, progress) {
          if (mounted) {
            setState(() {
              _downloadProgress[fileName] = progress;
            });
          }
        },
        onStatusUpdate: (status) {
          print('📥 [DOWNLOAD] $status');
          if (mounted) {
            setState(() {
              _downloadStatus = status;
            });
          }
        },
      );

      print('✅ [MAIN] Download complete!');
      if (mounted) {
        setState(() {
          _isDownloading = false;
          _needsDownload = false;
        });
        _initializeServiceWithDownloadedModels();
      }
    } catch (e, stack) {
      print('❌ [MAIN] Download failed: $e');
      print('Stack trace: $stack');
      if (mounted) {
        setState(() {
          _isDownloading = false;
          _error = 'Download failed: $e';
        });
      }
    }
  }

  Future<void> _initializeService() async {
    print('🔧 [MAIN] Initializing with assets...');
    setState(() {
      _isInitializing = true;
      _isCheckingModels = false;
      _error = null;
    });

    try {
      print('📦 [MAIN] Calling service.initialize() with no modelsPath (will use assets)...');
      await _service.initialize();

      print('✅ [MAIN] Service initialized successfully with assets!');
      if (mounted) {
        _populateLanguageList();
        setState(() {
          _isInitializing = false;
        });
      }
    } catch (e, stack) {
      print('❌ [MAIN] Initialization failed: $e');
      print('Stack trace: $stack');
      if (mounted) {
        setState(() {
          _isInitializing = false;
          _error = 'Initialization failed: $e';
        });
      }
    }
  }

  Future<void> _translate() async {
    if (_textController.text.trim().isEmpty) return;

    setState(() {
      _isTranslating = true;
      _translation = null;
      _error = null;
    });

    try {
      final result = await _service.translate(
        _textController.text,
        _targetLanguage,
        sourceLanguage: _sourceLanguage,
        beamSize: _settings.useBeamSearch ? _settings.beamSize : 1,
        maxLength: _settings.maxLength,
      );

      if (mounted) {
        setState(() {
          _translation = result;
          _isTranslating = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Translation failed: $e';
          _isTranslating = false;
        });
      }
    }
  }

  // ========== METHODS FOR DOCX ==========

  Future<void> _openSettings() async {
    final newSettings = await Navigator.push<AppSettings>(
      context,
      MaterialPageRoute(
        builder: (context) => SettingsPage(
          settings: _settings,
          onSettingsChanged: (settings) => _settings = settings,
        ),
      ),
    );
    
    if (newSettings != null) {
      setState(() => _settings = newSettings);
      if (_docxBackend != null) {
        await _docxBackend!.updateSettings(_settings);
      }
    }
  }

  Future<void> _pickDocx() async {
    print('📁 [DOCX] File picker button pressed');
    
    try {
      print('📁 [DOCX] Opening file picker...');
      
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['docx'],
        withData: true, // Force reading bytes
      );

      print('📁 [DOCX] File picker result: ${result != null ? "Got result" : "Cancelled"}');

      if (result != null) {
        final file = result.files.single;
        print('📁 [DOCX] Selected file: ${file.name}');
        print('📁 [DOCX] File size: ${file.size} bytes');
        print('📁 [DOCX] Has bytes: ${file.bytes != null}');
        print('📁 [DOCX] Has path: ${file.path != null}');
        
        Uint8List? bytes = file.bytes;
        
        // For desktop platforms, read from path if bytes not available
        if (bytes == null && file.path != null) {
          print('📁 [DOCX] Reading file from path: ${file.path}');
          try {
            bytes = await File(file.path!).readAsBytes();
            print('📁 [DOCX] Successfully read ${bytes.length} bytes from path');
          } catch (e) {
            print('❌ [DOCX] Failed to read file from path: $e');
            setState(() => _error = 'Failed to read file: $e');
            return;
          }
        }
        
        if (bytes != null) {
          print('✅ [DOCX] File loaded: ${file.name}, ${bytes.length} bytes');
          setState(() {
            _docxFileName = file.name;
            _docxBytes = bytes;
            _translatedDocxBytes = null;
            _segmentTranslations = [];
            _error = null;
          });
        } else {
          print('❌ [DOCX] No bytes available for file');
          setState(() => _error = 'Could not read file data');
        }
      } else {
        print('ℹ️  [DOCX] File picker cancelled by user');
      }
    } catch (e, stack) {
      print('❌ [DOCX] File picker error: $e');
      print('Stack trace: $stack');
      setState(() => _error = 'Failed to load file: $e');
    }
  }

  Future<void> _translateDocx() async {
    if (_docxBytes == null) return;

    setState(() {
      _isProcessingDocx = true;
      _translatedDocxBytes = null;
      _segmentTranslations = [];
      _error = null;
    });

    try {
      if (_useFlutterDocx) {
        // ========== FLUTTER NATIVE (ONNX BERT ALIGNMENT) ==========
        print('🔧 [MAIN] Using Flutter-native DOCX translation with ONNX alignment...');
        
        final service = flutter_docx.FlutterDocxTranslationService(
          onnxService: _service,
          verbose: _settings.verboseLogging,
        );

        final outputBytes = await service.translateDocx(
          inputBytes: _docxBytes!,
          sourceLang: _sourceLanguage,
          targetLang: _targetLanguage,
          onProgress: (progress) {
            setState(() => _docxProgress = progress as flutter_docx.DocxTranslationProgress);
          },
          onSegmentTranslated: (source, target, alignments) { // NOW RECEIVES ALIGNMENTS
            if (_settings.showAlignments) {
              setState(() {
                _segmentTranslations.add(_SegmentTranslation(
                  source: source,
                  target: target,
                  alignments: alignments, // Use ONNX alignments
                ));
              });
            }
          },
        );

        setState(() {
          _translatedDocxBytes = outputBytes;
          _isProcessingDocx = false;
        });
        
      } else {
        // ========== PYTHON BACKEND (WITH BERT ALIGNMENT) ==========
        print('🔧 [MAIN] Using Python backend for DOCX translation...');
        
        if (_docxBackend == null) {
          print('🔧 [BACKEND] Initializing Python backend...');
          _docxBackend = PythonNLLBONNXBackend(
            verbose: _settings.verboseLogging,
            debug: _settings.verboseLogging,
          );
          
          try {
            await _docxBackend!.initialize();
            await _docxBackend!.updateSettings(_settings);
            print('✅ [BACKEND] Python backend initialized successfully');
          } catch (e) {
            setState(() {
              _isProcessingDocx = false;
              _error = 'Python backend initialization failed.\n\n'
                      'DOCX translation requires Python 3.10+ with:\n'
                      '• pip install optimum onnxruntime transformers\n\n'
                      'Error: $e\n\n'
                      'Tip: Switch to "Flutter Mode" for no Python dependency!';
            });
            _docxBackend = null;
            return;
          }
        }

        final service = python_docx.DocxTranslationService(
          backend: _docxBackend!,
          verbose: _settings.verboseLogging,
        );

        final outputBytes = await service.translateDocx(
          inputBytes: _docxBytes!,
          sourceLang: _sourceLanguage,
          targetLang: _targetLanguage,
          onProgress: (progress) {
            setState(() => _docxProgress = progress as python_docx.DocxTranslationProgress);
          },
          onSegmentTranslated: (source, target, alignments) {
            setState(() {
              _segmentTranslations.add(_SegmentTranslation(
                source: source,
                target: target,
                alignments: alignments,
              ));
            });
          },
        );

        setState(() {
          _translatedDocxBytes = outputBytes;
          _isProcessingDocx = false;
        });
      }
    } catch (e, stack) {
      print('❌ [MAIN] DOCX translation failed: $e');
      print('Stack trace: $stack');
      setState(() {
        _error = 'DOCX translation failed: $e';
        _isProcessingDocx = false;
      });
    }
  }

  Future<void> _downloadTranslatedDocx() async {
    if (_translatedDocxBytes == null || _docxFileName == null) return;

    try {
      final fileName = _docxFileName!.replaceAll('.docx', '_${_targetLanguage.toLowerCase()}.docx');
      
      final outputPath = await FilePicker.platform.saveFile(
        dialogTitle: 'Save translated document',
        fileName: fileName,
        type: FileType.custom,
        allowedExtensions: ['docx'],
      );

      if (outputPath != null) {
        final file = File(outputPath);
        await file.writeAsBytes(_translatedDocxBytes!);
        print('✅ [SAVE] File written to: $outputPath');

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Saved to: ${file.path.split('/').last}'),
              duration: const Duration(seconds: 5),
              action: SnackBarAction(
                label: 'Open',
                onPressed: () async {
                  // For macOS: Opens the folder and selects the file
                  if (Platform.isMacOS) {
                    await Process.run('open', ['-R', outputPath]);
                  } else if (Platform.isWindows) {
                    await Process.run('explorer.exe', ['/select,', outputPath]);
                  }
                },
              ),
            ),
          );
        }
      }
    } catch (e) {
      print('❌ [SAVE] Error: $e');
      setState(() => _error = 'Failed to save file: $e');
    }
  }

  // ========== UI METHODS ==========

  void _showLanguagePicker(bool isSource) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        List<String> filteredLanguages = List.from(_languages);
        return StatefulBuilder(
          builder: (context, setModalState) {
            return Container(
              padding: const EdgeInsets.all(16),
              height: MediaQuery.of(context).size.height * 0.75,
              child: Column(
                children: [
                  Container(
                    width: 40,
                    height: 4,
                    margin: const EdgeInsets.only(bottom: 20),
                    decoration: BoxDecoration(
                      color: Colors.grey[300],
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  Text(
                    isSource ? 'Translate From' : 'Translate To',
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    decoration: InputDecoration(
                      hintText: 'Search languages...',
                      prefixIcon: const Icon(Icons.search),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      filled: true,
                      fillColor: Colors.grey[100],
                    ),
                    onChanged: (value) {
                      setModalState(() {
                        filteredLanguages = _languages
                            .where((l) => l.toLowerCase().contains(value.toLowerCase()))
                            .toList();
                      });
                    },
                  ),
                  const SizedBox(height: 16),
                  Expanded(
                    child: ListView.builder(
                      itemCount: filteredLanguages.length,
                      itemBuilder: (context, index) {
                        final lang = filteredLanguages[index];
                        final isSelected = isSource
                            ? lang == _sourceLanguage
                            : lang == _targetLanguage;

                        return ListTile(
                          title: Text(lang),
                          trailing: isSelected
                              ? const Icon(Icons.check, color: Colors.blue)
                              : null,
                          selected: isSelected,
                          onTap: () {
                            setState(() {
                              if (isSource) {
                                _sourceLanguage = lang;
                              } else {
                                _targetLanguage = lang;
                              }
                            });
                            Navigator.pop(context);
                          },
                        );
                      },
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildLanguageButton({
    required String label,
    required String value,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey[600],
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                Expanded(
                  child: Text(
                    value,
                    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const Icon(Icons.arrow_drop_down, size: 20),
              ],
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Model checking screen (UNCHANGED)
    if (_isCheckingModels) {
      return Scaffold(
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: const [
              CircularProgressIndicator(),
              SizedBox(height: 20),
              Text('Checking models...', style: TextStyle(fontSize: 16)),
            ],
          ),
        ),
      );
    }

    // Download screen (UNCHANGED)
    if (_needsDownload) {
      return Scaffold(
        appBar: AppBar(title: const Text('Model Download Required')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(32.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.cloud_download, size: 80, color: Colors.blue),
                const SizedBox(height: 24),
                const Text('Translation Models Required',
                  style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
                const SizedBox(height: 16),
                const Text('This app requires ~1.9 GB of AI models to function offline.',
                  textAlign: TextAlign.center, style: TextStyle(fontSize: 16)),
                const SizedBox(height: 8),
                Text('Models will be downloaded from HuggingFace.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 14, color: Colors.grey[600])),
                const SizedBox(height: 32),
                if (!_isDownloading) ...[
                  ElevatedButton.icon(
                    onPressed: _downloadModels,
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16)),
                    icon: const Icon(Icons.download),
                    label: const Text('Download Models', style: TextStyle(fontSize: 16)),
                  ),
                ] else ...[
                  const SizedBox(
                    width: 60, height: 60,
                    child: CircularProgressIndicator(strokeWidth: 4)),
                  const SizedBox(height: 24),
                  Text(_downloadStatus, textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 14)),
                  const SizedBox(height: 16),
                  ..._downloadProgress.entries.map((entry) {
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(entry.key, style: const TextStyle(fontSize: 12)),
                          const SizedBox(height: 4),
                          LinearProgressIndicator(value: entry.value, minHeight: 6),
                        ],
                      ),
                    );
                  }).toList(),
                ],
                if (_error != null) ...[
                  const SizedBox(height: 24),
                  Text(_error!, style: const TextStyle(color: Colors.red),
                    textAlign: TextAlign.center),
                  const SizedBox(height: 16),
                  TextButton(
                    onPressed: () => setState(() => _error = null),
                    child: const Text('Retry')),
                ],
              ],
            ),
          ),
        ),
      );
    }

    // Initializing screen (UNCHANGED)
    if (_isInitializing) {
      return Scaffold(
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const CircularProgressIndicator(),
              const SizedBox(height: 20),
              const Text('Initializing translation engine...',
                style: TextStyle(fontSize: 16)),
              const SizedBox(height: 10),
              Text('Loading ONNX models',
                style: TextStyle(fontSize: 14, color: Colors.grey[600])),
            ],
          ),
        ),
      );
    }

    // Main translator UI with TABS
    return Scaffold(
      appBar: AppBar(
        title: const Text('CrispTranslator'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: _openSettings,
          ),
          IconButton(
            icon: const Icon(Icons.info_outline),
            onPressed: () => _showAboutDialog(context),
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(icon: Icon(Icons.translate), text: 'Text'),
            Tab(icon: Icon(Icons.description), text: 'Documents'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildTextTranslationTab(),
          _buildDocxTranslationTab(),
        ],
      ),
    );
  }

  Widget _buildTextTranslationTab() {
    return SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Language selectors
            Card(
              elevation: 2,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                child: Row(
                  children: [
                    Expanded(
                      child: _buildLanguageButton(
                        label: 'From',
                        value: _sourceLanguage,
                        onTap: () => _showLanguagePicker(true),
                      ),
                    ),
                    Container(
                      margin: const EdgeInsets.symmetric(horizontal: 8),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.primaryContainer,
                        shape: BoxShape.circle,
                      ),
                      child: IconButton(
                        icon: const Icon(Icons.swap_horiz, size: 20),
                        onPressed: () {
                          setState(() {
                            final temp = _sourceLanguage;
                            _sourceLanguage = _targetLanguage;
                            _targetLanguage = temp;
                          });
                        },
                      ),
                    ),
                    Expanded(
                      child: _buildLanguageButton(
                        label: 'To',
                        value: _targetLanguage,
                        onTap: () => _showLanguagePicker(false),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 16),

            // Input text
            Card(
              elevation: 2,
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Input ($_sourceLanguage)',
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _textController,
                      maxLines: 6,
                      decoration: const InputDecoration(
                        hintText: 'Enter text to translate...',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 16),

            // Translate button
            ElevatedButton.icon(
              onPressed: _isTranslating ? null : _translate,
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.all(16),
                textStyle: const TextStyle(fontSize: 16),
              ),
              icon: _isTranslating
                  ? const SizedBox(
                      width: 20, height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(Colors.white)))
                  : const Icon(Icons.translate),
              label: Text(_isTranslating ? 'Translating...' : 'Translate'),
            ),

            // Translation result
            if (_translation != null) ...[
              const SizedBox(height: 16),
              Card(
                elevation: 2,
                color: Colors.green.shade50,
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.check_circle, color: Colors.green.shade700, size: 24),
                          const SizedBox(width: 8),
                          Text(_targetLanguage,
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: Colors.green.shade700)),
                        ],
                      ),
                      const SizedBox(height: 12),
                      SelectableText(_translation!,
                        style: const TextStyle(fontSize: 18, height: 1.5)),
                    ],
                  ),
                ),
              ),
            ],

            // Error message
            if (_error != null) ...[
              const SizedBox(height: 16),
              Card(
                elevation: 2,
                color: Colors.red.shade50,
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Row(
                    children: [
                      Icon(Icons.error, color: Colors.red.shade700),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(_error!,
                          style: TextStyle(color: Colors.red.shade900)),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildDocxTranslationTab() {
  return SingleChildScrollView(
    padding: const EdgeInsets.all(16),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // MODE SELECTOR
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Translation Engine',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                SegmentedButton<bool>(
                  segments: const [
                    ButtonSegment(
                      value: true,
                      label: Text('Flutter Mode'),
                      icon: Icon(Icons.flash_on),
                    ),
                    ButtonSegment(
                      value: false,
                      label: Text('Python Mode'),
                      icon: Icon(Icons.precision_manufacturing),
                    ),
                  ],
                  selected: {_useFlutterDocx},
                  onSelectionChanged: (Set<bool> newSelection) {
                    setState(() {
                      _useFlutterDocx = newSelection.first;
                    });
                  },
                ),
                const SizedBox(height: 8),
                Text(
                  _useFlutterDocx
                    ? '✓ Fast, no Python required, heuristic alignment'
                    : '✓ BERT-powered word alignment, requires Python',
                  style: const TextStyle(fontSize: 12, color: Colors.grey),
                ),
              ],
            ),
          ),
        ),
        
        const SizedBox(height: 16),
          Card(
            elevation: 2,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Expanded(
                    child: Text('${_sourceLanguage} → ${_targetLanguage}',
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                  ),
                  TextButton(
                    onPressed: () => _showLanguagePicker(true),
                    child: const Text('Change'),
                  ),
                ],
              ),
            ),
          ),
          
          const SizedBox(height: 16),
          
          // File picker
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Document Selection',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 12),
                  
                  if (_docxFileName == null)
                    ElevatedButton.icon(
                      onPressed: _pickDocx,
                      icon: const Icon(Icons.upload_file),
                      label: const Text('Select DOCX File'),
                    )
                  else
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.description, color: Colors.blue),
                            const SizedBox(width: 8),
                            Expanded(child: Text(_docxFileName!)),
                            IconButton(
                              icon: const Icon(Icons.close),
                              onPressed: () => setState(() {
                                _docxFileName = null;
                                _docxBytes = null;
                                _translatedDocxBytes = null;
                                _segmentTranslations = [];
                              }),
                            ),
                          ],
                        ),
                        Text('${(_docxBytes!.length / 1024).toStringAsFixed(1)} KB',
                          style: const TextStyle(fontSize: 12, color: Colors.grey)),
                      ],
                    ),
                ],
              ),
            ),
          ),
          
          if (_docxBytes != null) ...[
            const SizedBox(height: 16),
            
            ElevatedButton.icon(
              onPressed: _isProcessingDocx ? null : _translateDocx,
              icon: _isProcessingDocx
                ? const SizedBox(
                    width: 20, height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.translate),
              label: Text(_isProcessingDocx ? 'Translating...' : 'Translate Document'),
              style: ElevatedButton.styleFrom(padding: const EdgeInsets.all(16)),
            ),
          ],
          
          // Progress
          if (_docxProgress != null) ...[
            const SizedBox(height: 16),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: () {
                  // Handle both types of progress
                  double percentage;
                  int completed;
                  int total;
                  
                  if (_docxProgress is flutter_docx.DocxTranslationProgress) {
                    final p = _docxProgress as flutter_docx.DocxTranslationProgress;
                    percentage = p.percentage;
                    completed = p.completedSegments;
                    total = p.totalSegments;
                  } else if (_docxProgress is python_docx.DocxTranslationProgress) {
                    final p = _docxProgress as python_docx.DocxTranslationProgress;
                    percentage = p.percentage;
                    completed = p.completedSegments;
                    total = p.totalSegments;
                  } else {
                    percentage = 0;
                    completed = 0;
                    total = 0;
                  }
                  
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Progress: ${(percentage * 100).toStringAsFixed(1)}%',
                        style: const TextStyle(fontWeight: FontWeight.bold)),
                      const SizedBox(height: 8),
                      LinearProgressIndicator(value: percentage),
                      const SizedBox(height: 8),
                      Text('$completed / $total segments',
                        style: const TextStyle(fontSize: 12)),
                    ],
                  );
                }(),
              ),
            ),
          ],
          
          // Download
          if (_translatedDocxBytes != null) ...[
            const SizedBox(height: 16),
            Card(
              color: Colors.green.shade50,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    Row(
                      children: [
                        Icon(Icons.check_circle, color: Colors.green.shade700),
                        const SizedBox(width: 8),
                        const Expanded(
                          child: Text('Translation Complete!',
                            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    ElevatedButton.icon(
                      onPressed: _downloadTranslatedDocx,
                      icon: const Icon(Icons.download),
                      label: const Text('Download Translated Document'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green,
                        foregroundColor: Colors.white,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
          
          // Segment translations with alignments
          if (_settings.showAlignments && _segmentTranslations.isNotEmpty) ...[
            const SizedBox(height: 16),
            Card(
              child: ExpansionTile(
                title: Text('Translated Segments (${_segmentTranslations.length})'),
                children: [
                  Container(
                    constraints: const BoxConstraints(maxHeight: 400),
                    child: ListView.builder(
                      shrinkWrap: true,
                      itemCount: _segmentTranslations.length,
                      itemBuilder: (context, index) {
                        final seg = _segmentTranslations[index];
                        return AlignmentVisualizer(
                          sourceText: seg.source,
                          targetText: seg.target,
                          alignments: seg.alignments,
                          showLines: false,
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  void _showAboutDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('About'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('CrispTranslator Pro v1.0.2',
              style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            const Text('Powered by NLLB-200 (600M INT8)'),
            const SizedBox(height: 8),
            const Text('Offline neural machine translation'),
            const SizedBox(height: 8),
            const Text('Supports 202 languages'),
            const SizedBox(height: 8),
            const Text('• Text translation (ONNX)'),
            const Text('• Document translation (Python)'),
            const Text('• Word-level alignment (BERT)'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _textController.dispose();
    _tabController.dispose();
    _service.dispose();
    if (_docxBackend != null) {
      _docxBackend!.shutdown();
    }
    super.dispose();
  }
}

class _SegmentTranslation {
  final String source;
  final String target;
  final List<docx.Alignment> alignments;
  
  _SegmentTranslation({
    required this.source,
    required this.target,
    required this.alignments,
  });
}