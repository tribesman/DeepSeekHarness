FROM smanx/deepseek-harness:devtools-min-latest

# Тулчейн окружения — запекается в образ один раз при сборке, а не
# переустанавливается заново при каждом пересоздании контейнера.
#
#   gh                 — для dsh-github-cli / любых GitHub-плагинов сайдбара
#   python3, make, g++ — нативная сборка node-модулей плагинов (например node-pty
#                        для терминала в dsh-better-sidebar)
#   nano, mc, htop     — консольные утилиты для ручной работы внутри контейнера
RUN apt-get update && apt-get install -y --no-install-recommends \
    gh python3 make g++ nano mc htop \
    && rm -rf /var/lib/apt/lists/*

# glab — аналог gh, но для GitLab. В репозиториях Debian его нет, ставим
# из официального .deb-релиза GitLab (архитектура подбирается автоматически).
ARG GLAB_VERSION=1.117.0
RUN ARCH="$(dpkg --print-architecture)" \
    && curl -fsSL -o /tmp/glab.deb "https://gitlab.com/api/v4/projects/gitlab-org%2Fcli/packages/generic/glab/${GLAB_VERSION}/glab_${GLAB_VERSION}_linux_${ARCH}.deb" \
    && apt-get update && apt-get install -y /tmp/glab.deb \
    && rm -f /tmp/glab.deb && rm -rf /var/lib/apt/lists/*

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
