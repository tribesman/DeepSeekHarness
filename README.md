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
    на него ссылаются симлинки внутри `.dsh`. Стоит на **прибитом коммите**
    (`DSH_PLUGINS_REF`), а не на плавающем `main` — см. «Обновление плагинов»
- **`workspace/`** — папка на хосте, в которой агент будет кодить (монтируется
  в `/opt/workspace`)
- **`docker-compose.override.yml`** — секреты и личные пути хоста. В git не
  попадает — Docker Compose подхватывает этот файл автоматически рядом с
  `docker-compose.yml`, ничего дополнительно указывать не нужно. Шаблон —
  `docker-compose.override.example.yml`:
  - `PROXY_USERNAME` / `PROXY_PASSWORD` — **обязательны**: через прокси на порту
    `3080` Web UI смотрит наружу, и без этой пары любой, кто дотянется до порта
    (в том числе вся локальная сеть), получает полноценную сессию агента с шеллом
    в контейнере и доступом к смонтированным папкам хоста. Прокси включает
    проверку только когда заданы **оба** значения
  - `OPENAI_API_KEY`, `GH_TOKEN`, `GITLAB_TOKEN` — ключ провайдера и токены для
    API сайдбар-плагинов (для `git` по HTTP(S)/SSH токена недостаточно, см.
    «Git-доступ к приватным репозиториям»)
  - свои bind-mount'ы и `extra_hosts`

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
- `PROXY_USERNAME` / `PROXY_PASSWORD` — **обязательно**, своими значениями.
  Без них прокси на порту `3080` пускает кого угодно без пароля (см. «Структура»)
- `OPENAI_API_KEY` — ключ провайдера (DeepSeek, OpenRouter или OpenAI)
- `GH_TOKEN` / `GITLAB_TOKEN` — personal access token'ы GitHub/GitLab: их читают
  `gh`/`glab` (и через них — сайдбар-плагины) прямо из окружения, интерактивный
  `auth login` не нужен, что удобно: TTY в контейнере нет. Учтите, что сам `git`
  эти переменные не читает — см. следующий раздел
- при необходимости свои bind-mount'ы/`extra_hosts`

```bash
docker compose up -d --build
```

Веб-интерфейс будет доступен на `http://localhost:3080` (за Basic Auth из
`PROXY_USERNAME`/`PROXY_PASSWORD`). Порт привязан ко всем интерфейсам хоста — на
машине в чужой сети его лучше сузить до локального: `- "127.0.0.1:3080:3080"`.

После правок `Dockerfile` образ нужно пересобрать явно:

```bash
docker compose build && docker compose up -d
```

## Git-доступ к приватным репозиториям (по желанию)

`GH_TOKEN`/`GITLAB_TOKEN` закрывают только API: `git` сам их не читает, поэтому
клонирование и пуш приватных репозиториев из контейнера нужно подключить
осознанно. Ниже — два рабочих варианта, оба делаются один раз.

**HTTPS + credential helper.** В `docker-compose.override.yml` добавьте проброс
конфига, чтобы настройка пережила пересоздание контейнера:

```yaml
    volumes:
      - ./data/gitconfig:/root/.gitconfig
```

затем в контейнере один раз выполните:

```bash
docker compose exec deepseek-harness gh auth setup-git     # GitHub: helper для git
docker compose exec deepseek-harness glab auth login --hostname gitlab.com --stdin < token.txt
```

**SSH с ключом.** Смонтируйте ключи, а если ключ под паролем — дополнительно
пробросьте сокет ssh-agent'а хоста:

```yaml
    volumes:
      - ${HOME}/.ssh:/root/.ssh:ro
      - ${SSH_AUTH_SOCK}:/ssh-agent # только если ssh-agent запущен на хосте
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

Community-плагины стоят на прибитом коммите (`DSH_PLUGINS_REF` в
`docker-compose.yml`), и контейнер при каждом старте приводит копию ровно к нему
— плавающий `main` намеренно не тянется, чтобы чужая правка не приезжала в
работающее окружение сама по себе. Чтобы обновить:

1. посмотрите свежий коммит в [steve-magne/dsh-plugins](https://github.com/steve-magne/dsh-plugins);
2. впишите его в `DSH_PLUGINS_REF` внутри `docker-compose.override.yml`;
3. `docker compose up -d`.

Шаги старта (плагины и докачка Chromium) необязательные: если сети нет или
что-то не скачалось, контейнер печатает предупреждение и поднимается на том,
что уже лежит в `./data`. Если в `/root/dsh-plugins` остались ваши локальные
правки, реф не переключится — в логе будет предупреждение.
