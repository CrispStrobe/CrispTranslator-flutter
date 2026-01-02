// lib/services/

import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/services.dart';
import 'dart:io';

class NLLBTokenizer {
  Map<String, int>? _vocab;
  Map<int, String>? _reverseVocab;
  List<List<String>>? _merges;

  static const String spSpace = '\u2581';

  static const Map<String, int> nllbTags = {
    'ace_Arab': 256001,
    'ace_Latn': 256002,
    'acm_Arab': 256003,
    'acq_Arab': 256004,
    'aeb_Arab': 256005,
    'afr_Latn': 256006,
    'ajp_Arab': 256007,
    'aka_Latn': 256008,
    'als_Latn': 256162,
    'amh_Ethi': 256009,
    'apc_Arab': 256010,
    'arb_Arab': 256011,
    'ars_Arab': 256012,
    'ary_Arab': 256013,
    'arz_Arab': 256014,
    'asm_Beng': 256015,
    'ast_Latn': 256016,
    'awa_Deva': 256017,
    'ayr_Latn': 256018,
    'azb_Arab': 256019,
    'azj_Latn': 256020,
    'bak_Cyrl': 256021,
    'bam_Latn': 256022,
    'ban_Latn': 256023,
    'bel_Cyrl': 256024,
    'bem_Latn': 256025,
    'ben_Beng': 256026,
    'bho_Deva': 256027,
    'bjn_Arab': 256028,
    'bjn_Latn': 256029,
    'bod_Tibt': 256030,
    'bos_Latn': 256031,
    'bug_Latn': 256032,
    'bul_Cyrl': 256033,
    'cat_Latn': 256034,
    'ceb_Latn': 256035,
    'ces_Latn': 256036,
    'cjk_Latn': 256037,
    'ckb_Arab': 256038,
    'crh_Latn': 256039,
    'cym_Latn': 256040,
    'dan_Latn': 256041,
    'deu_Latn': 256042,
    'dik_Latn': 256043,
    'dyu_Latn': 256044,
    'dzo_Tibt': 256045,
    'ell_Grek': 256046,
    'eng_Latn': 256047,
    'epo_Latn': 256048,
    'est_Latn': 256049,
    'eus_Latn': 256050,
    'ewe_Latn': 256051,
    'fao_Latn': 256052,
    'fij_Latn': 256054,
    'fin_Latn': 256055,
    'fon_Latn': 256056,
    'fra_Latn': 256057,
    'fur_Latn': 256058,
    'fuv_Latn': 256059,
    'gaz_Latn': 256135,
    'gla_Latn': 256060,
    'gle_Latn': 256061,
    'glg_Latn': 256062,
    'grn_Latn': 256063,
    'guj_Gujr': 256064,
    'hat_Latn': 256065,
    'hau_Latn': 256066,
    'heb_Hebr': 256067,
    'hin_Deva': 256068,
    'hne_Deva': 256069,
    'hrv_Latn': 256070,
    'hun_Latn': 256071,
    'hye_Armn': 256072,
    'ibo_Latn': 256073,
    'ilo_Latn': 256074,
    'ind_Latn': 256075,
    'isl_Latn': 256076,
    'ita_Latn': 256077,
    'jav_Latn': 256078,
    'jpn_Jpan': 256079,
    'kab_Latn': 256080,
    'kac_Latn': 256081,
    'kam_Latn': 256082,
    'kan_Knda': 256083,
    'kas_Arab': 256084,
    'kas_Deva': 256085,
    'kat_Geor': 256086,
    'kaz_Cyrl': 256089,
    'kbp_Latn': 256090,
    'kea_Latn': 256091,
    'khk_Cyrl': 256122,
    'khm_Khmr': 256092,
    'kik_Latn': 256093,
    'kin_Latn': 256094,
    'kir_Cyrl': 256095,
    'kmb_Latn': 256096,
    'kmr_Latn': 256099,
    'knc_Arab': 256087,
    'knc_Latn': 256088,
    'kon_Latn': 256097,
    'kor_Hang': 256098,
    'lao_Laoo': 256100,
    'lij_Latn': 256102,
    'lim_Latn': 256103,
    'lin_Latn': 256104,
    'lit_Latn': 256105,
    'lmo_Latn': 256106,
    'ltg_Latn': 256107,
    'ltz_Latn': 256108,
    'lua_Latn': 256109,
    'lug_Latn': 256110,
    'luo_Latn': 256111,
    'lus_Latn': 256112,
    'lvs_Latn': 256101,
    'mag_Deva': 256113,
    'mai_Deva': 256114,
    'mal_Mlym': 256115,
    'mar_Deva': 256116,
    'min_Latn': 256117,
    'mkd_Cyrl': 256118,
    'mlt_Latn': 256120,
    'mni_Beng': 256121,
    'mos_Latn': 256123,
    'mri_Latn': 256124,
    'mya_Mymr': 256126,
    'nld_Latn': 256127,
    'nno_Latn': 256128,
    'nob_Latn': 256129,
    'npi_Deva': 256130,
    'nso_Latn': 256131,
    'nus_Latn': 256132,
    'nya_Latn': 256133,
    'oci_Latn': 256134,
    'ory_Orya': 256136,
    'pag_Latn': 256137,
    'pan_Guru': 256138,
    'pap_Latn': 256139,
    'pbt_Arab': 256143,
    'pes_Arab': 256053,
    'plt_Latn': 256119,
    'pol_Latn': 256140,
    'por_Latn': 256141,
    'prs_Arab': 256142,
    'quy_Latn': 256144,
    'ron_Latn': 256145,
    'run_Latn': 256146,
    'rus_Cyrl': 256147,
    'sag_Latn': 256148,
    'san_Deva': 256149,
    'sat_Beng': 256150,
    'scn_Latn': 256151,
    'shn_Mymr': 256152,
    'sin_Sinh': 256153,
    'slk_Latn': 256154,
    'slv_Latn': 256155,
    'smo_Latn': 256156,
    'sna_Latn': 256157,
    'snd_Arab': 256158,
    'som_Latn': 256159,
    'sot_Latn': 256160,
    'spa_Latn': 256161,
    'srd_Latn': 256163,
    'srp_Cyrl': 256164,
    'ssw_Latn': 256165,
    'sun_Latn': 256166,
    'swe_Latn': 256167,
    'swh_Latn': 256168,
    'szl_Latn': 256169,
    'tam_Taml': 256170,
    'taq_Latn': 256177,
    'taq_Tfng': 256178,
    'tat_Cyrl': 256171,
    'tel_Telu': 256172,
    'tgk_Cyrl': 256173,
    'tgl_Latn': 256174,
    'tha_Thai': 256175,
    'tir_Ethi': 256176,
    'tpi_Latn': 256179,
    'tsn_Latn': 256180,
    'tso_Latn': 256181,
    'tuk_Latn': 256182,
    'tum_Latn': 256183,
    'tur_Latn': 256184,
    'twi_Latn': 256185,
    'tzm_Tfng': 256186,
    'uig_Arab': 256187,
    'ukr_Cyrl': 256188,
    'umb_Latn': 256189,
    'urd_Arab': 256190,
    'uzn_Latn': 256191,
    'vec_Latn': 256192,
    'vie_Latn': 256193,
    'war_Latn': 256194,
    'wol_Latn': 256195,
    'xho_Latn': 256196,
    'ydd_Hebr': 256197,
    'yor_Latn': 256198,
    'yue_Hant': 256199,
    'zho_Hans': 256200,
    'zho_Hant': 256201,
    'zsm_Latn': 256125,
    'zul_Latn': 256202,
  };


  static const Map<String, int> languageTokens = {
    'Acehnese (Arabic script)': 256001,
    'Acehnese (Latin script)': 256002,
    'Mesopotamian Arabic': 256003,
    'Ta\'izzi-Adeni Arabic': 256004,
    'Tunisian Arabic': 256005,
    'Afrikaans': 256006,
    'South Levantine Arabic': 256007,
    'Akan': 256008,
    'Amharic': 256009,
    'North Levantine Arabic': 256010,
    'Modern Standard Arabic': 256011,
    'Modern Standard Arabic (Romanized)': 256047, // Re-mapped to eng_Latn style if needed, but keeping tag logic
    'Najdi Arabic': 256012,
    'Moroccan Arabic': 256013,
    'Egyptian Arabic': 256014,
    'Assamese': 256015,
    'Asturian': 256016,
    'Awadhi': 256017,
    'Central Aymara': 256018,
    'South Azerbaijani': 256019,
    'North Azerbaijani': 256020,
    'Bashkir': 256021,
    'Bambara': 256022,
    'Balinese': 256023,
    'Belarusian': 256024,
    'Bemba': 256025,
    'Bengali': 256026,
    'Bhojpuri': 256027,
    'Banjar (Arabic script)': 256028,
    'Banjar (Latin script)': 256029,
    'Standard Tibetan': 256030,
    'Bosnian': 256031,
    'Buginese': 256032,
    'Bulgarian': 256033,
    'Catalan': 256034,
    'Cebuano': 256035,
    'Czech': 256036,
    'Chokwe': 256037,
    'Central Kurdish': 256038,
    'Crimean Tatar': 256039,
    'Welsh': 256040,
    'Danish': 256041,
    'German': 256042,
    'Southwestern Dinka': 256043,
    'Dyula': 256044,
    'Dzongkha': 256045,
    'Greek': 256046,
    'English': 256047,
    'Esperanto': 256048,
    'Estonian': 256049,
    'Basque': 256050,
    'Ewe': 256051,
    'Faroese': 256052,
    'Fijian': 256054,
    'Finnish': 256055,
    'Fon': 256056,
    'French': 256057,
    'Friulian': 256058,
    'Nigerian Fulfulde': 256059,
    'Scottish Gaelic': 256060,
    'Irish': 256061,
    'Galician': 256062,
    'Guarani': 256063,
    'Gujarati': 256064,
    'Haitian Creole': 256065,
    'Hausa': 256066,
    'Hebrew': 256067,
    'Hindi': 256068,
    'Chhattisgarhi': 256069,
    'Croatian': 256070,
    'Hungarian': 256071,
    'Armenian': 256072,
    'Igbo': 256073,
    'Ilocano': 256074,
    'Indonesian': 256075,
    'Icelandic': 256076,
    'Italian': 256077,
    'Javanese': 256078,
    'Japanese': 256079,
    'Kabyle': 256080,
    'Jingpho': 256081,
    'Kamba': 256082,
    'Kannada': 256083,
    'Kashmiri (Arabic script)': 256084,
    'Kashmiri (Devanagari script)': 256085,
    'Georgian': 256086,
    'Central Kanuri (Arabic script)': 256087,
    'Central Kanuri (Latin script)': 256088,
    'Kazakh': 256089,
    'Kabiyè': 256090,
    'Kabuverdianu': 256091,
    'Khmer': 256092,
    'Kikuyu': 256093,
    'Kinyarwanda': 256094,
    'Kyrgyz': 256095,
    'Kimbundu': 256096,
    'Northern Kurdish': 256099,
    'Kikongo': 256097,
    'Korean': 256098,
    'Lao': 256100,
    'Ligurian': 256102,
    'Limburgish': 256103,
    'Lingala': 256104,
    'Lithuanian': 256105,
    'Lombard': 256106,
    'Latgalian': 256107,
    'Luxembourgish': 256108,
    'Luba-Kasai': 256109,
    'Ganda': 256110,
    'Luo': 256111,
    'Mizo': 256112,
    'Standard Latvian': 256101,
    'Magahi': 256113,
    'Maithili': 256114,
    'Malayalam': 256115,
    'Marathi': 256116,
    'Minangkabau (Arabic script)': 256028, // Using appropriate mapping if distinct
    'Minangkabau (Latin script)': 256117,
    'Macedonian': 256118,
    'Plateau Malagasy': 256119,
    'Maltese': 256120,
    'Meitei (Bengali script)': 256121,
    'Halh Mongolian': 256122,
    'Mossi': 256123,
    'Maori': 256124,
    'Burmese': 256126,
    'Dutch': 256127,
    'Norwegian Nynorsk': 256128,
    'Norwegian Bokmål': 256129,
    'Nepali': 256130,
    'Northern Sotho': 256131,
    'Nuer': 256132,
    'Nyanja': 256133,
    'Occitan': 256134,
    'West Central Oromo': 256135,
    'Odia': 256136,
    'Pangasinan': 256137,
    'Eastern Panjabi': 256138,
    'Papiamento': 256139,
    'Western Persian': 256053,
    'Polish': 256140,
    'Portuguese': 256141,
    'Dari': 256142,
    'Southern Pashto': 256143,
    'Ayacucho Quechua': 256144,
    'Romanian': 256145,
    'Rundi': 256146,
    'Russian': 256147,
    'Sango': 256148,
    'Sanskrit': 256149,
    'Santali': 256150,
    'Sicilian': 256151,
    'Shan': 256152,
    'Sinhala': 256153,
    'Slovak': 256154,
    'Slovenian': 256155,
    'Samoan': 256156,
    'Shona': 256157,
    'Sindhi': 256158,
    'Somali': 256159,
    'Southern Sotho': 256160,
    'Spanish': 256161,
    'Tosk Albanian': 256162,
    'Sardinian': 256163,
    'Serbian': 256164,
    'Swati': 256165,
    'Sundanese': 256166,
    'Swedish': 256167,
    'Swahili': 256168,
    'Silesian': 256169,
    'Tamil': 256170,
    'Tatar': 256171,
    'Telugu': 256172,
    'Tajik': 256173,
    'Tagalog': 256174,
    'Thai': 256175,
    'Tigrinya': 256176,
    'Tamasheq (Latin script)': 256177,
    'Tamasheq (Tifinagh script)': 256178,
    'Tok Pisin': 256179,
    'Tswana': 256180,
    'Tsonga': 256181,
    'Turkmen': 256182,
    'Tumbuka': 256183,
    'Turkish': 256184,
    'Twi': 256185,
    'Central Atlas Tamazight': 256186,
    'Uyghur': 256187,
    'Ukrainian': 256188,
    'Umbundu': 256189,
    'Urdu': 256190,
    'Northern Uzbek': 256191,
    'Venetian': 256192,
    'Vietnamese': 256193,
    'Waray': 256194,
    'Wolof': 256195,
    'Xhosa': 256196,
    'Eastern Yiddish': 256197,
    'Yoruba': 256198,
    'Yue Chinese': 256199,
    'Chinese (Simplified)': 256200,
    'Chinese (Traditional)': 256201,
    'Standard Malay': 256125,
    'Zulu': 256202,
  };

  // Special tokens
  static const int padTokenId = 1;
  static const int bosTokenId = 2;
  static const int eosTokenId = 2;
  static const int unkTokenId = 3;

  Future<void> initialize({String? modelsPath}) async {
    print('📝 Loading tokenizer...');

    String tokenizerData;

    if (modelsPath != null) {
      // Load from file system
      tokenizerData = await File('$modelsPath/tokenizer.json').readAsString();
    } else {
      // Load from assets
      tokenizerData =
          await rootBundle.loadString('assets/models/tokenizer.json');
    }

    final tokenizerJson = json.decode(tokenizerData);

    // Rest stays exactly the same...
    final model = tokenizerJson['model'];
    final vocabData = model['vocab'] as Map<String, dynamic>;

    _vocab = {};
    _reverseVocab = {};

    vocabData.forEach((token, id) {
      final tokenId = id as int;
      _vocab![token] = tokenId;
      _reverseVocab![tokenId] = token;
    });

    final mergesData = model['merges'];
    _merges = [];

    if (mergesData is List) {
      for (var merge in mergesData) {
        try {
          if (merge is String) {
            final parts = merge.split(' ');
            if (parts.length == 2) {
              _merges!.add(parts);
            }
          } else if (merge is List) {
            if (merge.length >= 2) {
              _merges!.add([merge[0].toString(), merge[1].toString()]);
            }
          }
        } catch (e) {
          continue;
        }
      }
    }

    print(
        '✅ Tokenizer loaded: ${_vocab!.length} tokens, ${_merges!.length} merges');
  }

  TokenizerOutput encode(String text,
      {int maxLength = 256, String sourceLanguage = 'English'}) {
    print('\n🔧 [Tokenizer] Starting encode for: "$text"');

    final List<String> tokens = _tokenizeBPE(text);
    print('DEBUG [Tokenizer] BPE Tokens: ${tokens.join("|")}');

    final List<int> ids = tokens.map((t) => _vocab![t] ?? unkTokenId).toList();
    print('DEBUG [Tokenizer] Token IDs (before src lang): $ids');

    // Get source language ID
    final int srcLangId = getLanguageTokenId(sourceLanguage);
    final List<int> fullIds = [srcLangId, ...ids, eosTokenId];

    print('DEBUG [Tokenizer] Full sequence (with src_lang + EOS): $fullIds');
    print(
        'DEBUG [Tokenizer] Source Language: $sourceLanguage -> ID: $srcLangId');

    final int actualLength = fullIds.length;
    final List<int> finalIds = List<int>.from(fullIds);
    final List<int> attentionMask = List<int>.filled(actualLength, 1);

    print('DEBUG [Tokenizer] Final sequence (NO padding): $finalIds');
    print('DEBUG [Tokenizer] Attention mask: $attentionMask');
    print('DEBUG [Tokenizer] Actual length: $actualLength');

    return TokenizerOutput(
      inputIds: Int32List.fromList(finalIds),
      attentionMask: Uint8List.fromList(Uint8List.fromList(attentionMask)),
    );
  }

  String decode(List<int> ids) {
    if (_reverseVocab == null) return '';

    print('\n🔧 [Tokenizer] Decoding ${ids.length} token IDs');
    print(
        'DEBUG [Tokenizer] IDs to decode: ${ids.take(20).toList()}${ids.length > 20 ? "..." : ""}');

    final tokens = <String>[];

    for (final id in ids) {
      // Ignore PAD, BOS/EOS, UNK, and Language Tokens
      if (id <= 3 || languageTokens.values.contains(id)) {
        print('DEBUG [Tokenizer] Skipping special token ID: $id');
        continue;
      }

      final t = _reverseVocab![id];
      if (t != null) {
        tokens.add(t);
        print('DEBUG [Tokenizer] ID $id -> Token: "$t"');
      }
    }

    // Join and replace the SentencePiece underscore (▁) with a standard space
    final decoded = tokens.join('').replaceAll('▁', ' ').trim();
    print('DEBUG [Tokenizer] Final decoded text: "$decoded"');

    return decoded;
  }

  List<String> _tokenizeBPE(String text) {
    // Use the correct SentencePiece character: \u2581
    String normalized = text.trim().replaceAll(' ', spSpace);
    if (!normalized.startsWith(spSpace)) {
      normalized = spSpace + normalized;
    }

    print('DEBUG [Tokenizer] Normalized text: "$normalized"');

    // Split into characters for BPE merging
    List<String> tokens = normalized.split('');

    if (_vocab == null) return tokens;

    // Apply BPE merges greedily based on vocab priority
    while (true) {
      int? bestPriority;
      int? bestIdx;
      String? bestPair;

      for (int i = 0; i < tokens.length - 1; i++) {
        final pair = tokens[i] + tokens[i + 1];
        if (_vocab!.containsKey(pair)) {
          int priority = _vocab![pair]!;
          if (bestPriority == null || priority < bestPriority) {
            bestPriority = priority;
            bestIdx = i;
            bestPair = pair;
          }
        }
      }

      if (bestIdx == null) break;
      tokens[bestIdx] = bestPair!;
      tokens.removeAt(bestIdx + 1);
    }

    return tokens;
  }

  // Use the exact NLLB-200 language tags used in your Python benchmark
  static const Map<String, String> languageToTag = {
    'Acehnese (Arabic script)': 'ace_Arab',
    'Acehnese (Latin script)': 'ace_Latn',
    'Mesopotamian Arabic': 'acm_Arab',
    'Ta\'izzi-Adeni Arabic': 'acq_Arab',
    'Tunisian Arabic': 'aeb_Arab',
    'Afrikaans': 'afr_Latn',
    'South Levantine Arabic': 'ajp_Arab',
    'Akan': 'aka_Latn',
    'Amharic': 'amh_Ethi',
    'North Levantine Arabic': 'apc_Arab',
    'Modern Standard Arabic': 'arb_Arab',
    'Modern Standard Arabic (Romanized)': 'arb_Latn',
    'Najdi Arabic': 'ars_Arab',
    'Moroccan Arabic': 'ary_Arab',
    'Egyptian Arabic': 'arz_Arab',
    'Assamese': 'asm_Beng',
    'Asturian': 'ast_Latn',
    'Awadhi': 'awa_Deva',
    'Central Aymara': 'ayr_Latn',
    'South Azerbaijani': 'azb_Arab',
    'North Azerbaijani': 'azj_Latn',
    'Bashkir': 'bak_Cyrl',
    'Bambara': 'bam_Latn',
    'Balinese': 'ban_Latn',
    'Belarusian': 'bel_Cyrl',
    'Bemba': 'bem_Latn',
    'Bengali': 'ben_Beng',
    'Bhojpuri': 'bho_Deva',
    'Banjar (Arabic script)': 'bjn_Arab',
    'Banjar (Latin script)': 'bjn_Latn',
    'Standard Tibetan': 'bod_Tibt',
    'Bosnian': 'bos_Latn',
    'Buginese': 'bug_Latn',
    'Bulgarian': 'bul_Cyrl',
    'Catalan': 'cat_Latn',
    'Cebuano': 'ceb_Latn',
    'Czech': 'ces_Latn',
    'Chokwe': 'cjk_Latn',
    'Central Kurdish': 'ckb_Arab',
    'Crimean Tatar': 'crh_Latn',
    'Welsh': 'cym_Latn',
    'Danish': 'dan_Latn',
    'German': 'deu_Latn',
    'Southwestern Dinka': 'dik_Latn',
    'Dyula': 'dyu_Latn',
    'Dzongkha': 'dzo_Tibt',
    'Greek': 'ell_Grek',
    'English': 'eng_Latn',
    'Esperanto': 'epo_Latn',
    'Estonian': 'est_Latn',
    'Basque': 'eus_Latn',
    'Ewe': 'ewe_Latn',
    'Faroese': 'fao_Latn',
    'Fijian': 'fij_Latn',
    'Finnish': 'fin_Latn',
    'Fon': 'fon_Latn',
    'French': 'fra_Latn',
    'Friulian': 'fur_Latn',
    'Nigerian Fulfulde': 'fuv_Latn',
    'Scottish Gaelic': 'gla_Latn',
    'Irish': 'gle_Latn',
    'Galician': 'glg_Latn',
    'Guarani': 'grn_Latn',
    'Gujarati': 'guj_Gujr',
    'Haitian Creole': 'hat_Latn',
    'Hausa': 'hau_Latn',
    'Hebrew': 'heb_Hebr',
    'Hindi': 'hin_Deva',
    'Chhattisgarhi': 'hne_Deva',
    'Croatian': 'hrv_Latn',
    'Hungarian': 'hun_Latn',
    'Armenian': 'hye_Armn',
    'Igbo': 'ibo_Latn',
    'Ilocano': 'ilo_Latn',
    'Indonesian': 'ind_Latn',
    'Icelandic': 'isl_Latn',
    'Italian': 'ita_Latn',
    'Javanese': 'jav_Latn',
    'Japanese': 'jpn_Jpan',
    'Kabyle': 'kab_Latn',
    'Jingpho': 'kac_Latn',
    'Kamba': 'kam_Latn',
    'Kannada': 'kan_Knda',
    'Kashmiri (Arabic script)': 'kas_Arab',
    'Kashmiri (Devanagari script)': 'kas_Deva',
    'Georgian': 'kat_Geor',
    'Central Kanuri (Arabic script)': 'knc_Arab',
    'Central Kanuri (Latin script)': 'knc_Latn',
    'Kazakh': 'kaz_Cyrl',
    'Kabiyè': 'kbp_Latn',
    'Kabuverdianu': 'kea_Latn',
    'Khmer': 'khm_Khmr',
    'Kikuyu': 'kik_Latn',
    'Kinyarwanda': 'kin_Latn',
    'Kyrgyz': 'kir_Cyrl',
    'Kimbundu': 'kmb_Latn',
    'Northern Kurdish': 'kmr_Latn',
    'Kikongo': 'kon_Latn',
    'Korean': 'kor_Hang',
    'Lao': 'lao_Laoo',
    'Ligurian': 'lij_Latn',
    'Limburgish': 'lim_Latn',
    'Lingala': 'lin_Latn',
    'Lithuanian': 'lit_Latn',
    'Lombard': 'lmo_Latn',
    'Latgalian': 'ltg_Latn',
    'Luxembourgish': 'ltz_Latn',
    'Luba-Kasai': 'lua_Latn',
    'Ganda': 'lug_Latn',
    'Luo': 'luo_Latn',
    'Mizo': 'lus_Latn',
    'Standard Latvian': 'lvs_Latn',
    'Magahi': 'mag_Deva',
    'Maithili': 'mai_Deva',
    'Malayalam': 'mal_Mlym',
    'Marathi': 'mar_Deva',
    'Minangkabau (Arabic script)': 'min_Arab',
    'Minangkabau (Latin script)': 'min_Latn',
    'Macedonian': 'mkd_Cyrl',
    'Plateau Malagasy': 'plt_Latn',
    'Maltese': 'mlt_Latn',
    'Meitei (Bengali script)': 'mni_Beng',
    'Halh Mongolian': 'khk_Cyrl',
    'Mossi': 'mos_Latn',
    'Maori': 'mri_Latn',
    'Burmese': 'mya_Mymr',
    'Dutch': 'nld_Latn',
    'Norwegian Nynorsk': 'nno_Latn',
    'Norwegian Bokmål': 'nob_Latn',
    'Nepali': 'npi_Deva',
    'Northern Sotho': 'nso_Latn',
    'Nuer': 'nus_Latn',
    'Nyanja': 'nya_Latn',
    'Occitan': 'oci_Latn',
    'West Central Oromo': 'gaz_Latn',
    'Odia': 'ory_Orya',
    'Pangasinan': 'pag_Latn',
    'Eastern Panjabi': 'pan_Guru',
    'Papiamento': 'pap_Latn',
    'Western Persian': 'pes_Arab',
    'Polish': 'pol_Latn',
    'Portuguese': 'por_Latn',
    'Dari': 'prs_Arab',
    'Southern Pashto': 'pbt_Arab',
    'Ayacucho Quechua': 'quy_Latn',
    'Romanian': 'ron_Latn',
    'Rundi': 'run_Latn',
    'Russian': 'rus_Cyrl',
    'Sango': 'sag_Latn',
    'Sanskrit': 'san_Deva',
    'Santali': 'sat_Olck',
    'Sicilian': 'scn_Latn',
    'Shan': 'shn_Mymr',
    'Sinhala': 'sin_Sinh',
    'Slovak': 'slk_Latn',
    'Slovenian': 'slv_Latn',
    'Samoan': 'smo_Latn',
    'Shona': 'sna_Latn',
    'Sindhi': 'snd_Arab',
    'Somali': 'som_Latn',
    'Southern Sotho': 'sot_Latn',
    'Spanish': 'spa_Latn',
    'Tosk Albanian': 'als_Latn',
    'Sardinian': 'srd_Latn',
    'Serbian': 'srp_Cyrl',
    'Swati': 'ssw_Latn',
    'Sundanese': 'sun_Latn',
    'Swedish': 'swe_Latn',
    'Swahili': 'swh_Latn',
    'Silesian': 'szl_Latn',
    'Tamil': 'tam_Taml',
    'Tatar': 'tat_Cyrl',
    'Telugu': 'tel_Telu',
    'Tajik': 'tgk_Cyrl',
    'Tagalog': 'tgl_Latn',
    'Thai': 'tha_Thai',
    'Tigrinya': 'tir_Ethi',
    'Tamasheq (Latin script)': 'taq_Latn',
    'Tamasheq (Tifinagh script)': 'taq_Tfng',
    'Tok Pisin': 'tpi_Latn',
    'Tswana': 'tsn_Latn',
    'Tsonga': 'tso_Latn',
    'Turkmen': 'tuk_Latn',
    'Tumbuka': 'tum_Latn',
    'Turkish': 'tur_Latn',
    'Twi': 'twi_Latn',
    'Central Atlas Tamazight': 'tzm_Tfng',
    'Uyghur': 'uig_Arab',
    'Ukrainian': 'ukr_Cyrl',
    'Umbundu': 'umb_Latn',
    'Urdu': 'urd_Arab',
    'Northern Uzbek': 'uzn_Latn',
    'Venetian': 'vec_Latn',
    'Vietnamese': 'vie_Latn',
    'Waray': 'war_Latn',
    'Wolof': 'wol_Latn',
    'Xhosa': 'xho_Latn',
    'Eastern Yiddish': 'ydd_Hebr',
    'Yoruba': 'yor_Latn',
    'Yue Chinese': 'yue_Hant',
    'Chinese (Simplified)': 'zho_Hans',
    'Chinese (Traditional)': 'zho_Hant',
    'Standard Malay': 'zsm_Latn',
    'Zulu': 'zul_Latn',
  };

  int getLanguageTokenId(String languageName) {
    final tag = languageToTag[languageName] ?? 'deu_Latn';
    final id = _vocab![tag];
    if (id == null) {
      print(
          'WARNING: Language tag $tag not found in vocab! Defaulting to 256049');
      return 256049;
    }
    print('DEBUG [Tokenizer] Language "$languageName" -> Tag "$tag" -> ID $id');
    return id;
  }

  bool get isInitialized => _vocab != null;
}

class TokenizerOutput {
  final Int32List inputIds;
  final Uint8List attentionMask;

  TokenizerOutput({
    required this.inputIds,
    required this.attentionMask,
  });
}
