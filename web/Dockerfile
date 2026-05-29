# Site de seleção de skins (LielXD/CS2-WeaponPaints-Website).
# Login via Steam OpenID; lê/grava na MESMA base MySQL do plugin WeaponPaints.
FROM php:8.3-apache

ARG WEBSITE_TAG=v2.3

# pdo_mysql (acesso ao banco) + mod_rewrite + AllowOverride (o site usa .htaccess)
RUN apt-get update \
    && apt-get install -y --no-install-recommends unzip \
    && docker-php-ext-install pdo_mysql \
    && a2enmod rewrite \
    && sed -ri 's!<Directory /var/www/>!<Directory /var/www/>\n\tAllowOverride All!' /etc/apache2/apache2.conf \
    && rm -rf /var/lib/apt/lists/*

# Baixa e extrai a release do site no docroot.
ADD https://github.com/LielXD/CS2-WeaponPaints-Website/releases/download/${WEBSITE_TAG}/cs2weaponpaints.zip /tmp/site.zip
RUN unzip -q /tmp/site.zip -d /var/www/html \
    && rm /tmp/site.zip \
    && chown -R www-data:www-data /var/www/html

# Gera config.php a partir das env vars no start.
COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
