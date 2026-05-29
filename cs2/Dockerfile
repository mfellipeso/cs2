# Servidor CS2 dedicado + Metamod + CounterStrikeSharp + WeaponPaints (+ deps).
#
# Os addons são baixados em build time para /opt/cs2-addons (FORA do volume).
# O volume monta /home/steam/cs2-dedicated/ e sobrescreveria qualquer coisa
# baixada ali, então o pre.sh sincroniza /opt/cs2-addons -> game/csgo a cada
# start (sobrevive a updates do jogo e a bumps de imagem).
FROM joedwards32/cs2:latest

# Versões fixadas de propósito (ver SPEC §6). Bumpar CS2+Metamod+CSSharp juntos.
ARG MMS_BUILD=1390
ARG CSSHARP_TAG=v1.0.368
ARG CSSHARP_VER=1.0.368
ARG WEAPONPAINTS_TAG=build-423
ARG MENUMANAGER_TAG=1.4.1
ARG PLAYERSETTINGS_TAG=0.9.4
ARG ANYBASELIB_TAG=0.9.4

USER root

# Ferramentas de build/runtime. libicu p/ globalização do .NET (CSSharp);
# também setamos DOTNET_SYSTEM_GLOBALIZATION_INVARIANT=true no compose como rede de segurança.
RUN apt-get update \
    && apt-get install -y --no-install-recommends curl unzip jq ca-certificates \
    && (apt-get install -y --no-install-recommends libicu-dev || true) \
    && rm -rf /var/lib/apt/lists/*

COPY install-plugins.sh /usr/local/bin/install-plugins.sh
RUN chmod +x /usr/local/bin/install-plugins.sh \
    && MMS_BUILD="$MMS_BUILD" \
       CSSHARP_TAG="$CSSHARP_TAG" CSSHARP_VER="$CSSHARP_VER" \
       WEAPONPAINTS_TAG="$WEAPONPAINTS_TAG" MENUMANAGER_TAG="$MENUMANAGER_TAG" \
       PLAYERSETTINGS_TAG="$PLAYERSETTINGS_TAG" ANYBASELIB_TAG="$ANYBASELIB_TAG" \
       /usr/local/bin/install-plugins.sh

COPY cs2-setup.sh /usr/local/bin/cs2-setup.sh
COPY cfg/ /opt/cs2-addons/cfg/
RUN chmod +x /usr/local/bin/cs2-setup.sh \
    && chown -R 1000:1000 /opt/cs2-addons

USER steam
