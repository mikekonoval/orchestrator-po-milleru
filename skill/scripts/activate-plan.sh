#!/usr/bin/env bash
# activate-plan.sh <plan-name>
#
# Переключает активный план — записывает имя в plans/.active.
# План должен существовать (plans/<name>/ должна быть). Без аргумента — печатает текущий активный план.

set -euo pipefail

SKILL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT_DIR="$(pwd)"
export PROJECT_DIR

# shellcheck source=lib/plan.sh
source "$SKILL_DIR/scripts/lib/plan.sh"

usage() {
  cat <<EOF
Usage: $0 [<plan-name>]

  без аргумента        печатает имя текущего активного плана и список доступных
  <plan-name>          активирует существующий план

  Создать новый план: $SKILL_DIR/scripts/init-project.sh <plan-name>
EOF
}

if [[ "${1:-}" == "-h" ]] || [[ "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

# Без аргумента — печатаем текущий активный план и список всех.
if [[ $# -eq 0 ]]; then
  if cur="$(active_plan_name 2>/dev/null)"; then
    echo "Активный план: $cur"
  else
    echo "Активный план не задан (нет plans/.active или он пустой)"
  fi
  echo
  echo "Доступные планы в plans/:"
  found=0
  while IFS= read -r p; do
    [[ -z "$p" ]] && continue
    echo "  - $p"
    found=1
  done < <(list_plans)
  if [[ "$found" -eq 0 ]]; then
    echo "  (нет ни одного — создай через init-project.sh <name>)"
  fi
  exit 0
fi

PLAN_NAME="$1"

if ! plan_name_valid "$PLAN_NAME"; then
  echo "ERROR: неверное имя плана: '$PLAN_NAME'" >&2
  echo "       Разрешено: [a-z][a-z0-9_-]*, длина 1..64 символа." >&2
  exit 1
fi

if ! plan_exists "$PLAN_NAME"; then
  echo "ERROR: план '$PLAN_NAME' не найден в $PROJECT_DIR/plans/" >&2
  echo "       Создай его: bash $SKILL_DIR/scripts/init-project.sh $PLAN_NAME" >&2
  echo
  echo "Доступные планы:" >&2
  while IFS= read -r p; do
    [[ -z "$p" ]] && continue
    echo "  - $p" >&2
  done < <(list_plans)
  exit 1
fi

set_active_plan "$PLAN_NAME"
echo "Активный план: $PLAN_NAME"
