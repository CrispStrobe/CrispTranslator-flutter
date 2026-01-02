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
    required Function(String, String, List<Alignment>) onSegmentTranslated,
    }) async {
    print('🔧 [FLUTTER-DOCX] ==================== TRANSLATION START ====================');
    print('🔧 [FLUTTER-DOCX] Source: $sourceLang → Target: $targetLang');
    
    // Initialize aligner if not done yet
    if (_aligner == null || !_aligner!.isInitialized) {
        await initialize();
    }
    
    final aligner = _aligner ?? HeuristicAligner();
    print('🔧 [FLUTTER-DOCX] Using aligner: ${_aligner != null ? "ONNX BERT" : "Heuristic"}');
    
    // Decode DOCX
    final archive = ZipDecoder().decodeBytes(inputBytes);
    final docXml = _getFileFromArchive(archive, 'word/document.xml');
    final docString = utf8.decode(docXml.content as List<int>);
    final document = XmlDocument.parse(docString);
    
    final paragraphs = document.findAllElements('w:p').toList();
    print('📄 [FLUTTER-DOCX] Found ${paragraphs.length} paragraphs');
    
    int totalSegments = paragraphs.where((p) => p.innerText.trim().isNotEmpty).length;
    int completedSegments = 0;
    
    // Create translator instance with extractParagraph method
    final translator = DocxTranslator(
        translationService: _ONNXTranslationServiceWrapper(onnxService),
        aligner: aligner,
        verbose: verbose,
    );
    
    // Process each paragraph
    for (final paraElem in paragraphs) {
        final originalText = paraElem.innerText.trim();
        if (originalText.isEmpty) continue;
        
        print('\n📝 [PARA] Processing: "${originalText.substring(0, originalText.length > 50 ? 50 : originalText.length)}..."');
        
        try {
        // STEP 1: Extract with formatting
        final transPara = translator.extractParagraph(paraElem);
        
        // STEP 2: Translate
        final translatedText = await onnxService.translate(
            originalText,
            targetLang,
            sourceLanguage: sourceLang,
        );
        
        print('📝 [PARA] Translated: "${translatedText.substring(0, translatedText.length > 50 ? 50 : translatedText.length)}..."');
        
        // STEP 3: Get alignments (CLEAN WORDS ONLY)
        final srcCleanWords = transPara.getWords();

        // ✅ FIX: Unicode-aware word extraction for German
        final tgtCleanWords = RegExp(r'[\p{L}\p{N}]+', unicode: true)
            .allMatches(translatedText)
            .map((m) => m.group(0)!)
            .toList();

        print('🔗 [PARA] Aligning: ${srcCleanWords.length} → ${tgtCleanWords.length}');
        final alignments = aligner.align(srcCleanWords, tgtCleanWords);
        
        print('🔗 [PARA] Got ${alignments.length} alignments');
        
        // STEP 4: Reconstruct with aligned formatting
        translator.applyAlignedFormatting(
            paraElem,
            transPara,
            translatedText,
            alignments,
        );
        
        // Progress callback
        completedSegments++;
        onProgress(DocxTranslationProgress(
            totalSegments: totalSegments,
            completedSegments: completedSegments,
            currentSegment: originalText.length > 50 
            ? '${originalText.substring(0, 50)}...' 
            : originalText,
        ));
        
        onSegmentTranslated(originalText, translatedText, alignments);
        
        } catch (e, stack) {
        print('❌ [PARA] Failed: $e');
        if (verbose) print(stack);
        }
    }
    
    // Re-encode DOCX
    final modifiedXml = document.toXmlString(pretty: false);
    
    // Replace document.xml in archive
    final newArchive = Archive();
    for (final file in archive.files) {
        if (file.name == 'word/document.xml') {
        newArchive.addFile(ArchiveFile(
            file.name,
            modifiedXml.length,
            utf8.encode(modifiedXml),
        ));
        } else {
        newArchive.addFile(file);
        }
    }
    
    final outputBytes = ZipEncoder().encode(newArchive)!;
    print('✅ [FLUTTER-DOCX] ==================== TRANSLATION COMPLETE ====================');
    
    return Uint8List.fromList(outputBytes);
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