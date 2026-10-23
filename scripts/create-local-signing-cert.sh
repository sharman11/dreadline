#!/bin/zsh
# One-time: creates a self-signed "Dreadline Local Signing" code signing certificate in the
# login keychain so local builds keep a stable identity. Remove it any time in Keychain Access.
set -euo pipefail
if security find-certificate -c "Dreadline Local Signing" >/dev/null 2>&1; then
  echo "Dreadline Local Signing already exists."; exit 0
fi
work=$(mktemp -d); trap 'rm -rf "$work"' EXIT
cat > "$work/cert.cnf" <<'CNF'
[req]
distinguished_name = dn
x509_extensions = ext
prompt = no
[dn]
CN = Dreadline Local Signing
[ext]
basicConstraints = critical,CA:false
keyUsage = critical,digitalSignature
extendedKeyUsage = critical,codeSigning
CNF
openssl req -x509 -newkey rsa:2048 -nodes -keyout "$work/key.pem" -out "$work/cert.pem" -days 3650 -config "$work/cert.cnf" 2>/dev/null
pass=$(openssl rand -hex 12)
openssl pkcs12 -export -inkey "$work/key.pem" -in "$work/cert.pem" -name "Dreadline Local Signing" -out "$work/id.p12" -passout "pass:$pass"
security import "$work/id.p12" -k ~/Library/Keychains/login.keychain-db -P "$pass" -T /usr/bin/codesign
echo "Created Dreadline Local Signing. Rebuild, then enable Dreadline once in System Settings → Privacy & Security → Accessibility."
