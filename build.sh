#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
W="$ROOT/vendor-whisper"
# Separate dir per configuration, so turning CoreML on forces a clean rebuild
# instead of linking a stale non-CoreML libwhisper.
B="$W/build-mac-coreml"
SHERPA_VERSION="1.13.8"
SH="$ROOT/vendor-sherpa"
SH_LIB="$SH/sherpa-onnx-v$SHERPA_VERSION-osx-arm64-shared-no-tts-lib/lib"
SH_REL="https://github.com/k2-fsa/sherpa-onnx/releases/download"
APP="${YAPPERRONI_INSTALL_DIR:-/Applications}/Yapperroni.app"
BUNDLE_ID="com.rahuldesai.yapperroni"
SUPPORT="$HOME/Library/Application Support/Yapperroni"
MODEL="ggml-small.en-q5_1.bin"
IDENTITY_NAME="Yapperroni Local Signing"

# --- bootstrap ----------------------------------------------------------------
# whisper.cpp and the 181 MB model are not in git. Fetch them on first build so
# a fresh clone works with no manual steps.
if ! command -v cmake >/dev/null 2>&1; then
  echo "!! cmake is required:  brew install cmake"
  exit 1
fi

if [ ! -d "$W" ]; then
  echo "==> cloning whisper.cpp (first build only)"
  git clone --depth 1 https://github.com/ggml-org/whisper.cpp.git "$W"
fi

if [ ! -f "$B/src/libwhisper.a" ]; then
  echo "==> building whisper.cpp with Metal + CoreML (first build only, a few minutes)"
  # CoreML runs the encoder on the Neural Engine when a matching
  # <model>-encoder.mlmodelc sits beside the .bin. ALLOW_FALLBACK keeps every
  # model without one (the bundled small.en) on Metal instead of failing.
  cmake -B "$B" -S "$W" \
    -DCMAKE_BUILD_TYPE=Release \
    -DBUILD_SHARED_LIBS=OFF \
    -DGGML_METAL=ON -DGGML_METAL_EMBED_LIBRARY=ON \
    -DWHISPER_COREML=ON -DWHISPER_COREML_ALLOW_FALLBACK=ON \
    -DWHISPER_BUILD_TESTS=OFF -DWHISPER_BUILD_SERVER=OFF \
    -DCMAKE_OSX_ARCHITECTURES=arm64 >/dev/null
  cmake --build "$B" --config Release -j "$(sysctl -n hw.ncpu)" >/dev/null
fi

if [ ! -f "$ROOT/models/$MODEL" ]; then
  echo "==> downloading model $MODEL (181 MB, first build only)"
  mkdir -p "$ROOT/models"
  curl -L --fail --progress-bar \
    -o "$ROOT/models/$MODEL" \
    "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/$MODEL"
fi

# Silero VAD weights for whisper.cpp's built-in voice detection. 885 KB, so
# bundled rather than optional.
VAD_MODEL="ggml-silero-v6.2.0.bin"
if [ ! -f "$ROOT/models/$VAD_MODEL" ]; then
  echo "==> downloading VAD model $VAD_MODEL"
  mkdir -p "$ROOT/models"
  curl -L --fail -s -o "$ROOT/models/$VAD_MODEL" \
    "https://huggingface.co/ggml-org/whisper-vad/resolve/main/$VAD_MODEL"
fi

# sherpa-onnx runs the NeMo models (Parakeet, Canary). Prebuilt: the release
# tarball carries the dylibs but not the header, so that comes from the tag.
if [ ! -f "$SH_LIB/libsherpa-onnx-c-api.dylib" ]; then
  echo "==> downloading sherpa-onnx $SHERPA_VERSION (first build only)"
  mkdir -p "$SH"
  curl -L --fail --progress-bar \
    "$SH_REL/v$SHERPA_VERSION/sherpa-onnx-v$SHERPA_VERSION-osx-arm64-shared-no-tts-lib.tar.bz2" \
    | tar xj -C "$SH"
fi
if [ ! -f "$SH/include/sherpa-onnx/c-api/c-api.h" ]; then
  mkdir -p "$SH/include/sherpa-onnx/c-api"
  curl -L --fail -s -o "$SH/include/sherpa-onnx/c-api/c-api.h" \
    "https://raw.githubusercontent.com/k2-fsa/sherpa-onnx/v$SHERPA_VERSION/sherpa-onnx/c-api/c-api.h"
fi

# Optional models for recording modes, into the support folder rather than the
# bundle — 1.4 GB is not something to copy on every build. Opt-in for the same
# reason. A mode naming a model that is not there runs on the dictation model.
if [ "${YAPPERRONI_FETCH_MODELS:-0}" = "1" ]; then
  mkdir -p "$SUPPORT"
  if [ ! -d "$SUPPORT/ggml-large-v3-turbo-encoder.mlmodelc" ]; then
    echo "==> downloading turbo's CoreML encoder (Neural Engine)"
    curl -L --fail --progress-bar -o "$SUPPORT/turbo-coreml.zip" \
      "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-large-v3-turbo-encoder.mlmodelc.zip" \
      && unzip -q -o "$SUPPORT/turbo-coreml.zip" -d "$SUPPORT" && rm "$SUPPORT/turbo-coreml.zip"
  fi
  if [ ! -f "$SUPPORT/ggml-large-v3-turbo-q5_0.bin" ]; then
    echo "==> downloading whisper large-v3-turbo (574 MB)"
    curl -L --fail --progress-bar -o "$SUPPORT/ggml-large-v3-turbo-q5_0.bin.part" \
      "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-large-v3-turbo-q5_0.bin" \
      && mv "$SUPPORT/ggml-large-v3-turbo-q5_0.bin.part" "$SUPPORT/ggml-large-v3-turbo-q5_0.bin"
  fi
  for m in sherpa-onnx-nemo-parakeet-tdt-0.6b-v3-int8 sherpa-onnx-nemo-canary-180m-flash-en-es-de-fr-int8; do
    if [ ! -f "$SUPPORT/$m/tokens.txt" ]; then
      echo "==> downloading $m"
      curl -L --fail --progress-bar "$SH_REL/asr-models/$m.tar.bz2" | tar xj -C "$SUPPORT"
    fi
  done
fi

# Rebuild the .icns whenever the artwork changes.
if [ -f "$ROOT/assets/icon.png" ]; then
  if [ ! -f "$ROOT/assets/Yapperroni.icns" ] || \
     [ "$ROOT/assets/icon.png" -nt "$ROOT/assets/Yapperroni.icns" ]; then
    "$ROOT/make-icon.sh"
  fi
fi

# --- stable code signing identity -------------------------------------------
# TCC keys the Accessibility grant on the code signature. An ad-hoc signature
# changes every build, so the grant goes stale silently and the hotkey dies
# with no error. A self-signed cert kept in the login keychain fixes that.
SIGN_ID="-"
if security find-identity -v -p codesigning 2>/dev/null | grep -q "$IDENTITY_NAME"; then
  SIGN_ID="$IDENTITY_NAME"
else
  echo "==> creating self-signed signing identity '$IDENTITY_NAME' (one time)"
  TMP="$(mktemp -d)"
  cat > "$TMP/ext.cnf" <<'CNF'
[req]
distinguished_name = dn
prompt = no
[dn]
CN = Yapperroni Local Signing
[v3]
basicConstraints = critical,CA:false
keyUsage = critical,digitalSignature
extendedKeyUsage = critical,codeSigning
CNF
  if openssl req -x509 -newkey rsa:2048 -nodes -days 3650 \
       -keyout "$TMP/k.pem" -out "$TMP/c.pem" \
       -config "$TMP/ext.cnf" -extensions v3 >/dev/null 2>&1 \
     && openssl pkcs12 -export -inkey "$TMP/k.pem" -in "$TMP/c.pem" \
       -out "$TMP/i.p12" -passout pass:flow -name "$IDENTITY_NAME" \
       -macalg sha1 -certpbe PBE-SHA1-3DES -keypbe PBE-SHA1-3DES -legacy >/dev/null 2>&1 \
     && security import "$TMP/i.p12" -k "$HOME/Library/Keychains/login.keychain-db" \
       -P flow -T /usr/bin/codesign -A >/dev/null 2>&1 \
     && security add-trusted-cert -r trustRoot -p codeSign \
       -k "$HOME/Library/Keychains/login.keychain-db" "$TMP/c.pem" >/dev/null 2>&1
  then
    SIGN_ID="$IDENTITY_NAME"
    echo "    ok"
  else
    echo "    could not create one — falling back to ad-hoc."
    echo "    You may need to re-grant Accessibility after each rebuild."
  fi
  rm -rf "$TMP"
fi

# --- compile ------------------------------------------------------------------
echo "==> compiling"
mkdir -p "$ROOT/.build"
BIN="$ROOT/.build/Yapperroni"

swiftc \
  -O -swift-version 5 \
  -target arm64-apple-macos26.0 \
  -import-objc-header "$ROOT/Sources/bridge.h" \
  -I "$W/include" -I "$W/ggml/include" -I "$SH/include" \
  "$ROOT/Sources/Config.swift" \
  "$ROOT/Sources/Log.swift" \
  "$ROOT/Sources/KeyBinding.swift" \
  "$ROOT/Sources/Keychain.swift" \
  "$ROOT/Sources/Cleanup.swift" \
  "$ROOT/Sources/Vocabulary.swift" \
  "$ROOT/Sources/Settings.swift" \
  "$ROOT/Sources/KeyRecorder.swift" \
  "$ROOT/Sources/History.swift" \
  "$ROOT/Sources/MainWindow.swift" \
  "$ROOT/Sources/VocabWindow.swift" \
  "$ROOT/Sources/Views.swift" \
  "$ROOT/Sources/ModesView.swift" \
  "$ROOT/Sources/Welcome.swift" \
  "$ROOT/Sources/Sherpa.swift" \
  "$ROOT/Sources/Whisper.swift" \
  "$ROOT/Sources/Streaming.swift" \
  "$ROOT/Sources/SystemAudio.swift" \
  "$ROOT/Sources/InputDevices.swift" \
  "$ROOT/Sources/Recorder.swift" \
  "$ROOT/Sources/Hotkey.swift" \
  "$ROOT/Sources/Injector.swift" \
  "$ROOT/Sources/HUD.swift" \
  "$ROOT/Sources/App.swift" \
  "$ROOT/Sources/main.swift" \
  "$B/src/libwhisper.a" \
  "$B/src/libwhisper.coreml.a" \
  "$B/ggml/src/libggml.a" \
  "$B/ggml/src/libggml-cpu.a" \
  "$B/ggml/src/ggml-metal/libggml-metal.a" \
  "$B/ggml/src/ggml-blas/libggml-blas.a" \
  "$B/ggml/src/libggml-base.a" \
  -L "$SH_LIB" -lsherpa-onnx-c-api \
  -Xlinker -rpath -Xlinker @executable_path/../Frameworks \
  -lc++ \
  -framework Accelerate -framework Metal -framework MetalKit -framework CoreML \
  -framework Foundation -framework AVFoundation -framework Cocoa \
  -framework CoreAudio -framework AudioToolbox -framework Carbon \
  -framework ServiceManagement -framework QuartzCore \
  -framework SwiftUI -framework Combine \
  -o "$BIN"

# --- bundle -------------------------------------------------------------------
echo "==> bundling $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Yapperroni"
cp "$ROOT/Info.plist" "$APP/Contents/Info.plist"
if [ -f "$ROOT/assets/Yapperroni.icns" ]; then
  cp "$ROOT/assets/Yapperroni.icns" "$APP/Contents/Resources/Yapperroni.icns"
fi
printf 'APPL????' > "$APP/Contents/PkgInfo"
cp "$ROOT/models/$VAD_MODEL" "$APP/Contents/Resources/$VAD_MODEL"
mkdir -p "$APP/Contents/Frameworks"
cp -L "$SH_LIB/libsherpa-onnx-c-api.dylib" "$SH_LIB/libonnxruntime.dylib" "$APP/Contents/Frameworks/"

# The model ships inside the bundle so the app is self-contained and can be
# handed over as a single .app. Anything the user drops in Application Support
# still wins over it. YAPPERRONI_SKIP_MODEL=1 skips the 181 MB copy for fast rebuilds
# when a copy is already in Application Support.
if [ -f "$ROOT/models/$MODEL" ]; then
  if [ "${YAPPERRONI_SKIP_MODEL:-0}" = "1" ] && [ -f "$APP/Contents/Resources/$MODEL" ]; then
    echo "==> skipping model copy (YAPPERRONI_SKIP_MODEL=1)"
  else
    echo "==> bundling model ($(du -h "$ROOT/models/$MODEL" | cut -f1))"
    cp "$ROOT/models/$MODEL" "$APP/Contents/Resources/$MODEL"
  fi
else
  echo "!! model missing: $ROOT/models/$MODEL"
fi

echo "==> signing with: $SIGN_ID"
# No --options runtime: hardened runtime denies microphone input without a
# com.apple.security.device.audio-input entitlement, and we are not notarizing.
codesign --force --deep \
  --sign "$SIGN_ID" \
  --identifier "$BUNDLE_ID" \
  "$APP" 2>&1 | sed 's/^/    /' || true

codesign --verify --strict "$APP" 2>&1 | sed 's/^/    /' \
  && echo "    signature verified"

touch "$APP"
echo
echo "built: $APP"
echo "run:   open '$APP'"
echo "test:  '$APP/Contents/MacOS/Yapperroni' --selftest-whisper $W/samples/jfk.wav"
