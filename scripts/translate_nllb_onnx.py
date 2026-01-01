#!/usr/bin/env python3
# scripts/translate_nllb_onnx.py
"""
NLLB-200 ONNX INT8 Translation Bridge
Supports both single translation and batch server mode
"""
import sys
import json
import argparse
from pathlib import Path
from optimum.onnxruntime import ORTModelForSeq2SeqLM
from transformers import AutoTokenizer
import os

os.environ["TOKENIZERS_PARALLELISM"] = "false"
# Suppress warnings
import warnings
warnings.filterwarnings("ignore")

class NLLBONNXTranslator:
    def __init__(self, model_dir: str, tokenizer_dir: str, verbose: bool = False):
        self.verbose = verbose
        
        if self.verbose:
            print(f"📦 Loading ONNX model from: {model_dir}", file=sys.stderr)
        
        self.model = ORTModelForSeq2SeqLM.from_pretrained(
            model_dir,
            encoder_file_name="encoder_model.onnx",
            decoder_file_name="decoder_model.onnx",
            decoder_with_past_file_name="decoder_with_past_model.onnx",
            use_cache=True
        )
        
        # Load tokenizer from separate directory
        if self.verbose:
            print(f"📦 Loading tokenizer from: {tokenizer_dir}", file=sys.stderr)
        self.tokenizer = AutoTokenizer.from_pretrained(tokenizer_dir)
        
        # Language code mapping
        self.lang_codes = {
            'English': 'eng_Latn',
            'German': 'deu_Latn',
            'Spanish': 'spa_Latn',
            'French': 'fra_Latn',
            'Italian': 'ita_Latn',
            'Portuguese': 'por_Latn',
            'Russian': 'rus_Cyrl',
            'Chinese': 'zho_Hans',
            'Japanese': 'jpn_Jpan',
            'Korean': 'kor_Hang',
            'Arabic': 'arb_Arab',
            'Dutch': 'nld_Latn',
            'Polish': 'pol_Latn',
            'Turkish': 'tur_Latn',
            'Czech': 'ces_Latn',
            'Ukrainian': 'ukr_Cyrl',
            'Vietnamese': 'vie_Latn',
            'Hindi': 'hin_Deva',
        }
        
        if self.verbose:
            print("✅ Model loaded successfully", file=sys.stderr)
    
    def translate(self, text: str, source_lang: str, target_lang: str) -> str:
        """Translate text from source to target language"""
        src_code = self.lang_codes.get(source_lang, 'eng_Latn')
        tgt_code = self.lang_codes.get(target_lang, 'deu_Latn')
        
        # Tokenize
        inputs = self.tokenizer(text, return_tensors="pt")
        forced_bos_token_id = self.tokenizer.convert_tokens_to_ids(tgt_code)
        
        # Generate
        translated_tokens = self.model.generate(
            **inputs,
            forced_bos_token_id=forced_bos_token_id,
            max_length=256
        )
        
        # Decode
        translation = self.tokenizer.batch_decode(
            translated_tokens, 
            skip_special_tokens=True
        )[0]
        
        return translation

def run_single(args):
    """Single translation mode"""
    try:
        translator = NLLBONNXTranslator(args.model_dir, args.tokenizer_dir, args.verbose)
        translation = translator.translate(args.text, args.source, args.target)
        
        result = {
            "translation": translation,
            "source": args.source,
            "target": args.target
        }
        print(json.dumps(result))
        
    except Exception as e:
        error = {
            "error": str(e),
            "type": type(e).__name__
        }
        print(json.dumps(error))
        sys.exit(1)

def run_server(args):
    """Batch server mode - reads JSON requests from stdin, writes responses to stdout"""
    try:
        # Initialize once
        translator = NLLBONNXTranslator(args.model_dir, args.tokenizer_dir, verbose=False)
        
        # Signal ready
        print(json.dumps({"status": "ready"}), flush=True)
        
        # Process requests
        for line in sys.stdin:
            try:
                line = line.strip()
                if not line:
                    continue
                
                request = json.loads(line)
                
                # Handle shutdown
                if request.get("command") == "shutdown":
                    print(json.dumps({"status": "shutdown"}), flush=True)
                    break
                
                # Translate
                text = request.get("text", "")
                source = request.get("source", "English")
                target = request.get("target", "German")
                
                translation = translator.translate(text, source, target)
                
                response = {
                    "translation": translation,
                    "request_id": request.get("request_id")
                }
                print(json.dumps(response), flush=True)
                
            except Exception as e:
                error = {
                    "error": str(e),
                    "type": type(e).__name__,
                    "request_id": request.get("request_id") if 'request' in locals() else None
                }
                print(json.dumps(error), flush=True)
        
    except Exception as e:
        error = {
            "error": str(e),
            "type": type(e).__name__,
            "status": "init_failed"
        }
        print(json.dumps(error))
        sys.exit(1)

def main():
    parser = argparse.ArgumentParser(description='NLLB ONNX Translation Bridge')
    parser.add_argument('--server', action='store_true', 
                       help='Run in server mode (batch processing)')
    parser.add_argument('--model-dir', default='assets/onnx_models',
                       help='Path to ONNX model directory')
    parser.add_argument('--tokenizer-dir', default='assets/models',
                       help='Path to tokenizer directory')
    parser.add_argument('--verbose', '-v', action='store_true',
                       help='Verbose output')
    
    # Single translation mode arguments
    parser.add_argument('text', nargs='?', help='Text to translate')
    parser.add_argument('source', nargs='?', help='Source language')
    parser.add_argument('target', nargs='?', help='Target language')
    
    args = parser.parse_args()
    
    if args.server:
        run_server(args)
    else:
        if not args.text or not args.source or not args.target:
            parser.error("Single mode requires text, source, and target arguments")
        run_single(args)

if __name__ == '__main__':
    main()