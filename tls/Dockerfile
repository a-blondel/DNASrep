# DNASrep - TLS service: stunnel + a from-source OpenSSL 1.0.2 (weak ciphers).
# Terminates the PS2's legacy handshake (SSLv2-format ClientHello, TLS 1.0,
# RC4-SHA / 3DES, 1024-bit RSA) that no modern distro OpenSSL can serve, and
# forwards plaintext to the "web" service.
FROM alpine:3.24.1

RUN apk --update --no-cache add \
		build-base \
		linux-headers \
		wget \
		ca-certificates \
		perl \
	&& rm -rf /var/cache/apk/*

RUN mkdir -p /opt/dnastls/scripts /app /etc/dnas
WORKDIR /opt/dnastls

# --- Cached heavy step: build OpenSSL 1.0.2 + stunnel ---
# Only provision.sh is copied first so editing the other scripts does not
# trigger a full rebuild.
COPY scripts/provision.sh /opt/dnastls/scripts/provision.sh
RUN sed -i 's/\r$//' scripts/provision.sh && chmod +x scripts/provision.sh \
	&& scripts/provision.sh /opt/dnastls

# Slim down the image: drop build tools, keep /opt/openssl and stunnel.
RUN apk del build-base linux-headers perl \
	&& rm -rf /opt/dnastls/openssl-* /opt/dnastls/stunnel-* /opt/dnastls/*.tar.gz /var/cache/apk/*

# --- Runtime scripts (light layer, iterable without recompiling) ---
COPY scripts/gen-certs.sh scripts/entrypoint.sh /opt/dnastls/scripts/
RUN sed -i 's/\r$//' scripts/gen-certs.sh scripts/entrypoint.sh \
	&& chmod +x scripts/gen-certs.sh scripts/entrypoint.sh

ENV OPENSSL_BIN=/opt/openssl/bin/openssl \
	CERT_DIR=/etc/dnas

EXPOSE 443

CMD ["/opt/dnastls/scripts/entrypoint.sh"]
