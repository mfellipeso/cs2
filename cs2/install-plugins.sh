#!/usr/bin/env bash
# Baixa Metamod + CounterStrikeSharp + WeaponPaints (+ deps) para /opt/cs2-addons.
# Executado UMA vez em build time. Ordem: Metamod -> CSSharp -> plugins.
set -euo pipefail

STAGE=/opt/cs2-addons
ADDONS="$STAGE/addons"
PLUGINS="$ADDONS/counterstrikesharp/plugins"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

mkdir -p "$ADDONS"

echo "==> Metamod:Source 2.0 (build ${MMS_BUILD})"
curl -fsSL "https://mms.alliedmods.net/mmsdrop/2.0/mmsource-2.0.0-git${MMS_BUILD}-linux.tar.gz" \
    -o "$WORK/mms.tar.gz"
tar -xzf "$WORK/mms.tar.gz" -C "$STAGE"   # -> $STAGE/addons/metamod[.vdf]

echo "==> CounterStrikeSharp ${CSSHARP_TAG} (with runtime)"
curl -fsSL "https://github.com/roflmuffin/CounterStrikeSharp/releases/download/${CSSHARP_TAG}/counterstrikesharp-with-runtime-linux-${CSSHARP_VER}.zip" \
    -o "$WORK/css.zip"
unzip -q "$WORK/css.zip" -d "$STAGE"      # -> $STAGE/addons/counterstrikesharp + metamod/counterstrikesharp.vdf

mkdir -p "$PLUGINS"

# Baixa um plugin/lib e mescla sua árvore addons/ no staging.
fetch_plugin() {
    local url="$1" name="$2"
    echo "==> $name"
    curl -fsSL "$url" -o "$WORK/$name.zip"
    mkdir -p "$WORK/$name"
    unzip -q "$WORK/$name.zip" -d "$WORK/$name"
    if [ -d "$WORK/$name/addons" ]; then
        cp -r "$WORK/$name/addons/." "$ADDONS/"
    else
        # zip sem prefixo addons/ -> trata como pasta de plugin
        cp -r "$WORK/$name" "$PLUGINS/$name"
    fi
}

# Cadeia: WeaponPaints -> MenuManager -> PlayerSettings -> AnyBaseLib (todas obrigatórias)
fetch_plugin "https://github.com/NickFox007/AnyBaseLibCS2/releases/download/${ANYBASELIB_TAG}/AnyBaseLib.zip"          AnyBaseLib
fetch_plugin "https://github.com/NickFox007/PlayerSettingsCS2/releases/download/${PLAYERSETTINGS_TAG}/PlayerSettings.zip" PlayerSettings
fetch_plugin "https://github.com/NickFox007/MenuManagerCS2/releases/download/${MENUMANAGER_TAG}/MenuManager.zip"        MenuManager
fetch_plugin "https://github.com/Nereziel/cs2-WeaponPaints/releases/download/${WEAPONPAINTS_TAG}/WeaponPaints.zip"      WeaponPaints

echo "==> Conteúdo final de $ADDONS:"
ls -la "$ADDONS"
