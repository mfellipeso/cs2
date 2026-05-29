#!/usr/bin/env bash
# Hook do joedwards32/cs2: executado ANTES do servidor subir (usuário steam).
# Montado via bind no docker-compose para que mudanças aqui valham sem rebuild.
# Toda a lógica de instalação/patch vive em /usr/local/bin/cs2-setup.sh (na imagem).
# NÃO usar 'exec' aqui: a imagem faz source deste arquivo, e o exec substituiria
# o processo do entrypoint — o servidor nunca subiria (sai 0 e entra em loop).
/usr/local/bin/cs2-setup.sh
