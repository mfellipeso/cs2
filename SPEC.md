# Spec — Servidor CS2 + Skins em Docker (auto-update)

> Objetivo: reproduzir, de forma reprodutível e versionada, o setup manual atual
> (CS2 dedicado + Metamod + CounterStrikeSharp + WeaponPaints + site de skins),
> orquestrado via Docker Compose, com atualização controlada do jogo.
>
> Status: **DRAFT** · Data: 2026-05-29

---

## 1. Visão geral

O sistema é composto por **4 serviços** num único `docker-compose.yml`, numa rede interna compartilhada:

```
┌─────────────────────────────────────────────────────────────┐
│ docker network: cs2net                                        │
│                                                               │
│  ┌──────────────┐   27015/udp+tcp   ┌─────────────────────┐  │
│  │   players    │ ────────────────▶ │  cs2 (game server)  │  │
│  └──────────────┘                   │  + Metamod          │  │
│                                      │  + CounterStrikeSharp│  │
│         browser                      │  + WeaponPaints      │  │
│           │ 80/443                   └──────────┬──────────┘  │
│           ▼                                     │ MySQL        │
│  ┌──────────────────┐                           ▼             │
│  │ web (PHP/Apache) │ ───── MySQL ────▶ ┌────────────────┐    │
│  │ site de skins    │                   │ db (MariaDB)   │    │
│  └──────────────────┘                   │ volume: dbdata │    │
│                                          └────────────────┘    │
│  ┌──────────────┐                                              │
│  │ watchtower   │ (opcional, auto-update da imagem)            │
│  └──────────────┘                                              │
└─────────────────────────────────────────────────────────────┘
```

**Fluxo de skins:** o jogador faz login com Steam no site → escolhe skins → o site grava
na **mesma base MySQL** que o plugin WeaponPaints lê → o plugin aplica a skin in-game no spawn.
O site **não cria** as tabelas; quem cria é o plugin (`CREATE TABLE IF NOT EXISTS`).

---

## 2. Serviços

### 2.1 `cs2` — servidor dedicado

| Item | Valor |
|------|-------|
| Imagem base | `joedwards32/cs2` (SteamCMD embutido, auto-update no boot) |
| App ID Steam | `730` |
| Portas | `27015/tcp`, `27015/udp`, `27020/udp` (SourceTV opcional) |
| Volume | `cs2data:/home/steam/cs2-dedicated/` (game files, ~60 GB) |
| UID/GID | `1000:1000` (dono do volume) |

**Por que `joedwards32/cs2`:** roda `steamcmd +app_update 730` a cada start (basta
`docker compose restart cs2` para atualizar o jogo), config 100% por env var, e expõe hooks
`pre.sh`/`post.sh` — o `pre.sh` é o ponto recomendado pelo mantenedor para habilitar Metamod.

**Alternativas consideradas:**
- `cm2network/cs2` — base limpa/vanilla, sem plugins (bom se quisermos montar tudo do zero).
- `xbird/cs2-matchzy` — já traz Metamod+CSSharp+MatchZy (foco em partidas competitivas).

#### Variáveis de ambiente principais

| Var | Exemplo | Descrição |
|-----|---------|-----------|
| `SRCDS_TOKEN` | `<GSLT>` | **Obrigatório p/ servidor público** (ver §5) |
| `CS2_SERVERNAME` | `Meu Servidor BR` | Nome visível |
| `CS2_RCONPW` | `<rcon>` | Senha RCON |
| `CS2_PW` | `` | Senha de entrada (opcional) |
| `CS2_MAXPLAYERS` | `12` | Slots |
| `CS2_PORT` | `27015` | Porta de jogo |
| `CS2_GAMEALIAS` | `competitive` | Modo (`casual`/`competitive`/`deathmatch`/...) |
| `CS2_MAPGROUP` | `mg_active` | Pool de mapas |
| `CS2_STARTMAP` | `de_inferno` | Mapa inicial |
| `CS2_SERVER_HIBERNATE` | `0` | Hibernar quando vazio (CPU baixa) |
| `STEAMAPPVALIDATE` | `0` | `1` força validação/redownload no boot |
| `CS2_ADDITIONAL_ARGS` | `` | Flags cruas extras |
| `DOTNET_SYSTEM_GLOBALIZATION_INVARIANT` | `true` | Evita crash do .NET por falta de `libicu` |

> **Nota:** não existe `CS2_TICKRATE` — CS2 usa arquitetura *sub-tick*. Qualquer flag crua
> vai em `CS2_ADDITIONAL_ARGS`.

### 2.2 `db` — MariaDB

| Item | Valor |
|------|-------|
| Imagem | `mariadb:11` (ou `mysql:8`) |
| Volume | `dbdata:/var/lib/mysql` |
| Rede | só interna (`cs2net`), **sem** porta exposta ao host |
| Tabelas | criadas automaticamente pelo plugin (prefixo `wp_`, InnoDB/utf8mb4) |

Env: `MARIADB_DATABASE=cs2skins`, `MARIADB_USER=cs2`, `MARIADB_PASSWORD=...`,
`MARIADB_ROOT_PASSWORD=...`. Só precisamos criar a base vazia + privilégios CRUD/DDL.

Tabelas geradas pelo plugin: `wp_player_skins`, `wp_player_knife`, `wp_player_gloves`,
`wp_player_agents`, `wp_player_music`, `wp_player_pins`.

### 2.3 `web` — site de seleção de skins

| Item | Valor |
|------|-------|
| Imagem base | `php:8.3-apache` |
| Projeto | `LielXD/CS2-WeaponPaints-Website` **v2.3** |
| Extensões PHP | `pdo_mysql` (instalar), `curl` (já vem) |
| Apache | `mod_rewrite` + `AllowOverride All` (usa `.htaccess`) |
| Portas | `80` (e `443` se TLS) |
| DB | aponta para `db` (a **mesma** base do plugin) |

A v2.3 reescreveu o login OpenID da Steam para funcionar em localhost/qualquer domínio
(bom para containers atrás de proxy). Config via `config.php` (gerado por `config-gen.php`):
`$SteamAPI_KEY` + `$DatabaseInfo[host|database|username|password|port]`.

**Alternativa Docker-friendly:** `rogeraabbccdd/CS2-WeaponPaints-Web` já vem com
`docker-compose` pronto (serve em `:8082`), mas é menos polido que o LielXD v2.3.

### 2.4 `watchtower` (opcional)

Auto-pull da imagem do servidor e recriação do container. **Recomendado deixar manual**
por causa do acoplamento de versões (ver §6).

---

## 3. Stack de plugins (instalada dentro do container `cs2`)

Ordem de instalação **sempre**: Metamod → CounterStrikeSharp → plugins.
Tudo em `game/csgo/addons/`.

| Camada | Projeto | Versão (2026-05) | Destino |
|--------|---------|------------------|---------|
| 1. Metamod:Source | `alliedmodders/metamod-source` (branch **2.0 dev**) | build ~`1401` | `addons/metamod` |
| 2. CounterStrikeSharp | `roflmuffin/CounterStrikeSharp` (**with-runtime**) | `v1.0.368` | `addons/counterstrikesharp` |
| 3. WeaponPaints | `Nereziel/cs2-WeaponPaints` | `3.3a` / Build 423 | `addons/counterstrikesharp/plugins/WeaponPaints` |
| 3a. dep | `NickFox007/MenuManagerCS2` | `1.4.1` | `.../plugins/MenuManager` |
| 3b. dep | `NickFox007/PlayerSettingsCS2` | `0.9.4` | `.../plugins/PlayerSettings` |
| 3c. dep | `NickFox007/AnyBaseLibCS2` | `0.9.4` | `.../plugins/AnyBaseLib` |

Cadeia de dependência: WeaponPaints → MenuManager → PlayerSettings → AnyBaseLib (todas obrigatórias).

> **Versões mudam rápido.** Resolver dinamicamente no build:
> - Metamod: último build do branch `master` em `sourcemm.net/downloads.php?branch=master`.
> - CSSharp / plugins: GitHub releases (`/releases/latest`).
> Sempre usar o pacote **with-runtime** do CSSharp (traz o .NET 8 embutido → imagem self-contained).

### 3.1 Edições obrigatórias

1. **`gameinfo.gi`** (`game/csgo/gameinfo.gi`) — adicionar, dentro de
   `GameInfo → FileSystem → SearchPaths`, **antes** do `Game csgo`:
   ```
   			Game	csgo/addons/metamod
   ```
   ⚠️ Editar `csgo/gameinfo.gi`, **não** `csgo_core/gameinfo.gi`.
   ⚠️ **Todo update do CS2 sobrescreve esse arquivo** → re-patch idempotente no entrypoint (ver §4).

2. **`core.json`** (`addons/counterstrikesharp/configs/core.json`) — definir:
   ```json
   "FollowCS2ServerGuidelines": false
   ```
   Sem isso, **as skins não renderizam** (causa nº 1 de "skin não aparece").

3. **`weaponpaints.json`** — copiar de
   `plugins/WeaponPaints/gamedata/weaponpaints.json` para
   `addons/counterstrikesharp/gamedata/weaponpaints.json`.

4. **`WeaponPaints.json`** (`configs/plugins/WeaponPaints/`) — preencher com os dados do DB
   (`DatabaseHost=db`, `DatabasePort=3306`, `DatabaseUser`, `DatabasePassword`, `DatabaseName`)
   e `Website` apontando para o domínio do site. Idealmente *templated* a partir de env vars.

---

## 4. Estratégia de imagem e entrypoint do `cs2`

Duas abordagens possíveis:

**A) `Dockerfile` próprio sobre `joedwards32/cs2`** (recomendado)
- Baixa Metamod + CSSharp + plugins em build time (camadas cacheáveis).
- Copia um `entrypoint`/`pre.sh` que, **a cada start** (idempotente):
  1. Re-aplica o patch do `gameinfo.gi` (guard clause com `grep -qF`).
  2. Garante `FollowCS2ServerGuidelines=false` no `core.json` (via `jq`).
  3. Renderiza `WeaponPaints.json` a partir das env vars do DB.
  4. Copia `weaponpaints.json` para `gamedata/` se faltar.

**B) Bind-mounts + `CS2_CFG_URL`** — montar `./addons` direto no volume e/ou apontar
`CS2_CFG_URL` para um tarball. Mais simples, menos reprodutível.

### Patch idempotente do `gameinfo.gi`

```sh
GAMEINFO="${CSGO_DIR}/csgo/gameinfo.gi"
grep -qF 'csgo/addons/metamod' "$GAMEINFO" || \
  sed -i '/SearchPaths/{n;a\\t\t\t\tGame\tcsgo/addons/metamod
}' "$GAMEINFO"
```
O `grep -qF` é a guard clause: depois de um update do jogo (que apaga a linha), o grep não
acha nada e re-aplica; num arquivo já corrigido, vira no-op (sem duplicar linha).

### Dependências de runtime (.NET)
CSSharp precisa de **.NET 8**. O pacote *with-runtime* já o embute, mas o Linux ainda quer
`libicu` — instalar `libicu` na imagem **ou** setar `DOTNET_SYSTEM_GLOBALIZATION_INVARIANT=true`.

---

## 5. GSLT (Game Server Login Token)

Necessário para o servidor aparecer na lista pública e usar VAC.
- Gerar em **https://steamcommunity.com/dev/managegameservers** com App ID **730**.
- Requer conta Steam não-limitada, com Steam Guard Mobile (telefone verificado), dona do jogo.
- **1 token por servidor.**
- Injetado via `SRCDS_TOKEN` (a imagem passa como `+sv_setsteamaccount`).

**Steam Web API Key** (diferente do GSLT) — para o login OpenID do **site**:
gerar em **https://steamcommunity.com/dev/apikey** → `$SteamAPI_KEY` no `config.php`.

---

## 6. Atualização (auto-update) — política

| Componente | Como atualiza | Risco |
|------------|---------------|-------|
| Jogo CS2 | SteamCMD no boot do container (`restart`) | Pode quebrar plugins |
| Metamod | rebuild da imagem (resolve último build) | Acompanha updates do Source 2 |
| CounterStrikeSharp | rebuild (resolve `/releases/latest`) | Offsets/assinaturas mudam por patch |
| Plugins (WeaponPaints etc.) | rebuild | Dependem do CSSharp |

**Recomendação:** **NÃO** deixar o jogo auto-atualizar sozinho à frente dos plugins.
Quando a Valve lança um patch de CS2, é comum CSSharp/Metamod quebrarem até saírem builds
compatíveis. Política sugerida:

1. Update **controlado**: bump de CS2 + Metamod + CSSharp + plugins **juntos**, via rebuild da imagem.
2. `gameinfo.gi` re-patchado **sempre** no start (sobrevive a updates).
3. Watchtower só se aceitarmos o risco de downtime pós-patch — ou apontado só para a imagem
   do site/DB, não para o `cs2`.

---

## 7. Estrutura de arquivos proposta

```
cs2-docker/
├── docker-compose.yml
├── .env                      # GSLT, senhas, Steam API key, DB creds (gitignored)
├── .env.example
├── cs2/
│   ├── Dockerfile            # FROM joedwards32/cs2 + plugins
│   ├── entrypoint.sh         # patch gameinfo.gi, core.json, render WeaponPaints.json
│   ├── install-plugins.sh    # baixa Metamod/CSSharp/WeaponPaints+deps (build time)
│   └── cfg/
│       └── gamemode_competitive_server.cfg
├── web/
│   ├── Dockerfile            # FROM php:8.3-apache + pdo_mysql + site v2.3
│   └── config.php.template   # templated a partir de env vars no entrypoint
└── README.md
```

---

## 8. Variáveis de ambiente (`.env`)

```dotenv
# --- Steam ---
SRCDS_TOKEN=                 # GSLT (managegameservers, app 730)
STEAM_API_KEY=               # Steam Web API key (dev/apikey) p/ login do site

# --- Servidor ---
CS2_SERVERNAME=Meu Servidor BR
CS2_RCONPW=
CS2_MAXPLAYERS=12
CS2_GAMEALIAS=competitive
CS2_STARTMAP=de_inferno

# --- Banco ---
DB_NAME=cs2skins
DB_USER=cs2
DB_PASSWORD=
DB_ROOT_PASSWORD=

# --- Site ---
WEB_URL=http://localhost:8080
```

---

## 9. Requisitos de infraestrutura

| Recurso | Mínimo | Recomendado (12 slots) |
|---------|--------|------------------------|
| CPU | 2 cores | 4+ cores, 3.0–3.5 GHz+ (sensível a clock single-thread) |
| RAM | 2 GB | 4 GB (limite Docker `mem_limit: 4g`); 8 GB p/ 24 slots |
| Disco | 60 GB SSD | 80 GB+ SSD |
| Rede | porta 27015 udp/tcp liberada + 80/443 p/ site | |

---

## 10. Riscos e pontos em aberto

1. **Quebra pós-patch do CS2** — principal risco operacional. Mitigação: update controlado (§6).
2. **`config.php` do site** usa variáveis PHP (não `getenv()`) → precisamos *templating* no
   entrypoint ou `config.php` pré-preenchido montado como volume. **Confirmar** lendo o ZIP
   da release v2.3 se dá para gerar de forma não-interativa.
3. **Versões "latest" vs pinadas** — pinar dá reprodutibilidade; "latest" reduz manutenção mas
   aumenta risco. Decisão de projeto: **pinar** e bumpar de propósito.
4. **`libicu` vs INVARIANT** — validar qual abordagem é estável na imagem base escolhida.
5. **Persistência do `csgo/`** em volume nomeado para não rebaixar ~60 GB a cada recriação.
6. **GSLT obrigatório** para uso público — sem ele só LAN/local.

---

## 11. Referências

**Servidor / imagem**
- https://github.com/joedwards32/CS2 · https://hub.docker.com/r/joedwards32/cs2
- https://hub.docker.com/r/cm2network/cs2 · https://hub.docker.com/r/xbird/cs2-matchzy
- GSLT: https://steamcommunity.com/dev/managegameservers
- https://developer.valvesoftware.com/wiki/Counter-Strike_2/Dedicated_Servers

**Metamod / CounterStrikeSharp**
- https://www.sourcemm.net/downloads.php?branch=master · https://github.com/alliedmodders/metamod-source
- https://cs2.poggu.me/metamod/installation/
- https://github.com/roflmuffin/CounterStrikeSharp · https://github.com/roflmuffin/CounterStrikeSharp/blob/main/INSTALL.md

**WeaponPaints (plugin + deps)**
- https://github.com/Nereziel/cs2-WeaponPaints
- https://github.com/NickFox007/MenuManagerCS2 · https://github.com/NickFox007/PlayerSettingsCS2 · https://github.com/NickFox007/AnyBaseLibCS2
- https://docs.gamecms.org/integrations/counter-strike-2/weapon-paints/

**Site de skins**
- https://github.com/LielXD/CS2-WeaponPaints-Website (v2.3)
- https://github.com/rogeraabbccdd/CS2-WeaponPaints-Web (Docker pronto)
- Steam Web API key: https://steamcommunity.com/dev/apikey
