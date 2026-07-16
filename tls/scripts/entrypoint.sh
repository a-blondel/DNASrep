#!/bin/sh
# entrypoint.sh - generate certs, write stunnel.conf, run stunnel in the foreground.
set -e

OPENSSL_BIN="${OPENSSL_BIN:-/opt/openssl/bin/openssl}"
CERT_DIR="${CERT_DIR:-/etc/dnas}"
REGION="$(echo "${REGION:-eu}" | tr -d ' ' | tr 'A-Z' 'a-z')"
REGEN_CERTS="${REGEN_CERTS:-true}"
BACKEND="${BACKEND:-web:80}"
DH_BITS="${DH_BITS:-1024}"
STUNNEL_CONF=/app/stunnel.conf

export OPENSSL_BIN CERT_DIR REGION

echo "================================================"
echo " DNASrep TLS (stunnel + OpenSSL 1.0.2)"
echo "   Region      : $REGION"
echo "   Backend     : $BACKEND"
echo "   REGEN_CERTS : $REGEN_CERTS"
echo "================================================"

CRT="${CERT_DIR}/cert-${REGION}.pem"

# --- Certificates ---
if [ "$REGEN_CERTS" = "false" ]; then
	echo "[entrypoint] REGEN_CERTS=false -> using existing certificates in $CERT_DIR"
	[ -f "$CRT" ] || { echo "[entrypoint] ERROR: $CRT not found." >&2; exit 1; }
elif [ "$REGEN_CERTS" = "force" ] || [ ! -f "$CRT" ]; then
	echo "[entrypoint] Generating certificates..."
	/opt/dnastls/scripts/gen-certs.sh
else
	echo "[entrypoint] Certificates already present -> kept"
fi

# --- Diffie-Hellman parameters (needed for DHE cipher suites) ---
DH_FILE="${CERT_DIR}/dhparam.pem"
if [ ! -f "$DH_FILE" ]; then
	echo "[entrypoint] Generating ${DH_BITS}-bit DH parameters (please wait)..."
	"$OPENSSL_BIN" dhparam -out "$DH_FILE" "$DH_BITS" 2>/dev/null
fi

# --- Presented chain: leaf + CA + DH (stunnel reads DH from the cert file) ---
cat "$CRT" "${CERT_DIR}/ca-cert.pem" "$DH_FILE" > "${CERT_DIR}/server-chain.pem"
cp "${CERT_DIR}/cert-${REGION}-key.pem" "${CERT_DIR}/server-key.pem"

# --- stunnel configuration ---
mkdir -p /app
cat > "$STUNNEL_CONF" <<EOF
foreground = yes
pid =
; Resolve the backend DNS on each connection (web may start slightly later)
delay = yes

[dnas]
accept = 0.0.0.0:443
connect = ${BACKEND}
cert = ${CERT_DIR}/server-chain.pem
key = ${CERT_DIR}/server-key.pem
; With OpenSSL 1.0.2, stunnel negotiates TLS 1.0->1.2 (SSLv2/3 off by default) and
; accepts the PS2's SSLv2-format ClientHello. ciphers = ALL exposes the weak
; suites (RC4-SHA / 3DES) the PS2 actually uses.
ciphers = ALL
TIMEOUTclose = 0
EOF

echo "[entrypoint] Presented certificate (region $REGION):"
"$OPENSSL_BIN" x509 -in "$CRT" -noout -subject -issuer -dates 2>/dev/null || true
echo "[entrypoint] stunnel.conf:"
cat "$STUNNEL_CONF"

echo "[entrypoint] Starting stunnel..."
exec /usr/local/bin/stunnel "$STUNNEL_CONF"
