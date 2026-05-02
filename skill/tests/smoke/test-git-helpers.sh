#!/usr/bin/env bash
# Smoke-тест git-хелперов из lib/git.sh: phase_description, git_tree_clean,
# git_available, git_commit_phase.

set -euo pipefail

SKILL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

PROJECT_DIR="$TMP"
export PROJECT_DIR

# shellcheck source=../../scripts/lib/git.sh
source "$SKILL_DIR/scripts/lib/git.sh"

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
    echo "      ждали:  $expected"
    echo "      получили: $actual"
    FAIL=$((FAIL + 1))
  fi
}

assert_exit() {
  local expected="$1"
  local label="$2"
  shift 2
  local actual=0
  "$@" >/dev/null 2>&1 || actual=$?
  if [[ "$actual" == "$expected" ]]; then
    echo "  ✓ $label"
    PASS=$((PASS + 1))
  else
    echo "  ✗ $label — ждали exit=$expected, получили exit=$actual"
    FAIL=$((FAIL + 1))
  fi
}

# --- phase_description ------------------------------------------------------

PLAN="$TMP/plan.md"
cat > "$PLAN" <<'EOF'
# План

## Фазы

- [ ] Фаза 1: построить базовую структуру
- [x] Фаза 2: добавить логирование
- [ ] Фаза 10: масштабирование
EOF

echo "phase_description:"
assert_eq "построить базовую структуру" "$(phase_description "$PLAN" 1)" "извлекает описание для фазы 1 (открытая)"
assert_eq "добавить логирование"        "$(phase_description "$PLAN" 2)" "извлекает описание для фазы 2 (закрытая)"
assert_eq "масштабирование"             "$(phase_description "$PLAN" 10)" "извлекает описание для двузначной фазы 10"
assert_eq ""                            "$(phase_description "$PLAN" 99)" "пусто для несуществующей фазы"
assert_eq ""                            "$(phase_description "$TMP/no-such-file.md" 1)" "пусто если файла нет"

# --- git_available + git_tree_clean (вне git-репо) ---------------------------

echo
echo "git_available / git_tree_clean (НЕ git-репо):"
assert_exit 1 "git_available возвращает false вне git-репо"  git_available
assert_exit 0 "git_tree_clean возвращает true вне git-репо (не блокирует)" git_tree_clean

# --- инициализируем git-репо в чистой sub-директории ------------------------
# (на $TMP уже лежит untracked plan.md из предыдущего блока, не путаем)

REPO="$TMP/repo"
mkdir -p "$REPO"
git -C "$REPO" init -q
git -C "$REPO" config user.email "test@example.com"
git -C "$REPO" config user.name "Test"

# Переключаем PROJECT_DIR для git-хелперов
PROJECT_DIR="$REPO"

echo
echo "git_available / git_tree_clean (пустой git-репо):"
assert_exit 0 "git_available возвращает true в git-репо"     git_available
assert_exit 0 "git_tree_clean true на пустом чистом репо"    git_tree_clean

# --- грязное дерево ---------------------------------------------------------

echo "untracked content" > "$REPO/some-file.md"

echo
echo "git_tree_clean (есть untracked-файл):"
assert_exit 1 "git_tree_clean возвращает false когда есть untracked" git_tree_clean

# Стейджим и проверяем staged-вариант
git -C "$REPO" add some-file.md
echo
echo "git_tree_clean (есть staged-файл):"
assert_exit 1 "git_tree_clean возвращает false когда есть staged" git_tree_clean

# Коммитим, чтобы продолжить
git -C "$REPO" commit -m "initial" -q

# --- git_commit_phase -------------------------------------------------------

# Симулируем то, что наоркестрировал run-phase: создаём plan-папку и отчёты.
PLAN_NAME="myplan"
PLAN_DIR_REL="plans/$PLAN_NAME"
mkdir -p "$REPO/$PLAN_DIR_REL/phase1"
cp "$PLAN" "$REPO/$PLAN_DIR_REL/plan.md"
echo "## FOUND: пусто" > "$REPO/$PLAN_DIR_REL/phase1/errors.md"
echo "## FOUND: пусто" > "$REPO/$PLAN_DIR_REL/phase1/missing.md"
echo "## FOUND: пусто" > "$REPO/$PLAN_DIR_REL/phase1/review.md"
echo "## FOUND: пусто" > "$REPO/$PLAN_DIR_REL/phase1/security.md"
cat > "$REPO/$PLAN_DIR_REL/phase1/final_check.md" <<'EOF'
## REGRESSION
чисто

## SMOKE
pass
EOF

echo
echo "git_commit_phase:"
SHA="$(git_commit_phase 1 "$REPO/$PLAN_DIR_REL/plan.md" "$PLAN_NAME")"
if [[ -n "$SHA" && "$SHA" =~ ^[0-9a-f]+$ ]]; then
  echo "  ✓ возвращает короткий sha: $SHA"
  PASS=$((PASS + 1))
else
  echo "  ✗ не вернул валидный sha (получили: '$SHA')"
  FAIL=$((FAIL + 1))
fi

# Проверяем содержимое коммита
SUBJECT="$(git -C "$REPO" log -1 --format=%s)"
BODY="$(git -C "$REPO" log -1 --format=%b)"

if [[ "$SUBJECT" == "[$PLAN_NAME] phase 1: построить базовую структуру" ]]; then
  echo "  ✓ заголовок коммита корректный: $SUBJECT"
  PASS=$((PASS + 1))
else
  echo "  ✗ неверный заголовок: $SUBJECT"
  FAIL=$((FAIL + 1))
fi

if echo "$BODY" | grep -q "$PLAN_DIR_REL/phase1/errors.md"; then
  echo "  ✓ в теле коммита есть ссылки на отчёты по новым путям"
  PASS=$((PASS + 1))
else
  echo "  ✗ в теле коммита нет ссылок на отчёты"
  FAIL=$((FAIL + 1))
fi

# Файлы должны быть в коммите
FILES="$(git -C "$REPO" show --name-only --format= HEAD | sort)"
for fname in errors.md missing.md review.md security.md final_check.md; do
  expected="$PLAN_DIR_REL/phase1/$fname"
  if echo "$FILES" | grep -qE "^${expected}$"; then
    echo "  ✓ закоммичен: $expected"
    PASS=$((PASS + 1))
  else
    echo "  ✗ НЕ закоммичен: $expected"
    FAIL=$((FAIL + 1))
  fi
done

# После коммита дерево должно быть чистым
echo
echo "после autocommit:"
assert_exit 0 "git_tree_clean true после коммита" git_tree_clean

# Проверим, что без plan_name (третий аргумент) git_commit_phase вытаскивает имя из пути.
echo
echo "git_commit_phase без явного plan_name:"
mkdir -p "$REPO/$PLAN_DIR_REL/phase2"
echo "## FOUND: пусто" > "$REPO/$PLAN_DIR_REL/phase2/errors.md"
echo "## FOUND: пусто" > "$REPO/$PLAN_DIR_REL/phase2/missing.md"
echo "## FOUND: пусто" > "$REPO/$PLAN_DIR_REL/phase2/review.md"
echo "## FOUND: пусто" > "$REPO/$PLAN_DIR_REL/phase2/security.md"
cat > "$REPO/$PLAN_DIR_REL/phase2/final_check.md" <<'EOF'
## REGRESSION
чисто

## SMOKE
pass
EOF

SHA2="$(git_commit_phase 2 "$REPO/$PLAN_DIR_REL/plan.md")"
SUBJECT2="$(git -C "$REPO" log -1 --format=%s)"
if [[ "$SUBJECT2" == "[$PLAN_NAME] phase 2: добавить логирование" ]]; then
  echo "  ✓ git_commit_phase извлёк plan_name из пути: $SUBJECT2"
  PASS=$((PASS + 1))
else
  echo "  ✗ не извлёк plan_name из пути, заголовок: $SUBJECT2"
  FAIL=$((FAIL + 1))
fi

echo
echo "Итого: $PASS прошло, $FAIL упало"
[[ "$FAIL" -eq 0 ]] || exit 1
