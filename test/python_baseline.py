#!/usr/bin/env python3
import time
import sys
import os

# Add parent directory to path
sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..'))

from transformers import AutoTokenizer
import onnxruntime as ort
import numpy as np

print("="*70)
print("🐍 Python ONNX Performance Baseline")
print("="*70)

# Load tokenizer
print("\nLoading tokenizer...")
tokenizer = AutoTokenizer.from_pretrained("assets/models")

# Load ONNX models
print("Loading ONNX models...")
encoder_path = "assets/onnx_models/encoder_model.onnx"
decoder_path = "assets/onnx_models/decoder_model.onnx"

encoder = ort.InferenceSession(encoder_path)
decoder = ort.InferenceSession(decoder_path)

print(f"\nEncoder inputs: {[i.name for i in encoder.get_inputs()]}")
print(f"Encoder outputs: {[o.name for o in encoder.get_outputs()]}")
print(f"Decoder inputs: {[i.name for i in decoder.get_inputs()]}")
print(f"Decoder outputs: {[o.name for o in decoder.get_outputs()]}")

# Language tokens
lang_tokens = {
    'German': 256049,
    'French': 256057,
    'Spanish': 256014,
}

test_cases = [
    ("This is a test.", "German"),
    ("Hello, how are you?", "German"),
    ("Good morning!", "French"),
]

for text, target_lang in test_cases:
    print("\n" + "="*70)
    print(f"Input: \"{text}\"")
    print(f"Target: {target_lang}")
    print("-"*70)
    
    # Tokenize
    tok_start = time.time()
    inputs = tokenizer(text, return_tensors="np", padding="max_length", 
                      max_length=256, truncation=True)
    input_ids = inputs['input_ids'].astype(np.int64)
    attention_mask = inputs['attention_mask'].astype(np.int64)
    tok_time = (time.time() - tok_start) * 1000
    
    actual_tokens = np.sum(attention_mask)
    print(f"Tokenization: {tok_time:.1f}ms")
    print(f"Tokens: {actual_tokens}")
    print(f"Input IDs (first 10): {input_ids[0][:10].tolist()}")
    
    # Encode
    enc_start = time.time()
    encoder_outputs = encoder.run(
        None,
        {
            'input_ids': input_ids,
            'attention_mask': attention_mask,
        }
    )
    enc_time = (time.time() - enc_start) * 1000
    print(f"Encoder: {enc_time:.1f}ms")
    
    # Decode
    lang_token = lang_tokens[target_lang]
    decoder_input_ids = np.array([[2, lang_token]], dtype=np.int64)
    
    # Pad decoder input
    decoder_input = np.pad(
        decoder_input_ids[0],
        (0, 256 - len(decoder_input_ids[0])),
        constant_values=1
    ).reshape(1, 256).astype(np.int64)
    
    print(f"\nLanguage token: {lang_token}")
    print(f"Initial decoder input (first 10): {decoder_input[0][:10].tolist()}")
    
    generated_tokens = [2, lang_token]
    dec_start = time.time()
    
    for step in range(254):
        step_start = time.time()
        
        # Update decoder input
        decoder_input = np.array([generated_tokens + [1] * (256 - len(generated_tokens))], 
                                dtype=np.int64)
        
        # Run decoder
        decoder_outputs = decoder.run(
            None,
            {
                'input_ids': decoder_input,
                'encoder_hidden_states': encoder_outputs[0],
                'encoder_attention_mask': attention_mask,
            }
        )
        
        # Get next token
        logits = decoder_outputs[0]
        next_token_logits = logits[0, len(generated_tokens) - 1, :]
        next_token = np.argmax(next_token_logits)
        
        step_time = (time.time() - step_start) * 1000
        
        if step < 5:
            print(f"Step {step}: token={next_token}, time={step_time:.1f}ms")
        
        if next_token == 2:  # EOS
            print(f"EOS at step {step}")
            break
        
        generated_tokens.append(int(next_token))
    
    dec_time = (time.time() - dec_start) * 1000
    print(f"\nDecoder: {dec_time:.1f}ms")
    print(f"Generated tokens: {len(generated_tokens) - 2}")
    
    # Decode
    detok_start = time.time()
    output_tokens = generated_tokens[2:]  # Remove BOS and lang token
    result = tokenizer.decode(output_tokens, skip_special_tokens=True)
    detok_time = (time.time() - detok_start) * 1000
    
    print(f"Detokenization: {detok_time:.1f}ms")
    print(f"\n✅ Result: \"{result}\"")
    print(f"Total: {tok_time + enc_time + dec_time + detok_time:.1f}ms")

print("\n" + "="*70)