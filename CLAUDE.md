# CLAUDE.md

Guia para trabalhar neste repositório. Para uso rápido, ver [`README.md`](./README.md).

## O que é

Servidor **Counter-Strike 2** dedicado em Docker com sistema de **skins** (WeaponPaints) e
um **site** onde jogadores escolhem suas skins via login Steam. Tudo via Docker Compose.

Fluxo das skins: jogador entra no site com a Steam → escolhe skin → grava no MySQL → o
plugin in-game lê a mesma base e aplica a skin no spawn. **O site não cria as tabelas;
quem cria é o plugin** (`CREATE TABLE IF NOT EXISTS`, prefixo `wp_`).

## Serviços (`docker-compose.yml`)

| Serviço | Imagem | Papel |
|---------|--------|-------|
| `cs2` | build `./cs2` (FROM `joedwards32/cs2`) | Servidor + Metamod + CounterStrikeSharp + WeaponPaints (+ MenuManager/PlayerSettings/AnyBaseLib) |
| `db` | `mariadb:11` | Base compartilhada plugin ↔ site (volume `dbdata`) |
| `web` | build `./web` (FROM `php:8.3-apache`) | Site de skins (`LielXD/CS2-WeaponPaints-Website` v2.3) |

Portas: `27015` udp/tcp (jogo), `27020` udp (SourceTV), `8080→80` (site, via `WEB_PORT`).

## Arquivos-chave

```
cs2/Dockerfile          # baixa addons em build time para /opt/cs2-addons (FORA do volume)
cs2/install-plugins.sh  # download dos addons (build time); versões via ARGs
cs2/cs2-setup.sh        # sync + patches a CADA start (idempotente) — o coração da lógica
cs2/pre.sh              # hook chamado pela imagem antes do server subir; só faz exec do cs2-setup.sh
cs2/cfg/*.cfg           # configs de servidor, sincronizadas para csgo/cfg/
web/Dockerfile          # site + pdo_mysql + mod_rewrite
web/entrypoint.sh       # gera config.php a partir das env vars no start
```

### Por que os addons ficam em `/opt/cs2-addons` e não no volume

O volume monta `/home/steam/cs2-dedicated/` e **sobrescreveria** qualquer coisa baixada ali
no build. Por isso baixamos os addons para `/opt/cs2-addons` (fora do volume) e o
`cs2-setup.sh` os **sincroniza** para `game/csgo/addons/` a cada start. Isso faz os addons
**sobreviverem** tanto a updates do jogo quanto a recriação do container.

### O que o `cs2-setup.sh` faz a cada start (idempotente)

1. Copia `/opt/cs2-addons/addons` → `csgo/addons`
2. Copia os `cfg/` para `csgo/cfg`
3. **Re-patcha `gameinfo.gi`** (insere `Game csgo/addons/metamod`) — guard com `grep -qF`, insere via `awk`
4. `core.json`: força `FollowCS2ServerGuidelines=false` via `jq` (**sem isso skins não renderizam**)
5. Copia `weaponpaints.json` para `addons/counterstrikesharp/gamedata/`
6. Gera `WeaponPaints.json` (creds do DB) via `jq --arg` (escapa senha com aspas/`$`/`\`)

## Rodar

```bash
cp .env.example .env     # preencher SRCDS_TOKEN, STEAM_API_KEY, senhas
docker compose up -d --build
```

Primeira subida baixa o jogo (~60 GB) — demora.

## Processo de atualização ⚠️

**O maior risco operacional é o acoplamento de versões CS2 ↔ Metamod ↔ CounterStrikeSharp.**
Quando a Valve lança um patch do CS2, é comum Metamod/CSSharp pararem de carregar até saírem
builds compatíveis (mudam offsets/assinaturas; e o update zera o patch do `gameinfo.gi`).

### Atualizar só o jogo (rápido, arriscado)

```bash
docker compose restart cs2   # SteamCMD atualiza no boot; cs2-setup re-sincroniza + re-patcha
```

Use quando NÃO houve patch que quebra plugins. Se os plugins quebrarem, faça o update completo.

### Atualizar de propósito (recomendado)

**Passo 0 — descobrir as versões compatíveis (ANTES de mexer em qualquer coisa):**
- **Metamod 2.0 dev build**: o build mais novo precisa suportar a versão atual do CS2.
  Lista: <https://www.sourcemm.net/downloads.php?branch=master&all=1> ou os releases em
  <https://github.com/alliedmodders/metamod-source/releases>.
  ⚠️ **Lição aprendida:** Metamod velho carrega o core mas resolve o path dos plugins
  contra `/` (`[META] Loaded 0 plugins`) → CSSharp **não** carrega. Sempre o dev build novo.
- **CounterStrikeSharp**: releases em <https://github.com/roflmuffin/CounterStrikeSharp/releases>;
  após um patch do CS2, confirmar no Discord do CSSharp qual build é compatível.
- **WeaponPaints + deps**: releases dos repos (Nereziel / NickFox007).

**Passo 1 — bumpar os ARGs em `cs2/Dockerfile`:**
- `MMS_BUILD` (só o número, ex.: `1401`). **Fonte: GitHub releases**, tag `2.0.0.<build>`
  (o `install-plugins.sh` monta a URL). O CDN `mmsdrop` só serve o build "latest" e
  retorna **403** em builds específicos — por isso usamos o GitHub.
- `CSSHARP_TAG` (ex.: `v1.0.368`) **e** `CSSHARP_VER` (ex.: `1.0.368`) — os dois.
- `WEAPONPAINTS_TAG`, `MENUMANAGER_TAG`, `PLAYERSETTINGS_TAG`, `ANYBASELIB_TAG`.

**Passo 2 — rebuild + recriar:**
```bash
docker compose build cs2 && docker compose up -d cs2
docker compose logs -f cs2          # acompanhar o boot
```

> Regra de ouro: **bumpar CS2 + Metamod + CSSharp juntos.** Não deixe o jogo auto-atualizar
> à frente dos plugins. O `watchtower` no compose está **comentado** de propósito.

### Verificação pós-update (checklist)

Rodar depois de `up -d cs2` (dar ~40-60s pro .NET subir):

```bash
# 1. Servidor de pé, não em loop de restart
docker compose ps                                   # cs2 = Up (não "Restarting")

# 2. Metamod carregou o(s) plugin(s)
docker compose exec cs2 csadmin rcon "meta list"    # deve listar CounterStrikeSharp (NÃO "0 plugins")

# 3. CSSharp carregou os plugins
docker compose exec cs2 csadmin rcon "css_plugins list"  # MenuManager + PlayerSettings + WeaponPaints

# 4. Skins renderizam (guideline desligada)
grep FollowCS2ServerGuidelines csgo/addons/counterstrikesharp/configs/core.json   # = false

# 5. Plugin conectou no banco (tabelas criadas)
docker compose exec db sh -c 'mariadb -u"$MARIADB_USER" -p"$MARIADB_PASSWORD" "$MARIADB_DATABASE" -e "SHOW TABLES;"'
# deve listar wp_player_skins, wp_player_knife, ...

# 6. Sem exceções no log do plugin
docker compose logs cs2 | grep -iE "exception|could not|0 plugins"   # idealmente vazio
```

Sinais de **sucesso** no log: `CounterStrikeSharp.API Loaded Successfully` e
`[META] Loaded 1 plugin`. Se aparecer `[META] Loaded 0 plugins` → Metamod incompatível
(voltar ao Passo 0 e pegar um dev build mais novo).

**Rollback:** se quebrar, reverter os ARGs no `cs2/Dockerfile` para os valores anteriores
(estão no git) e `docker compose build cs2 && docker compose up -d cs2`. O volume do jogo
permanece; só a imagem/addons voltam à versão boa conhecida.

### Atualizar o site / lista de skins

```bash
# Site (código). DATA_REF segue o WEBSITE_TAG por padrão (dados casam com a versão do site).
docker compose build web --build-arg WEBSITE_TAG=vX.Y && docker compose up -d web

# Só a lista de skins mais atual (mantendo o código do site), por sua conta e risco:
docker compose build web --build-arg DATA_REF=main --no-cache && docker compose up -d web
```

Verificar: abrir `http://localhost:8080/skins` (logado) — sem warnings de
`file_get_contents`/`foreach`, lista de skins aparecendo. Lembrar que **a lista do site e os
dados do plugin precisam casar**: skin nova no site que o build do WeaponPaints não conhece
pode não aplicar in-game.

## Debug

```bash
docker compose ps                  # status / health
docker compose logs -f cs2         # logs do servidor (procurar erros de Metamod/CSSharp)
docker compose logs -f web db
docker compose exec cs2 bash       # shell dentro do container do servidor
```

No console do servidor (RCON ou stdin via `docker attach`):
- `meta list` → Metamod carregou? (deve listar CounterStrikeSharp)
- `css_plugins list` → CSSharp carregou os plugins? (deve aparecer WeaponPaints)

### Problemas comuns

| Sintoma | Causa provável | Verificar |
|---------|----------------|-----------|
| **Skins não aparecem** | `FollowCS2ServerGuidelines` não está `false` | `csgo/addons/counterstrikesharp/configs/core.json` |
| **Metamod não carrega** | `gameinfo.gi` foi revertido por update | `grep metamod csgo/gameinfo.gi` → senão `docker compose restart cs2` re-patcha |
| **CSSharp não carrega / crash após patch** | versão do jogo à frente do CSSharp | fazer update de propósito (bumpar ARGs) |
| **`[META] Loaded 0 plugins` / `meta load` busca em `/addons/...`** | **Metamod dev build velho** (não acompanha a versão do CS2) | bumpar `MMS_BUILD` para o dev build mais novo (ver Passo 0) |
| **Site: warnings `file_get_contents(src/data/*.json)`** | `src/data` vazio (não vem na release) | rebuild do `web` baixa os dados; ver "Atualizar o site" |
| **Skin escolhida no site não aplica in-game** | lista do site à frente do build do WeaponPaints | bumpar `WEAPONPAINTS_TAG` (casar dados site ↔ plugin) |
| **Plugin não conecta no banco** | creds erradas | `WeaponPaints.json` gerado; `docker compose logs db`; healthcheck do `db` |
| **Crash do .NET (globalization)** | falta `libicu` | já mitigado por `DOTNET_SYSTEM_GLOBALIZATION_INVARIANT=true` no compose |
| **Site não loga com Steam** | `STEAM_API_KEY` ausente/errada | `.env`; o `config.php` é gerado no start pelo `web/entrypoint.sh` |
| **Servidor não lista público** | `SRCDS_TOKEN` (GSLT) ausente/banido | `.env`; regenerar em managegameservers |

Caminhos dentro do container `cs2`:
- Jogo/addons: `/home/steam/cs2-dedicated/game/csgo/`
- Addons "fonte" (build): `/opt/cs2-addons/addons/`
- Lógica de setup: `/usr/local/bin/cs2-setup.sh`

## Segredos e convenções

- **Tudo sensível vai no `.env`** (gitignored): `SRCDS_TOKEN` (GSLT), `STEAM_API_KEY`,
  `CS2_RCONPW`, `DB_PASSWORD`, `DB_ROOT_PASSWORD`. Nunca commitar; nunca hardcodar em `.cfg`.
- `CS2_PW` = senha de **entrada** (vazio = público). `CS2_RCONPW` = senha de **admin remoto** (sempre forte, diferente).
- `CS2_ADDITIONAL_ARGS=-insecure` desliga o VAC (vazio = VAC ligado).
- Versões dos addons são **pinadas** nos ARGs do `cs2/Dockerfile` (bumpar de propósito).
- `pre.sh` é **bind-mount** → editou, `docker compose restart cs2` aplica sem rebuild.

## Validação local (sem subir a stack)

```bash
docker compose config            # valida sintaxe/interpolação (precisa de .env)
bash -n cs2/*.sh web/*.sh        # syntax check dos scripts
```
Os scripts usam `jq`/`awk` para serem idempotentes e seguros com valores que contêm aspas.
