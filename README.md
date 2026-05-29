# cs2-docker

Servidor **Counter-Strike 2** dedicado em Docker, com sistema de **skins** (WeaponPaints)
e **site** para os jogadores escolherem suas skins — tudo orquestrado via Docker Compose.

> Projeto guiado pela [`SPEC.md`](./SPEC.md). Leia-a para a arquitetura completa,
> versões dos componentes e a política de atualização.

## Componentes

| Serviço | O que é |
|---------|---------|
| `cs2` | Servidor dedicado (`joedwards32/cs2`) + Metamod + CounterStrikeSharp + WeaponPaints (+ MenuManager, PlayerSettings, AnyBaseLib) |
| `db` | MariaDB — base compartilhada entre o plugin e o site |
| `web` | Site de skins em PHP (`LielXD/CS2-WeaponPaints-Website`), login via Steam |

O jogador entra no site com a Steam, escolhe a skin → grava no MySQL → o plugin aplica in-game.

## Pré-requisitos

- Docker + Docker Compose
- **GSLT** (token do servidor): https://steamcommunity.com/dev/managegameservers (App ID `730`)
- **Steam Web API key** (login do site): https://steamcommunity.com/dev/apikey
- ~60 GB de disco, 4+ GB RAM (ver SPEC §9)

## Uso

```bash
cp .env.example .env
# edite .env: SRCDS_TOKEN, STEAM_API_KEY, senhas do banco, etc.

docker compose up -d --build
```

- Servidor: porta `27015` (UDP/TCP)
- Site de skins: http://localhost:8080 (ou `WEB_PORT` do `.env`)

A primeira subida baixa o jogo (~60 GB) e os addons — pode demorar.

### Atualizar o jogo

```bash
docker compose restart cs2   # SteamCMD atualiza no boot; addons são re-sincronizados
```

> ⚠️ Updates do CS2 podem quebrar Metamod/CSSharp até saírem builds compatíveis.
> Prefira atualizar **de propósito**, bumpando as versões (ARGs no `cs2/Dockerfile`)
> e o jogo juntos. Ver SPEC §6.

## Estrutura

```
.
├── docker-compose.yml
├── .env.example
├── SPEC.md                       # especificação completa
├── cs2/
│   ├── Dockerfile                # FROM joedwards32/cs2 + addons
│   ├── install-plugins.sh        # download dos addons (build time)
│   ├── cs2-setup.sh              # sync + patches (a cada start)
│   ├── pre.sh                    # hook chamado pela imagem (bind-mount)
│   └── cfg/gamemode_competitive_server.cfg
└── web/
    ├── Dockerfile                # FROM php:8.3-apache + site v2.3
    └── entrypoint.sh             # gera config.php das env vars
```

## Notas

- Sem `SRCDS_TOKEN` o servidor só funciona em LAN/local.
- As tabelas do banco (`wp_*`) são criadas automaticamente pelo plugin no 1º load.
- O `pre.sh` é montado por bind: editou, reinicia o `cs2` e vale (sem rebuild).
