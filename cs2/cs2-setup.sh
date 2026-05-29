#!/usr/bin/env bash
# Executado a CADA start (via pre.sh) antes do servidor subir, como usuário steam.
# Sincroniza os addons baixados em build time e (re)aplica os patches que o
# update do jogo costuma reverter. Idempotente.
set -euo pipefail

CSGO="/home/steam/cs2-dedicated/game/csgo"
SRC="/opt/cs2-addons"
ADDONS_SRC="$SRC/addons"
GAMEINFO="$CSGO/gameinfo.gi"

log() { echo "[cs2-setup] $*"; }

# --- 1. Sincroniza addons (Metamod + CSSharp + plugins) ---
log "sincronizando addons -> $CSGO/addons"
mkdir -p "$CSGO/addons"
cp -r "$ADDONS_SRC/." "$CSGO/addons/"

# --- 2. Copia cfgs do servidor ---
if [ -d "$SRC/cfg" ]; then
    log "copiando cfgs do servidor"
    mkdir -p "$CSGO/cfg"
    cp -r "$SRC/cfg/." "$CSGO/cfg/"
fi

# --- 3. Patch idempotente do gameinfo.gi (Metamod) ---
# O update do CS2 sobrescreve este arquivo; por isso refazemos sempre.
if [ ! -f "$GAMEINFO" ]; then
    log "AVISO: gameinfo.gi ainda não existe ($GAMEINFO) — pulando patch"
elif grep -qF 'csgo/addons/metamod' "$GAMEINFO"; then
    log "gameinfo.gi já contém o caminho do Metamod"
else
    log "aplicando patch do Metamod no gameinfo.gi"
    awk '
        /Game_LowViolence/ && !done { print "\t\t\tGame\tcsgo/addons/metamod"; done=1 }
        { print }
    ' "$GAMEINFO" > "$GAMEINFO.tmp" && mv "$GAMEINFO.tmp" "$GAMEINFO"
fi

# --- 4. core.json: skins não renderizam sem isto ---
CORE="$CSGO/addons/counterstrikesharp/configs/core.json"
if [ -f "$CORE" ]; then
    log "core.json: FollowCS2ServerGuidelines=false"
    tmp="$(mktemp)"
    jq '.FollowCS2ServerGuidelines = false' "$CORE" > "$tmp" && mv "$tmp" "$CORE"
fi

# --- 5. gamedata do WeaponPaints no lugar certo ---
GD_SRC="$CSGO/addons/counterstrikesharp/plugins/WeaponPaints/gamedata/weaponpaints.json"
GD_DST_DIR="$CSGO/addons/counterstrikesharp/gamedata"
if [ -f "$GD_SRC" ]; then
    log "copiando weaponpaints.json para gamedata/"
    mkdir -p "$GD_DST_DIR"
    cp "$GD_SRC" "$GD_DST_DIR/weaponpaints.json"
fi

# --- 6. WeaponPaints.json a partir das env vars do banco ---
# Geramos com jq --arg para escapar com segurança (senha pode ter aspas, \, $, etc.).
WP_DIR="$CSGO/addons/counterstrikesharp/configs/plugins/WeaponPaints"
log "renderizando WeaponPaints.json (DB=${DB_HOST:-db}/${DB_NAME:-cs2skins})"
mkdir -p "$WP_DIR"
jq -n \
    --arg     lang "${WP_LANG:-en}" \
    --arg     host "${DB_HOST:-db}" \
    --argjson port "${DB_PORT:-3306}" \
    --arg     user "${DB_USER:-cs2}" \
    --arg     pass "${DB_PASSWORD:-}" \
    --arg     name "${DB_NAME:-cs2skins}" \
    --arg     site "${WEB_URL:-example.com/skins}" \
    '{
        ConfigVersion: 10,
        SkinsLanguage: $lang,
        DatabaseHost: $host,
        DatabasePort: $port,
        DatabaseUser: $user,
        DatabasePassword: $pass,
        DatabaseName: $name,
        CmdRefreshCooldownSeconds: 3,
        Website: $site,
        MenuType: "selectable",
        Additional: {
            SkinEnabled: true, KnifeEnabled: true, GloveEnabled: true,
            AgentEnabled: true, MusicEnabled: true, PinsEnabled: true,
            CommandWpEnabled: true, CommandKillEnabled: true,
            GiveRandomKnife: false, GiveRandomSkin: false, ShowSkinImage: true
        }
    }' > "$WP_DIR/WeaponPaints.json"

log "concluído."
