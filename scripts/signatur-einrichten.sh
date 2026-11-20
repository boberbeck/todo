#!/bin/bash
# Richtet einmalig eine feste Signatur für Tagwerk ein. Auf deinem Mac im Repository ausführen:
#   scripts/signatur-einrichten.sh
#
# Warum: macOS merkt sich die Freigaben für Kalender, Schlüsselbund und Musik anhand der Signatur.
# Ohne festes Zertifikat ist jede neue Fassung für macOS eine andere App, und die Freigaben sind weg.
#
# Was passiert:
# 1. Ein selbst signiertes Zertifikat „Tagwerk Lokal“ wird erzeugt (nur für Tagwerk, 10 Jahre gültig).
# 2. Es kommt in deinen Schlüsselbund; scripts/make-app.sh signiert damit.
# 3. Es wird bei GitHub als Secret hinterlegt; die fertigen Downloads werden ab dann damit signiert.
set -euo pipefail
cd "$(dirname "$0")/.."

NAME="Tagwerk Lokal"
OPENSSL=/usr/bin/openssl   # LibreSSL von macOS; dessen .p12 kann der Schlüsselbund lesen
WORK="$(mktemp -d)"
trap 'rm -rf "${WORK}"' EXIT

if security find-identity -p codesigning 2>/dev/null | grep -q "\"${NAME}\""; then
  echo "Es gibt schon ein Zertifikat „${NAME}“ in deinem Schlüsselbund."
  echo "Zum Neuanlegen erst löschen: security delete-identity -c \"${NAME}\""
  exit 1
fi

PASSWORD="$(LC_ALL=C tr -dc 'A-Za-z0-9' </dev/urandom | head -c 24)"

cat > "${WORK}/zertifikat.cnf" <<EOF
[req]
distinguished_name = dn
x509_extensions = ext
prompt = no
[dn]
CN = ${NAME}
[ext]
basicConstraints = critical, CA:false
keyUsage = critical, digitalSignature
extendedKeyUsage = critical, codeSigning
EOF

"${OPENSSL}" req -x509 -newkey rsa:2048 -nodes -days 3650 -sha256 \
  -keyout "${WORK}/schluessel.pem" -out "${WORK}/zertifikat.pem" -config "${WORK}/zertifikat.cnf" 2>/dev/null
"${OPENSSL}" pkcs12 -export -name "${NAME}" -inkey "${WORK}/schluessel.pem" -in "${WORK}/zertifikat.pem" \
  -out "${WORK}/tagwerk.p12" -passout "pass:${PASSWORD}"

security import "${WORK}/tagwerk.p12" -k "${HOME}/Library/Keychains/login.keychain-db" -P "${PASSWORD}" -T /usr/bin/codesign >/dev/null
echo "Zertifikat „${NAME}“ ist in deinem Schlüsselbund."

P12_BASE64="$(base64 -i "${WORK}/tagwerk.p12")"

if command -v gh >/dev/null 2>&1 && gh auth status >/dev/null 2>&1; then
  printf '%s' "${P12_BASE64}" | gh secret set TAGWERK_SIGNING_P12
  printf '%s' "${PASSWORD}" | gh secret set TAGWERK_SIGNING_PASSWORD
  echo "Bei GitHub hinterlegt. Ab dem nächsten Build sind die Downloads fest signiert."
  exit 0
fi

REPO_URL="$(git config --get remote.origin.url | sed -E 's#(git@github.com:|https://github.com/)##; s#\.git$##')"
SECRETS_URL="https://github.com/${REPO_URL}/settings/secrets/actions/new"
echo
echo "Jetzt noch zwei Secrets bei GitHub anlegen (Settings › Secrets and variables › Actions › New repository secret):"
echo
printf '%s' "${P12_BASE64}" | pbcopy
echo "1. Name: TAGWERK_SIGNING_P12"
echo "   Wert: liegt schon in der Zwischenablage, einfach einfügen (⌘V) und speichern."
open "${SECRETS_URL}" 2>/dev/null || echo "   Seite: ${SECRETS_URL}"
read -r -p "   Fertig? Dann Enter drücken … " _
printf '%s' "${PASSWORD}" | pbcopy
echo "2. Name: TAGWERK_SIGNING_PASSWORD"
echo "   Wert: liegt jetzt in der Zwischenablage, wieder einfügen und speichern."
open "${SECRETS_URL}" 2>/dev/null || true
read -r -p "   Fertig? Dann Enter drücken … " _
printf '' | pbcopy
echo "Danke. Ab dem nächsten Build sind die Downloads fest signiert."
