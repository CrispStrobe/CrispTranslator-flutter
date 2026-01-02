#!/usr/bin/env python3
# scripts/translate_nllb_onnx.py
"""
NLLB-200 ONNX INT8 Translation & BERT Alignment Bridge
Unified Multi-Capability Server for Docx Preservation
"""

import sys
import json
import argparse
import traceback
import os
import time
import warnings
from pathlib import Path

# Third-party imports
try:
    import numpy as np
    import onnxruntime as ort
    from optimum.onnxruntime import ORTModelForSeq2SeqLM
    from transformers import AutoTokenizer
except ImportError as e:
    print(json.dumps({
        "error": f"Missing required packages: {str(e)}",
        "type": "ImportError",
        "status": "init_failed"
    }), flush=True)
    sys.exit(1)

# Environment configuration
os.environ["TOKENIZERS_PARALLELISM"] = "false"
warnings.filterwarnings("ignore")

class UnifiedTranslator:
    def __init__(self, model_dir, tokenizer_dir, aligner_dir, verbose=False):
        self.verbose = verbose
        self.model_path = Path(model_dir).resolve()
        self.tokenizer_path = Path(tokenizer_dir).resolve()
        self.align_path = Path(aligner_dir).resolve() if aligner_dir else None
        self.beam_size = 4
        self.repetition_penalty = 1.2
        self.no_repeat_ngram_size = 3
        self.max_length = 256


        if self.verbose:
            print(f"📦 Loading ONNX model from: {self.model_path}", file=sys.stderr)
            print(f"📦 Loading tokenizer from: {self.tokenizer_path}", file=sys.stderr)
            sys.stderr.flush()

        # 1. Load NLLB Translation Model
        try:
            # Note: We point to the model_path where weights + config co-exist
            self.model = ORTModelForSeq2SeqLM.from_pretrained(
                self.model_path.as_posix(),
                encoder_file_name="encoder_model.onnx",
                decoder_file_name="decoder_model.onnx",
                decoder_with_past_file_name="decoder_with_past_model.onnx",
                use_cache=True,
                local_files_only=True
            )
            self.tokenizer = AutoTokenizer.from_pretrained(self.tokenizer_path.as_posix())
            if self.verbose:
                print(f"✅ NLLB translation engine ready", file=sys.stderr)
        except Exception as e:
            self._handle_fatal_error("NLLB Load Failure", e)

        # 2. Load BERT Aligner (Optional but recommended)
        self.align_sess = None
        self.align_tokenizer = None
        if self.align_path and self.align_path.exists():
            try:
                if self.verbose:
                    print(f"📦 Loading BERT Aligner from: {self.align_path}", file=sys.stderr)
                
                sess_options = ort.SessionOptions()
                sess_options.intra_op_num_threads = 1
                
                model_file = self.align_path / "model.onnx"
                if not model_file.exists():
                    raise FileNotFoundError(f"model.onnx not found in {self.align_path}")

                self.align_sess = ort.InferenceSession(
                    model_file.as_posix(),
                    sess_options,
                    providers=['CPUExecutionProvider']
                )
                self.align_tokenizer = AutoTokenizer.from_pretrained("bert-base-multilingual-cased")
                if self.verbose:
                    print(f"✅ BERT alignment engine ready", file=sys.stderr)
            except Exception as e:
                print(f"⚠️ Aligner failed to load (falling back to no-align mode): {e}", file=sys.stderr)

        # Language code mapping
        self.lang_codes = {
            'English': 'eng_Latn', 'German': 'deu_Latn', 'Spanish': 'spa_Latn',
            'French': 'fra_Latn', 'Italian': 'ita_Latn', 'Portuguese': 'por_Latn',
            'Russian': 'rus_Cyrl', 'Chinese': 'zho_Hans', 'Japanese': 'jpn_Jpan',
            'Korean': 'kor_Hang', 'Arabic': 'arb_Arab', 'Dutch': 'nld_Latn',
            'Polish': 'pol_Latn', 'Turkish': 'tur_Latn', 'Czech': 'ces_Latn',
            'Ukrainian': 'ukr_Cyrl', 'Vietnamese': 'vie_Latn', 'Hindi': 'hin_Deva',
        }

    def update_settings(self, beam_size=None, repetition_penalty=None, 
                       no_repeat_ngram_size=None, max_length=None):
        if beam_size is not None:
            self.beam_size = beam_size
        if repetition_penalty is not None:
            self.repetition_penalty = repetition_penalty
        if no_repeat_ngram_size is not None:
            self.no_repeat_ngram_size = no_repeat_ngram_size
        if max_length is not None:
            self.max_length = max_length

    def _handle_fatal_error(self, context, exception):
        error_data = {
            "error": f"{context}: {str(exception)}",
            "type": type(exception).__name__,
            "traceback": traceback.format_exc(),
            "status": "init_failed"
        }
        print(json.dumps(error_data), flush=True)
        print(f"❌ FATAL: {error_data['error']}", file=sys.stderr)
        sys.stderr.flush()
        sys.exit(1)

    def _get_bert_embeddings(self, words):
        #BERT embedding generation for word alignment
        encoded = self.align_tokenizer(words, is_split_into_words=True, return_tensors="np")
        word_map = []
        for i, word in enumerate(words):
            sub_tokens = self.align_tokenizer.tokenize(word) or [self.align_tokenizer.unk_token]
            word_map.extend([i] * len(sub_tokens))

        outputs = self.align_sess.run(None, {
            "input_ids": encoded["input_ids"],
            "attention_mask": encoded["attention_mask"]
        })
        
        # Remove [CLS] and [SEP] tokens (start/end)
        embeddings = outputs[0][0, 1:-1, :]
        
        # Normalize for cosine similarity
        norm = embeddings / (np.linalg.norm(embeddings, axis=-1, keepdims=True) + 1e-9)
        return norm, word_map

    def translate_and_align(self, text, source_lang, target_lang):
        """Perform translation and word alignment in a single pass"""
        try:
            # PASS-THROUGH FILTER
            if text.startswith("http") or text.startswith("www"):
                return text, [] # Don't translate URLs, return as is
            
            # 1. Translation Setup
            src_code = self.lang_codes.get(source_lang, 'eng_Latn')
            tgt_code = self.lang_codes.get(target_lang, 'deu_Latn')
            
            # CRITICAL: Set the source language on the tokenizer
            self.tokenizer.src_lang = src_code
            
            # Prepare inputs
            inputs = self.tokenizer(text, return_tensors="pt")
            forced_bos_token_id = self.tokenizer.convert_tokens_to_ids(tgt_code)
            
            # Generate with stricter parameters to prevent EU Commission loops
            tokens = self.model.generate(
                **inputs,
                forced_bos_token_id=forced_bos_token_id,
                max_length=self.max_length,
                num_beams=self.beam_size,
                repetition_penalty=self.repetition_penalty,
                no_repeat_ngram_size=self.no_repeat_ngram_size
            )

            
            translation = self.tokenizer.batch_decode(tokens, skip_special_tokens=True)[0]

            # 2. Alignment Logic (Remains as before)
            links = []
            if self.align_sess:
                # Tokenize by simple whitespace for alignment input
                src_words = text.split()
                tgt_words = translation.split()
                
                if src_words and tgt_words:
                    src_emb, src_map = self._get_bert_embeddings(src_words)
                    tgt_emb, tgt_map = self._get_bert_embeddings(tgt_words)
                    
                    similarity = np.dot(src_emb, tgt_emb.T)
                    
                    # Symmetric Argmax (Competitive Selection)
                    best_tgt_for_src = np.argmax(similarity, axis=1)
                    best_src_for_tgt = np.argmax(similarity, axis=0)

                    seen = set()
                    for i, j in enumerate(best_tgt_for_src):
                        if best_src_for_tgt[j] == i:
                            # Map sub-token indices back to whole word indices
                            s_idx, t_idx = src_map[i], tgt_map[j]
                            if (s_idx, t_idx) not in seen:
                                links.append({"s": int(s_idx), "t": int(t_idx)})
                                seen.add((s_idx, t_idx))

            return translation, links

        except Exception as e:
            return None, str(e)

def run_server(args):
    """Server mode for batch processing requests via stdin"""
    try:
        if args.verbose:
            print("🚀 Initializing Unified Translation Server...", file=sys.stderr)
        
        engine = UnifiedTranslator(
            args.model_dir, 
            args.tokenizer_dir, 
            args.aligner_dir, 
            args.verbose
        )
        
        # Ready signal for Dart
        print(json.dumps({"status": "ready"}), flush=True)
        if args.verbose:
            print("📡 Server ready, listening on stdin...", file=sys.stderr)
        
        for line in sys.stdin:
            line = line.strip()
            if not line: continue
            
            try:
                request = json.loads(line)
                
                if request.get("command") == "update_settings":
                    engine.update_settings(
                        beam_size=request.get("beam_size"),
                        repetition_penalty=request.get("repetition_penalty"),
                        no_repeat_ngram_size=request.get("no_repeat_ngram_size"),
                        max_length=request.get("max_length")
                    )
                    print(json.dumps({"status": "settings_updated"}), flush=True)
                    continue
                
                text = request.get("text", "")
                source = request.get("source", "English")
                target = request.get("target", "German")
                req_id = request.get("request_id")
                
                translation, alignments = engine.translate_and_align(text, source, target)
                
                if translation is not None:
                    response = {
                        "translation": translation,
                        "alignments": alignments,
                        "request_id": req_id
                    }
                else:
                    response = {
                        "error": alignments, # In case of error, translation is None and alignments is the error string
                        "request_id": req_id
                    }
                
                print(json.dumps(response), flush=True)
                
            except Exception as e:
                print(f"❌ Error processing request: {e}", file=sys.stderr)
                print(json.dumps({"error": str(e), "status": "error"}), flush=True)

    except Exception as e:
        # Final catch-all for init failures
        error_msg = str(e)
        print(json.dumps({
            "error": error_msg, 
            "status": "init_failed",
            "traceback": traceback.format_exc()
        }), flush=True)
        sys.exit(1)

def run_single(args):
    """Single-shot translation mode"""
    engine = UnifiedTranslator(args.model_dir, args.tokenizer_dir, args.aligner_dir, args.verbose)
    translation, alignments = engine.translate_and_align(args.text, args.source, args.target)
    
    if translation:
        print(json.dumps({
            "translation": translation,
            "alignments": alignments,
            "source": args.source,
            "target": args.target
        }))
    else:
        print(json.dumps({"error": alignments}))
        sys.exit(1)

def main():
    parser = argparse.ArgumentParser(description='Unified NLLB ONNX & BERT Bridge')
    parser.add_argument('--server', action='store_true', help='Run in server mode')
    parser.add_argument('--model-dir', default='assets/onnx_models', help='Path to ONNX weights')
    parser.add_argument('--tokenizer-dir', default='assets/models', help='Path to tokenizer/config')
    parser.add_argument('--aligner-dir', default='assets/onnx_models/awesome_align_int8', help='Path to Aligner model')
    parser.add_argument('--verbose', '-v', action='store_true', help='Enable verbose debug logs')
    
    parser.add_argument('text', nargs='?', help='Text to translate')
    parser.add_argument('source', nargs='?', help='Source language')
    parser.add_argument('target', nargs='?', help='Target language')
    
    args = parser.parse_args()
    
    if args.server:
        run_server(args)
    else:
        if not args.text or not args.source or not args.target:
            parser.error("Single mode requires text, source, and target")
        run_single(args)

if __name__ == '__main__':
    main()