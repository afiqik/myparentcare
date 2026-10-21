#!/usr/bin/env bash
# Jana kunci UPLOAD Google Play untuk MyParentCare (sekali sahaja).
#
# * Keystore disimpan DI LUAR projek: ~/myparentcare-keys/upload-keystore.jks
# * Kata laluan rawak ditulis ke android/key.properties (diabaikan oleh git)
# * SIMPAN SALINAN keystore + key.properties di tempat selamat (contoh: Google
#   Drive peribadi / pengurus kata laluan). Jika hilang, kunci upload boleh
#   diset semula melalui Play Console (Play App Signing), tetapi prosesnya lambat.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
KEY_DIR="${MYPARENTCARE_KEY_DIR:-$HOME/myparentcare-keys}"
STORE="$KEY_DIR/upload-keystore.jks"
PROPS="$ROOT/android/key.properties"

if [[ -f "$STORE" || -f "$PROPS" ]]; then
  echo "Keystore atau key.properties sudah wujud – tidak ditimpa."
  echo "  $STORE"
  echo "  $PROPS"
  exit 1
fi

mkdir -p "$KEY_DIR"
chmod 700 "$KEY_DIR"
PASS="$(openssl rand -hex 24)"

keytool -genkeypair -v \
  -keystore "$STORE" -storetype PKCS12 \
  -keyalg RSA -keysize 4096 -validity 10000 \
  -alias upload \
  -storepass "$PASS" -keypass "$PASS" \
  -dname "CN=MyParentCare, OU=Mobile, O=MyParentCare, L=Batu Pahat, ST=Johor, C=MY" >/dev/null

umask 077
cat > "$PROPS" <<PROPS
storePassword=$PASS
keyPassword=$PASS
keyAlias=upload
storeFile=$STORE
PROPS
chmod 600 "$PROPS" "$STORE"

echo "Kunci upload dicipta:"
echo "  Keystore : $STORE"
echo "  Tetapan  : $PROPS"
echo
echo "Cap jari (tambah kedua-duanya dalam Firebase > Project settings > Android app):"
keytool -list -v -keystore "$STORE" -alias upload -storepass "$PASS" | grep -E "SHA1:|SHA256:"
