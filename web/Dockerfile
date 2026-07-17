# DNASrep - application service (Apache + PHP), plain HTTP.
# The legacy TLS termination is handled by the "tls" service (stunnel) upstream.
# Debian trixie + PHP 8.4 (current, maintained). connect.php uses the "des-ecb"
# cipher, which OpenSSL 3.x moved to the legacy provider, so we enable it below.
FROM debian:trixie-slim

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update \
	&& apt-get install -y --no-install-recommends \
		apache2 \
		libapache2-mod-php8.4 \
		php8.4 \
	&& rm -rf /var/lib/apt/lists/*

RUN a2enmod php8.4 \
	&& (a2dissite 000-default || true)

# Enable the OpenSSL legacy provider so PHP's openssl_encrypt(..., "des-ecb", ...)
# used by connect.php keeps working on OpenSSL 3.x.
RUN printf 'openssl_conf = openssl_init\n[openssl_init]\nproviders = provider_sect\n[provider_sect]\ndefault = default_sect\nlegacy = legacy_sect\n[default_sect]\nactivate = 1\n[legacy_sect]\nactivate = 1\n' \
	> /etc/dnas-openssl.cnf
ENV OPENSSL_CONF=/etc/dnas-openssl.cnf

COPY app/dnas/ /var/www/dnas/
COPY conf/dnas.conf /etc/apache2/sites-available/dnas.conf
# Cap prefork workers (bounded RAM on small hosts)
COPY conf/mpm_prefork.conf /etc/apache2/mods-available/mpm_prefork.conf

RUN a2ensite dnas \
	&& chown -R www-data:www-data /var/www/dnas \
	&& ln -sf /proc/self/fd/1 /var/log/apache2/dnas_access.log \
	&& ln -sf /proc/self/fd/2 /var/log/apache2/dnas_error.log

EXPOSE 80

CMD ["apache2ctl", "-D", "FOREGROUND"]
