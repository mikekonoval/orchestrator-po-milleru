#!/usr/bin/env bash
# init-project.sh <plan-name> — раскладывает структуру оркестратора в текущей директории проекта.
#
# Создаёт:
#   plans/.active                      — имя активного плана (одна строка)
#   plans/<plan-name>/plan.md          — сам план фаз
#   plans/<plan-name>/promts/          — каталог промтов фаз
#   plans/<plan-name>/state.json       — стартовое состояние
#   architecture/                      — каталог под архитектурную доку (если ещё нет)
#
# Идемпотентно: ничего не перезаписывает, только создаёт отсутствующее.
# Имя плана: [a-z][a-z0-9_-]* до 64 символов.

set -euo pipefail

SKILL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT_DIR="$(pwd)"
export PROJECT_DIR

# shellcheck source=lib/plan.sh
source "$SKILL_DIR/scripts/lib/plan.sh"

usage() {
  cat <<EOF
Usage: $0 <plan-name>

  <plan-name>   имя нового или существующего плана.
                Допустимые символы: a-z, 0-9, '_', '-'. Начинается с буквы или цифры.
                Пример: 'auth-rewrite', 'mvp_v2', '2026-q1-billing'.

Если план с таким именем уже есть — каталог не пересоздаётся, только активируется.
EOF
}

if [[ $# -eq 0 ]] || [[ "${1:-}" == "-h" ]] || [[ "${1:-}" == "--help" ]]; then
  usage
  [[ $# -eq 0 ]] && exit 1 || exit 0
fi

PLAN_NAME="$1"

if ! plan_name_valid "$PLAN_NAME"; then
  echo "ERROR: неверное имя плана: '$PLAN_NAME'" >&2
  echo "       Разрешено: [a-z][a-z0-9_-]*, длина 1..64 символа." >&2
  exit 1
fi

create_dir() {
  local d="$1"
  if [[ -d "$d" ]]; then
    echo "  уже есть: $d/"
  else
    mkdir -p "$d"
    echo "  создал:   $d/"
  fi
}

copy_template_if_missing() {
  local src="$1"
  local dst="$2"
  if [[ -f "$dst" ]]; then
    echo "  уже есть: $dst"
  else
    cp "$src" "$dst"
    echo "  создал:   $dst"
  fi
}

PLAN_DIR="$PROJECT_DIR/plans/$PLAN_NAME"

echo "Установка orchestrator-po-milleru в $PROJECT_DIR"
echo "План: $PLAN_NAME"
echo

create_dir "$PROJECT_DIR/plans"
create_dir "$PLAN_DIR"
create_dir "$PLAN_DIR/promts"
create_dir "$PROJECT_DIR/architecture"

# state.json — стартовое состояние внутри папки плана.
copy_template_if_missing "$SKILL_DIR/templates/state.json" "$PLAN_DIR/state.json"

# Сам plan.md — кладём только если его ещё нет.
copy_template_if_missing "$SKILL_DIR/templates/plan.md" "$PLAN_DIR/plan.md"

# Активируем план.
set_active_plan "$PLAN_NAME"
echo "  активный план: $PLAN_NAME (записан в plans/.active)"

echo
echo "Готово. Дальше:"
echo "  1. Опиши архитектуру в architecture/*.md (опционально, но без неё мета-промт фазы будет слабым)."
echo "  2. Заполни план фаз в plans/$PLAN_NAME/plan.md — список строк '- [ ] Фаза N: краткое описание'."
echo "  3. Запусти первую фазу:"
echo "       bash $SKILL_DIR/scripts/run-phase.sh 1"
echo "     или весь план:"
echo "       bash $SKILL_DIR/scripts/run-all.sh"
echo
echo "Переключение между планами:"
echo "       bash $SKILL_DIR/scripts/activate-plan.sh <other-plan-name>"
