#!/usr/bin/env bash
# progress.sh — прогресс-бар для run-phase.sh.
# Печатает в stderr две строки (План + Фаза) на каждом переходе шага.
# Между шагами раз в HEARTBEAT_INTERVAL_SEC секунд обновляет одну строку
# с idle-временем — через \r, новые строки не плодятся.
#
# Подключается через `source`. Не требует обязательных переменных.
# ORCHESTRATOR_NO_HEARTBEAT=1 — выключает heartbeat (для dry-run и тестов).

PROGRESS_BAR_WIDTH="${PROGRESS_BAR_WIDTH:-20}"
HEARTBEAT_INTERVAL_SEC="${HEARTBEAT_INTERVAL_SEC:-30}"
PROGRESS_STEPS_TOTAL=16

PROGRESS_HEARTBEAT_PID=""
# "1" если в stderr последним напечатан heartbeat без \n — следующий вывод
# должен сначала затереть эту строку, иначе он размажется поверх тика.
PROGRESS_HEARTBEAT_ACTIVE=""

# Маппинг имени шага → номер 1..16. Знаменатель фиксированный, потому что
# часть шагов в фазе пропускается (find→empty, prove без РЕАЛЬНАЯ). На пропусках
# бар «прыгает» вперёд — это намеренно, чтобы не считать развилки в bash.
progress_step_num() {
  case "$1" in
    init)            echo 1  ;;
    phase_generate)  echo 2  ;;
    phase_run)       echo 3  ;;
    errors_find)     echo 4  ;;
    errors_prove)    echo 5  ;;
    errors_apply)    echo 6  ;;
    missing_find)    echo 7  ;;
    missing_prove)   echo 8  ;;
    missing_apply)   echo 9  ;;
    review_find)     echo 10 ;;
    review_prove)    echo 11 ;;
    review_apply)    echo 12 ;;
    security_find)   echo 13 ;;
    security_prove)  echo 14 ;;
    security_apply)  echo 15 ;;
    final_check)     echo 16 ;;
    *)               echo 0  ;;
  esac
}

# Считает фазы плана: "<closed> <total>".
# Фаза в плане — строка вида "- [ ] Фаза N: ..." или "- [x] Фаза N: ...".
progress_plan_counts() {
  local plan_file="$1"
  local closed=0 total=0
  if [[ -f "$plan_file" ]]; then
    closed=$(grep -cE "^- \[x\] Фаза " "$plan_file" 2>/dev/null || true)
    total=$(grep -cE "^- \[[ x]\] Фаза " "$plan_file" 2>/dev/null || true)
  fi
  echo "$closed $total"
}

# Рендерит ascii-бар фиксированной ширины + проценты.
# Аргументы: numerator denominator [width]
progress_bar() {
  local num="$1"
  local denom="$2"
  local width="${3:-$PROGRESS_BAR_WIDTH}"
  local pct=0
  if [[ "$denom" -gt 0 ]]; then
    pct=$(( num * 100 / denom ))
  fi
  if [[ "$pct" -gt 100 ]]; then pct=100; fi
  if [[ "$pct" -lt 0   ]]; then pct=0;   fi
  local filled=$(( pct * width / 100 ))
  local empty=$(( width - filled ))
  local bar=""
  local i
  for (( i=0; i<filled; i++ )); do bar="${bar}█"; done
  for (( i=0; i<empty;  i++ )); do bar="${bar}░"; done
  printf "%s %3d%%" "$bar" "$pct"
}

# Стирает активную heartbeat-строку. Идемпотентна. Не убивает фоновый процесс.
_progress_clear_heartbeat_line() {
  if [[ "$PROGRESS_HEARTBEAT_ACTIVE" == "1" ]]; then
    # \r → начало текущей строки, \033[K → стереть до конца.
    printf "\r\033[K" >&2
    PROGRESS_HEARTBEAT_ACTIVE=""
  fi
}

# Печатает две строки бара (План + Фаза) в stderr.
# Аргументы: plan_file step_name
progress_render() {
  local plan_file="$1"
  local step_name="$2"

  _progress_clear_heartbeat_line

  local counts plan_closed plan_total
  counts="$(progress_plan_counts "$plan_file")"
  plan_closed="${counts% *}"
  plan_total="${counts#* }"

  local step_num step_label
  step_num="$(progress_step_num "$step_name")"
  step_label="$step_name"
  [[ "$step_num" == "0" ]] && step_label="$step_name (?)"

  local plan_bar phase_bar
  plan_bar="$(progress_bar  "$plan_closed" "$plan_total")"
  phase_bar="$(progress_bar "$step_num"    "$PROGRESS_STEPS_TOTAL")"

  printf "[План  %2d/%-2d %s]\n"     "$plan_closed" "$plan_total"          "$plan_bar"  >&2
  printf "[Фаза  %2d/%-2d %s] %s\n"  "$step_num"    "$PROGRESS_STEPS_TOTAL" "$phase_bar" "$step_label" >&2
}

# Печатает финальную строку после закрытия/провала фазы.
# Аргументы: plan_file phase result
# result: done | escalate | smoke_fail | commit_failed | <свободная строка>
progress_phase_done() {
  local plan_file="$1"
  local phase="$2"
  local result="$3"

  _progress_clear_heartbeat_line

  local counts plan_closed plan_total
  counts="$(progress_plan_counts "$plan_file")"
  plan_closed="${counts% *}"
  plan_total="${counts#* }"

  local plan_bar
  plan_bar="$(progress_bar "$plan_closed" "$plan_total")"

  local marker
  case "$result" in
    done)          marker="✓ Фаза $phase закрыта" ;;
    escalate)      marker="✗ Фаза $phase: ESCALATE" ;;
    smoke_fail)    marker="✗ Фаза $phase: smoke fail / regression" ;;
    commit_failed) marker="⚠ Фаза $phase: autocommit упал" ;;
    *)             marker="Фаза $phase: $result" ;;
  esac

  printf "[План  %2d/%-2d %s] %s\n" "$plan_closed" "$plan_total" "$plan_bar" "$marker" >&2
}

# Запускает фоновый процесс, который раз в HEARTBEAT_INTERVAL_SEC секунд
# перерисовывает на месте строку с idle-временем шага.
# Аргумент: step_name
progress_start_heartbeat() {
  local step_name="$1"

  [[ "${ORCHESTRATOR_NO_HEARTBEAT:-}" == "1" ]] && return 0

  local started_at
  started_at="$(date +%s)"

  (
    while sleep "$HEARTBEAT_INTERVAL_SEC"; do
      local now elapsed mm ss
      now="$(date +%s)"
      elapsed=$(( now - started_at ))
      mm=$(( elapsed / 60 ))
      ss=$(( elapsed % 60 ))
      printf "\r[idle %d:%02d] %s\033[K" "$mm" "$ss" "$step_name" >&2
    done
  ) &
  PROGRESS_HEARTBEAT_PID=$!
  PROGRESS_HEARTBEAT_ACTIVE="1"
}

# Останавливает heartbeat. Идемпотентна. Безопасна для trap EXIT.
progress_stop_heartbeat() {
  if [[ -n "$PROGRESS_HEARTBEAT_PID" ]]; then
    kill "$PROGRESS_HEARTBEAT_PID" 2>/dev/null || true
    wait "$PROGRESS_HEARTBEAT_PID" 2>/dev/null || true
    PROGRESS_HEARTBEAT_PID=""
  fi
  _progress_clear_heartbeat_line
}
