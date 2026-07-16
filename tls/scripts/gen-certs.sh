#!/bin/sh
# gen-certs.sh - Generate a certificate chain accepted by the PS2 DNAS.
#
# The PS2 does NOT verify the CA signature (the "VeriSign" CA is forged); it only
# checks the certificate DN (the CN must match the hostname the game connects to)
# and the validity dates. A fresh self-signed CA plus a leaf with the right DN is
# therefore enough. RSA must be 1024-bit (the PS2's TLS rejects larger keys here).
#
# Generates, for the single configured REGION:
#   ca-cert.pem, cert-<region>.pem, cert-<region>-key.pem
#
# The DN is written directly into the [dn] section of the .cnf (OpenSSL 1.0.2
# ignores -subj when prompt=no). Uses the bundled OpenSSL 1.0.2 ($OPENSSL_BIN).
set -e

OPENSSL_BIN="${OPENSSL_BIN:-/opt/openssl/bin/openssl}"
CERT_DIR="${CERT_DIR:-/etc/dnas}"
REGION="$(echo "${REGION:-eu}" | tr -d ' ' | tr 'A-Z' 'a-z')"
KEY_BITS="${KEY_BITS:-1024}"
CERT_DAYS="${CERT_DAYS:-8000}"   # ~21.9 years -> stays before 2050 (UTCTime)

CA_KEY="${CERT_DIR}/ca-key.pem"
CA_CERT="${CERT_DIR}/ca-cert.pem"

mkdir -p "$CERT_DIR"

# Write a temporary openssl.cnf with an explicit DN ($1 = [dn] section lines)
# plus the extension sections. Echoes the file path.
write_cnf() {
	f="$(mktemp)"
	cat > "$f" <<EOF
[ req ]
default_md          = sha256
distinguished_name  = dn
string_mask         = default
prompt              = no
x509_extensions     = v3_ca

[ dn ]
$1

[ v3_ca ]
basicConstraints    = critical, CA:TRUE
keyUsage            = critical, keyCertSign, cRLSign

[ v3_leaf ]
basicConstraints    = CA:FALSE
keyUsage            = digitalSignature, keyEncipherment
EOF
	echo "$f"
}

# [dn] lines per region (country kept per region, O=Cyberpunks as in the original).
region_dn() {
	case "$1" in
		jp) printf 'C = JP\nO = Cyberpunks\nCN = gate1.jp.dnas.playstation.org\n' ;;
		eu) printf 'C = GB\nO = Cyberpunks\nCN = gate1.eu.dnas.playstation.org\n' ;;
		us) printf 'C = US\nO = Cyberpunks\nCN = gate1.us.dnas.playstation.org\n' ;;
		*)  printf 'C = US\nO = Cyberpunks\nCN = gate1.%s.dnas.playstation.org\n' "$1" ;;
	esac
}

# --- 1) Forged VeriSign Class 3 CA (self-signed) ---
echo "[gen-certs] Creating forged VeriSign Class 3 CA"
CA_DN="$(printf 'C = US\nO = VeriSign, Inc.\nOU = Class 3 Public Primary Certification Authority\n')"
CA_CNF="$(write_cnf "$CA_DN")"
"$OPENSSL_BIN" genrsa -out "$CA_KEY" "$KEY_BITS" 2>/dev/null
"$OPENSSL_BIN" req -new -x509 -config "$CA_CNF" \
	-key "$CA_KEY" -out "$CA_CERT" -days "$CERT_DAYS" -set_serial 1
rm -f "$CA_CNF"

# --- 2) Leaf certificate for the configured region, signed by the CA ---
echo "[gen-certs] Region ${REGION}: CN=gate1.${REGION}.dnas.playstation.org"
key="${CERT_DIR}/cert-${REGION}-key.pem"
crt="${CERT_DIR}/cert-${REGION}.pem"
cnf="$(write_cnf "$(region_dn "$REGION")")"
csr="$(mktemp)"
"$OPENSSL_BIN" genrsa -out "$key" "$KEY_BITS" 2>/dev/null
"$OPENSSL_BIN" req -new -config "$cnf" -key "$key" -out "$csr"
"$OPENSSL_BIN" x509 -req -sha256 -in "$csr" \
	-CA "$CA_CERT" -CAkey "$CA_KEY" \
	-extfile "$cnf" -extensions v3_leaf \
	-out "$crt" -days "$CERT_DAYS" -set_serial "$(date +%s)" 2>/dev/null
rm -f "$csr" "$cnf"

echo "[gen-certs] Done. Certificates in ${CERT_DIR}:"
ls -1 "$CERT_DIR"/*.pem
