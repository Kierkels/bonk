#!/usr/bin/env bash
# Maakt eenmalig een zelf-ondertekende code-signing identiteit aan, zodat
# verleende toestemmingen (zoals Schermopname) blijven kleven over herbouwen heen
# — in tegenstelling tot ad-hoc ondertekenen, waarbij elke build een nieuwe hash
# krijgt en macOS de toestemming opnieuw vraagt.
set -euo pipefail

CN="Bonk Self-Signed Dev"

if security find-identity -v -p codesigning 2>/dev/null | grep -q "$CN"; then
    echo "Identiteit '$CN' bestaat al — niets te doen."
    exit 0
fi

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

echo "==> certificaat genereren"
openssl req -x509 -newkey rsa:2048 -nodes -days 3650 \
    -keyout "$TMP/key.pem" -out "$TMP/cert.pem" \
    -subj "/CN=$CN" \
    -addext "basicConstraints=critical,CA:false" \
    -addext "keyUsage=critical,digitalSignature" \
    -addext "extendedKeyUsage=critical,codeSigning"

# Apple's `security import` gebruikt een oudere PKCS12-parser; dwing daarom
# legacy-algoritmes af (anders: "MAC verification failed").
PKCS12_ARGS=(-export -inkey "$TMP/key.pem" -in "$TMP/cert.pem"
    -out "$TMP/bonk.p12" -passout pass:bonk -name "$CN"
    -macalg sha1 -certpbe PBE-SHA1-3DES -keypbe PBE-SHA1-3DES)
if openssl version | grep -q "OpenSSL 3"; then
    PKCS12_ARGS+=(-legacy)
fi
openssl pkcs12 "${PKCS12_ARGS[@]}"

echo "==> importeren in login-keychain"
security import "$TMP/bonk.p12" -k "$HOME/Library/Keychains/login.keychain-db" \
    -P bonk -T /usr/bin/codesign

echo
echo "Klaar. Bouw opnieuw met ./app/build.sh."
echo "Bij de eerste build vraagt de keychain eenmalig toestemming — kies 'Always Allow'."
echo "Geef daarna Bonk schermopname-toegang; die blijft nu behouden over builds heen."
