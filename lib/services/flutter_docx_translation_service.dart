// lib/services/flutter_docx_translation_service.dart
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:archive/archive.dart';
import 'package:xml/xml.dart';
import 'dart:convert';
import 'docx_translator.dart';
import 'onnx_translation_service.dart';
import 'onnx_bert_aligner.dart'; // ADD THIS

class FlutterDocxTranslationService {
  final ONNXTranslationService onnxService;
  final bool verbose;
  ONNXBertAligner? _aligner; // ADD THIS
  
  FlutterDocxTranslationService({
    required this.onnxService,
    this.verbose = false,
  });
  
  Future<void> initialize({String? modelsPath}) async {
    // Initialize BERT aligner
    try {
      print('🔧 [FLUTTER-DOCX] Initializing BERT aligner...');
      _aligner = ONNXBertAligner(verbose: verbose);
      await _aligner!.initialize(modelsPath: modelsPath);
      print('✅ [FLUTTER-DOCX] BERT aligner ready');
    } catch (e) {
      print('⚠️  [FLUTTER-DOCX] BERT aligner failed, will use heuristic: $e');
      _aligner = null;
    }
  }
  
  Future<Uint8List> translateDocx({
    required Uint8List inputBytes,
    required String sourceLang,
    required String targetLang,
    required Function(DocxTranslationProgress) onProgress,
    required Function(String, String, List<Alignment>) onSegmentTranslated, // CHANGED
  }) async {
    print('🔧 [FLUTTER-DOCX] Starting Flutter-native DOCX translation...');
    
    // Initialize aligner if not done yet
    if (_aligner == null || !_aligner!.isInitialized) {
      await initialize();
    }
    
    final wrappedService = _ONNXTranslationServiceWrapper(onnxService);
    
    // Use ONNX aligner if available, otherwise heuristic
    final aligner = _aligner ?? HeuristicAligner();
    print('🔧 [FLUTTER-DOCX] Using aligner: ${_aligner != null ? "ONNX BERT" : "Heuristic"}');
    
    final translator = DocxTranslator(
      translationService: wrappedService,
      aligner: aligner,
      verbose: verbose,
    );
    
    int totalSegments = await _countSegments(inputBytes);
    int completedSegments = 0;
    
    wrappedService.onTranslate = (source, target) {
      completedSegments++;
      
      onProgress(DocxTranslationProgress(
        totalSegments: totalSegments,
        completedSegments: completedSegments,
        currentSegment: source.length > 50 
          ? '${source.substring(0, 50)}...' 
          : source,
      ));
      
      // Get alignments from the aligner
      final sourceWords = source.split(RegExp(r'\s+'));
      final targetWords = target.split(RegExp(r'\s+'));
      final alignments = aligner.align(sourceWords, targetWords);
      
      onSegmentTranslated(source, target, alignments);
    };
    
    final outputBytes = await translator.translateDocument(
      docxBytes: inputBytes,
      targetLanguage: targetLang,
      sourceLanguage: sourceLang,
    );
    
    print('✅ [FLUTTER-DOCX] Translation complete!');
    return outputBytes;
  }
  
  Future<int> _countSegments(Uint8List docxBytes) async {
    try {
      final archive = ZipDecoder().decodeBytes(docxBytes);
      final docXml = _getFileFromArchive(archive, 'word/document.xml');
      final docString = utf8.decode(docXml.content as List<int>);
      final document = XmlDocument.parse(docString);
      
      int count = 0;
      for (final elem in document.descendants.whereType<XmlElement>()) {
        if (elem.name.local == 'p') {
          final text = elem.innerText.trim();
          if (text.isNotEmpty) count++;
        }
      }
      return count;
    } catch (e) {
      return 100;
    }
  }
  
  ArchiveFile _getFileFromArchive(Archive archive, String name) {
    return archive.files.firstWhere(
      (f) => f.name == name,
      orElse: () => throw Exception('File not found: $name'),
    );
  }
  
  void dispose() {
    _aligner?.dispose();
  }
}

class _ONNXTranslationServiceWrapper implements TranslationService {
  final ONNXTranslationService onnxService;
  Function(String source, String target)? onTranslate;
  
  _ONNXTranslationServiceWrapper(this.onnxService);
  
  @override
  Future<String> translate(String text, String targetLang, String sourceLang) async {
    final result = await onnxService.translate(
      text,
      targetLang,
      sourceLanguage: sourceLang,
    );
    onTranslate?.call(text, result);
    return result;
  }
}

class DocxTranslationProgress {
  final int totalSegments;
  final int completedSegments;
  final String currentSegment;
  final double percentage;
  
  DocxTranslationProgress({
    required this.totalSegments,
    required this.completedSegments,
    required this.currentSegment,
  }) : percentage = totalSegments > 0 ? completedSegments / totalSegments : 0.0;
}