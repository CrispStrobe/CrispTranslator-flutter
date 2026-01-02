// lib/services/docx_translation_service.dart
import 'dart:typed_data';
import 'dart:convert'; 
import 'package:flutter/foundation.dart';
import 'package:archive/archive.dart'; 
import 'package:xml/xml.dart'; 
import 'docx_translator.dart';
import 'backends/python_nllb_onnx_backend.dart';

// Alias to avoid confusion with Flutter's Alignment
import 'docx_translator.dart' as docx show Alignment;

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

class DocxTranslationService {
  final PythonNLLBONNXBackend backend;
  final bool verbose;
  
  DocxTranslationService({
    required this.backend,
    this.verbose = false,
  });
  
  Future<Uint8List> translateDocx({
    required Uint8List inputBytes,
    required String sourceLang,
    required String targetLang,
    required Function(DocxTranslationProgress) onProgress,
    required Function(String, String, List<docx.Alignment>) onSegmentTranslated,
  }) async {
    final translator = DocxTranslator(
      translationService: backend,
      aligner: HeuristicAligner(),
      verbose: verbose,
    );
    
    int totalSegments = 0;
    int completedSegments = 0;
    
    final wrappedBackend = _ProgressTrackingBackend(
      backend: backend,
      onTranslate: (source, target) {
        completedSegments++;
        
        final alignments = backend.lastAlignments ?? [];
        
        onProgress(DocxTranslationProgress(
          totalSegments: totalSegments,
          completedSegments: completedSegments,
          currentSegment: source.length > 50 
            ? '${source.substring(0, 50)}...' 
            : source,
        ));
        
        onSegmentTranslated(source, target, alignments);
      },
    );
    
    totalSegments = await _countSegments(inputBytes);
    
    final outputBytes = await translator.translateDocument(
      docxBytes: inputBytes,
      targetLanguage: targetLang,
      sourceLanguage: sourceLang,
    );
    
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
}

class _ProgressTrackingBackend implements TranslationService {
  final TranslationService backend;
  final Function(String source, String target) onTranslate;
  
  _ProgressTrackingBackend({
    required this.backend,
    required this.onTranslate,
  });
  
  @override
  Future<String> translate(String text, String targetLang, String sourceLang) async {
    final result = await backend.translate(text, targetLang, sourceLang);
    onTranslate(text, result);
    return result;
  }
}