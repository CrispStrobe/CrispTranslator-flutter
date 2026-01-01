// main.dart:

import 'package:flutter/material.dart';
import 'services/onnx_translation_service.dart';
import 'services/nllb_tokenizer.dart';
import 'services/model_downloader.dart';

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

class _TranslatorPageState extends State<TranslatorPage> {
  final _textController = TextEditingController();
  final _service = ONNXTranslationService();
  final _downloader = ModelDownloader();

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

  @override
  void initState() {
    super.initState();
    _checkModels();
  }

  // Helper method to populate the list once the service/tokenizer is ready
  void _populateLanguageList() {
    setState(() {
      // Access the static map from the NLLBTokenizer class
      _languages = NLLBTokenizer.languageTokens.keys.toList();
      _languages.sort(); // Sort alphabetically for easier searching
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
      // First check if models are bundled in assets
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
      // If not in assets, check if downloaded
      final modelsExist = await _downloader.areModelsDownloaded();
      print('🔍 [MAIN] Downloaded models check result: $modelsExist');

      if (mounted) {
        if (modelsExist) {
          print(
              '✅ [MAIN] Downloaded models found! Will use downloaded models.');
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

      print(
          '✅ [MAIN] Service initialized successfully with downloaded models!');
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
      print(
          '📦 [MAIN] Calling service.initialize() with no modelsPath (will use assets)...');
      // No modelsPath = use assets
      await _service.initialize();

      print('✅ [MAIN] Service initialized successfully with assets!');
      if (mounted) {
        _populateLanguageList(); // adds the rest of the 202 languages nllb supports
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
                  // Handle bar
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
                    style: const TextStyle(
                        fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 16),
                  // Search Field
                  TextField(
                    decoration: InputDecoration(
                      hintText: 'Search languages...',
                      prefixIcon: const Icon(Icons.search),
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12)),
                      filled: true,
                      fillColor: Colors.grey[100],
                    ),
                    onChanged: (value) {
                      setModalState(() {
                        filteredLanguages = _languages
                            .where((l) =>
                                l.toLowerCase().contains(value.toLowerCase()))
                            .toList();
                      });
                    },
                  ),
                  const SizedBox(height: 16),
                  // List
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
                              if (isSource)
                                _sourceLanguage = lang;
                              else
                                _targetLanguage = lang;
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
                    style: const TextStyle(
                        fontSize: 15, fontWeight: FontWeight.w600),
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
    // Model checking screen
    if (_isCheckingModels) {
      return Scaffold(
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const CircularProgressIndicator(),
              const SizedBox(height: 20),
              const Text(
                'Checking models...',
                style: TextStyle(fontSize: 16),
              ),
            ],
          ),
        ),
      );
    }

    // Download screen
    if (_needsDownload) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Model Download Required'),
        ),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(32.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(
                  Icons.cloud_download,
                  size: 80,
                  color: Colors.blue,
                ),
                const SizedBox(height: 24),
                const Text(
                  'Translation Models Required',
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  'This app requires ~1.9 GB of AI models to function offline.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 16),
                ),
                const SizedBox(height: 8),
                Text(
                  'Models will be downloaded from HuggingFace.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.grey[600],
                  ),
                ),
                const SizedBox(height: 32),
                if (!_isDownloading) ...[
                  ElevatedButton.icon(
                    onPressed: _downloadModels,
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 32,
                        vertical: 16,
                      ),
                    ),
                    icon: const Icon(Icons.download),
                    label: const Text(
                      'Download Models',
                      style: TextStyle(fontSize: 16),
                    ),
                  ),
                ] else ...[
                  const SizedBox(
                    width: 60,
                    height: 60,
                    child: CircularProgressIndicator(strokeWidth: 4),
                  ),
                  const SizedBox(height: 24),
                  Text(
                    _downloadStatus,
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 14),
                  ),
                  const SizedBox(height: 16),
                  ..._downloadProgress.entries.map((entry) {
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            entry.key,
                            style: const TextStyle(fontSize: 12),
                          ),
                          const SizedBox(height: 4),
                          LinearProgressIndicator(
                            value: entry.value,
                            minHeight: 6,
                          ),
                        ],
                      ),
                    );
                  }).toList(),
                ],
                if (_error != null) ...[
                  const SizedBox(height: 24),
                  Text(
                    _error!,
                    style: const TextStyle(color: Colors.red),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 16),
                  TextButton(
                    onPressed: () => setState(() => _error = null),
                    child: const Text('Retry'),
                  ),
                ],
              ],
            ),
          ),
        ),
      );
    }

    // Initializing screen
    if (_isInitializing) {
      return Scaffold(
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const CircularProgressIndicator(),
              const SizedBox(height: 20),
              const Text(
                'Initializing translation engine...',
                style: TextStyle(fontSize: 16),
              ),
              const SizedBox(height: 10),
              Text(
                'Loading ONNX models',
                style: TextStyle(fontSize: 14, color: Colors.grey[600]),
              ),
            ],
          ),
        ),
      );
    }

    // Main translator UI
    return Scaffold(
      appBar: AppBar(
        title: const Text('NLLB Translator'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        actions: [
          IconButton(
            icon: const Icon(Icons.info_outline),
            onPressed: () => _showAboutDialog(context),
          ),
        ],
      ),
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Language selectors

              Card(
                elevation: 2,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                  child: Row(
                    children: [
                      // Source Language Selector
                      Expanded(
                        child: _buildLanguageButton(
                          label: 'From',
                          value: _sourceLanguage,
                          onTap: () => _showLanguagePicker(true),
                        ),
                      ),

                      // Swap Button
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

                      // Target Language Selector
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
                      Text(
                        'Input ($_sourceLanguage)',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
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
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor:
                              AlwaysStoppedAnimation<Color>(Colors.white),
                        ),
                      )
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
                            Icon(
                              Icons.check_circle,
                              color: Colors.green.shade700,
                              size: 24,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              _targetLanguage,
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: Colors.green.shade700,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        SelectableText(
                          _translation!,
                          style: const TextStyle(
                            fontSize: 18,
                            height: 1.5,
                          ),
                        ),
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
                        Icon(
                          Icons.error,
                          color: Colors.red.shade700,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _error!,
                            style: TextStyle(
                              color: Colors.red.shade900,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  void _showAboutDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('About'),
        content: const Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'CrispTranslator v1.0.1',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            SizedBox(height: 16),
            Text('Powered by NLLB-200 (600M parameters)'),
            SizedBox(height: 8),
            Text('Offline neural machine translation'),
            SizedBox(height: 8),
            Text('Supports 202 languages'),
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
    _service.dispose();
    super.dispose();
  }
}
