import 'dart:io';

void main() async {
  print('=' * 70);
  print('🚀 Quick Translation Test via Python');
  print('=' * 70);
  print('');

  // Create a quick Python script for comparison
  final pythonScript = '''
from optimum.onnxruntime import ORTModelForSeq2SeqLM
from transformers import AutoTokenizer

print("Loading models...", flush=True)
model = ORTModelForSeq2SeqLM.from_pretrained(
    "assets/onnx_models/nllb_600m_int8",
    encoder_file_name="encoder_model.onnx",
    decoder_file_name="decoder_model.onnx",
)
tokenizer = AutoTokenizer.from_pretrained("assets/models")
print("Models loaded!", flush=True)

test_cases = [
    ("Hello, how are you?", "deu_Latn"),
    ("Good morning!", "fra_Latn"),
    ("Thank you very much!", "spa_Latn"),
]

for text, lang in test_cases:
    print(f"\\n📝 '{text}' → {lang}")
    
    inputs = tokenizer(text, return_tensors="pt")
    translated = model.generate(
        **inputs, 
        forced_bos_token_id=tokenizer.convert_tokens_to_ids(lang),
        max_length=256
    )
    result = tokenizer.batch_decode(translated, skip_special_tokens=True)[0]
    
    print(f"   {result}")
    print("   ✅ Success")

print("\\n" + "="*70)
print("All translations completed!")
print("="*70)
''';

  // Write Python script
  final scriptFile = File('test_translate.py');
  await scriptFile.writeAsString(pythonScript);

  print('Running Python translation test...\n');

  // Run Python script
  final result = await Process.run('python3', ['test_translate.py']);

  print(result.stdout);
  if (result.stderr.toString().isNotEmpty) {
    print('Warnings: ${result.stderr}');
  }

  // Clean up
  await scriptFile.delete();

  if (result.exitCode == 0) {
    print('\n✅ Python test completed successfully!');
    print('Now compare with Flutter app results.');
  } else {
    print('\n❌ Python test failed');
    exit(1);
  }
}
