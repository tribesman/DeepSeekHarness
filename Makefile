# DeepSeekHarness — задачи управления окружением.
#
# Все параметры (пути, порты, секреты) берутся из .env, шаблон — .env.example:
#   cp .env.example .env
#   nano .env
#   make sync
#
# Если .env нет, переменные берутся из окружения/значений по умолчанию,
# а `make sync` попросит задать VDS_HOST.

ifneq (,$(wildcard .env))
include .env
export
endif

.DEFAULT_GOAL := help

# --- Значения по умолчанию (переопределяются .env) ---------------------------
VDS_HOST ?=
VDS_USER ?= root
VDS_PORT ?= 22
VDS_DIR  ?= /srv/deepseek-harness
SSH_KEY  ?=
WORKSPACE_DIR ?= ./workspace

# Флаги rsync. На старом macOS-rsync (2.6.9) нет --info=progress2 —
# тогда поставьте в .env: RSYNC_FLAGS = -aH -v
RSYNC_FLAGS ?= -aH --info=progress2

# Что не тащим в копии проекта: состояние и секреты едут отдельно,
# рабочая папка агента — отдельной командой.
PROJECT_EXCLUDES = \
	--exclude=.git \
	--exclude=.dsh \
	--exclude=.env \
	--exclude=data \
	--exclude=workspace \
	--exclude=.idea \
	--exclude=.vscode \
	--exclude=.DS_Store

# Кэши, которые VDS соберёт/скачает сам.
DATA_EXCLUDES = \
	--exclude=playwright-cache \
	--exclude=.pnpm-store

REMOTE = $(VDS_USER)@$(VDS_HOST)
SSH_CMD = ssh $(if $(SSH_KEY),-i $(SSH_KEY),) -p $(VDS_PORT)
RSYNC_CMD = rsync $(RSYNC_FLAGS) -e "$(SSH_CMD)" \
	$(if $(SYNC_EXCLUDES),$(addprefix --exclude=,$(SYNC_EXCLUDES)),)

.PHONY: help sync sync-workspace check-env

help:
	@echo "make sync           — перенести проект и состояние data/ на VDS"
	@echo "make sync-workspace — перенести WORKSPACE_DIR (код) на VDS"
	@echo ""
	@echo "Параметры — в .env (шаблон .env.example): VDS_HOST, VDS_USER, VDS_PORT,"
	@echo "VDS_DIR, SSH_KEY, SYNC_EXCLUDES, RSYNC_FLAGS."

## sync: проект и состояние (data/) на VDS по rsync
sync: check-env
	@echo "==> $(REMOTE):$(VDS_DIR)"
	$(SSH_CMD) $(REMOTE) 'mkdir -p $(VDS_DIR)'
	@echo "==> проект (без .git, .dsh, .env, data/, workspace/)"
	$(RSYNC_CMD) $(PROJECT_EXCLUDES) ./ $(REMOTE):$(VDS_DIR)/
	@if [ -d data ]; then \
		echo "==> состояние data/ (без playwright-cache и .pnpm-store)"; \
		$(RSYNC_CMD) $(DATA_EXCLUDES) data/ $(REMOTE):$(VDS_DIR)/data/; \
	else \
		echo "==> каталога data/ нет — состояние не переносится"; \
	fi
	@echo "==> готово. На VDS: cd $(VDS_DIR) && docker compose up -d --build"

## sync-workspace: код из WORKSPACE_DIR на VDS
sync-workspace: check-env
	@test -n "$(WORKSPACE_DIR)" || { echo "WORKSPACE_DIR не задан (см. .env)"; exit 1; }
	$(SSH_CMD) $(REMOTE) 'mkdir -p $(VDS_DIR)/workspace'
	$(RSYNC_CMD) $(WORKSPACE_DIR)/ $(REMOTE):$(VDS_DIR)/workspace/
	@echo "==> готово"

check-env:
	@test -n "$(VDS_HOST)" || { \
		echo "VDS_HOST не задан. Скопируйте .env.example в .env и заполните его:"; \
		echo '  cp .env.example .env'; \
		echo '  затем отредактируйте .env — все переменные там прокомментированы'; \
		exit 1; \
	}
