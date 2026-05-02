#!/usr/bin/env bash
# install.sh — distribution installer.
#
# Копирует skill/ в одну из локаций, где Claude Code ищет скиллы:
#   --global  → ~/.claude/skills/orchestrator-po-milleru/   (для всех проектов)
#   --local   → ./.claude/skills/orchestrator-po-milleru/   (для текущего проекта)
#
# Скиллу не нужно ничего билдить или собирать — это просто bash + промты.
# Установка = копирование папки skill/ в нужное место.

set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL_SRC="$REPO_DIR/skill"
SKILL_NAME="orchestrator-po-milleru"

usage() {
  cat <<EOF
Usage: $0 [--global | --local <project-dir>] [--force]

  --global              Установить в ~/.claude/skills/${SKILL_NAME}/ (для всех проектов).
  --local <dir>         Установить в <dir>/.claude/skills/${SKILL_NAME}/.
                        Если <dir> не указан — текущая директория.
  --force               Перезаписать существующую установку.
  --uninstall <scope>   scope = global | local <dir>. Удалить установленный скилл.

Примеры:
  $0 --global
  $0 --local                          # ставит в \$(pwd)/.claude/skills/
  $0 --local ~/projects/my-app
  $0 --uninstall global
  $0 --uninstall local ~/projects/my-app
EOF
}

require_skill_src() {
  if [[ ! -d "$SKILL_SRC" ]]; then
    echo "ERROR: не нашёл $SKILL_SRC. Запускай этот скрипт из корня клонированного репозитория." >&2
    exit 1
  fi
  if [[ ! -f "$SKILL_SRC/SKILL.md" ]]; then
    echo "ERROR: $SKILL_SRC/SKILL.md отсутствует — структура репозитория повреждена." >&2
    exit 1
  fi
}

resolve_target() {
  local scope="$1"
  local project_dir="${2:-}"
  case "$scope" in
    global) echo "$HOME/.claude/skills/$SKILL_NAME" ;;
    local)
      [[ -z "$project_dir" ]] && project_dir="$(pwd)"
      project_dir="$(cd "$project_dir" && pwd)"
      echo "$project_dir/.claude/skills/$SKILL_NAME"
      ;;
    *)
      echo "ERROR: неизвестный scope: $scope" >&2
      exit 1
      ;;
  esac
}

do_install() {
  local target="$1"
  local force="$2"

  require_skill_src

  if [[ -e "$target" ]]; then
    if [[ "$force" != "yes" ]]; then
      echo "ERROR: $target уже существует. Используй --force, чтобы перезаписать." >&2
      exit 1
    fi
    echo "удаляю существующий $target"
    rm -rf "$target"
  fi

  mkdir -p "$(dirname "$target")"
  cp -R "$SKILL_SRC/" "$target/"

  # Сохраняем executable bit на скриптах (cp -R обычно сохраняет, но для надёжности).
  find "$target/scripts" -type f -name '*.sh' -exec chmod +x {} +

  echo "✓ установлено: $target"
  echo
  echo "Дальше:"
  if [[ "$target" == "$HOME/.claude/skills/$SKILL_NAME" ]]; then
    echo "  — Claude Code увидит скилл в любом проекте."
  else
    echo "  — Claude Code увидит скилл только когда запущен из проекта, где лежит $(dirname "$(dirname "$target")")"
  fi
  echo "  — В корне проекта запусти: bash $target/scripts/init-project.sh"
  echo "  — Затем заполни plans/*.md, architecture/*.md и запусти первую фазу:"
  echo "      bash $target/scripts/run-phase.sh 1"
}

do_uninstall() {
  local target="$1"
  if [[ ! -e "$target" ]]; then
    echo "$target не существует — нечего удалять"
    return 0
  fi
  rm -rf "$target"
  echo "✓ удалено: $target"
}

# --- argument parsing -------------------------------------------------------

[[ $# -eq 0 ]] && { usage; exit 1; }

MODE=""
SCOPE=""
PROJECT_DIR=""
FORCE="no"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --global)        MODE="install"; SCOPE="global"; shift ;;
    --local)
      MODE="install"; SCOPE="local"
      shift
      if [[ $# -gt 0 && "$1" != --* ]]; then
        PROJECT_DIR="$1"
        shift
      fi
      ;;
    --uninstall)
      MODE="uninstall"
      shift
      [[ $# -eq 0 ]] && { echo "ERROR: --uninstall требует scope (global|local)" >&2; exit 1; }
      SCOPE="$1"
      shift
      if [[ "$SCOPE" == "local" && $# -gt 0 && "$1" != --* ]]; then
        PROJECT_DIR="$1"
        shift
      fi
      ;;
    --force)         FORCE="yes"; shift ;;
    -h|--help)       usage; exit 0 ;;
    *)               echo "ERROR: неизвестный аргумент: $1" >&2; usage; exit 1 ;;
  esac
done

[[ -z "$MODE" ]] && { usage; exit 1; }

TARGET="$(resolve_target "$SCOPE" "$PROJECT_DIR")"

case "$MODE" in
  install)   do_install "$TARGET" "$FORCE" ;;
  uninstall) do_uninstall "$TARGET" ;;
esac
