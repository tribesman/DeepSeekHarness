FROM smanx/deepseek-harness:devtools-min-latest

# Тулчейн окружения — запекается в образ один раз при сборке, а не
# переустанавливается заново при каждом пересоздании контейнера.
#
#   gh                 — для dsh-github-cli / любых GitHub-плагинов сайдбара
#                        (ставится ниже из официальных релизов, см. ARG GH_VERSION)
#   glab               — то же для GitLab (ниже, из .deb-релиза GitLab)
#   python3 (+pip, venv), make, g++, pkg-config
#                      — скрипты и нативная сборка node-модулей плагинов
#                        (например node-pty для терминала в dsh-better-sidebar);
#                        pip-пакеты ставятся в venv — системный Python в Debian
#                        помечен PEP 668, а uv для Python уже есть в базе
#   php-cli + composer — PHP-проекты: composer install, phpunit, миграции;
#                        расширения — curl/gd/intl/mbstring/mysql/xml/zip/bcmath/sqlite3
#   mariadb-client, sqlite3 — консольные клиенты БД (mysql/mariadb и sqlite3)
#   nano, mc, htop, tmux, rsync, ripgrep, file, zip, poppler-utils
#                      — утилиты для ручной работы в контейнере (pdftotext идёт
#                        из poppler-utils, rg — быстрый поиск по коду)
#   openssh-client     — ssh/ssh-agent для git по SSH и для gh/glab, если нужен ключ вместо токена
#                        (сами ключи/агент в контейнер не пробрасываются — см. README)
RUN apt-get update && apt-get install -y --no-install-recommends \
    python3 python3-pip python3-venv pkg-config \
    make g++ \
    nano mc htop tmux \
    openssh-client rsync \
    ripgrep file zip poppler-utils sqlite3 \
    mariadb-client \
    php-cli php-curl php-gd php-intl php-mbstring php-mysql php-xml php-zip php-bcmath php-sqlite3 \
    composer \
    && rm -rf /var/lib/apt/lists/*

# gh — из официальных релизов cli.github.com, а не из репозитория Debian:
# в bookworm лежит gh 2.23.0 (февраль 2023), чего мало современным плагинам.
# Версия пинится, скачанный .deb сверяется с официальным checksums-файлом релиза.
ARG GH_VERSION=2.100.0
RUN ARCH="$(dpkg --print-architecture)" \
    && curl -fsSL -o /tmp/gh.deb "https://github.com/cli/cli/releases/download/v${GH_VERSION}/gh_${GH_VERSION}_linux_${ARCH}.deb" \
    && curl -fsSL -o /tmp/gh.checksums "https://github.com/cli/cli/releases/download/v${GH_VERSION}/gh_${GH_VERSION}_checksums.txt" \
    && EXPECTED_SHA="$(grep -F "gh_${GH_VERSION}_linux_${ARCH}.deb" /tmp/gh.checksums | cut -d' ' -f1)" \
    && echo "${EXPECTED_SHA}  /tmp/gh.deb" | sha256sum -c - \
    && apt-get update && apt-get install -y --no-install-recommends /tmp/gh.deb \
    && rm -f /tmp/gh.deb /tmp/gh.checksums && rm -rf /var/lib/apt/lists/*

# glab — аналог gh, но для GitLab. В репозиториях Debian его нет, ставим
# из официального .deb-релиза GitLab (архитектура подбирается автоматически).
# Версия пинится, .deb сверяется с checksums.txt того же релиза.
ARG GLAB_VERSION=1.117.0
RUN ARCH="$(dpkg --print-architecture)" \
    && curl -fsSL -o /tmp/glab.deb "https://gitlab.com/api/v4/projects/gitlab-org%2Fcli/packages/generic/glab/${GLAB_VERSION}/glab_${GLAB_VERSION}_linux_${ARCH}.deb" \
    && curl -fsSL -o /tmp/glab.checksums "https://gitlab.com/api/v4/projects/gitlab-org%2Fcli/packages/generic/glab/${GLAB_VERSION}/checksums.txt" \
    && EXPECTED_SHA="$(grep -F "glab_${GLAB_VERSION}_linux_${ARCH}.deb" /tmp/glab.checksums | cut -d' ' -f1)" \
    && echo "${EXPECTED_SHA}  /tmp/glab.deb" | sha256sum -c - \
    && apt-get update && apt-get install -y --no-install-recommends /tmp/glab.deb \
    && rm -f /tmp/glab.deb /tmp/glab.checksums && rm -rf /var/lib/apt/lists/*

# Системные библиотеки для headless Chromium (нужны dsh-browser / Playwright).
# Сам браузерный бинарник НЕ запекаем сюда — он остаётся рантайм-данными в
# ./data/playwright-cache (см. docker-compose.yml), чтобы образ не раздувать и
# чтобы кэш браузера переживал пересборку образа отдельно от него. А вот
# системные .so-библиотеки — это часть окружения ОС, их место здесь.
# Версия playwright-core пина под dsh-browser (см. package.json плагина).
RUN npm init -y >/dev/null 2>&1 && npm install --no-save playwright-core@1.63.0 \
    && node_modules/.bin/playwright-core install-deps chromium \
    && rm -rf node_modules package.json package-lock.json \
    && rm -rf /var/lib/apt/lists/*

# ── Пользователь контейнера ───────────────────────────────────────────────────
# Контейнер работает от uid/gid пользователя VDS (DSH_UID/DSH_GID), а не от
# root. Причина: данные лежат в bind-mount'ах ./data/... и должны принадлежать
# тому же пользователю, под которым делается `make sync`. Если писать от root,
# всё созданное контейнером (сессии, attachments, storages/*.json) на хосте
# становится root:root, и rsync под обычным пользователем падает с
# "Permission denied" и "failed to set times ... Operation not permitted".
#
#   /root  — отдаём этому uid: compose монтирует данные в /root/.dsh и
#            /root/dsh-plugins, а симлинки плагинов ведут на /root/dsh-plugins;
#   /app   — каталог, а не содержимое: entrypoint пишет туда .dsh-web.log и
#            .dsh-launch-token, а код остаётся root-owned и read-only.
#
# После смены DSH_UID/DSH_GID образ нужно пересобрать: docker compose up -d --build.
ARG DSH_UID=1000
ARG DSH_GID=1000
RUN chown -R ${DSH_UID}:${DSH_GID} /root \
    && chown ${DSH_UID}:${DSH_GID} /app
USER ${DSH_UID}:${DSH_GID}
