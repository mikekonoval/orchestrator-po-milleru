#!/usr/bin/env bash
# state.sh — управление state.json активного плана.
# Подключается через `source`. Ожидает, что переменные STATE_FILE и PHASE заданы.
# STATE_FILE — путь к state.json внутри plan-папки ($PLAN_DIR/state.json).

state_now() { date -u +%Y-%m-%dT%H:%M:%SZ; }

state_init() {
  local phase="$1"
  if [[ ! -f "$STATE_FILE" ]]; then
    jq -n --argjson p "$phase" --arg t "$(state_now)" '{
      phase: $p,
      step: "init",
      status: "running",
      started_at: $t,
      updated_at: $t
    }' > "$STATE_FILE"
    return
  fi

  # state.json есть. Если фаза другая или старая закончена — переинициализируем под новую.
  local cur_phase cur_status
  cur_phase=$(jq -r '.phase // empty' "$STATE_FILE")
  cur_status=$(jq -r '.status // empty' "$STATE_FILE")

  if [[ "$cur_phase" != "$phase" ]] || [[ "$cur_status" == "done" ]] || [[ "$cur_status" == "failed" ]] || [[ "$cur_status" == "escalated" ]]; then
    jq --argjson p "$phase" --arg t "$(state_now)" '
      .phase = $p |
      .step = "init" |
      .status = "running" |
      .started_at = $t |
      .updated_at = $t |
      del(.error)
    ' "$STATE_FILE" > "$STATE_FILE.tmp" && mv "$STATE_FILE.tmp" "$STATE_FILE"
  fi
}

state_set() {
  local key="$1"
  local value="$2"
  local tmp
  tmp="$(mktemp)"
  jq --arg k "$key" --arg v "$value" --arg t "$(state_now)" \
    '.[$k] = $v | .updated_at = $t' "$STATE_FILE" > "$tmp" && mv "$tmp" "$STATE_FILE"
}

state_get() {
  jq -r ".$1 // empty" "$STATE_FILE"
}

state_already_done() {
  local phase="$1"
  [[ ! -f "$STATE_FILE" ]] && return 1
  local cur_phase cur_status
  cur_phase=$(jq -r '.phase // empty' "$STATE_FILE")
  cur_status=$(jq -r '.status // empty' "$STATE_FILE")
  [[ "$cur_phase" == "$phase" && "$cur_status" == "done" ]]
}
