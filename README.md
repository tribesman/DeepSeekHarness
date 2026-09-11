# DeepSeekHarness

Docker-окружение для [DeepSeek Harness (dsh)](https://hub.docker.com/r/smanx/deepseek-harness) —
веб-агента с плагинами, настроенное так, чтобы быть максимально похожим на
Claude Code: боковая панель с файлами/терминалом/git, переключение веток,
git worktree и браузерная автоматизация.

## Структура

- **`Dockerfile`** — расширяет базовый образ `smanx/deepseek-harness:devtools-min-latest`
  тулчейном, который нужен плагинам и не должен переустанавливаться при каждом
  старте контейнера:
  - `gh`, `glab` — CLI для GitHub и GitLab (для сайдбар-плагинов)
  - `python3`, `make`, `g++` — сборка нативных node-модулей плагинов (например
    `node-pty` для терминала в `dsh-better-sidebar`)
  - системные библиотеки для headless Chromium (нужны `dsh-browser` / Playwright)
  - `nano`, `mc`, `htop` — консольные утилиты для ручной работы в контейнере
- **`docker-compose.yml`** — поднимает контейнер, пробрасывает порт `3080` и
  монтирует persistent-данные с хоста (см. ниже)
- **`data/`** — все данные DSH лежат на хосте бинд-маунтами и переживают
  `docker compose down` (в git не попадают, см. `.gitignore`):
  - `data/dsh-home` → `/root/.dsh` — сессии, чаты, `settings.yaml`, credentials
    и **все установленные плагины** (их `node_modules` лежат тут же)
  - `data/playwright-cache` → `/root/.cache/ms-playwright` — скачанный
    браузер Chromium для `dsh-browser`
  - `data/dsh-plugins` → `/root/dsh-plugins` — git-клон community-плагинов
    ([worktree-launcher, changes-lens, agent-terminal](https://github.com/steve-magne/dsh-plugins)),
    на него ссылаются симлинки внутри `.dsh`
- **`workspace/`** — папка на хосте, в которой агент будет кодить (монтируется
  в `/opt/workspace`)
- **`docker-compose.override.yml`** — секреты (`OPENAI_API_KEY`, `GH_TOKEN`,
  `GITLAB_TOKEN`, при желании `PROXY_USERNAME`/`PROXY_PASSWORD`) и личные
  пути хоста (свои bind-mount'ы, `extra_hosts`). В git не попадает — Docker
  Compose подхватывает этот файл автоматически рядом с `docker-compose.yml`,
  ничего дополнительно указывать не нужно. Шаблон — `docker-compose.override.example.yml`

## Установленные плагины

- `dsh-better-sidebar` — VSCode-подобная боковая панель (файлы/редактор/терминал/git)
- `dsh-git-status` — индикатор и переключение git-веток
- `dsh-task-worktree` + community-плагин `worktree-launcher` — полноценная
  поддержка git worktree для параллельных задач
- `dsh-browser` — браузерная автоматизация на Playwright (открыть/кликнуть/
  ввести текст/скриншот)
- `changes-lens`, `agent-terminal` — доп. community-плагины из сайдбара

> `dsh-github-cli` (GitHub-сайдбар через `gh`) сейчас **не установлен** —
> его npm-пакет ссылается на приватную зависимость `@deepseek-ai/dsh-type-meta`
> и не собирается. Сам `gh` в контейнере есть, доступен вручную через терминал.

## Запуск

Перед первым запуском:

```bash
cp docker-compose.override.example.yml docker-compose.override.yml
nano docker-compose.override.yml
```

и заполните:
- `OPENAI_API_KEY` — ключ провайдера (DeepSeek, OpenRouter или OpenAI)
- `GH_TOKEN` / `GITLAB_TOKEN` — personal access token'ы GitHub/GitLab (нужны
  для приватных репозиториев). `gh`/`glab` подхватывают их из окружения сами,
  без интерактивного `auth login` — это удобно, так как в контейнере нет TTY
- при необходимости `PROXY_USERNAME`/`PROXY_PASSWORD` для базовой авторизации
  Web UI и свои bind-mount'ы/`extra_hosts`

```bash
docker compose up -d --build
```

Веб-интерфейс будет доступен на `http://localhost:3080`.

После правок `Dockerfile` образ нужно пересобрать явно:

```bash
docker compose build && docker compose up -d
```
