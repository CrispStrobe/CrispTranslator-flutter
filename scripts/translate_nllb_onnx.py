#!/usr/bin/env python3
# scripts/translate_nllb_onnx.py
"""
NLLB-200 ONNX INT8 Translation Bridge
Supports both single translation and batch server mode
"""
import sys
import json
import argparse
import traceback
from pathlib import Path
from optimum.onnxruntime import ORTModelForSeq2SeqLM
from transformers import AutoTokenizer
import os

os.environ["TOKENIZERS_PARALLELISM"] = "false"
# Suppress warnings to stderr
import warnings
warnings.filterwarnings("ignore")

class NLLBONNXTranslator:
    def __init__(self, model_dir: str, tokenizer_dir: str, verbose: bool = False):
        self.verbose = verbose
        
        # Resolve to absolute paths for stability
        model_path = Path(model_dir).resolve()
        tokenizer_path = Path(tokenizer_dir).resolve()
        
        if self.verbose:
            print(f"📦 Loading ONNX model from: {model_path}", file=sys.stderr)
            sys.stderr.flush()
        
        try:
            
            self.model = ORTModelForSeq2SeqLM.from_pretrained(
                model_path.as_posix(),
                encoder_file_name="encoder_model.onnx",
                decoder_file_name="decoder_model.onnx",
                decoder_with_past_file_name="decoder_with_past_model.onnx",
                use_cache=True,
                local_files_only=True
            )
            
            if self.verbose:
                print(f"✅ ONNX model loaded", file=sys.stderr)
                sys.stderr.flush()
        except Exception as e:
            import traceback
            print(f"❌ Failed to load ONNX model: {e}", file=sys.stderr)
            print(traceback.format_exc(), file=sys.stderr)
            sys.stderr.flush()
            raise
        
        try:
            if self.verbose:
                print(f"📦 Loading tokenizer from: {tokenizer_path}", file=sys.stderr)
                sys.stderr.flush()
            
            self.tokenizer = AutoTokenizer.from_pretrained(tokenizer_path.as_posix())
            
            if self.verbose:
                print(f"✅ Tokenizer loaded", file=sys.stderr)
                sys.stderr.flush()
        except Exception as e:
            print(f"❌ Failed to load tokenizer: {str(e)}", file=sys.stderr)
            sys.stderr.flush()
            raise
        
        # Language code mapping
        self.lang_codes = {
            'English': 'eng_Latn', 'German': 'deu_Latn', 'Spanish': 'spa_Latn',
            'French': 'fra_Latn', 'Italian': 'ita_Latn', 'Portuguese': 'por_Latn',
            'Russian': 'rus_Cyrl', 'Chinese': 'zho_Hans', 'Japanese': 'jpn_Jpan',
            'Korean': 'kor_Hang', 'Arabic': 'arb_Arab', 'Dutch': 'nld_Latn',
            'Polish': 'pol_Latn', 'Turkish': 'tur_Latn', 'Czech': 'ces_Latn',
            'Ukrainian': 'ukr_Cyrl', 'Vietnamese': 'vie_Latn', 'Hindi': 'hin_Deva',
        }
        
        if self.verbose:
            print("✅ Translator initialized successfully", file=sys.stderr)
            sys.stderr.flush()
    
    def translate(self, text: str, source_lang: str, target_lang: str) -> str:
        """Translate text from source to target language"""
        src_code = self.lang_codes.get(source_lang, 'eng_Latn')
        tgt_code = self.lang_codes.get(target_lang, 'deu_Latn')
        
        # Ensure we set the source language for the tokenizer if needed
        # NLLB usually expects the source lang to be set in the tokenizer
        inputs = self.tokenizer(text, return_tensors="pt")
        forced_bos_token_id = self.tokenizer.convert_tokens_to_ids(tgt_code)
        
        translated_tokens = self.model.generate(
            **inputs,
            forced_bos_token_id=forced_bos_token_id,
            max_length=256
        )
        
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
        sys.stdout.flush()
        
    except Exception as e:
        error = {
            "error": str(e),
            "type": type(e).__name__,
            "traceback": traceback.format_exc()
        }
        print(json.dumps(error))
        sys.stdout.flush()
        sys.exit(1)

def run_server(args):
    """Batch server mode - reads JSON requests from stdin"""
    try:
        print("🚀 Starting translation server...", file=sys.stderr)
        sys.stderr.flush()
        
        # Initialize once
        translator = NLLBONNXTranslator(args.model_dir, args.tokenizer_dir, verbose=True)
        
        print("📡 Sending ready signal...", file=sys.stderr)
        sys.stderr.flush()
        
        # Signal ready - CRITICAL: must flush!
        print(json.dumps({"status": "ready"}), flush=True)
        
        print("✅ Server ready, waiting for requests...", file=sys.stderr)
        sys.stderr.flush()
        
        # Process requests
        for line in sys.stdin:
            try:
                line = line.strip()
                if not line:
                    continue
                
                request = json.loads(line)
                
                if request.get("command") == "shutdown":
                    print("🛑 Shutdown command received", file=sys.stderr)
                    sys.stderr.flush()
                    print(json.dumps({"status": "shutdown"}), flush=True)
                    break
                
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
                print(f"❌ Error processing request: {e}", file=sys.stderr)
                sys.stderr.flush()
                error = {
                    "error": str(e),
                    "type": type(e).__name__,
                    "request_id": request.get("request_id") if 'request' in locals() else None
                }
                print(json.dumps(error), flush=True)
        
    except Exception as e:
        # Full error output for the Dart side to capture
        err_msg = str(e)
        tb = traceback.format_exc()
        print(f"❌ Server initialization failed: {err_msg}", file=sys.stderr)
        print(tb, file=sys.stderr)
        sys.stderr.flush()
        
        error = {
            "error": err_msg,
            "type": type(e).__name__,
            "status": "init_failed",
            "traceback": tb
        }
        print(json.dumps(error), flush=True)
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