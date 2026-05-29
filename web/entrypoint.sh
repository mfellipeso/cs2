#!/usr/bin/env bash
# Gera config.php a partir das env vars (evita depender de getenv() sob Apache)
# e sobe o Apache. config.php é um simples script PHP de atribuições.
set -e

# Escapa um valor para string PHP entre aspas simples (trata \ e ').
php_sq() { local s=${1//\\/\\\\}; printf "%s" "${s//\'/\\\'}"; }

cat > /var/www/html/config.php <<PHP
<?php
\$Website_Translate = '$(php_sq "${WEB_LANG:-en}")';
\$Website_MainColor = '#5D3FD3';
\$Website_UseCategories = true;
\$Website_UseThreejs = true;
\$Website_TeamOnlyWeapons = false;
\$Website_Settings = [
    "language" => true,
    "theme" => true,
];
\$SteamAPI_KEY = '$(php_sq "${STEAM_API_KEY:-}")';
\$DatabaseInfo = [
    "host" => '$(php_sq "${DB_HOST:-db}")',
    "database" => '$(php_sq "${DB_NAME:-cs2skins}")',
    "username" => '$(php_sq "${DB_USER:-cs2}")',
    "password" => '$(php_sq "${DB_PASSWORD:-}")',
    "port" => '$(php_sq "${DB_PORT:-3306}")',
];
PHP

chown www-data:www-data /var/www/html/config.php

exec apache2-foreground
