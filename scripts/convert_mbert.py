import os
import torch
import shutil
from pathlib import Path
from transformers import BertModel, BertTokenizer, BertConfig
from optimum.onnxruntime import ORTQuantizer
from optimum.onnxruntime.configuration import AutoQuantizationConfig

# Disable TF to avoid conflicts
os.environ["USE_TF"] = "OFF"

class MBERTLayerExtractor(torch.nn.Module):
    """Extracts exactly up to the target layer for awesome-align"""
    def __init__(self, bert_model, target_layer=8):
        super().__init__()
        self.embeddings = bert_model.embeddings
        self.encoder_layers = torch.nn.ModuleList(
            [bert_model.encoder.layer[i] for i in range(target_layer)]
        )
        
    def forward(self, input_ids, attention_mask):
        # 1. Embeddings
        hidden_states = self.embeddings(input_ids=input_ids)
        
        # 2. Mask preparation (BERT expects a mask of [batch, 1, 1, seq_len])
        extended_attention_mask = attention_mask[:, None, None, :]
        extended_attention_mask = extended_attention_mask.to(dtype=hidden_states.dtype)
        extended_attention_mask = (1.0 - extended_attention_mask) * torch.finfo(hidden_states.dtype).min
        
        # 3. Process through layers
        for layer in self.encoder_layers:
            layer_output = layer(hidden_states, extended_attention_mask)
            hidden_states = layer_output[0]
            
        return hidden_states

def convert_and_quantize_mbert(model_id="bert-base-multilingual-cased", target_layer=8):
    output_dir = Path("onnx_models/awesome_align")
    output_dir.mkdir(parents=True, exist_ok=True)
    onnx_path = output_dir / "model.onnx"

    print(f"📦 Loading mBERT and extracting up to Layer {target_layer}...")
    tokenizer = BertTokenizer.from_pretrained(model_id)
    config = BertConfig.from_pretrained(model_id)
    base_model = BertModel.from_pretrained(model_id, config=config)
    
    model = MBERTLayerExtractor(base_model, target_layer)
    model.eval()

    # Prepare dummy inputs
    dummy_input = tokenizer("Hello world", return_tensors="pt")
    input_tuple = (dummy_input['input_ids'], dummy_input['attention_mask'])
    
    print("🚀 Exporting to ONNX (Legacy Exporter)...")
    
    with torch.no_grad():
        torch.onnx.export(
            model,
            input_tuple,
            str(onnx_path),
            export_params=True,
            opset_version=17,
            do_constant_folding=True,
            input_names=['input_ids', 'attention_mask'],
            output_names=['last_hidden_state'],
            dynamic_axes={
                'input_ids': {0: 'batch', 1: 'sequence'},
                'attention_mask': {0: 'batch', 1: 'sequence'},
                'last_hidden_state': {0: 'batch', 1: 'sequence'}
            },
            dynamo=False # Forces weights to be bundled
        )

    # Save configs and tokenizer
    config.save_pretrained(output_dir)
    tokenizer.save_pretrained(output_dir)

    # FIXED: Correct size checking logic
    size_mb = onnx_path.stat().st_size / (1024 * 1024)
    print(f"✅ Exported Size: {size_mb:.2f} MB")

    if size_mb < 10:
        print("❌ ERROR: Model weights were not exported correctly.")
        return

    # Quantization Step
    print("\n⚖️ Quantizing to INT8 (Optimized for ARM64)...")
    quant_dir = Path(str(output_dir) + "_int8")
    quant_dir.mkdir(exist_ok=True)
    
    # AutoQuantizationConfig.arm64 is perfect for Apple Silicon
    q_config = AutoQuantizationConfig.arm64(is_static=False, per_channel=True)
    
    quantizer = ORTQuantizer.from_pretrained(output_dir, file_name="model.onnx")
    quantizer.quantize(save_dir=quant_dir, quantization_config=q_config)
    
    # Standardize files for InferenceSession
    config_files = ["tokenizer_config.json", "vocab.txt", "config.json", "special_tokens_map.json"]
    for f in config_files:
        if (output_dir / f).exists():
            shutil.copy(output_dir / f, quant_dir / f)
            
    # Cleanup: Rename to standard model.onnx
    if (quant_dir / "model_quantized.onnx").exists():
        if (quant_dir / "model.onnx").exists():
            (quant_dir / "model.onnx").unlink()
        (quant_dir / "model_quantized.onnx").rename(quant_dir / "model.onnx")

    print(f"✨ Success! Quantized model ready in: {quant_dir}")

if __name__ == "__main__":
    convert_and_quantize_mbert()