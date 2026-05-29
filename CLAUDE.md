# CLAUDE.md

Guia para trabalhar neste repositório. Para a especificação completa e as decisões de
arquitetura, ver [`SPEC.md`](./SPEC.md); para uso rápido, ver [`README.md`](./README.md).

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

1. Confirmar versões compatíveis (Discord do CounterStrikeSharp após patches).
2. Bumpar os **ARGs** em `cs2/Dockerfile`:
   - `MMS_BUILD` (Metamod 2.0 — `sourcemm.net/downloads.php?branch=master`)
   - `CSSHARP_TAG` / `CSSHARP_VER` (`roflmuffin/CounterStrikeSharp` releases)
   - `WEAPONPAINTS_TAG`, `MENUMANAGER_TAG`, `PLAYERSETTINGS_TAG`, `ANYBASELIB_TAG`
3. Rebuild + recriar:
   ```bash
   docker compose build cs2 && docker compose up -d cs2
   ```

> Regra: **bumpar CS2 + Metamod + CSSharp juntos.** Não deixe o jogo auto-atualizar à
> frente dos plugins. O `watchtower` no compose está **comentado** de propósito.

Atualizar o site:
```bash
docker compose build web --build-arg WEBSITE_TAG=vX.Y && docker compose up -d web
```

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
