# scripts/translate_nllb.py
#!/usr/bin/env python3
import sys
import json
from transformers import AutoTokenizer, AutoModelForSeq2SeqLM

# Global cache
model = None
tokenizer = None

def init_model():
    global model, tokenizer
    if model is None:
        tokenizer = AutoTokenizer.from_pretrained("facebook/nllb-200-distilled-600M")
        model = AutoModelForSeq2SeqLM.from_pretrained("facebook/nllb-200-distilled-600M")

def translate(text, src_lang, tgt_lang):
    init_model()
    
    lang_codes = {
        'English': 'eng_Latn', 'German': 'deu_Latn', 'Spanish': 'spa_Latn',
        'French': 'fra_Latn', 'Italian': 'ita_Latn', 'Portuguese': 'por_Latn',
    }
    
    src_code = lang_codes.get(src_lang, 'eng_Latn')
    tgt_code = lang_codes.get(tgt_lang, 'deu_Latn')
    
    inputs = tokenizer(text, return_tensors="pt", src_lang=src_code)
    translated = model.generate(
        **inputs,
        forced_bos_token_id=tokenizer.convert_tokens_to_ids(tgt_code),
        max_length=256
    )
    
    return tokenizer.decode(translated[0], skip_special_tokens=True)

if __name__ == '__main__':
    if len(sys.argv) != 4:
        print(json.dumps({"error": "Usage: script.py <text> <src> <tgt>"}))
        sys.exit(1)
    
    text, src, tgt = sys.argv[1], sys.argv[2], sys.argv[3]
    result = translate(text, src, tgt)
    print(json.dumps({"translation": result}))