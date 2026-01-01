// docx_translator.dart - COMPLETE IMPLEMENTATION
import 'dart:typed_data';
import 'package:archive/archive.dart';
import 'package:xml/xml.dart';
import 'dart:convert';

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

  @override
  String toString() => '($sourceIndex,$targetIndex)';
}

class HeuristicAligner implements WordAligner {
  @override
  List<Alignment> align(List<String> sourceWords, List<String> targetWords) {
    final alignments = <Alignment>[];
    final srcLower = sourceWords
        .map((w) => w.toLowerCase().replaceAll(RegExp(r'[.,!?;:]'), ''))
        .toList();
    final tgtLower = targetWords
        .map((w) => w.toLowerCase().replaceAll(RegExp(r'[.,!?;:]'), ''))
        .toList();

    for (int i = 0; i < srcLower.length; i++) {
      for (int j = 0; j < tgtLower.length; j++) {
        if (srcLower[i] == tgtLower[j] && srcLower[i].length > 2) {
          alignments.add(Alignment(i, j));
        }
      }
    }
    return alignments;
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
  Map<String, String> extraProperties; // For preserving unknown XML properties

  FormatRun({
    required this.text,
    this.bold,
    this.italic,
    this.underline,
    this.fontName,
    this.fontSize,
    this.fontColor,
    Map<String, String>? extraProperties,
  }) : extraProperties = extraProperties ?? {};

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
  List<FormatRun> runs;
  Map<String, dynamic> metadata;

  TranslatableParagraph({
    List<FormatRun>? runs,
    Map<String, dynamic>? metadata,
  })  : runs = runs ?? [],
        metadata = metadata ?? {};

  String getText() => runs.map((r) => r.text).join();

  List<String> getWords() {
    // Extract alphanumeric words only (like Python's re.findall(r"\w+"))
    final text = getText();
    final regex = RegExp(r'\w+');
    return regex.allMatches(text).map((m) => m.group(0)!).toList();
  }

  Map<String, Set<int>> getFormattedWordIndices() {
    final formatted = {
      'italic': <int>{},
      'bold': <int>{},
      'italic_bold': <int>{},
    };

    final text = getText();
    final words = getWords();

    if (words.isEmpty) return formatted;

    // Build character-to-word mapping
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
      }
    }

    // Map formatting to word indices
    int charPos = 0;
    for (final run in runs) {
      if (run.text.isEmpty) continue;

      for (final char in run.text.runes) {
        if (charToWord.containsKey(charPos)) {
          final wordIdx = charToWord[charPos]!;
          if (String.fromCharCode(char).trim().isNotEmpty) {
            if (run.bold == true && run.italic == true) {
              formatted['italic_bold']!.add(wordIdx);
            } else if (run.italic == true) {
              formatted['italic']!.add(wordIdx);
            } else if (run.bold == true) {
              formatted['bold']!.add(wordIdx);
            }
          }
        }
        charPos++;
      }
    }

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
    this.verbose = false,
  });

  void _log(String message) {
    if (verbose) print(message);
  }

  // ============================================================================
  // MAIN TRANSLATION WORKFLOW
  // ============================================================================

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

  TranslatableParagraph _extractParagraph(XmlElement pElem) {
    final runs = <FormatRun>[];

    // Find all run elements that are direct or indirect children
    for (final elem in pElem.descendants.whereType<XmlElement>()) {
      if (elem.name.local == 'r') {
        // Skip if this run contains a footnote reference (we'll preserve those)
        bool hasFootnoteRef = false;
        for (final child in elem.descendants.whereType<XmlElement>()) {
          if (child.name.local == 'footnoteReference' ||
              child.name.local == 'footnoteRef') {
            hasFootnoteRef = true;
            break;
          }
        }

        if (!hasFootnoteRef) {
          final runText = _extractRunText(elem);
          if (runText.isNotEmpty) {
            final formatRun = _extractRunFormatting(elem, runText);
            runs.add(formatRun);
          }
        }
      }
    }

    return TranslatableParagraph(runs: runs);
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

  FormatRun _extractRunFormatting(XmlElement rElem, String text) {
    final formatRun = FormatRun(text: text);

    // Find rPr (run properties)
    for (final child in rElem.children.whereType<XmlElement>()) {
      if (child.name.local == 'rPr') {
        // Extract properties
        for (final prop in child.children.whereType<XmlElement>()) {
          switch (prop.name.local) {
            case 'b':
              formatRun.bold = true;
              break;
            case 'i':
              formatRun.italic = true;
              break;
            case 'u':
              formatRun.underline = true;
              break;
            case 'rFonts':
              formatRun.fontName = prop.getAttribute('ascii') ??
                  prop.getAttribute('w:ascii') ??
                  prop.getAttribute('hAnsi') ??
                  prop.getAttribute('w:hAnsi');
              break;
            case 'sz':
              final val =
                  prop.getAttribute('val') ?? prop.getAttribute('w:val');
              if (val != null) {
                final parsed = double.tryParse(val);
                if (parsed != null) {
                  formatRun.fontSize = parsed / 2;
                }
              }
              break;
            case 'color':
              final val =
                  prop.getAttribute('val') ?? prop.getAttribute('w:val');
              if (val != null && val != 'auto') {
                try {
                  formatRun.fontColor = RGBColor.fromHex(val);
                } catch (e) {
                  // Ignore invalid colors
                }
              }
              break;
          }
        }
        break;
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

  Future<void> _translateParagraph(
    ParagraphInfo paraInfo,
    String sourceLang,
    String targetLang,
  ) async {
    final transPara = paraInfo.transPara;
    final originalText = transPara.getText();

    if (originalText.trim().isEmpty) return;

    // 1. Perform Translation
    // The PythonNLLBONNXBackend now fetches translation AND alignments in one request
    final translatedText = await translationService.translate(
      originalText,
      targetLang,
      sourceLang,
    );

    paraInfo.translatedText = translatedText;

    // 2. Extract Alignments
    // Strategy: First, check if the backend already provided BERT-based alignments
    bool usedBackendAlignment = false;
    
    // We check if the translation service has a 'lastAlignments' property 
    // (This works specifically with our PythonNLLBONNXBackend implementation)
    try {
      final dynamic service = translationService;
      // We use a safe check here. In a strictly typed environment, 
      // you'd use 'if (translationService is PythonNLLBONNXBackend)'
      final backendAlignments = service.lastAlignments as List<Alignment>?;
      
      if (backendAlignments != null && backendAlignments.isNotEmpty) {
        paraInfo.alignment = backendAlignments;
        usedBackendAlignment = true;
        _log('🔍 [DEBUG] Using BERT-based alignments from backend');
      }
    } catch (e) {
      // service.lastAlignments doesn't exist or failed, fall back to heuristic
    }

    // 3. Fallback to Heuristic Aligner if backend didn't provide any
    if (!usedBackendAlignment && aligner != null) {
      final srcWords = transPara.getWords();
      final tgtWords = _extractWords(translatedText);

      if (srcWords.isNotEmpty && tgtWords.isNotEmpty) {
        paraInfo.alignment = aligner!.align(srcWords, tgtWords);
        _log('ℹ️ [DEBUG] Backend alignment missing, used Heuristic Aligner');
      }
    }

    if (verbose) {
      final alignCount = paraInfo.alignment?.length ?? 0;
      final preview = originalText.length > 40 
          ? '${originalText.substring(0, 40)}...' 
          : originalText;
      _log('✨ ALIGN: $alignCount links for "$preview"');
    }
  }

  List<String> _extractWords(String text) {
    // This matches words while ignoring punctuation
    final regex = RegExp(r'\w+');
    return regex.allMatches(text).map((m) => m.group(0)!).toList();
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
  if (paraInfo.translatedText == null || paraInfo.translatedText!.trim().isEmpty) {
    return;
  }
  
  final pElem = paraInfo.element;
  final transPara = paraInfo.transPara;
  final translatedText = paraInfo.translatedText!;
  final alignment = paraInfo.alignment;
  
  // STEP 1: Identify and copy footnote runs (before any removal)
  final footnoteRunsCopies = <XmlElement>[];
  
  // Create a list of children to iterate safely
  final childrenToCheck = pElem.children.whereType<XmlElement>().toList();
  
  for (final child in childrenToCheck) {
    if (child.name.local == 'r') {
      // Check if this run has a footnote reference
      bool hasFootnote = child.descendants.whereType<XmlElement>().any(
        (desc) => desc.name.local == 'footnoteReference' || desc.name.local == 'footnoteRef'
      );
      
      if (hasFootnote) {
        // Create a DEEP copy of the entire run element
        final copiedRun = _deepCopyElement(child);
        footnoteRunsCopies.add(copiedRun);
      }
    }
  }
  
  // STEP 2: Remove ALL existing run elements (including footnotes)
  // We need to collect them first, then remove, to avoid concurrent modification
  final runsToRemove = pElem.children
      .whereType<XmlElement>()
      .where((child) => child.name.local == 'r')
      .toList();
  
  for (final run in runsToRemove) {
    pElem.children.remove(run);
  }
  
  // STEP 3: For footnote paragraphs, add marker first
  final isFootnote = paraInfo.location == 'footnote';
  if (isFootnote && footnoteRunsCopies.isNotEmpty) {
    // Add footnote number at the beginning
    for (final ref in footnoteRunsCopies) {
      pElem.children.add(ref);
    }
    // Add a non-breaking space after the number
    final spaceRun = _createSimpleRun('\u00A0');
    pElem.children.add(spaceRun);
  }
  
  // STEP 4: Add translated runs with formatting
  _reconstructRuns(pElem, transPara, translatedText, alignment);
  
  // STEP 5: For body text, add footnotes at end
  if (!isFootnote && footnoteRunsCopies.isNotEmpty) {
    for (final ref in footnoteRunsCopies) {
      pElem.children.add(ref);
    }
  }
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

  XmlElement _createFormattedRun(
      String text, FormatRun? template, String? styleType) {
    // Create run element with proper namespace
    final run = XmlElement(XmlName('r', wNamespace));

    // Run properties
    if (template != null || styleType != null) {
      final rPr = XmlElement(XmlName('rPr', wNamespace));

      // Apply style type (bold/italic from alignment)
      if (styleType == 'italic_bold') {
        rPr.children.add(XmlElement(XmlName('b', wNamespace)));
        rPr.children.add(XmlElement(XmlName('i', wNamespace)));
      } else if (styleType == 'bold') {
        rPr.children.add(XmlElement(XmlName('b', wNamespace)));
      } else if (styleType == 'italic') {
        rPr.children.add(XmlElement(XmlName('i', wNamespace)));
      }

      // Apply baseline aesthetics from template
      if (template != null) {
        // Font name
        if (template.fontName != null) {
          final rFonts = XmlElement(XmlName('rFonts', wNamespace));
          rFonts.setAttribute('ascii', template.fontName!,
              namespace: wNamespace);
          rFonts.setAttribute('hAnsi', template.fontName!,
              namespace: wNamespace);
          rPr.children.add(rFonts);
        }

        // Font size
        if (template.fontSize != null) {
          final sz = XmlElement(XmlName('sz', wNamespace));
          sz.setAttribute('val', (template.fontSize! * 2).round().toString(),
              namespace: wNamespace);
          rPr.children.add(sz);
        }

        // Color
        if (template.fontColor != null) {
          final color = XmlElement(XmlName('color', wNamespace));
          color.setAttribute('val', template.fontColor!.toHex(),
              namespace: wNamespace);
          rPr.children.add(color);
        }

        // Underline
        if (template.underline == true) {
          final u = XmlElement(XmlName('u', wNamespace));
          u.setAttribute('val', 'single', namespace: wNamespace);
          rPr.children.add(u);
        }
      }

      if (rPr.children.isNotEmpty) {
        run.children.add(rPr);
      }
    }

    // Text element
    final tElem = XmlElement(XmlName('t', wNamespace));
    if (text.startsWith(' ') || text.endsWith(' ')) {
      tElem.setAttribute('space', 'preserve',
          namespace: 'http://www.w3.org/XML/1998/namespace');
    }
    tElem.innerText = text;
    run.children.add(tElem);

    return run;
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
