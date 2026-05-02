#!/usr/bin/env bash
# run-phase.sh <phase-number> [--dry-run] [--no-commit] [--allow-dirty]
#
# Гонит одну фазу через 5 блоков (ERRORS → MISSING → REVIEW → SECURITY → FINAL CHECK).
# Запускается из корня проекта. Отчёты пишутся в текущую директорию.
# По итогам успешной фазы делает один git-коммит (если в репо).
#
# Флаги:
#   --dry-run       не вызывает claude -p, симулирует прогон.
#   --no-commit     не делать git commit на закрытии фазы.
#   --allow-dirty   разрешить запуск с грязным рабочим деревом (по умолчанию — abort).

set -euo pipefail

PHASE=""
DRY_RUN=""
NO_COMMIT="no"
ALLOW_DIRTY="no"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run)     DRY_RUN="--dry-run"; shift ;;
    --no-commit)   NO_COMMIT="yes"; shift ;;
    --allow-dirty) ALLOW_DIRTY="yes"; shift ;;
    -h|--help)
      echo "Usage: $0 <phase-number> [--dry-run] [--no-commit] [--allow-dirty]"
      exit 0
      ;;
    -*)
      echo "ERROR: неизвестный флаг: $1" >&2
      exit 1
      ;;
    *)
      if [[ -z "$PHASE" ]]; then
        PHASE="$1"
      else
        echo "ERROR: позиционный аргумент уже задан: $PHASE (получили лишний $1)" >&2
        exit 1
      fi
      shift
      ;;
  esac
done

if [[ -z "$PHASE" ]]; then
  echo "Usage: $0 <phase-number> [--dry-run] [--no-commit] [--allow-dirty]" >&2
  exit 1
fi

if ! [[ "$PHASE" =~ ^[0-9]+$ ]]; then
  echo "ERROR: phase must be a positive integer, got: $PHASE" >&2
  exit 1
fi

SKILL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT_DIR="$(pwd)"
STATE_FILE="$PROJECT_DIR/state.json"
PROMPTS_DIR="$SKILL_DIR/prompts"

# shellcheck source=lib/state.sh
source "$SKILL_DIR/scripts/lib/state.sh"
# shellcheck source=lib/parse-report.sh
source "$SKILL_DIR/scripts/lib/parse-report.sh"
# shellcheck source=lib/git.sh
source "$SKILL_DIR/scripts/lib/git.sh"
# shellcheck source=lib/summary.sh
source "$SKILL_DIR/scripts/lib/summary.sh"

# --- helpers ----------------------------------------------------------------

log() {
  printf '[phase %s] %s\n' "$PHASE" "$*" >&2
}

die() {
  log "FATAL: $*"
  state_set "status" "failed" 2>/dev/null || true
  state_set "error" "$*" 2>/dev/null || true
  exit 1
}

# Подставляет {N} → номер фазы, {PROJECT_DIR} → корень проекта.
render_prompt() {
  local prompt_file="$1"
  local path="$PROMPTS_DIR/$prompt_file"
  [[ -f "$path" ]] || die "prompt file not found: $path"
  sed -e "s|{N}|$PHASE|g" -e "s|{PROJECT_DIR}|$PROJECT_DIR|g" "$path"
}

run_agent() {
  local prompt="$1"
  local label="$2"

  if [[ "$DRY_RUN" == "--dry-run" ]]; then
    log "[DRY RUN $label] промт длиной $(printf '%s' "$prompt" | wc -c) байт"
    return 0
  fi

  log "[агент: $label] запуск..."
  claude --print --permission-mode acceptEdits "$prompt" \
    || die "claude -p упал на шаге $label"
}

require_file() {
  local f="$1"
  local hint="$2"
  if [[ "$DRY_RUN" == "--dry-run" ]]; then
    return 0  # в dry-run суб-агенты ничего не пишут, проверку пропускаем
  fi
  [[ -f "$f" ]] || die "ожидаю файл $f после шага «$hint», но его нет — суб-агент не записал отчёт"
}

# --- блок: один из errors|missing|review|security ---------------------------

run_block() {
  local block="$1"
  local report_file="$PROJECT_DIR/${block}_phase${PHASE}.md"

  state_set "step" "${block}_find"
  log "блок $block: поиск"
  run_agent "$(render_prompt "${block}_find.md")" "$block:find"
  require_file "$report_file" "${block}_find"

  if found_empty "$report_file"; then
    log "блок $block: ## FOUND пусто, пропускаю"
    return 0
  fi

  state_set "step" "${block}_prove"
  log "блок $block: доказательство"
  run_agent "$(render_prompt "${block}_prove.md")" "$block:prove"

  if ! has_real "$report_file"; then
    log "блок $block: в ## PROVEN нет реальных, пропускаю применение"
    return 0
  fi

  state_set "step" "${block}_apply"
  log "блок $block: применение"
  run_agent "$(render_prompt "${block}_apply.md")" "$block:apply"

  if has_escalate "$report_file"; then
    log "блок $block: ESCALATE в ## APPLIED, останавливаю фазу"
    state_set "status" "escalated"
    state_set "error" "ESCALATE in ${block}_phase${PHASE}.md"
    exit 2
  fi
}

# --- main -------------------------------------------------------------------

cd "$PROJECT_DIR"

[[ -d "$PROJECT_DIR/plans" ]] || die "не вижу plans/ в $PROJECT_DIR — сначала init-project.sh"
mkdir -p "$PROJECT_DIR/plans/promts"

# Стартовая проверка: рабочее дерево должно быть чистым, чтобы фазовый коммит
# не утащил с собой случайные несвязанные правки. В dry-run проверку пропускаем.
if [[ "$DRY_RUN" != "--dry-run" ]] && [[ "$ALLOW_DIRTY" != "yes" ]] && git_available; then
  if ! git_tree_clean; then
    log "ERROR: рабочее дерево не чистое."
    log "       Закоммить текущие изменения, сделай 'git stash', либо запусти с --allow-dirty."
    log "       Подробнее: git status"
    exit 1
  fi
fi

if state_already_done "$PHASE"; then
  log "фаза $PHASE уже done в state.json — нечего делать. Чтобы перезапустить: rm state.json"
  exit 0
fi

state_init "$PHASE"

# 0. Промт фазы. Если нет — генерируем через мета-промт.
PHASE_PROMPT_FILE="$PROJECT_DIR/plans/promts/phase${PHASE}.md"
if [[ ! -f "$PHASE_PROMPT_FILE" ]]; then
  log "$PHASE_PROMPT_FILE отсутствует, генерирую"
  state_set "step" "phase_generate"
  run_agent "$(render_prompt "phase_generate.md")" "phase:generate"
  if [[ "$DRY_RUN" != "--dry-run" ]]; then
    [[ -f "$PHASE_PROMPT_FILE" ]] || die "после phase_generate ожидаю $PHASE_PROMPT_FILE, его нет"
  fi
fi

# 1. Сама фаза.
state_set "step" "phase_run"
log "запуск фазы по $PHASE_PROMPT_FILE"
if [[ -f "$PHASE_PROMPT_FILE" ]]; then
  PHASE_PROMPT_BODY="$(cat "$PHASE_PROMPT_FILE")"
else
  PHASE_PROMPT_BODY="<dry-run: phase prompt would be loaded here>"
fi
run_agent "$PHASE_PROMPT_BODY" "phase:run"

# 2. Блоки.
run_block errors
run_block missing
run_block review
run_block security

# 3. Final check.
state_set "step" "final_check"
log "финальная проверка (regression + smoke)"
run_agent "$(render_prompt "final_check.md")" "final:check"

FINAL_FILE="$PROJECT_DIR/final_check_phase${PHASE}.md"
require_file "$FINAL_FILE" "final_check"

# В dry-run финальной проверки не было — статус «прошло бы», выход 0.
if [[ "$DRY_RUN" == "--dry-run" ]]; then
  state_set "status" "dry-run-completed"
  log "✓ dry-run прошёл по всему пайплайну без падений"
  exit 0
fi

# 4. Закрытие фазы.
PLAN_FILE="$(ls "$PROJECT_DIR"/plans/*.md 2>/dev/null | grep -v '^.*/promts/' | head -n 1 || true)"

if smoke_passed "$FINAL_FILE" && regression_clean "$FINAL_FILE"; then
  if [[ -n "$PLAN_FILE" ]] && grep -qE "^- \[ \] Фаза $PHASE" "$PLAN_FILE"; then
    if sed --version >/dev/null 2>&1; then
      sed -i "s/^- \[ \] Фаза $PHASE/- [x] Фаза $PHASE/" "$PLAN_FILE"
    else
      sed -i '' "s/^- \[ \] Фаза $PHASE/- [x] Фаза $PHASE/" "$PLAN_FILE"
    fi
    log "проставил [x] на фазу $PHASE в $PLAN_FILE"

    # Резюме фазы — детерминированно из отчётов и плана. Вставляется до autocommit,
    # поэтому попадает в тот же фазовый коммит, что и [x].
    SUMMARY_BLOCK="$(phase_summary_block "$PHASE" "$PLAN_FILE" "$PROJECT_DIR")"
    insert_summary_into_plan "$PLAN_FILE" "$SUMMARY_BLOCK"
    log "вставил резюме фазы $PHASE в $PLAN_FILE"
  else
    log "WARNING: не нашёл строку '- [ ] Фаза $PHASE' в плане, статус и резюме не обновил"
  fi
  state_set "status" "done"
  log "✓ фаза $PHASE закрыта"

  # 5. Автокоммит. На успехе и только если в git-репо и не --no-commit.
  if [[ "$NO_COMMIT" == "yes" ]]; then
    log "autocommit пропущен (--no-commit)"
  elif ! git_available; then
    log "autocommit пропущен (не git-репо)"
  else
    SHA="$(git_commit_phase "$PHASE" "$PLAN_FILE")"
    log "autocommit: $SHA"
  fi

  exit 0
else
  # На smoke fail / regression dirty — не коммитим. Пользователь должен разобраться.
  state_set "status" "failed"
  state_set "error" "smoke fail or regression dirty"
  log "✗ фаза $PHASE не закрыта: ## SMOKE != pass или ## REGRESSION != чисто"
  log "  смотри $FINAL_FILE"
  log "  autocommit пропущен (фаза не закрылась)"
  exit 3
fi
