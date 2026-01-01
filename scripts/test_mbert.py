import numpy as np
import onnxruntime as ort
from transformers import AutoTokenizer
import time
from typing import List, Tuple, Dict

class AwesomeAlignTester:
    def __init__(self, model_path: str, name: str):
        self.name = name
        # Optimization: Use sequential execution for small models like BERT on CPU
        sess_options = ort.SessionOptions()
        sess_options.intra_op_num_threads = 1
        
        self.session = ort.InferenceSession(model_path, sess_options, providers=['CPUExecutionProvider'])
        self.tokenizer = AutoTokenizer.from_pretrained("bert-base-multilingual-cased")

    def get_embeddings(self, words: List[str]):
        # is_split_into_words ensures the tokenizer doesn't re-split on spaces
        encoded = self.tokenizer(words, is_split_into_words=True, return_tensors="np")
        
        # Build word map for subwords manually to ensure alignment
        word_map = []
        for word_idx, word in enumerate(words):
            sub_tokens = self.tokenizer.tokenize(word) or [self.tokenizer.unk_token]
            word_map.extend([word_idx] * len(sub_tokens))

        outputs = self.session.run(None, {
            "input_ids": encoded["input_ids"],
            "attention_mask": encoded["attention_mask"]
        })
        # Slice out [CLS] and [SEP]
        return outputs[0][0, 1:-1, :], word_map

    def align(self, src_words: List[str], tgt_words: List[str]) -> List[Tuple[int, int]]:
        src_out, src_map = self.get_embeddings(src_words)
        tgt_out, tgt_map = self.get_embeddings(tgt_words)

        # Cosine Similarity
        src_norm = src_out / np.linalg.norm(src_out, axis=-1, keepdims=True)
        tgt_norm = tgt_out / np.linalg.norm(tgt_out, axis=-1, keepdims=True)
        similarity = np.dot(src_norm, tgt_norm.T)

        best_tgt_for_src = np.argmax(similarity, axis=1)
        best_src_for_tgt = np.argmax(similarity, axis=0)

        align_indices = set()
        for i, j in enumerate(best_tgt_for_src):
            if best_src_for_tgt[j] == i:
                align_indices.add((src_map[i], tgt_map[j]))
        
        return sorted(list(align_indices))

def run_benchmark():
    models = {
        "FP32": "assets/onnx_models/awesome_align/model.onnx",
        "INT8": "assets/onnx_models/awesome_align_int8/model.onnx"
    }
    
    test_cases = [
        {
            "src": "The international financial architecture is complex .".split(),
            "tgt": "L' architecture financière internationale est complexe .".split()
        },
        {
            "src": "I will go to the hospital tomorrow morning .".split(),
            "tgt": "Ich werde morgen früh ins Krankenhaus gehen .".split()
        }
    ]

    for label, path in models.items():
        print(f"\n" + "="*50)
        print(f"🚀 BENCHMARKING: {label}")
        print(f"Path: {path}")
        print("="*50)
        
        try:
            tester = AwesomeAlignTester(path, label)
            start_time = time.time()
            
            # Run test cases
            for i, case in enumerate(test_cases):
                links = tester.align(case["src"], case["tgt"])
                print(f"\nCase {i+1}: {' '.join(case['src'][:5])}...")
                print(f"Links: {links}")
                
                # Visual Check for the first few links
                for s_idx, t_idx in links[:3]:
                    print(f"  [Match] {case['src'][s_idx]} <-> {case['tgt'][t_idx]}")
            
            end_time = time.time()
            avg_time = (end_time - start_time) / len(test_cases)
            print(f"\n⏱️ Average Latency: {avg_time*1000:.2f} ms per sentence")
            
        except Exception as e:
            print(f"❌ Error testing {label}: {e}")

if __name__ == "__main__":
    run_benchmark()