#!/usr/bin/env bash
# Smoke-тест прогресс-бара. Покрывает:
#   - маппинг имён шагов → номер 1..16
#   - подсчёт закрытых/всех фаз в plan.md
#   - формат бара (пустой/полный/половина)
#   - render двух строк в stderr
#   - финальная строка фазы (done/escalate/smoke_fail/commit_failed)
#   - heartbeat выключается через ORCHESTRATOR_NO_HEARTBEAT=1
#   - progress_stop_heartbeat идемпотентна

set -euo pipefail

SKILL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
# shellcheck source=../../scripts/lib/progress.sh
source "$SKILL_DIR/scripts/lib/progress.sh"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

PASS=0
FAIL=0

assert_eq() {
  local expected="$1"
  local actual="$2"
  local label="$3"
  if [[ "$expected" == "$actual" ]]; then
    echo "  ✓ $label"
    PASS=$((PASS + 1))
  else
    echo "  ✗ $label"
    echo "      expected: $expected"
    echo "      actual:   $actual"
    FAIL=$((FAIL + 1))
  fi
}

assert_contains() {
  local needle="$1"
  local haystack="$2"
  local label="$3"
  if [[ "$haystack" == *"$needle"* ]]; then
    echo "  ✓ $label"
    PASS=$((PASS + 1))
  else
    echo "  ✗ $label — нет '$needle' в выводе"
    echo "      output: $haystack"
    FAIL=$((FAIL + 1))
  fi
}

# --- 1. progress_step_num ----------------------------------------------------
echo "progress_step_num:"
assert_eq "1"  "$(progress_step_num init)"            "init → 1"
assert_eq "2"  "$(progress_step_num phase_generate)"  "phase_generate → 2"
assert_eq "3"  "$(progress_step_num phase_run)"       "phase_run → 3"
assert_eq "4"  "$(progress_step_num errors_find)"     "errors_find → 4"
assert_eq "6"  "$(progress_step_num errors_apply)"    "errors_apply → 6"
assert_eq "9"  "$(progress_step_num missing_apply)"   "missing_apply → 9"
assert_eq "12" "$(progress_step_num review_apply)"    "review_apply → 12"
assert_eq "15" "$(progress_step_num security_apply)"  "security_apply → 15"
assert_eq "16" "$(progress_step_num final_check)"     "final_check → 16"
assert_eq "0"  "$(progress_step_num bogus_step)"      "неизвестное имя → 0"

# --- 2. progress_plan_counts -------------------------------------------------
echo
echo "progress_plan_counts:"

# Фикстура: 3 закрытых, 5 открытых, 1 фаза за пределами плана (комментарий).
PLAN1="$TMP/plan1.md"
cat > "$PLAN1" <<'EOF'
# Тестовый план

- [x] Фаза 1: подготовка
- [x] Фаза 2: каркас
- [x] Фаза 3: первый прогон
- [ ] Фаза 4: интеграция
- [ ] Фаза 5: правки
- [ ] Фаза 6: smoke
- [ ] Фаза 7: review
- [ ] Фаза 8: финал

Заметка: упоминание "Фаза 9" в тексте не должно учитываться.
EOF

assert_eq "3 8" "$(progress_plan_counts "$PLAN1")" "3 закрытых из 8"

# Пустой план
PLAN_EMPTY="$TMP/plan_empty.md"
echo "# План пуст" > "$PLAN_EMPTY"
assert_eq "0 0" "$(progress_plan_counts "$PLAN_EMPTY")" "пустой план → 0 0"

# Несуществующий файл — graceful
assert_eq "0 0" "$(progress_plan_counts "$TMP/nope.md")" "нет файла → 0 0"

# --- 3. progress_bar ---------------------------------------------------------
echo
echo "progress_bar:"

bar_empty="$(progress_bar 0 10 10)"
assert_contains "0%" "$bar_empty" "0/10 содержит 0%"
assert_contains "░░░░░░░░░░" "$bar_empty" "0/10 — все ░"

bar_full="$(progress_bar 10 10 10)"
assert_contains "100%" "$bar_full" "10/10 содержит 100%"
assert_contains "██████████" "$bar_full" "10/10 — все █"

bar_half="$(progress_bar 5 10 10)"
assert_contains "50%" "$bar_half" "5/10 содержит 50%"
assert_contains "█████░░░░░" "$bar_half" "5/10 — половина █, половина ░"

# Деление на ноль не должно падать
bar_zero_denom="$(progress_bar 0 0 10)"
assert_contains "0%" "$bar_zero_denom" "0/0 не падает, даёт 0%"

# --- 4. progress_render: две строки в stderr --------------------------------
echo
echo "progress_render:"

export ORCHESTRATOR_NO_HEARTBEAT=1
out_stderr="$(progress_render "$PLAN1" "errors_apply" 2>&1 >/dev/null)"
line_count="$(printf '%s\n' "$out_stderr" | grep -c '^\[' || true)"
assert_eq "2" "$line_count" "render печатает ровно 2 строки бара"
assert_contains "[План" "$out_stderr" "первая строка — План"
assert_contains "[Фаза" "$out_stderr" "вторая строка — Фаза"
assert_contains "errors_apply" "$out_stderr" "имя шага в строке Фазы"
assert_contains "3/8" "$out_stderr" "счётчик фаз 3/8"
assert_contains "6/16" "$out_stderr" "счётчик шагов 6/16"

# Неизвестный шаг — render не падает, в строке Фазы помечается (?)
out_unknown="$(progress_render "$PLAN1" "weird" 2>&1 >/dev/null)"
assert_contains "weird (?)" "$out_unknown" "неизвестный шаг помечен (?)"

# --- 5. progress_phase_done -------------------------------------------------
echo
echo "progress_phase_done:"

out_done="$(progress_phase_done "$PLAN1" 3 done 2>&1 >/dev/null)"
assert_contains "✓ Фаза 3 закрыта" "$out_done" "done → '✓ Фаза N закрыта'"

out_esc="$(progress_phase_done "$PLAN1" 3 escalate 2>&1 >/dev/null)"
assert_contains "ESCALATE" "$out_esc" "escalate → 'ESCALATE'"

out_smoke="$(progress_phase_done "$PLAN1" 3 smoke_fail 2>&1 >/dev/null)"
assert_contains "smoke fail" "$out_smoke" "smoke_fail → 'smoke fail'"

out_commit="$(progress_phase_done "$PLAN1" 3 commit_failed 2>&1 >/dev/null)"
assert_contains "autocommit упал" "$out_commit" "commit_failed → 'autocommit упал'"

# --- 6. heartbeat: ORCHESTRATOR_NO_HEARTBEAT=1 не запускает фон ------------
echo
echo "heartbeat:"

PROGRESS_HEARTBEAT_PID=""
export ORCHESTRATOR_NO_HEARTBEAT=1
progress_start_heartbeat "errors_apply"
assert_eq "" "$PROGRESS_HEARTBEAT_PID" "под NO_HEARTBEAT=1 фон не запускается"

# stop без работающего heartbeat — не падает
progress_stop_heartbeat
assert_eq "" "$PROGRESS_HEARTBEAT_PID" "stop_heartbeat идемпотентна (без активного)"

# stop при наличии PID, но процесс уже мёртв — не падает (kill пробрасывает в /dev/null)
PROGRESS_HEARTBEAT_PID="999999"  # заведомо несуществующий PID
progress_stop_heartbeat
assert_eq "" "$PROGRESS_HEARTBEAT_PID" "stop при дохлом PID — не падает"

# --- summary ----------------------------------------------------------------
echo
echo "Итого: $PASS прошло, $FAIL упало"
[[ "$FAIL" -eq 0 ]] || exit 1
