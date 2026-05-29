#!/usr/bin/env bash
# Atalho de administração do servidor via RCON (roda DENTRO do container cs2).
# Uso: docker compose exec cs2 csadmin <comando> [args]
set -euo pipefail

RCON_HOST="${RCON_HOST:-127.0.0.1}"
RCON_PORT="${CS2_PORT:-27015}"
RCON_PW="${CS2_RCONPW:-}"
MODES_DIR="${MODES_DIR:-/home/steam/cs2-dedicated/game/csgo/cfg/modes}"

rc() { rcon -a "${RCON_HOST}:${RCON_PORT}" -p "${RCON_PW}" "$*"; }

list_modes() {
    if [ -d "$MODES_DIR" ]; then
        for f in "$MODES_DIR"/*.cfg; do
            [ -e "$f" ] || continue
            basename "$f" .cfg
        done
    fi
}

usage() {
    cat <<TXT
csadmin — administração do servidor CS2 via RCON

  csadmin map <mapa>      troca de mapa (ex.: csadmin map de_dust2)
  csadmin maps            lista os mapas que o servidor conhece
  csadmin mode <nome>     aplica um modo divertido (ex.: csadmin mode only_pistol)
  csadmin modes           lista os modos disponíveis
  csadmin pause           pausa a partida (mp_pause_match)
  csadmin unpause         despausa a partida (mp_unpause_match)
  csadmin say <texto>     manda mensagem no chat
  csadmin status          status do servidor (players, mapa, etc.)
  csadmin rcon <comando>  executa um comando RCON cru
  csadmin help            esta ajuda

Modos disponíveis:
$(list_modes | sed 's/^/  - /')
TXT
}

[ -n "$RCON_PW" ] || { echo "ERRO: CS2_RCONPW não definido no .env"; exit 1; }

cmd="${1:-help}"; shift || true
case "$cmd" in
    map)
        [ $# -ge 1 ] || { echo "uso: csadmin map <mapa>"; exit 1; }
        rc "changelevel $1" ;;
    maps)
        rc "maps *" ;;
    mode)
        [ $# -ge 1 ] || { echo "uso: csadmin mode <nome>"; echo "modos:"; list_modes | sed 's/^/  - /'; exit 1; }
        [ -f "$MODES_DIR/$1.cfg" ] || { echo "modo '$1' não existe. disponíveis:"; list_modes | sed 's/^/  - /'; exit 1; }
        rc "exec modes/$1" ;;
    modes)
        list_modes ;;
    pause)
        rc "mp_pause_match" ;;
    unpause)
        rc "mp_unpause_match" ;;
    say)
        rc "say $*" ;;
    status)
        rc "status" ;;
    rcon)
        [ $# -ge 1 ] || { echo "uso: csadmin rcon <comando>"; exit 1; }
        rc "$*" ;;
    help|-h|--help)
        usage ;;
    *)
        echo "comando desconhecido: $cmd"; echo; usage; exit 1 ;;
esac
