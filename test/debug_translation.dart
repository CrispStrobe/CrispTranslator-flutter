import 'dart:io';

void main() async {
  print('=' * 70);
  print('🐍 Python Performance Baseline');
  print('=' * 70);

  final pythonScript = '''
import time
from optimum.onnxruntime import ORTModelForSeq2SeqLM
from transformers import AutoTokenizer

print("Loading models...")
start = time.time()
model = ORTModelForSeq2SeqLM.from_pretrained(
    "assets/onnx_models",
    encoder_file_name="encoder_model.onnx",
    decoder_file_name="decoder_model.onnx",
)
tokenizer = AutoTokenizer.from_pretrained("assets/models")
print(f"Models loaded in {(time.time()-start)*1000:.0f}ms\\n")

test_cases = [
    ("This is a test.", "deu_Latn"),
    ("Hello, how are you?", "deu_Latn"),
    ("Good morning!", "fra_Latn"),
]

for text, lang in test_cases:
    print("="*70)
    print(f"Input: \\"{text}\\"")
    print(f"Target: {lang}")
    print("-"*70)
    
    start = time.time()
    inputs = tokenizer(text, return_tensors="pt")
    tok_time = (time.time() - start) * 1000
    print(f"Tokenization: {tok_time:.1f}ms")
    
    start = time.time()
    translated = model.generate(
        **inputs, 
        forced_bos_token_id=tokenizer.convert_tokens_to_ids(lang),
        max_length=256
    )
    gen_time = (time.time() - start) * 1000
    print(f"Generation: {gen_time:.1f}ms")
    
    start = time.time()
    result = tokenizer.batch_decode(translated, skip_special_tokens=True)[0]
    detok_time = (time.time() - start) * 1000
    print(f"Detokenization: {detok_time:.1f}ms")
    
    print(f"\\nResult: \\"{result}\\"")
    print(f"Total: {tok_time + gen_time + detok_time:.1f}ms")
    print()
''';

  final scriptFile = File('debug_translate.py');
  await scriptFile.writeAsString(pythonScript);

  print('Running Python baseline test...\n');

  final result = await Process.run('python3', ['debug_translate.py']);
  print(result.stdout);

  if (result.stderr.toString().isNotEmpty) {
    print('Stderr: ${result.stderr}');
  }

  await scriptFile.delete();
}
