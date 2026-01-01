# CrispTranslator

A cross-platform offline neural machine translation app powered by NLLB-200 (No Language Left Behind).

## Features

- 🌍 **200+ Languages** - Translate between any supported language pair
- 📴 **Fully Offline** - All processing happens on-device after initial model download
- 🚀 **Fast Translation** - Optimized ONNX models with INT8 quantization
- 💾 **Auto Model Management** - Downloads models from HuggingFace on first launch
- 🎯 **High Quality** - State-of-the-art neural machine translation

## Supported Languages

- English, German, French, Spanish, Italian, Portuguese
- Japanese, Chinese (Simplified), Korean
- Arabic, Hindi
- ...and 190+ more!

## Requirements

- **Storage**: ~1.9 GB for AI models
- **RAM**: 2 GB minimum recommended
- **Internet**: Required only for initial model download

## Getting Started

### Installation

1. Clone the repository:
```bash
git clone https://github.com/CrispStrobe/CrispTranslator-flutter
cd CrispTranslator-flutter
```

2. Install dependencies:
```bash
flutter pub get
```

3. Run the app:
```bash
flutter run
```

On first launch, the app will download the required AI models (~1.9 GB) from HuggingFace.

### Building

**Android:**
```bash
flutter build apk --release
```

**iOS:**
```bash
flutter build ios --release
```

**Desktop:**
```bash
flutter build macos --release  # macOS
flutter build windows --release  # Windows
flutter build linux --release  # Linux
```

## How It Works

CrispTranslator uses the NLLB-200 model (600M parameters, INT8 quantized) converted to ONNX format for efficient on-device inference:

1. **Tokenization** - Text is split into subword tokens using SentencePiece
2. **Encoding** - Source text is encoded into embeddings
3. **Decoding** - Target language text is generated using autoregressive decoding with KV caching
4. **Detokenization** - Tokens are converted back to readable text

## Model Details

- **Model**: NLLB-200-distilled-600M
- **Quantization**: INT8 (4x smaller than FP32)
- **Format**: ONNX with separate encoder/decoder
- **Source**: [HuggingFace - cstr/nllb_600m_int8_onnx](https://huggingface.co/cstr/nllb_600m_int8_onnx)

## Architecture
```
lib/
├── main.dart                           # UI and app entry point
└── services/
    ├── onnx_translation_service.dart   # ONNX inference engine
    ├── nllb_tokenizer.dart             # SentencePiece tokenizer
    └── model_downloader.dart           # HuggingFace model management
```

## Performance

Translation speed varies by device and text length:
- **Mobile**: ~1-2 seconds per sentence
- **Desktop**: ~0.5-1 second per sentence

## License

MIT License - See LICENSE file for details

## Credits

- **NLLB Model**: Meta AI Research
- **ONNX Conversion**: cstr
- **Flutter ONNX Runtime**: onnxruntime package

## Troubleshooting

**Models fail to download:**
- Check internet connection
- Verify ~2 GB free storage
- Try restarting the app

**Translation errors:**
- Ensure models are fully downloaded
- Check available RAM (2 GB minimum)
- Restart the app

**Slow performance:**
- Close other apps to free RAM
- Try shorter input text
- Consider using a more powerful device

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.
