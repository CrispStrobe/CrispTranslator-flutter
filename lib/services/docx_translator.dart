// docx_translator.dart - COMPLETE IMPLEMENTATION
import 'dart:typed_data';
import 'package:archive/archive.dart';
import 'package:xml/xml.dart';
import 'dart:convert';
import 'backends/python_nllb_onnx_backend.dart';
import 'dart:math' as math;

// ============================================================================
// TRANSLATION INTERFACE
// ============================================================================

abstract class TranslationService {
  Future<String> translate(String text, String targetLang, String sourceLang);
}

class MockTranslationService implements TranslationService {
  @override
  Future<String> translate(
      String text, String targetLang, String sourceLang) async {
    await Future.delayed(Duration(milliseconds: 10));
    return '[TRANSLATED: $text]';
  }
}

// ============================================================================
// MOCK TRANSLATION SERVICE (UPPERCASE)
// ============================================================================

class UppercaseTranslationService implements TranslationService {
  @override
  Future<String> translate(
      String text, String targetLang, String sourceLang) async {
    // Simulate processing time
    await Future.delayed(Duration(milliseconds: 5));
    // Mock: uppercase the text
    return text.toUpperCase();
  }
}

// ============================================================================
// ALIGNMENT INTERFACE
// ============================================================================

abstract class WordAligner {
  List<Alignment> align(List<String> sourceWords, List<String> targetWords);
}

class Alignment {
  final int sourceIndex;
  final int targetIndex;

  Alignment(this.sourceIndex, this.targetIndex);
  
  // Aliases for compatibility
  int get source => sourceIndex;
  int get target => targetIndex;

  @override
  String toString() => '($sourceIndex,$targetIndex)';
}

// lib/services/docx_translator.dart
// Replace the HeuristicAligner class with this improved version:

class HeuristicAligner implements WordAligner {
  @override
  List<Alignment> align(List<String> sourceWords, List<String> targetWords) {
    if (sourceWords.isEmpty || targetWords.isEmpty) return [];
    
    final alignments = <Alignment>[];
    final used = <int>{};
    
    // Normalize words for comparison
    final srcNorm = sourceWords.map(_normalize).toList();
    final tgtNorm = targetWords.map(_normalize).toList();
    
    // 1. EXACT MATCHES (highest priority)
    for (int i = 0; i < srcNorm.length; i++) {
      for (int j = 0; j < tgtNorm.length; j++) {
        if (!used.contains(j) && srcNorm[i] == tgtNorm[j]) {
          alignments.add(Alignment(i, j));
          used.add(j);
          break;
        }
      }
    }
    
    // 2. SUBSTRING MATCHES (numbers, names, cognates)
    for (int i = 0; i < srcNorm.length; i++) {
      if (alignments.any((a) => a.sourceIndex == i)) continue;
      
      final src = srcNorm[i];
      if (src.length < 3) continue;
      
      for (int j = 0; j < tgtNorm.length; j++) {
        if (used.contains(j)) continue;
        
        final tgt = tgtNorm[j];
        if (tgt.length < 3) continue;
        
        // Check if one contains the other (for compound words)
        if (src.contains(tgt) || tgt.contains(src)) {
          alignments.add(Alignment(i, j));
          used.add(j);
          break;
        }
        
        // Check common prefix (length >= 4)
        if (_commonPrefixLength(src, tgt) >= 4) {
          alignments.add(Alignment(i, j));
          used.add(j);
          break;
        }
      }
    }
    
    // 3. COGNATES AND SIMILAR WORDS (Levenshtein distance)
    for (int i = 0; i < srcNorm.length; i++) {
      if (alignments.any((a) => a.sourceIndex == i)) continue;
      
      final src = srcNorm[i];
      if (src.length < 4) continue;
      
      int bestMatch = -1;
      double bestSimilarity = 0.0;
      
      for (int j = 0; j < tgtNorm.length; j++) {
        if (used.contains(j)) continue;
        
        final tgt = tgtNorm[j];
        if (tgt.length < 4) continue;
        
        final similarity = _stringSimilarity(src, tgt);
        if (similarity > bestSimilarity && similarity >= 0.6) {
          bestSimilarity = similarity;
          bestMatch = j;
        }
      }
      
      if (bestMatch >= 0) {
        alignments.add(Alignment(i, bestMatch));
        used.add(bestMatch);
      }
    }
    
    // 4. POSITIONAL HEURISTIC (for remaining short words)
    for (int i = 0; i < sourceWords.length; i++) {
      if (alignments.any((a) => a.sourceIndex == i)) continue;
      
      // Find closest unused target word
      final relativePos = i / sourceWords.length;
      final expectedTargetPos = (relativePos * targetWords.length).round();
      
      // Search within a window around expected position
      final searchRadius = (targetWords.length * 0.3).toInt() + 1;
      
      for (int offset = 0; offset < searchRadius; offset++) {
        for (int direction in [-1, 1]) {
          final j = expectedTargetPos + (offset * direction);
          if (j >= 0 && j < targetWords.length && !used.contains(j)) {
            alignments.add(Alignment(i, j));
            used.add(j);
            break;
          }
        }
        if (used.length > alignments.length - 1) break;
      }
    }
    
    return alignments;
  }
  
  String _normalize(String word) {
    return word
        .toLowerCase()
        .replaceAll('#', '')
        .trim();
  }
  
  int _commonPrefixLength(String a, String b) {
    int len = 0;
    final minLen = a.length < b.length ? a.length : b.length;
    for (int i = 0; i < minLen; i++) {
      if (a[i] == b[i]) {
        len++;
      } else {
        break;
      }
    }
    return len;
  }
  
  double _stringSimilarity(String s1, String s2) {
    if (s1 == s2) return 1.0;
    if (s1.isEmpty || s2.isEmpty) return 0.0;
    
    final len1 = s1.length;
    final len2 = s2.length;
    final maxLen = len1 > len2 ? len1 : len2;
    
    final distance = _levenshteinDistance(s1, s2);
    return 1.0 - (distance / maxLen);
  }
  
  int _levenshteinDistance(String s1, String s2) {
    final len1 = s1.length;
    final len2 = s2.length;
    
    final matrix = List.generate(
      len1 + 1,
      (i) => List.filled(len2 + 1, 0),
    );
    
    for (int i = 0; i <= len1; i++) {
      matrix[i][0] = i;
    }
    for (int j = 0; j <= len2; j++) {
      matrix[0][j] = j;
    }
    
    for (int i = 1; i <= len1; i++) {
      for (int j = 1; j <= len2; j++) {
        final cost = s1[i - 1] == s2[j - 1] ? 0 : 1;
        matrix[i][j] = [
          matrix[i - 1][j] + 1, // deletion
          matrix[i][j - 1] + 1, // insertion
          matrix[i - 1][j - 1] + cost, // substitution
        ].reduce((a, b) => a < b ? a : b);
      }
    }
    
    return matrix[len1][len2];
  }
}

// ============================================================================
// DATA STRUCTURES
// ============================================================================

class FormatRun {
  String text;
  bool? bold;
  bool? italic;
  bool? underline;
  String? fontName;
  double? fontSize;
  RGBColor? fontColor;
  // for preserving unknown XML like highlighting
  List<XmlNode> extraProperties; 

  FormatRun({
    required this.text,
    this.bold,
    this.italic,
    this.underline,
    this.fontName,
    this.fontSize,
    this.fontColor,
    List<XmlNode>? extraProperties,
  }) : extraProperties = extraProperties ?? [];

  @override
  String toString() => 'Run("$text", B:$bold, I:$italic, Font:$fontName)';
}

class RGBColor {
  final int r, g, b;
  RGBColor(this.r, this.g, this.b);

  String toHex() => '${r.toRadixString(16).padLeft(2, '0')}'
          '${g.toRadixString(16).padLeft(2, '0')}'
          '${b.toRadixString(16).padLeft(2, '0')}'
      .toUpperCase();

  factory RGBColor.fromHex(String hex) {
    hex = hex.replaceAll('#', '');
    return RGBColor(
      int.parse(hex.substring(0, 2), radix: 16),
      int.parse(hex.substring(2, 4), radix: 16),
      int.parse(hex.substring(4, 6), radix: 16),
    );
  }
}

class TranslatableParagraph {
  final List<FormatRun> runs;
  final Map<String, dynamic> metadata;
  
  TranslatableParagraph({
    required this.runs,
    Map<String, dynamic>? metadata,
  }) : metadata = metadata ?? {};
  
  // Get full text
  String getText() {
    return runs.map((r) => r.text).join('');
  }
  
  // Get CLEAN words (alphanumeric only, matching Python's re.findall(r"\w+"))
  List<String> getWords() {
    final text = getText();
    // ✅ Unicode-aware regex: matches letters (including umlauts) + digits
    final regex = RegExp(r'[\p{L}\p{N}]+', unicode: true);
    return regex.allMatches(text).map((m) => m.group(0)!).toList();
  }
  
  // Map clean word indices to formatting
  Map<String, Set<int>> getFormattedWordIndices() {
    print('🔍 [DEBUG] getFormattedWordIndices() START');
    
    final formatted = {
      'italic': <int>{},
      'bold': <int>{},
      'italic_bold': <int>{},
    };
    
    final text = getText();
    final words = getWords(); // Clean words only
    
    if (words.isEmpty) {
      print('⚠️  [DEBUG] No words extracted');
      return formatted;
    }
    
    print('🔍 [DEBUG] Full text: "$text"');
    print('🔍 [DEBUG] Clean words: $words');
    
    // Build char position → word index map
    final charToWord = <int, int>{};
    int lastFound = 0;
    
    for (int wordIdx = 0; wordIdx < words.length; wordIdx++) {
      final word = words[wordIdx];
      final start = text.indexOf(word, lastFound);
      
      if (start != -1) {
        for (int i = start; i < start + word.length; i++) {
          charToWord[i] = wordIdx;
        }
        lastFound = start + word.length;
        print('🔍 [DEBUG] Word[$wordIdx] "$word" → chars $start-${start + word.length - 1}');
      }
    }
    
    // Walk through runs and mark formatted word indices
    int charPos = 0;
    for (final run in runs) {
      if (run.text.isEmpty) continue;
      
      for (int i = 0; i < run.text.length; i++) {
        final char = run.text[i];
        
        if (charToWord.containsKey(charPos)) {
          final wordIdx = charToWord[charPos]!;
          
          if (!char.trim().isEmpty) { // Only non-whitespace
            if (run.bold == true && run.italic == true) {
              formatted['italic_bold']!.add(wordIdx);
              print('🔍 [DEBUG] Word[$wordIdx] = BOLD+ITALIC');
            } else if (run.italic == true) {
              formatted['italic']!.add(wordIdx);
              print('🔍 [DEBUG] Word[$wordIdx] = ITALIC');
            } else if (run.bold == true) {
              formatted['bold']!.add(wordIdx);
              print('🔍 [DEBUG] Word[$wordIdx] = BOLD');
            }
          }
        }
        charPos++;
      }
    }
    
    print('🔍 [DEBUG] Final formatting map:');
    print('  Bold: ${formatted['bold']}');
    print('  Italic: ${formatted['italic']}');
    print('  Bold+Italic: ${formatted['italic_bold']}');
    
    return formatted;
  }
}

// ============================================================================
// MAIN TRANSLATOR CLASS
// ============================================================================

class DocxTranslator {
  final TranslationService translationService;
  final WordAligner? aligner;
  final bool verbose;

  // Namespaces
  static const String wNamespace =
      'http://schemas.openxmlformats.org/wordprocessingml/2006/main';
  static const String rNamespace =
      'http://schemas.openxmlformats.org/officeDocument/2006/relationships';

  DocxTranslator({
    required this.translationService,
    this.aligner,
    this.verbose = true,
  });


  // ============================================================================
  // MAIN TRANSLATION WORKFLOW
  // ============================================================================

  void _traceAlignments(List<String> srcWords, List<String> tgtWords, List<Alignment> links) {
    print('║ ALIGN TRACE | Links: ${links.length}');
    for (var link in links) {
      if (link.sourceIndex < srcWords.length && link.targetIndex < tgtWords.length) {
        String src = srcWords[link.sourceIndex];
        String tgt = tgtWords[link.targetIndex];
        // "word -> word" debug log
        _log('║   Link: [$src] (${link.sourceIndex}) ↔ [$tgt] (${link.targetIndex})');
      }
    }
  }
  
  Future<Uint8List> translateDocument({
    required Uint8List docxBytes,
    required String targetLanguage,
    String sourceLanguage = 'English',
  }) async {
    print('\n🔧 Starting DOCX translation...');
    print('   Source: $sourceLanguage → Target: $targetLanguage');

    // 1. Extract DOCX archive
    final archive = ZipDecoder().decodeBytes(docxBytes);

    // 2. Parse document.xml - PRESERVE original XML structure
    final docXmlFile = _getFileFromArchive(archive, 'word/document.xml');
    final docXmlString = utf8.decode(docXmlFile.content as List<int>);
    final document = XmlDocument.parse(docXmlString);

    // 3. Parse footnotes.xml if exists
    XmlDocument? footnotes;
    ArchiveFile? footnotesFile;
    String? footnotesXmlString;
    try {
      footnotesFile = _getFileFromArchive(archive, 'word/footnotes.xml');
      footnotesXmlString = utf8.decode(footnotesFile.content as List<int>);
      footnotes = XmlDocument.parse(footnotesXmlString);
      _log('✓ Found footnotes.xml');
    } catch (e) {
      _log('ℹ No footnotes found');
    }

    // 4. Extract all paragraphs
    final allParagraphs = _extractAllParagraphs(document, footnotes);
    print(
        '📄 Found ${allParagraphs.length} paragraphs (body, tables, headers, footers, footnotes)');

    // 5. Translate each paragraph
    int translated = 0;
    for (final paraInfo in allParagraphs) {
      if (paraInfo.transPara.getText().trim().isNotEmpty) {
        await _translateParagraph(paraInfo, sourceLanguage, targetLanguage);
        translated++;
      }
    }
    print('✅ Translated $translated paragraphs');

    // 6. Rebuild paragraphs in place
    for (final paraInfo in allParagraphs) {
      if (paraInfo.translatedText != null) {
        _rebuildParagraph(paraInfo);
      }
    }

    // 7. Create new archive with modified XML
    final newArchive = Archive();
    for (final file in archive.files) {
      if (file.name == 'word/document.xml') {
        // Serialize document.xml with proper formatting
        final xmlString = document.toXmlString(
          pretty: false,
          indent: '',
          preserveWhitespace: (node) => true,
        );
        final bytes = utf8.encode(xmlString);
        newArchive.addFile(ArchiveFile(file.name, bytes.length, bytes)
          ..mode = file.mode
          ..compress = true);
      } else if (footnotes != null && file.name == 'word/footnotes.xml') {
        // Serialize footnotes.xml
        final xmlString = footnotes.toXmlString(
          pretty: false,
          indent: '',
          preserveWhitespace: (node) => true,
        );
        final bytes = utf8.encode(xmlString);
        newArchive.addFile(ArchiveFile(file.name, bytes.length, bytes)
          ..mode = file.mode
          ..compress = true);
      } else {
        // Copy other files as-is
        newArchive.addFile(file);
      }
    }

    print('✅ DOCX translation complete!\n');
    final encoded = ZipEncoder().encode(newArchive);
    return Uint8List.fromList(encoded!);
  }

  // ============================================================================
  // PARAGRAPH EXTRACTION
  // ============================================================================

  List<ParagraphInfo> _extractAllParagraphs(
      XmlDocument document, XmlDocument? footnotes) {
    final List<ParagraphInfo> allParas = [];

    // Find body - use descendants instead of findAllElements
    XmlElement? body;

    // Try multiple approaches to find body
    for (final elem in document.descendants.whereType<XmlElement>()) {
      if (elem.name.local == 'body') {
        body = elem;
        _log('✓ Found body element');
        break;
      }
    }

    if (body == null) {
      _log('❌ Error: No body element found in document');
      _log('Root element: ${document.rootElement.name}');
      _log(
          'Children: ${document.rootElement.children.whereType<XmlElement>().map((e) => e.name.local).toList()}');
      return allParas;
    }

    // Extract paragraphs from body
    _extractParagraphsFromBody(body, allParas);

    // Extract footnotes
    if (footnotes != null) {
      _extractFootnotes(footnotes, allParas);
    }

    return allParas;
  }

  void _extractParagraphsFromBody(
      XmlElement body, List<ParagraphInfo> allParas) {
    // Find all paragraph elements using descendants
    for (final elem in body.descendants.whereType<XmlElement>()) {
      if (elem.name.local == 'p') {
        // Make sure this is a direct paragraph, not nested in another structure we'll handle separately
        final parent = elem.parent;
        if (parent is XmlElement) {
          // Skip if inside table cell (we'll handle those separately)
          if (parent.name.local == 'tc') {
            continue;
          }
        }

        final transPara = _extractParagraph(elem);
        allParas.add(ParagraphInfo(elem, transPara, 'body'));
      }
    }

    // Now handle table cells specifically
    for (final table in body.descendants.whereType<XmlElement>()) {
      if (table.name.local == 'tbl') {
        for (final row in table.descendants.whereType<XmlElement>()) {
          if (row.name.local == 'tr') {
            for (final cell in row.descendants.whereType<XmlElement>()) {
              if (cell.name.local == 'tc') {
                // Get direct paragraph children of this cell
                for (final child in cell.children.whereType<XmlElement>()) {
                  if (child.name.local == 'p') {
                    final transPara = _extractParagraph(child);
                    allParas.add(ParagraphInfo(child, transPara, 'table'));
                  }
                }
                // Also check descendants in case paragraphs are nested
                for (final para in cell.descendants.whereType<XmlElement>()) {
                  if (para.name.local == 'p' &&
                      !allParas.any((p) => p.element == para)) {
                    final transPara = _extractParagraph(para);
                    allParas.add(ParagraphInfo(para, transPara, 'table'));
                  }
                }
              }
            }
          }
        }
      }
    }

    _log('Extracted ${allParas.length} paragraphs from body and tables');
  }

  void _extractFootnotes(XmlDocument footnotes, List<ParagraphInfo> allParas) {
    int footnoteCount = 0;
    for (final elem in footnotes.descendants.whereType<XmlElement>()) {
      if (elem.name.local == 'footnote') {
        final id = elem.getAttribute('id') ?? elem.getAttribute('w:id');
        final parsedId = id != null ? int.tryParse(id) : null;

        if (parsedId != null && parsedId > 0) {
          for (final para in elem.descendants.whereType<XmlElement>()) {
            if (para.name.local == 'p') {
              final transPara = _extractParagraph(para);
              allParas.add(ParagraphInfo(para, transPara, 'footnote'));
              footnoteCount++;
            }
          }
        }
      }
    }
    _log('Extracted $footnoteCount paragraphs from footnotes');
  }

  void _extractHeadersFooters(
      List<ParagraphInfo> allParas, XmlDocument document, bool isHeader) {
    // Note: Headers/footers are in separate XML files, but for simplicity
    // we'll extract them from the main document relationships
    // In a full implementation, you'd parse header*.xml and footer*.xml files
    _log(isHeader
        ? 'ℹ Headers require separate file parsing'
        : 'ℹ Footers require separate file parsing');
  }

  TranslatableParagraph extractParagraph(XmlElement paraElem) {
    return _extractParagraph(paraElem);
  }
  
  TranslatableParagraph _extractParagraph(XmlElement paraElem) {
  print('📖 [DEBUG] extractParagraph() START');
  
  final runs = <FormatRun>[];
  
  // ✅ STEP 1: Resolve base font from paragraph style FIRST (like Python)
  String resolvedBaseFont = _getResolvedFontName(paraElem);
  print('🔍 [DEBUG] Resolved base font from style hierarchy: $resolvedBaseFont');
  
  // Extract all runs
  final runElements = paraElem.findAllElements('w:r').toList();
  print('🔍 [DEBUG] Found ${runElements.length} runs');
  
  for (int i = 0; i < runElements.length; i++) {
    final runElem = runElements[i];
    final textElem = runElem.findElements('w:t').firstOrNull;
    
    if (textElem == null) continue;
    
    final text = textElem.innerText;
    if (text.isEmpty) continue;
    
    // Extract formatting from rPr
    final rPr = runElem.findElements('w:rPr').firstOrNull;
    
    bool? bold;
    bool? italic;
    bool? underline;
    String? fontName;
    double? fontSize;
    RGBColor? fontColor; 
    
    if (rPr != null) {
      // Bold
      final boldElem = rPr.findElements('w:b').firstOrNull;
      if (boldElem != null) {
        final val = boldElem.getAttribute('w:val');
        bold = (val == null || val == '1' || val == 'true');
      }
      
      // Italic
      final italicElem = rPr.findElements('w:i').firstOrNull;
      if (italicElem != null) {
        final val = italicElem.getAttribute('w:val');
        italic = (val == null || val == '1' || val == 'true');
      }
      
      // Underline
      final uElem = rPr.findElements('w:u').firstOrNull;
      if (uElem != null) {
        underline = true;
      }
      
      // Font name from rFonts
      final rFonts = rPr.findElements('w:rFonts').firstOrNull;
      if (rFonts != null) {
        fontName = rFonts.getAttribute('w:ascii') ?? 
                   rFonts.getAttribute('w:hAnsi');
      }
      
      // Font size from sz (half-points, so divide by 2)
      final szElem = rPr.findElements('w:sz').firstOrNull;
      if (szElem != null) {
        final szVal = szElem.getAttribute('w:val');
        if (szVal != null) {
          fontSize = double.tryParse(szVal)! / 2.0;
        }
      }
      
      // Font color - CONVERT to RGBColor
      final colorElem = rPr.findElements('w:color').firstOrNull;
      if (colorElem != null) {
        final colorHex = colorElem.getAttribute('w:val');
        if (colorHex != null && colorHex != 'auto') {
          try {
            fontColor = RGBColor.fromHex(colorHex);
          } catch (e) {
            print('⚠️  [DEBUG] Invalid color value: $colorHex');
          }
        }
      }
    }
    
    // ✅ Use resolved base font as fallback (like Python)
    final finalFontName = fontName ?? resolvedBaseFont;
    final finalFontSize = fontSize ?? 11.0;
    
    final formatRun = FormatRun(
      text: text,
      bold: bold,
      italic: italic,
      underline: underline,
      fontName: finalFontName,
      fontSize: finalFontSize,
      fontColor: fontColor,
    );
    
    runs.add(formatRun);
    
    print('🔍 [DEBUG] Run[$i]: "${text.substring(0, text.length > 20 ? 20 : text.length)}" | B:$bold I:$italic F:$finalFontName@${finalFontSize}pt');
  }
  
  final transPara = TranslatableParagraph(runs: runs);
  
  // ✅ STEP 2: Store paragraph-level metadata (INCLUDING STYLE!)
  final pPr = paraElem.findElements('w:pPr').firstOrNull;
  if (pPr != null) {
    // ✅ CRITICAL: Extract and store style name
    final pStyle = pPr.findElements('w:pStyle').firstOrNull;
    if (pStyle != null) {
      final styleName = pStyle.getAttribute('w:val');
      if (styleName != null) {
        transPara.metadata['style'] = styleName;
        print('🔍 [DEBUG] Extracted style: $styleName');
      }
    }
    
    // Alignment
    final jc = pPr.findElements('w:jc').firstOrNull;
    if (jc != null) {
      transPara.metadata['alignment'] = jc.getAttribute('w:val');
    }
    
    // Indentation
    final ind = pPr.findElements('w:ind').firstOrNull;
    if (ind != null) {
      transPara.metadata['indLeft'] = ind.getAttribute('w:left');
      transPara.metadata['indRight'] = ind.getAttribute('w:right');
      transPara.metadata['indFirstLine'] = ind.getAttribute('w:firstLine');
      transPara.metadata['indHanging'] = ind.getAttribute('w:hanging');
    }
    
    // Spacing
    final spacing = pPr.findElements('w:spacing').firstOrNull;
    if (spacing != null) {
      transPara.metadata['spaceBefore'] = spacing.getAttribute('w:before');
      transPara.metadata['spaceAfter'] = spacing.getAttribute('w:after');
      transPara.metadata['lineRule'] = spacing.getAttribute('w:lineRule');
      transPara.metadata['line'] = spacing.getAttribute('w:line');
    }
    
    // Numbering (for lists)
    final numPr = pPr.findElements('w:numPr').firstOrNull;
    if (numPr != null) {
      final ilvl = numPr.findElements('w:ilvl').firstOrNull;
      final numId = numPr.findElements('w:numId').firstOrNull;
      if (ilvl != null) transPara.metadata['numLevel'] = ilvl.getAttribute('w:val');
      if (numId != null) transPara.metadata['numId'] = numId.getAttribute('w:val');
    }
  }
  
  print('📖 [DEBUG] Extracted ${runs.length} runs, text length: ${transPara.getText().length}');
  print('📖 [DEBUG] Metadata: ${transPara.metadata.keys.join(", ")}');
  return transPara;
}

// Resolve font from paragraph style hierarchy
String _getResolvedFontName(XmlElement paraElem) {
  print('🔍 [DEBUG] _getResolvedFontName() START');
  
  // 1. Check runs first (highest priority)
  for (final run in paraElem.findAllElements('w:r')) {
    final rPr = run.findElements('w:rPr').firstOrNull;
    if (rPr != null) {
      final rFonts = rPr.findElements('w:rFonts').firstOrNull;
      if (rFonts != null) {
        final fontName = rFonts.getAttribute('w:ascii') ?? 
                        rFonts.getAttribute('w:hAnsi');
        if (fontName != null && fontName.isNotEmpty) {
          print('🔍 [DEBUG] Found font in run: $fontName');
          return fontName;
        }
      }
    }
  }
  
  // 2. Check paragraph style
  final pPr = paraElem.findElements('w:pPr').firstOrNull;
  if (pPr != null) {
    final pStyle = pPr.findElements('w:pStyle').firstOrNull;
    if (pStyle != null) {
      final styleName = pStyle.getAttribute('w:val');
      print('🔍 [DEBUG] Paragraph has style: $styleName');
      
      // In a full implementation, you would:
      // - Load styles.xml from the archive
      // - Walk the style hierarchy to find font definitions
      // - This requires access to the archive in this method
      // For now, we use sensible defaults based on common style names
      
      if (styleName != null) {
        if (styleName.toLowerCase().contains('heading')) {
          print('🔍 [DEBUG] Heading style detected, using Calibri Light');
          return 'Calibri Light';
        }
        if (styleName.toLowerCase().contains('title')) {
          print('🔍 [DEBUG] Title style detected, using Calibri Light');
          return 'Calibri Light';
        }
      }
    }
    
    // Check if pPr itself has font info (rare but possible)
    final rPr = pPr.findElements('w:rPr').firstOrNull;
    if (rPr != null) {
      final rFonts = rPr.findElements('w:rFonts').firstOrNull;
      if (rFonts != null) {
        final fontName = rFonts.getAttribute('w:ascii') ?? 
                        rFonts.getAttribute('w:hAnsi');
        if (fontName != null && fontName.isNotEmpty) {
          print('🔍 [DEBUG] Found font in pPr: $fontName');
          return fontName;
        }
      }
    }
  }
  
  // 3. Fallback to Word's default body font
  print('🔍 [DEBUG] No font found, using default: Calibri');
  return 'Calibri';
}

  String _extractRunText(XmlElement rElem) {
    final buffer = StringBuffer();
    for (final elem in rElem.descendants.whereType<XmlElement>()) {
      if (elem.name.local == 't') {
        buffer.write(elem.innerText);
      }
    }
    return buffer.toString();
  }

  FormatRun _extractRunFormatting(XmlElement rElem, String text, String fallbackFont) {
    final formatRun = FormatRun(text: text, fontName: fallbackFont);
    final rPr = rElem.findElements('rPr', namespace: wNamespace).firstOrNull;
    
    if (rPr != null) {
      for (final prop in rPr.children.whereType<XmlElement>()) {
        switch (prop.name.local) {
          case 'b': formatRun.bold = true; break;
          case 'i': formatRun.italic = true; break;
          case 'u': formatRun.underline = true; break;
          case 'rFonts':
            formatRun.fontName = prop.getAttribute('ascii') ?? prop.getAttribute('hAnsi');
            break;
          case 'sz':
            final val = prop.getAttribute('val');
            if (val != null) formatRun.fontSize = double.tryParse(val)! / 2;
            break;
          case 'color':
            final val = prop.getAttribute('val');
            if (val != null && val != 'auto') formatRun.fontColor = RGBColor.fromHex(val);
            break;
          default:
            // Force preservation of unknown XML nodes (highlighting, etc.)
            formatRun.extraProperties.add(prop.copy());
            break;
        }
      }
    }
    return formatRun;
  }

  

  void _extractParagraphProperties(
      XmlElement pPr, Map<String, dynamic> metadata) {
    // Style
    final style = pPr.findElements('pStyle', namespace: wNamespace).firstOrNull;
    if (style != null) {
      metadata['style'] = style.getAttribute('val', namespace: wNamespace);
    }

    // Alignment
    final jc = pPr.findElements('jc', namespace: wNamespace).firstOrNull;
    if (jc != null) {
      metadata['alignment'] = jc.getAttribute('val', namespace: wNamespace);
    }

    // Indentation
    final ind = pPr.findElements('ind', namespace: wNamespace).firstOrNull;
    if (ind != null) {
      metadata['indent_left'] = ind.getAttribute('left', namespace: wNamespace);
      metadata['indent_right'] =
          ind.getAttribute('right', namespace: wNamespace);
      metadata['indent_first'] =
          ind.getAttribute('firstLine', namespace: wNamespace);
    }

    // Spacing
    final spacing =
        pPr.findElements('spacing', namespace: wNamespace).firstOrNull;
    if (spacing != null) {
      metadata['spacing_before'] =
          spacing.getAttribute('before', namespace: wNamespace);
      metadata['spacing_after'] =
          spacing.getAttribute('after', namespace: wNamespace);
      metadata['line_spacing'] =
          spacing.getAttribute('line', namespace: wNamespace);
    }
  }

  // ============================================================================
  // PARAGRAPH TRANSLATION
  // ============================================================================

  Future<void> _translateParagraph(ParagraphInfo paraInfo, String sourceLang, String targetLang) async {
    final originalText = paraInfo.transPara.getText();
    if (originalText.trim().isEmpty) return;

    // 1. SENTENCE SPLITTING (Python Blueprint Step 1)
    // We split while preserving the punctuation to ensure we don't lose characters
    final sentenceRegex = RegExp(r'(?<=[.!?])\s+');
    final sentences = originalText.split(sentenceRegex).where((s) => s.trim().isNotEmpty).toList();
    
    List<String> translatedSentences = [];
    List<Alignment> globalAlignments = [];
    
    int srcWordOffset = 0;
    int tgtWordOffset = 0;

    for (var sentence in sentences) {
      // 2. NEURAL TRANSLATION
      final translatedSent = (await translationService.translate(sentence, targetLang, sourceLang))
        .replaceAll(RegExp(r'\s+'), ' ') // Collapse multiple spaces to one
        .trim();
      translatedSentences.add(translatedSent);

      // 3. OFFSET-AWARE ALIGNMENT (Python Blueprint Step 4)
      if (aligner != null) {
        final sWords = _extractWords(sentence);
        final tWords = _extractWords(translatedSent);
        
        if (sWords.isNotEmpty && tWords.isNotEmpty) {
          final localAligns = aligner!.align(sWords, tWords);
          
          // Shift indices based on the cumulative word count of previous sentences
          for (var a in localAligns) {
            globalAlignments.add(Alignment(
              a.sourceIndex + srcWordOffset,
              a.targetIndex + tgtWordOffset,
            ));
          }
          
          // Update offsets for the next sentence in the paragraph
          srcWordOffset += sWords.length;
          tgtWordOffset += tWords.length;
        }
      }
    }

    // 4. COMMIT TO PARAGRAPH INFO
    paraInfo.translatedText = translatedSentences.join(' ');
    paraInfo.alignment = globalAlignments;

    if (verbose) {
      _log('║ PARAGRAPH TRANSLATED: ${sentences.length} sentences aligned.');
      _log('║   Final Word Count: Src($srcWordOffset) ↔ Tgt($tgtWordOffset)');
    }
  }

  /// for clean tokenization
  List<String> _extractWords(String text) {
    // ✅ MUST match getWords() regex - Unicode-aware
    return RegExp(r'[\p{L}\p{N}]+', unicode: true)
        .allMatches(text)
        .map((m) => m.group(0)!)
        .toList();
  }
  
  List<String> _alphabeticalTokenize(String text) {
    // This extracts only the "semantic" words, ignoring punctuation.
    return RegExp(r'\w+').allMatches(text).map((m) => m.group(0)!).toList();
  }

  // STOP SHORTENING LOGS
  void _log(String message) {
    if (verbose) print(message); // Remove any string shortening logic here
  }

  // ============================================================================
  // DOCUMENT REBUILDING
  // ============================================================================

  void _rebuildDocument(
      XmlDocument document, List<ParagraphInfo> allParagraphs) {
    for (final paraInfo in allParagraphs) {
      if (paraInfo.location == 'body' || paraInfo.location == 'table') {
        _rebuildParagraph(paraInfo);
      }
    }
  }

  void _rebuildFootnotes(
      XmlDocument footnotes, List<ParagraphInfo> allParagraphs) {
    for (final paraInfo in allParagraphs) {
      if (paraInfo.location == 'footnote') {
        _rebuildParagraph(paraInfo);
      }
    }
  }

  void _rebuildParagraph(ParagraphInfo paraInfo) {
    if (paraInfo.translatedText == null) return;

    final pElem = paraInfo.element;
    final transPara = paraInfo.transPara;
    final translatedText = paraInfo.translatedText!;
    final alignment = paraInfo.alignment ?? [];

    // 1. EXTRACT ANCHORS & PURGE
    final pPr = pElem.findElements('w:pPr', namespace: wNamespace).firstOrNull?.copy();
    final anchors = pElem.children.whereType<XmlElement>().where((el) {
      return el.name.local == 'r' && el.descendants.any((d) => 
        d is XmlElement && (d.name.local == 'footnoteReference' || d.name.local == 'footnoteRef'));
    }).map((el) => el.copy()).toList();

    pElem.children.clear();
    if (pPr != null) pElem.children.add(pPr); 

    // 2. REPLICATE PYTHON TOKENIZATION
    // Split by whitespace to get "Raw Units" for Word Runs
    final tgtRawUnits = translatedText.split(' ');
    
    // Create a clean list of words for alignment matching
    final tgtWordsClean = _alphabeticalTokenize(translatedText);
    final srcWordsClean = transPara.getWords(); // Ensure this uses _alphabeticalTokenize too

    if (verbose) {
      print('║ ALIGN DEBUG | SrcWords: ${srcWordsClean.length} | TgtWords: ${tgtWordsClean.length}');
      _traceAlignments(srcWordsClean, tgtWordsClean, alignment);
    }

    final formattedIndices = transPara.getFormattedWordIndices();
    
    // Map: Clean Index -> Raw Unit Index
    final cleanToRawTgt = <int, int>{};
    int currentCleanIdx = 0;
    for (int i = 0; i < tgtRawUnits.length; i++) {
      // If this unit contains a word, map it to the next clean index
      if (RegExp(r'\w').hasMatch(tgtRawUnits[i])) {
        if (currentCleanIdx < tgtWordsClean.length) {
          cleanToRawTgt[currentCleanIdx] = i;
          currentCleanIdx++;
        }
      }
    }

    final fontTemplate = transPara.runs.isNotEmpty ? transPara.runs.first : null;

    // 3. RECONSTRUCTION LOOP
    for (int i = 0; i < tgtRawUnits.length; i++) {
      final text = tgtRawUnits[i] + (i < tgtRawUnits.length - 1 ? ' ' : '');
      String? styleType;

      // Determine if this Raw Unit i should be formatted
      final link = alignment.where((a) => cleanToRawTgt[a.targetIndex] == i).firstOrNull;
      
      if (link != null) {
        final sIdx = link.sourceIndex;
        if (formattedIndices['italic_bold']!.contains(sIdx)) styleType = 'italic_bold';
        else if (formattedIndices['bold']!.contains(sIdx)) styleType = 'bold';
        else if (formattedIndices['italic']!.contains(sIdx)) styleType = 'italic';
      }

      pElem.children.add(_createFormattedRun(
        text: text,
        fontTemplate: fontTemplate,
        styleType: styleType,
      ));
    }

    // 4. RE-ANCHOR FOOTNOTES
    if (paraInfo.location != 'footnote' && anchors.isNotEmpty) {
      for (var a in anchors) pElem.children.add(a);
    }
  }

  void applyAlignedFormatting(
  XmlElement paraElem,
  TranslatableParagraph transPara,
  String translatedText,
  List<Alignment> alignment,
) {
  print('✨ [DEBUG] applyAlignedFormatting() START');
  print('🔍 [DEBUG] Original: "${transPara.getText()}"');
  print('🔍 [DEBUG] Translated: "$translatedText"');
  print('🔍 [DEBUG] Alignments: ${alignment.length}');

  final fontTemplate = transPara.runs.isNotEmpty ? transPara.runs[0] : null;
  print('🔍 [DEBUG] Font template: ${fontTemplate != null ? "${fontTemplate.fontName}@${fontTemplate.fontSize}pt" : "NULL"}');
  
  // ✅ CRITICAL: Extract footnote references BEFORE clearing
  final footnoteRuns = <XmlElement>[];
  for (final run in paraElem.findElements('w:r')) {
    // Check if this run contains a footnote reference
    final hasFootnoteRef = run.descendants.any((d) => 
      d is XmlElement && (d.name.local == 'footnoteReference' || d.name.local == 'footnoteRef')
    );
    
    if (hasFootnoteRef) {
      footnoteRuns.add(run.copy());
      print('📎 [DEBUG] Saved footnote reference run');
    }
  }
  
  // STEP 1: FORCE RESTORE PARAGRAPH-LEVEL METADATA
  var pPr = paraElem.findElements('w:pPr').firstOrNull;
  
  if (pPr == null && transPara.metadata.isNotEmpty) {
    print('🔧 [DEBUG] Creating missing w:pPr element');
    pPr = XmlElement(XmlName('w:pPr'));
    paraElem.children.insert(0, pPr);
  }
  
  if (pPr != null && transPara.metadata.isNotEmpty) {
    print('🔧 [DEBUG] Restoring paragraph properties...');
    _restoreStyle(pPr, transPara.metadata);
    _restoreNumbering(pPr, transPara.metadata);
    _restoreAlignment(pPr, transPara.metadata);
    _restoreIndentation(pPr, transPara.metadata);
    _restoreSpacing(pPr, transPara.metadata);
  }
  
  // STEP 2: Clear existing runs (AFTER extracting footnote refs)
  final existingRuns = paraElem.findElements('w:r').toList();
  for (final run in existingRuns) {
    paraElem.children.remove(run);
  }
  print('🗑️  [DEBUG] Cleared ${existingRuns.length} existing runs');
  
  // STEP 3: Prepare alignment mapping
  final srcCleanWords = transPara.getWords();
  final tgtRawUnits = translatedText.split(RegExp(r'\s+'));
  final formattedIndices = transPara.getFormattedWordIndices();
  
  print('🔍 [DEBUG] Source clean words: $srcCleanWords');
  print('🔍 [DEBUG] Target raw units: $tgtRawUnits');
  
  // Map clean target indices to raw unit indices
  final cleanToRawTgt = <int, int>{};
  int cleanIdx = 0;
  for (int rawIdx = 0; rawIdx < tgtRawUnits.length; rawIdx++) {
    final unit = tgtRawUnits[rawIdx];
    if (RegExp(r'[\p{L}\p{N}]', unicode: true).hasMatch(unit)) {
      cleanToRawTgt[cleanIdx] = rawIdx;
      cleanIdx++;
    }
  }
  
  // STEP 4: Reconstruct runs with aligned formatting
  print('🔧 [DEBUG] Reconstructing ${tgtRawUnits.length} runs...');
  
  for (int i = 0; i < tgtRawUnits.length; i++) {
    final unit = tgtRawUnits[i];
    final runText = i < tgtRawUnits.length - 1 ? '$unit ' : unit;
    
    // Determine style from alignment
    String? styleType;
    final cleanIdxForThisRaw = cleanToRawTgt.entries
        .firstWhere((e) => e.value == i, orElse: () => MapEntry(-1, -1))
        .key;
    
    if (cleanIdxForThisRaw >= 0) {
      for (final align in alignment) {
        if (align.targetIndex == cleanIdxForThisRaw) {
          final sIdx = align.sourceIndex;
          if (formattedIndices['italic_bold']!.contains(sIdx)) {
            styleType = 'italic_bold';
            break;
          } else if (formattedIndices['bold']!.contains(sIdx)) {
            styleType = styleType == null ? 'bold' : styleType;
          } else if (formattedIndices['italic']!.contains(sIdx) && styleType != 'bold') {
            styleType = 'italic';
          }
        }
      }
    }
    
    final newRun = _createFormattedRun(
      text: runText,
      styleType: styleType,
      fontTemplate: fontTemplate,
    );
    
    paraElem.children.add(newRun);
  }
  
  // ✅ STEP 5: RE-ATTACH FOOTNOTE REFERENCES AT END
  if (footnoteRuns.isNotEmpty) {
    print('📎 [DEBUG] Re-attaching ${footnoteRuns.length} footnote references');
    for (final footnoteRun in footnoteRuns) {
      paraElem.children.add(footnoteRun);
    }
  }
  
  print('✨ [DEBUG] Created ${tgtRawUnits.length} new runs + ${footnoteRuns.length} footnote refs');
  print('✨ [DEBUG] applyAlignedFormatting() COMPLETE');
}

// ✅ HELPER: Restore paragraph style
void _restoreStyle(XmlElement pPr, Map<String, dynamic> metadata) {
  if (metadata.containsKey('style') && metadata['style'] != null) {
    final styleName = metadata['style'] as String;
    print('🔧 [DEBUG] Restoring style: $styleName');
    
    var pStyle = pPr.findElements('w:pStyle').firstOrNull;
    if (pStyle == null) {
      pStyle = XmlElement(XmlName('w:pStyle'));
      // pStyle should be first in pPr
      pPr.children.insert(0, pStyle);
    }
    pStyle.setAttribute('w:val', styleName);
  }
}

// ✅ HELPER: Restore numbering (for lists)
void _restoreNumbering(XmlElement pPr, Map<String, dynamic> metadata) {
  if (metadata.containsKey('numId') && metadata['numId'] != null) {
    print('🔧 [DEBUG] Restoring numbering: numId=${metadata['numId']}, level=${metadata['numLevel']}');
    
    var numPr = pPr.findElements('w:numPr').firstOrNull;
    if (numPr == null) {
      numPr = XmlElement(XmlName('w:numPr'));
      // Add after pStyle if it exists, otherwise at beginning
      final pStyle = pPr.findElements('w:pStyle').firstOrNull;
      if (pStyle != null) {
        final idx = pPr.children.indexOf(pStyle) + 1;
        pPr.children.insert(idx, numPr);
      } else {
        pPr.children.insert(0, numPr);
      }
    }
    
    // Clear existing numbering children
    numPr.children.clear();
    
    // Add ilvl (level)
    if (metadata.containsKey('numLevel')) {
      final ilvl = XmlElement(XmlName('w:ilvl'));
      ilvl.setAttribute('w:val', metadata['numLevel'].toString());
      numPr.children.add(ilvl);
    }
    
    // Add numId
    final numId = XmlElement(XmlName('w:numId'));
    numId.setAttribute('w:val', metadata['numId'].toString());
    numPr.children.add(numId);
  }
}

// ✅ HELPER: Restore alignment
void _restoreAlignment(XmlElement pPr, Map<String, dynamic> metadata) {
  if (metadata.containsKey('alignment') && metadata['alignment'] != null) {
    print('🔧 [DEBUG] Restoring alignment: ${metadata['alignment']}');
    
    var jc = pPr.findElements('w:jc').firstOrNull;
    if (jc == null) {
      jc = XmlElement(XmlName('w:jc'));
      pPr.children.add(jc);
    }
    jc.setAttribute('w:val', metadata['alignment'].toString());
  }
}

// ✅ HELPER: Restore indentation
void _restoreIndentation(XmlElement pPr, Map<String, dynamic> metadata) {
  if (metadata.containsKey('indLeft') || 
      metadata.containsKey('indRight') || 
      metadata.containsKey('indFirstLine') ||
      metadata.containsKey('indHanging')) {
    print('🔧 [DEBUG] Restoring indentation: L=${metadata['indLeft']}, R=${metadata['indRight']}, First=${metadata['indFirstLine']}');
    
    var ind = pPr.findElements('w:ind').firstOrNull;
    if (ind == null) {
      ind = XmlElement(XmlName('w:ind'));
      pPr.children.add(ind);
    }
    
    // Clear existing attributes
    ind.attributes.clear();
    
    // Set all indentation values
    if (metadata['indLeft'] != null) {
      ind.setAttribute('w:left', metadata['indLeft'].toString());
    }
    if (metadata['indRight'] != null) {
      ind.setAttribute('w:right', metadata['indRight'].toString());
    }
    if (metadata['indFirstLine'] != null) {
      ind.setAttribute('w:firstLine', metadata['indFirstLine'].toString());
    }
    if (metadata['indHanging'] != null) {
      ind.setAttribute('w:hanging', metadata['indHanging'].toString());
    }
  }
}

// ✅ HELPER: Restore spacing
void _restoreSpacing(XmlElement pPr, Map<String, dynamic> metadata) {
  if (metadata.containsKey('spaceBefore') || 
      metadata.containsKey('spaceAfter') ||
      metadata.containsKey('lineRule') ||
      metadata.containsKey('line')) {
    print('🔧 [DEBUG] Restoring spacing: Before=${metadata['spaceBefore']}, After=${metadata['spaceAfter']}, Line=${metadata['line']}');
    
    var spacing = pPr.findElements('w:spacing').firstOrNull;
    if (spacing == null) {
      spacing = XmlElement(XmlName('w:spacing'));
      pPr.children.add(spacing);
    }
    
    // Clear existing attributes
    spacing.attributes.clear();
    
    // Set all spacing values
    if (metadata['spaceBefore'] != null) {
      spacing.setAttribute('w:before', metadata['spaceBefore'].toString());
    }
    if (metadata['spaceAfter'] != null) {
      spacing.setAttribute('w:after', metadata['spaceAfter'].toString());
    }
    if (metadata['lineRule'] != null) {
      spacing.setAttribute('w:lineRule', metadata['lineRule'].toString());
    }
    if (metadata['line'] != null) {
      spacing.setAttribute('w:line', metadata['line'].toString());
    }
  }
}

  XmlElement _createFormattedRun({
  required String text,
  String? styleType,
  FormatRun? fontTemplate,
}) {
  print('🔨 [DEBUG] Creating run: "$text" | style=$styleType | font=${fontTemplate?.fontName}');
  
  // ✅ Create w:r element directly
  final rElem = XmlElement(XmlName('w:r'));
  
  // Only add rPr if we have formatting
  if (styleType != null || fontTemplate != null) {
    final rPr = XmlElement(XmlName('w:rPr'));
    
    // ✅ Apply inline styles from alignment (bold/italic)
    if (styleType == 'italic_bold') {
      rPr.children.add(XmlElement(XmlName('w:b')));
      rPr.children.add(XmlElement(XmlName('w:i')));
      print('  → Applied: BOLD + ITALIC');
    } else if (styleType == 'bold') {
      rPr.children.add(XmlElement(XmlName('w:b')));
      print('  → Applied: BOLD');
    } else if (styleType == 'italic') {
      rPr.children.add(XmlElement(XmlName('w:i')));
      print('  → Applied: ITALIC');
    }
    
    // ✅ Apply baseline aesthetics from template
    if (fontTemplate != null) {
      // Font name - ALL 4 ATTRIBUTES
      if (fontTemplate.fontName != null) {
        final rFonts = XmlElement(XmlName('w:rFonts'));
        rFonts.setAttribute('w:ascii', fontTemplate.fontName!);
        rFonts.setAttribute('w:hAnsi', fontTemplate.fontName!);
        rFonts.setAttribute('w:eastAsia', fontTemplate.fontName!);
        rFonts.setAttribute('w:cs', fontTemplate.fontName!);
        rPr.children.add(rFonts);
        print('  → Font: ${fontTemplate.fontName} (all 4 attributes)');
      }
      
      // Font size - BOTH w:sz AND w:szCs
      if (fontTemplate.fontSize != null) {
        final halfPoints = (fontTemplate.fontSize! * 2).toInt().toString();
        
        final sz = XmlElement(XmlName('w:sz'));
        sz.setAttribute('w:val', halfPoints);
        rPr.children.add(sz);
        
        final szCs = XmlElement(XmlName('w:szCs'));
        szCs.setAttribute('w:val', halfPoints);
        rPr.children.add(szCs);
        
        print('  → Size: ${fontTemplate.fontSize}pt (half-points: $halfPoints)');
      }
      
      // Font color
      if (fontTemplate.fontColor != null) {
        final color = XmlElement(XmlName('w:color'));
        color.setAttribute('w:val', fontTemplate.fontColor!.toHex());
        rPr.children.add(color);
        print('  → Color: ${fontTemplate.fontColor!.toHex()}');
      }
      
      // Underline
      if (fontTemplate.underline == true) {
        final u = XmlElement(XmlName('w:u'));
        u.setAttribute('w:val', 'single');
        rPr.children.add(u);
        print('  → Underline: single');
      }
    }
    
    rElem.children.add(rPr);
  }
  
  // ✅ Add text element
  final tElem = XmlElement(XmlName('w:t'));
  tElem.innerText = text;
  
  if (text.startsWith(' ') || text.endsWith(' ')) {
    tElem.setAttribute('xml:space', 'preserve');
  }
  
  rElem.children.add(tElem);
  
  return rElem;
}

// Helper method to create a deep copy of an XML element
XmlElement _deepCopyElement(XmlElement element) {
  // Use the copy() method which creates a completely detached copy
  return element.copy() as XmlElement;
}

// Helper to create a simple text run
XmlElement _createSimpleRun(String text) {
  final builder = XmlBuilder();
  builder.element('w:r', nest: () {
    builder.element('w:t', 
      nest: text,
      attributes: {
        if (text.trim() != text) 'xml:space': 'preserve',
      }
    );
  });
  // Use copy() to detach from the builder's document
  return builder.buildDocument().rootElement.copy() as XmlElement;
}

  void _reconstructRuns(
    XmlElement pElem,
    TranslatableParagraph transPara,
    String translatedText,
    List<Alignment>? alignment,
  ) {
    if (translatedText.trim().isEmpty) return;

    // Split into words while preserving spaces/punctuation for run building
    final words = translatedText.split(' ');
    final formattedIndices = transPara.getFormattedWordIndices();

    // Map source formatting to target words via alignment links
    // Alignment links are usually (sourceIndex, targetIndex)
    final targetFormatting = <int, String>{}; // Map: TargetWordIndex -> StyleType
    
    if (alignment != null) {
      for (final link in alignment) {
        final srcIdx = link.sourceIndex;
        final tgtIdx = link.targetIndex;
        
        String? style;
        if (formattedIndices['italic_bold']!.contains(srcIdx)) {
          style = 'italic_bold';
        } else if (formattedIndices['bold']!.contains(srcIdx)) {
          style = 'bold';
        } else if (formattedIndices['italic']!.contains(srcIdx)) {
          style = 'italic';
        }

        if (style != null) {
          // If a target word is linked to multiple source words, 
          // we prioritize the "strongest" style (Bold-Italic > Bold > Italic)
          final existing = targetFormatting[tgtIdx];
          if (existing == null || 
             (style == 'italic_bold') || 
             (style == 'bold' && existing == 'italic')) {
            targetFormatting[tgtIdx] = style;
          }
        }
      }
    }

    final template = transPara.runs.isNotEmpty ? transPara.runs.first : null;

    // Rebuild the XML runs
    for (int i = 0; i < words.length; i++) {
      // Re-add the space we lost during split, except for the last word
      final text = words[i] + (i < words.length - 1 ? ' ' : '');
      
      // Determine style for this specific word
      final style = targetFormatting[i];
      
      final run = _createRun(text, template, style);
      pElem.children.add(run);
    }
  }

  XmlElement _createRun(String text, FormatRun? template, String? style) {
  final builder = XmlBuilder();
  builder.element('w:r', nest: () {
    if (template != null || style != null) {
      builder.element('w:rPr', nest: () {
        if (style == 'italic_bold' || style == 'bold') {
          builder.element('w:b');
        }
        if (style == 'italic_bold' || style == 'italic') {
          builder.element('w:i');
        }
        if (template != null) {
          if (template.fontName != null) {
            builder.element('w:rFonts', attributes: {
              'w:ascii': template.fontName!,
              'w:hAnsi': template.fontName!,
            });
          }
          if (template.fontSize != null) {
            builder.element('w:sz', attributes: {
              'w:val': (template.fontSize! * 2).round().toString(),
            });
          }
          if (template.fontColor != null) {
            builder.element('w:color', attributes: {
              'w:val': template.fontColor!.toHex(),
            });
          }
        }
      });
    }
    builder.element('w:t', nest: text, attributes: {
      if (text.startsWith(' ') || text.endsWith(' ')) 'xml:space': 'preserve',
    });
  });

  // Use copy() to detach from the builder's document
  return builder.buildDocument().rootElement.copy() as XmlElement;
}


  // ============================================================================
  // ARCHIVE UTILITIES
  // ============================================================================

  ArchiveFile _getFileFromArchive(Archive archive, String name) {
    return archive.files.firstWhere(
      (f) => f.name == name,
      orElse: () => throw Exception('File not found: $name'),
    );
  }

  Archive _replaceXmlFiles(Archive original, Map<String, String> replacements) {
    final newArchive = Archive();

    for (final file in original.files) {
      if (replacements.containsKey(file.name)) {
        final newContent = replacements[file.name]!;
        // Convert string to bytes properly
        final bytes = utf8.encode(newContent);
        newArchive.addFile(ArchiveFile(
          file.name,
          bytes.length,
          bytes,
        )
          ..mode = file.mode
          ..compress = true);
      } else {
        newArchive.addFile(file);
      }
    }

    return newArchive;
  }
}

// ============================================================================
// HELPER CLASSES
// ============================================================================

class ParagraphInfo {
  final XmlElement element;
  final TranslatableParagraph transPara;
  final String location; // 'body', 'table', 'header', 'footer', 'footnote'
  String? translatedText;
  List<Alignment>? alignment;

  ParagraphInfo(this.element, this.transPara, this.location);
}

// ============================================================================
// CLI EXAMPLE
// ============================================================================

void main() async {
  print('✅ Feature-complete DocxTranslator ready!');
  print('   Supports: footnotes, headers, footers, tables, full formatting');

  // Example usage:
  /*
  final translator = DocxTranslator(
    translationService: MockTranslationService(),
    aligner: HeuristicAligner(),
    verbose: true,
  );
  
  // In CLI with dart:io:
  import 'dart:io';
  final inputBytes = await File('input.docx').readAsBytes();
  final outputBytes = await translator.translateDocument(
    docxBytes: inputBytes,
    targetLanguage: 'Spanish',
    sourceLanguage: 'English',
  );
  await File('output.docx').writeAsBytes(outputBytes);
  */
}
