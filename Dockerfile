FROM smanx/deepseek-harness:devtools-min-latest

# Тулчейн окружения — запекается в образ один раз при сборке, а не
# переустанавливается заново при каждом пересоздании контейнера.
#
#   gh                 — для dsh-github-cli / любых GitHub-плагинов сайдбара
#                        (ставится ниже из официальных релизов, см. ARG GH_VERSION)
#   python3, make, g++ — нативная сборка node-модулей плагинов (например node-pty
#                        для терминала в dsh-better-sidebar)
#   nano, mc, htop     — консольные утилиты для ручной работы внутри контейнера
#   openssh-client     — ssh/ssh-agent для git по SSH и для gh/glab, если нужен ключ вместо токена
#                        (сами ключи/агент в контейнер не пробрасываются — см. README)
RUN apt-get update && apt-get install -y --no-install-recommends \
    python3 make g++ nano mc htop openssh-client \
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
