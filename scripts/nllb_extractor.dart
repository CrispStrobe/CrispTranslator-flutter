import 'dart:convert';
import 'dart:io';

void main(List<String> args) async {
  if (args.isEmpty) {
    print('Usage: dart nllb_extractor.dart <path_to_tokenizer.json>');
    return;
  }

  final File file = File(args[0]);
  if (!await file.exists()) {
    print('Error: File not found at ${args[0]}');
    return;
  }

  print('📖 Reading tokenizer.json...');
  final String content = await file.readAsString();
  final Map<String, dynamic> data = json.decode(content);

  // 1. Extract the Model Vocab
  // NLLB-200 uses a "Unigram" or "BPE" model stored under the 'model' key
  final Map<String, dynamic> model = data['model'];
  final Map<String, dynamic> vocab = model['vocab'];

  print('✨ Successfully loaded ${vocab.length} tokens.');

  // 2. Identify and Extract Language Tags
  // NLLB tags follow the pattern: 3 lowercase letters + underscore + 4 capitalized letters
  // Example: eng_Latn, fra_Latn, hin_Deva
  final RegExp tagRegex = RegExp(r'^[a-z]{3}_[A-Z][a-z]{3}$');

  final Map<String, int> extractedTags = {};

  vocab.forEach((token, id) {
    if (tagRegex.hasMatch(token)) {
      extractedTags[token] = id as int;
    }
  });

  // 3. Output the results in a format you can copy/paste into your Dart code
  print('\n--- Generated Dart Maps ---');

  print('\n// Language Tags to Token IDs');
  print('const Map<String, int> nllbTags = {');

  // Sort alphabetically by tag for cleanliness
  final sortedKeys = extractedTags.keys.toList()..sort();
  for (var tag in sortedKeys) {
    print("  '$tag': ${extractedTags[tag]},");
  }
  print('};');

  print('\n// Total Tags Found: ${extractedTags.length}');
}
