# DNASrep - application service (Apache + PHP), plain HTTP.
# The legacy TLS termination is handled by the "tls" service (stunnel) upstream.
# Debian bullseye is used on purpose: PHP 7.4 links OpenSSL 1.1.1, so the
# "des-ecb" cipher required by connect.php works (OpenSSL 3.x would break it).
FROM debian:bullseye-slim

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update \
	&& apt-get install -y --no-install-recommends \
		apache2 \
		libapache2-mod-php7.4 \
		php7.4 \
	&& rm -rf /var/lib/apt/lists/*

RUN a2enmod php7.4 \
	&& (a2dissite 000-default || true)

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
