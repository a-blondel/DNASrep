#!/bin/sh
# provision.sh - build an OpenSSL 1.0.2 (with weak ciphers) + stunnel.
#
# Required because no modern distro OpenSSL (1.1.1 / 3.x) can still serve the
# legacy handshake the PS2 uses: an SSLv2-format ClientHello, TLS 1.0, weak
# ciphers (RC4-SHA / 3DES) and a 1024-bit RSA certificate.
#
# 1.0.2u is the last PUBLIC 1.0.2 release (Dec 2019); later 1.0.2z* versions are
# only available under OpenSSL's paid premium support.
set -e

app_home="$1"
cd "$app_home"

echo "================================================"
echo "Building OpenSSL 1.0.2u (weak ciphers)"
echo "================================================"
wget -q https://github.com/openssl/openssl/releases/download/OpenSSL_1_0_2u/openssl-1.0.2u.tar.gz
tar -xf openssl-1.0.2u.tar.gz
cd openssl-1.0.2u
# enable-ssl2/ssl3 lets the server accept the PS2's SSLv2-format ClientHello;
# enable-weak-ssl-ciphers brings back RC4/DES/3DES.
./config --prefix=/opt/openssl --openssldir=/opt/openssl \
	enable-ssl2 enable-ssl3 enable-weak-ssl-ciphers no-shared
make depend
make -j"$(nproc)"
make install

# string_mask = default is required by these old clients (string encoding).
if [ -f /opt/openssl/openssl.cnf ]; then
	sed -i 's/string_mask = utf8only/string_mask = default/g' /opt/openssl/openssl.cnf || true
	sed -i 's/string_mask=utf8only/string_mask=default/g' /opt/openssl/openssl.cnf || true
fi

echo "================================================"
echo "Building stunnel"
echo "================================================"
cd "$app_home"
# Latest published tarball (June 2026). Note: it self-reports as "5.78" via
# `stunnel -version` (upstream release quirk); the source is the 5.79 archive.
wget -q https://www.stunnel.org/archive/5.x/stunnel-5.79.tar.gz
tar xzf stunnel-5.79.tar.gz
cd stunnel-5.79/
./configure CPPFLAGS="-I/opt/openssl/include" LDFLAGS="-L/opt/openssl/lib"
make -j"$(nproc)"
make install

echo "================================================"
echo "Provisioning done"
echo "  OpenSSL : /opt/openssl/bin/openssl"
echo "  stunnel : /usr/local/bin/stunnel"
echo "================================================"
