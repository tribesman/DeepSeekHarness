# DeepSeekHarness

Docker-окружение для [DeepSeek Harness (dsh)](https://hub.docker.com/r/smanx/deepseek-harness) —
веб-агента с плагинами, настроенное так, чтобы быть максимально похожим на
Claude Code: боковая панель с файлами/терминалом/git, переключение веток,
git worktree и браузерная автоматизация.

## Структура

- **`Dockerfile`** — расширяет базовый образ `smanx/deepseek-harness:devtools-min-latest`
  тулчейном, который нужен плагинам и не должен переустанавливаться при каждом
  старте контейнера:
  - `gh`, `glab` — CLI для GitHub и GitLab (для сайдбар-плагинов). Ставятся не из
    репозитория Debian (там `gh` 2.23.0 от 2023 года), а из официальных релизов:
    версии прибиты (`ARG GH_VERSION`, `ARG GLAB_VERSION`), скачанные `.deb`
    проверяются по контрольной сумме того же релиза
  - `python3` + `pip`/`venv`, `make`, `g++`, `pkg-config` — скрипты и сборка
    нативных node-модулей плагинов (например `node-pty` для терминала в
    `dsh-better-sidebar`). `pip install` работает в venv: системный Python в
    Debian помечен PEP 668, а `uv` для Python-пакетов уже есть в базе
  - `php-cli` + `composer` (PHP 8.2 из bookworm) с расширениями
    curl/gd/intl/mbstring/mysql/xml/zip/bcmath/sqlite3 — `composer install`,
    `phpunit`, миграции
  - `mariadb-client`, `sqlite3` — консольные клиенты БД
  - `nano`, `mc`, `htop`, `tmux`, `rsync`, `ripgrep`, `file`, `zip`,
    `poppler-utils` (`pdftotext`) — утилиты для ручной работы в контейнере
  - системные библиотеки для headless Chromium (нужны `dsh-browser` / Playwright)
- **`docker-compose.yml`** — поднимает контейнер и монтирует persistent-данные с
  хоста (см. ниже). Порты, модель, плагины, секреты и пути подставляются из
  `.env` — литеральных доступов в файле нет
- **`.env`** — все пути, порты и секреты для этой машины. В git не попадает,
  шаблон с комментарием к каждой переменной — `.env.example` (см. «Окружение»)
- **`Makefile`** — задачи для работы с окружением: `make sync` переносит только
  состояние `data/` на VDS (код и compose-файлы едут через git, см.
  «Синхронизация на VDS»), `make sync-workspace` — отдельно код агента
- **`data/`** — все данные DSH лежат на хосте бинд-маунтами и переживают
  `docker compose down` (в git не попадают, см. `.gitignore`):
  - `data/dsh-home` → `/root/.dsh` — сессии, чаты, `settings.yaml`, credentials
    и **все установленные плагины** (их `node_modules` лежат тут же)
  - `data/playwright-cache` → `/root/.cache/ms-playwright` — скачанный
    браузер Chromium для `dsh-browser`
  - `data/dsh-plugins` → `/root/dsh-plugins` — git-клон community-плагинов
    ([worktree-launcher, changes-lens, agent-terminal](https://github.com/steve-magne/dsh-plugins)),
    на него ссылаются симлинки внутри `.dsh`. Стоит на **прибитом коммите**
    (`DSH_PLUGINS_REF`), а не на плавающем `main` — см. «Обновление плагинов»
- **`workspace/`** — папка на хосте, в которой агент будет кодить (монтируется
  в `/opt/workspace`; путь задаёт `WORKSPACE_DIR` из `.env`)
- **`docker-compose.override.yml`** — необязательные машинные дополнения:
  SSH-ключи/ssh-agent, дополнительные проекты, `extra_hosts`. В git не
  попадает — Docker Compose подхватывает файл автоматически, ничего
  дополнительно указывать не нужно. Шаблон —
  `docker-compose.override.example.yml`; секреты и пути там больше не хранятся,
  только `${...}`-ссылки на переменные из `.env`

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

## Окружение (`.env`)

Все пути, порты и доступы живут в `.env` — один файл на машину. Его читают
Docker Compose (подставляет `${...}` в `docker-compose*.yml`) и `Makefile`.
В git, в контекст сборки образа и в `make sync` он не попадает, поэтому
секретов в репозитории нет.

```bash
cp .env.example .env
nano .env
```

В `.env.example` у каждой переменной есть комментарий; группы:

| Группа | Переменные |
|---|---|
| перенос на VDS | `VDS_HOST`, `VDS_USER`, `VDS_PORT`, `VDS_DIR`, `SSH_KEY`, `SYNC_EXCLUDES`, `RSYNC_FLAGS` |
| сеть и порты | `DSH_PORT`, `PROXY_PORT`, `PROXY_BIND` |
| модель и плагины | `DSH_MODEL`, `DSH_PLUGINS_REPO`, `DSH_PLUGINS_REF` |
| секреты | `OPENAI_API_KEY`, `PROXY_USERNAME`, `PROXY_PASSWORD`, `GH_TOKEN`, `GITLAB_TOKEN` |
| пути хоста и git-конфиг | `WORKSPACE_DIR`, `GH_CONFIG_DIR`, `GLAB_CONFIG_DIR`, `GIT_CONFIG_GLOBAL`, `SSH_DIR`, `SSH_AUTH_SOCK_PATH`, `PROJECT_HLRD_DIR`, `PROJECT_DATING_DIR` |

`PROXY_USERNAME`/`PROXY_PASSWORD` обязательны: через прокси на `PROXY_PORT`
Web UI смотрит наружу, и без этой пары любой, кто дотянется до порта (в том
числе вся локальная сеть), получает сессию агента с шеллом в контейнере.

Значения пишите без кавычек; комментарии — отдельной строкой; в секретах и
путях избегайте пробелов, `#` и `$` — Make и Compose прочитают их по-разному.

## Запуск

Перед первым запуском — заполните `.env` (см. выше), как минимум:

- `PROXY_USERNAME` / `PROXY_PASSWORD` — **обязательно**, своими значениями
- `OPENAI_API_KEY` — ключ провайдера (DeepSeek, OpenRouter или OpenAI)
- `GH_TOKEN` / `GITLAB_TOKEN` — personal access token'ы GitHub/GitLab: их читают
  `gh`/`glab` (и через них — сайдбар-плагины) прямо из окружения, интерактивный
  `auth login` не нужен, что удобно: TTY в контейнере нет. Учтите, что сам `git`
  эти переменные не читает — см. следующий раздел
- при необходимости `WORKSPACE_DIR`, `GH_CONFIG_DIR`, `GLAB_CONFIG_DIR`

```bash
docker compose up -d --build
```

Веб-интерфейс будет доступен на `http://localhost:3080` (за Basic Auth из
`PROXY_USERNAME`/`PROXY_PASSWORD`). По умолчанию `PROXY_BIND=127.0.0.1` — порт
слушает только сам хост, это правильный выбор для VDS (дальше ставится
TLS-прокси или SSH-туннель). Если нужен доступ из локальной сети (например,
Mac в домашней сети), поставьте `PROXY_BIND=0.0.0.0` — но тогда пароль
обязателен: сеть получает полную сессию агента.

После правок `Dockerfile` образ нужно пересобрать явно:

```bash
docker compose build && docker compose up -d
```

Проверить, что тулчейн на месте:

```bash
docker compose exec deepseek-harness sh -lc \
  'python3 -V && php -v | head -1 && composer -V && mysql --version'
```

## Синхронизация на VDS (`make sync`)

Код и compose-файлы приезжают на сервер через git, а `make sync` переносит
**только состояние** — каталог `data/`: сессии, настройки, credentials,
установленные плагины, клон `dsh-plugins`, конфиги gh/glab. Кэши не
переносятся — Chromium entrypoint докачает при старте.

Порядок:

1. на VDS клонируйте репозиторий в `VDS_DIR` (один раз);
2. с локальной машины выполните `make sync` — он создаст `data/` и зальёт
   состояние по SSH/rsync;
3. на VDS создайте `.env` (секреты и пути сервера) и запустите
   `docker compose up -d --build`.

```bash
# на VDS
git clone git@github.com:tribesman/DeepSeekHarness.git /srv/deepseek-harness

# локально (VDS_HOST/VDS_USER/VDS_PORT/VDS_DIR — в .env)
make sync

# на VDS
cd /srv/deepseek-harness && cp .env.example .env && nano .env
docker compose up -d --build
```

Понадобятся SSH-доступ на VDS и `rsync` на обеих машинах (`apt install rsync`
на сервере; на macOS подойдёт системный или `brew install rsync`).

Что делает `make sync`:

1. проверяет, что на VDS в `VDS_DIR` уже лежит репозиторий (если нет —
   предупреждает, но `data/` всё равно создаёт);
2. копирует `data/` без `playwright-cache` и `.pnpm-store`;
3. подсказывает команду запуска.

На сервере `WORKSPACE_DIR` по умолчанию `./workspace` — именно туда
`make sync-workspace` складывает код, и именно эту папку монтирует контейнер.
Если код агенту на VDS не нужен, этот шаг можно пропустить.

`.env` на VDS не копируется: пути и секреты у сервера свои (как минимум
`PROXY_BIND=127.0.0.1`, публичные хост/порт и пути хоста). Создайте его там
один раз — вручную или `scp .env root@VDS:$VDS_DIR/`.

Повторный `make sync` обновляет файлы на месте; удалённые локально файлы он
**не** удаляет (rsync без `--delete`) — состояние и `.env` сервера в
безопасности. Если на сервере другая архитектура (обычно x86_64 против
Apple Silicon), `node-pty` придётся пересобрать:

```bash
docker compose exec deepseek-harness sh -lc \
  'cd /root/.dsh/profiles/web && pnpm rebuild node-pty'
```

## Git-доступ к приватным репозиториям (по желанию)

`GH_TOKEN`/`GITLAB_TOKEN` закрывают только API: `git` сам их не читает, поэтому
клонирование и пуш приватных репозиториев из контейнера подключается отдельно.

**Чтобы логин не слетал при пересоздании контейнера.** Из содержимого образа
переживает только `/root/.dsh` (это `./data/dsh-home`), а `gh`/`glab` держат вход
в `/root/.config/gh` и `/root/.config/glab-cli`; кроме того, `gh auth login`
прописывает credential helper для git в `/root/.gitconfig`. Поэтому в
`docker-compose.yml` уже есть проброс: логины монтируются из `GH_CONFIG_DIR` и
`GLAB_CONFIG_DIR` (по умолчанию `./data/gh-config` и `./data/glab-config`), а
конфиг git уведён в персистимый путь переменной
`GIT_CONFIG_GLOBAL=/root/.dsh/gitconfig`. Без этого после `docker compose up -d`
с пересозданием контейнера логин и доступ git к приватным репозиториям придётся
настраивать заново. Если хочется один вход на контейнер и хост — задайте в
`.env` `GH_CONFIG_DIR`, `GLAB_CONFIG_DIR` и `GIT_CONFIG_GLOBAL` (хост-пути
`~/.config/gh`, `~/.config/glab-cli` и `~/.gitconfig`).

Дальше — два рабочих варианта, оба делаются один раз.

**HTTPS + credential helper.** В контейнере выполните:

```bash
docker compose exec deepseek-harness gh auth login            # GitHub: вход + helper для git
docker compose exec deepseek-harness glab auth login --hostname gitlab.com --stdin < token.txt
```

Если `gh` авторизован только переменной `GH_TOKEN` (интерактивный вход не
делали), helper ставится отдельно: `docker compose exec deepseek-harness gh auth setup-git`.

**SSH с ключом.** Смонтируйте ключи, а если ключ под паролем — дополнительно
пробросьте сокет ssh-agent'а хоста. Строки уже есть в
`docker-compose.override.example.yml` закомментированными: раскомментируйте их
и задайте `SSH_DIR`/`SSH_AUTH_SOCK_PATH` в `.env`.

```yaml
    volumes:
      - ${SSH_DIR}:/root/.ssh:ro
      - ${SSH_AUTH_SOCK_PATH}:/ssh-agent # только если ssh-agent запущен на хосте
    environment:
      - SSH_AUTH_SOCK=/ssh-agent
```

и переключите git на SSH:

```bash
docker compose exec deepseek-harness git config --global url."git@github.com:".insteadOf "https://github.com/"
```

Команды `ssh`/`ssh-agent` в образе есть (`openssh-client`), но ни ключей, ни
агента по умолчанию в контейнер не пробрасывается — без шагов выше `git` по SSH
и по HTTPS к приватным репозиториям работать не будет.

## Обновление плагинов

Community-плагины стоят на прибитом коммите (`DSH_PLUGINS_REF` из `.env`), и
контейнер при каждом старте приводит копию ровно к нему — плавающий `main`
намеренно не тянется, чтобы чужая правка не приезжала в работающее окружение
сама по себе. Чтобы обновить:

1. посмотрите свежий коммит в [steve-magne/dsh-plugins](https://github.com/steve-magne/dsh-plugins);
2. впишите его в `DSH_PLUGINS_REF` в `.env`;
3. `docker compose up -d`.

Шаги старта (плагины и докачка Chromium) необязательные: если сети нет или
что-то не скачалось, контейнер печатает предупреждение и поднимается на том,
что уже лежит в `./data`. Если в `/root/dsh-plugins` остались ваши локальные
правки, реф не переключится — в логе будет предупреждение.
