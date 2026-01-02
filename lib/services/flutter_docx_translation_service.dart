// lib/services/flutter_docx_translation_service.dart
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:archive/archive.dart';
import 'package:xml/xml.dart';
import 'dart:convert';
import 'docx_translator.dart';
import 'onnx_translation_service.dart';
import 'onnx_bert_aligner.dart'; 

class FlutterDocxTranslationService {
  final ONNXTranslationService onnxService;
  final bool verbose;
  ONNXBertAligner? _aligner; 
  
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
  print('🔧 [FLUTTER-DOCX] Input size: ${inputBytes.length} bytes');
  
  // Initialize aligner if not done yet
  if (_aligner == null || !_aligner!.isInitialized) {
    await initialize();
  }
  
  final aligner = _aligner ?? HeuristicAligner();
  print('🔧 [FLUTTER-DOCX] Using aligner: ${_aligner != null ? "ONNX BERT" : "Heuristic"}');
  
  // ===== STEP 1: Decode and parse DOCX =====
  print('\n📦 [FLUTTER-DOCX] ===== STEP 1: DECODE DOCX =====');
  final archive = ZipDecoder().decodeBytes(inputBytes);
  print('📦 [FLUTTER-DOCX] Archive contains ${archive.files.length} files');
  
  // ===== STEP 2: Parse document.xml =====
  print('\n📄 [FLUTTER-DOCX] ===== STEP 2: PARSE DOCUMENT.XML =====');
  final docXml = _getFileFromArchive(archive, 'word/document.xml');
  final docString = utf8.decode(docXml.content as List<int>);
  final document = XmlDocument.parse(docString);
  
  final body = document.findAllElements('w:body').firstOrNull;
  if (body == null) {
    throw Exception('No w:body found in document.xml');
  }
  
  // Extract body paragraphs
  final bodyParagraphs = <XmlElement>[];
  _extractParagraphsFromBody(body, bodyParagraphs);
  
  print('📄 [FLUTTER-DOCX] Found ${bodyParagraphs.length} paragraphs in document body');
  
  // ===== STEP 3: Parse footnotes.xml if exists =====
  print('\n📝 [FLUTTER-DOCX] ===== STEP 3: PARSE FOOTNOTES.XML =====');
  XmlDocument? footnotesDoc;
  List<XmlElement> footnoteParagraphs = [];
  
  try {
    final footnotesXml = _getFileFromArchive(archive, 'word/footnotes.xml');
    final footnotesString = utf8.decode(footnotesXml.content as List<int>);
    footnotesDoc = XmlDocument.parse(footnotesString);
    
    // Extract paragraphs from footnotes (skip special markers with id <= 0)
    for (final footnote in footnotesDoc.findAllElements('w:footnote')) {
      final id = footnote.getAttribute('w:id');
      final parsedId = id != null ? int.tryParse(id) : null;
      
      if (parsedId != null && parsedId > 0) {
        for (final child in footnote.children.whereType<XmlElement>()) {
          if (child.name.local == 'p') {
            footnoteParagraphs.add(child);
          }
        }
      }
    }
    
    print('📝 [FLUTTER-DOCX] Found ${footnoteParagraphs.length} paragraphs in footnotes');
  } catch (e) {
    print('ℹ️  [FLUTTER-DOCX] No footnotes.xml: $e');
  }
  
  // ===== STEP 4: Count translatable segments =====
  print('\n📊 [FLUTTER-DOCX] ===== STEP 4: COUNT SEGMENTS =====');
  
  int translatableBodyCount = 0;
  for (final para in bodyParagraphs) {
    if (para.innerText.trim().isNotEmpty) {
      translatableBodyCount++;
    }
  }
  
  int translatableFootnoteCount = 0;
  for (final para in footnoteParagraphs) {
    if (para.innerText.trim().isNotEmpty) {
      translatableFootnoteCount++;
    }
  }
  
  final totalSegments = translatableBodyCount + translatableFootnoteCount;
  int completedSegments = 0;
  
  print('📊 [FLUTTER-DOCX] Total segments: $totalSegments');
  print('   Body: $translatableBodyCount');
  print('   Footnotes: $translatableFootnoteCount');
  
  // Create translator instance
  final translator = DocxTranslator(
    translationService: _ONNXTranslationServiceWrapper(onnxService),
    aligner: aligner,
    verbose: verbose,
  );
  
  // ===== STEP 5: Translate BODY paragraphs =====
  print('\n📄 [FLUTTER-DOCX] ===== STEP 5: TRANSLATE BODY PARAGRAPHS =====');
  
  for (int i = 0; i < bodyParagraphs.length; i++) {
    final paraElem = bodyParagraphs[i];
    final originalText = paraElem.innerText.trim();
    
    if (originalText.isEmpty) {
      print('⏭️  [PARA ${i + 1}/${bodyParagraphs.length}] Skipping empty paragraph');
      continue;
    }
    
    print('\n📝 [PARA ${i + 1}/${bodyParagraphs.length}] Original: "${originalText.substring(0, originalText.length > 60 ? 60 : originalText.length)}..."');
    
    try {
      await _translateParagraph(
        paraElem, 
        translator, 
        sourceLang, 
        targetLang, 
        aligner,
        (translated, alignments) {
          completedSegments++;
          onProgress(DocxTranslationProgress(
            totalSegments: totalSegments,
            completedSegments: completedSegments,
            currentSegment: originalText.length > 50 ? '${originalText.substring(0, 50)}...' : originalText,
          ));
          onSegmentTranslated(originalText, translated, alignments);
        },
      );
    } catch (e, stack) {
      print('❌ [PARA ${i + 1}] Translation failed: $e');
      if (verbose) print(stack);
      // Continue with next paragraph instead of failing completely
    }
  }
  
  // ===== STEP 6: Translate FOOTNOTE paragraphs =====
  if (footnoteParagraphs.isNotEmpty) {
    print('\n📝 [FLUTTER-DOCX] ===== STEP 6: TRANSLATE FOOTNOTES =====');
    
    for (int i = 0; i < footnoteParagraphs.length; i++) {
      final paraElem = footnoteParagraphs[i];
      final originalText = paraElem.innerText.trim();
      
      if (originalText.isEmpty) {
        print('⏭️  [FOOTNOTE ${i + 1}/${footnoteParagraphs.length}] Skipping empty');
        continue;
      }
      
      print('\n📝 [FOOTNOTE ${i + 1}/${footnoteParagraphs.length}] Original: "${originalText.substring(0, originalText.length > 60 ? 60 : originalText.length)}..."');
      
      try {
        await _translateParagraph(
          paraElem, 
          translator, 
          sourceLang, 
          targetLang, 
          aligner,
          (translated, alignments) {
            completedSegments++;
            onProgress(DocxTranslationProgress(
              totalSegments: totalSegments,
              completedSegments: completedSegments,
              currentSegment: originalText.length > 50 ? '${originalText.substring(0, 50)}...' : originalText,
            ));
            onSegmentTranslated(originalText, translated, alignments);
          },
        );
      } catch (e, stack) {
        print('❌ [FOOTNOTE ${i + 1}] Translation failed: $e');
        if (verbose) print(stack);
      }
    }
  }
  
  // ===== STEP 7: Validate XML before serializing =====
  print('\n✅ [FLUTTER-DOCX] ===== STEP 7: VALIDATE XML =====');
  
  try {
    final testDoc = document.toXmlString(pretty: false, preserveWhitespace: (node) => true);
    XmlDocument.parse(testDoc);
    print('✅ [VALIDATE] document.xml is valid');
  } catch (e) {
    print('❌ [VALIDATE] document.xml is INVALID: $e');
    throw Exception('Generated invalid document.xml: $e');
  }
  
  if (footnotesDoc != null) {
    try {
      final testFootnotes = footnotesDoc.toXmlString(pretty: false, preserveWhitespace: (node) => true);
      XmlDocument.parse(testFootnotes);
      print('✅ [VALIDATE] footnotes.xml is valid');
    } catch (e) {
      print('❌ [VALIDATE] footnotes.xml is INVALID: $e');
      throw Exception('Generated invalid footnotes.xml: $e');
    }
  }
  
  // ===== STEP 8: Serialize modified XMLs =====
  print('\n📦 [FLUTTER-DOCX] ===== STEP 8: SERIALIZE XML =====');
  
  final modifiedDocXml = document.toXmlString(
    pretty: false,
    preserveWhitespace: (node) => true,
  );
  print('📦 [FLUTTER-DOCX] document.xml: ${modifiedDocXml.length} bytes');
  
  String? modifiedFootnotesXml;
  if (footnotesDoc != null) {
    modifiedFootnotesXml = footnotesDoc.toXmlString(
      pretty: false,
      preserveWhitespace: (node) => true,
    );
    print('📦 [FLUTTER-DOCX] footnotes.xml: ${modifiedFootnotesXml.length} bytes');
  }
  
  // ===== STEP 9: Rebuild archive =====
  print('\n📦 [FLUTTER-DOCX] ===== STEP 9: REBUILD ARCHIVE =====');
  
  final newArchive = Archive();
  int filesReplaced = 0;
  int filesKept = 0;
  
  for (final file in archive.files) {
    if (file.name == 'word/document.xml') {
      newArchive.addFile(ArchiveFile(
        file.name,
        modifiedDocXml.length,
        utf8.encode(modifiedDocXml),
      )..compress = true);
      filesReplaced++;
      print('✅ [ARCHIVE] Replaced: ${file.name}');
    } else if (file.name == 'word/footnotes.xml' && modifiedFootnotesXml != null) {
      newArchive.addFile(ArchiveFile(
        file.name,
        modifiedFootnotesXml.length,
        utf8.encode(modifiedFootnotesXml),
      )..compress = true);
      filesReplaced++;
      print('✅ [ARCHIVE] Replaced: ${file.name}');
    } else {
      newArchive.addFile(file);
      filesKept++;
    }
  }
  
  print('📦 [FLUTTER-DOCX] Archive rebuilt: $filesReplaced replaced, $filesKept kept');
  
  // ===== STEP 10: Encode final DOCX =====
  print('\n📦 [FLUTTER-DOCX] ===== STEP 10: ENCODE FINAL DOCX =====');
  
  final outputBytes = ZipEncoder().encode(newArchive)!;
  
  print('✅ [FLUTTER-DOCX] ==================== TRANSLATION COMPLETE ====================');
  print('📦 [FLUTTER-DOCX] Input size: ${inputBytes.length} bytes');
  print('📦 [FLUTTER-DOCX] Output size: ${outputBytes.length} bytes');
  print('📊 [FLUTTER-DOCX] Segments translated: $completedSegments/$totalSegments');
  print('   Success rate: ${(completedSegments / totalSegments * 100).toStringAsFixed(1)}%');
  print('=' * 80);
  
  return Uint8List.fromList(outputBytes);
}

// ===== HELPER: Extract paragraphs from body =====
void _extractParagraphsFromBody(XmlElement body, List<XmlElement> paragraphs) {
  print('🔍 [EXTRACT] Extracting paragraphs from body...');
  
  // Get direct paragraph children
  for (final child in body.children.whereType<XmlElement>()) {
    if (child.name.local == 'p') {
      paragraphs.add(child);
    } else if (child.name.local == 'tbl') {
      // Extract from tables
      for (final row in child.findAllElements('w:tr')) {
        for (final cell in row.findAllElements('w:tc')) {
          for (final para in cell.children.whereType<XmlElement>()) {
            if (para.name.local == 'p') {
              paragraphs.add(para);
            }
          }
        }
      }
    }
  }
  
  print('🔍 [EXTRACT] Extracted ${paragraphs.length} paragraphs');
}

// ===== HELPER: Translate single paragraph =====
Future<void> _translateParagraph(
  XmlElement paraElem,
  DocxTranslator translator,
  String sourceLang,
  String targetLang,
  WordAligner aligner,
  Function(String translated, List<Alignment> alignments) onComplete,
) async {
  final transPara = translator.extractParagraph(paraElem);
  final fullOriginalText = transPara.getText();
  
  if (fullOriginalText.trim().isEmpty) return;

  // 1. SENTENCE SPLITTING
  final sentenceRegex = RegExp(r'(?<=[.!?])\s+');
  final sentences = fullOriginalText.split(sentenceRegex).where((s) => s.trim().isNotEmpty).toList();
  
  List<String> translatedSentences = [];
  List<Alignment> globalAlignments = [];
  int srcWordOffset = 0;
  int tgtWordOffset = 0;

  print('🧩 [PARA] Splitting into ${sentences.length} sentences for NMT stability.');

  for (var sentence in sentences) {
    // 2. NEURAL TRANSLATION (Per Sentence)
    final translatedSent = await onnxService.translate(
      sentence,
      targetLang,
      sourceLanguage: sourceLang,
    );
    translatedSentences.add(translatedSent);

    // 3. OFFSET-AWARE ALIGNMENT
    final sWords = RegExp(r'[\p{L}\p{N}]+', unicode: true)
        .allMatches(sentence).map((m) => m.group(0)!).toList();
    final tWords = RegExp(r'[\p{L}\p{N}]+', unicode: true)
        .allMatches(translatedSent).map((m) => m.group(0)!).toList();
    
    if (sWords.isNotEmpty && tWords.isNotEmpty) {
      final localAligns = aligner.align(sWords, tWords);
      for (var a in localAligns) {
        globalAlignments.add(Alignment(
          a.sourceIndex + srcWordOffset,
          a.targetIndex + tgtWordOffset,
        ));
      }
      srcWordOffset += sWords.length;
      tgtWordOffset += tWords.length;
    }
  }

  final finalFullTranslation = translatedSentences.join(' ');

  // 4. RECONSTRUCT WITH CLONED NODES (Prevents XmlParentException)
  translator.applyAlignedFormatting(
    paraElem,
    transPara,
    finalFullTranslation,
    globalAlignments,
  );
  
  onComplete(finalFullTranslation, globalAlignments);
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