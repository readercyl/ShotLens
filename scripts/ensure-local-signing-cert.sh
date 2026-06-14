#!/usr/bin/env bash
set -euo pipefail

IDENTITY="${SHOTLENS_LOCAL_CODESIGN_IDENTITY:-ShotLens Local Signing}"
KEYCHAIN="${SHOTLENS_KEYCHAIN:-$HOME/Library/Keychains/login.keychain-db}"

if security find-identity -v -p codesigning "$KEYCHAIN" 2>/dev/null | rg -F "$IDENTITY" >/dev/null; then
  echo "$IDENTITY"
  exit 0
fi

TMP_DIR="$(mktemp -d)"
P12_PASSWORD="$(openssl rand -hex 24)"
cleanup() {
  rm -rf "$TMP_DIR"
}
trap cleanup EXIT

OPENSSL_CONF="$TMP_DIR/openssl.cnf"
cat > "$OPENSSL_CONF" <<EOF
[ req ]
default_bits = 2048
distinguished_name = req_distinguished_name
x509_extensions = codesign_ext
prompt = no

[ req_distinguished_name ]
CN = $IDENTITY

[ codesign_ext ]
basicConstraints = critical,CA:FALSE
keyUsage = critical,digitalSignature
extendedKeyUsage = codeSigning
subjectKeyIdentifier = hash
EOF

openssl req \
  -new \
  -x509 \
  -nodes \
  -days 3650 \
  -newkey rsa:2048 \
  -keyout "$TMP_DIR/identity.key" \
  -out "$TMP_DIR/identity.crt" \
  -config "$OPENSSL_CONF" >/dev/null 2>&1

openssl pkcs12 \
  -export \
  -inkey "$TMP_DIR/identity.key" \
  -in "$TMP_DIR/identity.crt" \
  -name "$IDENTITY" \
  -out "$TMP_DIR/identity.p12" \
  -passout "pass:$P12_PASSWORD" >/dev/null 2>&1

security import "$TMP_DIR/identity.p12" \
  -k "$KEYCHAIN" \
  -P "$P12_PASSWORD" \
  -A \
  -T /usr/bin/codesign >/dev/null

security add-trusted-cert \
  -r trustRoot \
  -p codeSign \
  -k "$KEYCHAIN" \
  "$TMP_DIR/identity.crt" >/dev/null 2>&1 || true

if ! security find-identity -v -p codesigning "$KEYCHAIN" 2>/dev/null | rg -F "$IDENTITY" >/dev/null; then
  echo "Unable to create a usable local code signing identity: $IDENTITY" >&2
  echo "Open Keychain Access, trust the certificate for code signing, then rerun packaging." >&2
  exit 1
fi

echo "$IDENTITY"
