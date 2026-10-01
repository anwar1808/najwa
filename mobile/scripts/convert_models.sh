#!/bin/bash
# Reproduce the model files the app downloads: HF checkpoint → ggml f16 →
# quantised → uploaded as assets of the GitHub release mobile-models-v1
# (the HF token on this machine is read-only; see mobile/README.md → hosting).
#
# One-time setup (already done on Annie's Mac, 23 Sep 2026):
#   python3.11 -m venv .venv && source .venv/bin/activate
#   pip install torch transformers huggingface_hub numpy safetensors
#   git clone --depth 1 https://github.com/ggml-org/whisper.cpp ~/Annie-Claude/whisper.cpp
#   git clone --depth 1 https://github.com/openai/whisper     ~/Annie-Claude/openai-whisper
#   cmake (from the Android SDK) → build whisper-quantize in whisper.cpp/build
#
# Notes:
# - scripts/convert-h5-to-ggml-najwa.py is whisper.cpp's convert-h5-to-ggml.py
#   with two patches: (1) load weights as float32 (Mesolitica ships bf16, which
#   the stock script can't serialise); (2) drop Mesolitica's extra
#   <|transcribeprecise|> token — whisper.cpp derives every special-token id
#   from n_vocab, so that one extra row shifted them all (turbo segfaulted,
#   small leaked "<|6.0|>" timestamp tokens into the text).
# - Their repos have no vocab.json; it is regenerated from tokenizer.json.
set -euo pipefail
cd "$(dirname "$0")/.."
source .venv/bin/activate
source ~/.zshrc >/dev/null 2>&1 || true   # HF_TOKEN

W=~/Annie-Claude
Q=$W/whisper.cpp/build/bin/whisper-quantize
CONV=scripts/convert-h5-to-ggml-najwa.py

convert() { # <hf repo> <short>
  local repo=$1 short=$2 dir=models-work/$(basename "$1") out=models-work/ggml-$2
  python -c "from huggingface_hub import snapshot_download as s; s('$repo', local_dir='$dir', allow_patterns=['*.json','*.safetensors','*.txt'])"
  [ -f "$dir/vocab.json" ] || python -c "import json; json.dump(json.load(open('$dir/tokenizer.json'))['model']['vocab'], open('$dir/vocab.json','w'), ensure_ascii=False)"
  mkdir -p "$out"
  python "$CONV" "$dir" $W/openai-whisper "$out"
  for q in "${@:3}"; do "$Q" "$out/ggml-model.bin" "$out/$short-$q.bin" "$q"; done
}

convert mesolitica/Malaysian-whisper-large-v3-turbo-v3 malaysian-whisper-large-v3-turbo-v3 q5_0 q8_0
convert mesolitica/malaysian-whisper-small-v3          malaysian-whisper-small-v3          q8_0

# Publish: replace the release assets (asset ids change on --clobber; update
# app/src/main/assets/models.json accordingly).
gh release upload mobile-models-v1 --repo anwar1808/najwa --clobber \
  models-work/ggml-malaysian-whisper-large-v3-turbo-v3/malaysian-whisper-large-v3-turbo-v3-q5_0.bin \
  models-work/ggml-malaysian-whisper-large-v3-turbo-v3/malaysian-whisper-large-v3-turbo-v3-q8_0.bin \
  models-work/ggml-malaysian-whisper-small-v3/malaysian-whisper-small-v3-q8_0.bin
gh release view mobile-models-v1 --repo anwar1808/najwa --json assets --jq '.assets[] | "\(.name) \(.apiUrl)"'
