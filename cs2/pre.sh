#!/usr/bin/env bash
# Hook do joedwards32/cs2: executado ANTES do servidor subir (usuário steam).
# Montado via bind no docker-compose para que mudanças aqui valham sem rebuild.
# Toda a lógica de instalação/patch vive em /usr/local/bin/cs2-setup.sh (na imagem).
exec /usr/local/bin/cs2-setup.sh
