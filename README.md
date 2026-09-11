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

```bash
docker compose up -d --build
```

Веб-интерфейс будет доступен на `http://localhost:3080`.

Перед первым запуском задайте в `docker-compose.yml`:
- `OPENAI_API_KEY` — ключ провайдера (DeepSeek, OpenRouter или OpenAI)
- при необходимости `PROXY_USERNAME`/`PROXY_PASSWORD` для базовой авторизации

После правок `Dockerfile` образ нужно пересобрать явно:

```bash
docker compose build && docker compose up -d
```
