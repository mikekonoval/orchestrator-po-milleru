# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Что это за репозиторий

Это **исходник скилла** `orchestrator-po-milleru` — bash-оркестратор многофазного review-workflow для Claude Code. Репозиторий рассчитан на публикацию в GitHub и установку через `install.sh` глобально (`~/.claude/skills/`) или локально в проект (`.claude/skills/`).

Структура:

- [README.md](README.md) — пользовательский front page: что, зачем, как установить, как запускать.
- [install.sh](install.sh) — distribution installer: `--global` / `--local <dir>` / `--uninstall`.
- [skill/](skill/) — **канонический источник скилла**, который и копируется при установке.
  - [skill/SKILL.md](skill/SKILL.md) — триггеры и пользовательские инструкции, видны Claude Code при загрузке скилла.
  - [skill/scripts/](skill/scripts/) — `run-phase.sh`, `run-all.sh`, `init-project.sh`, `lib/state.sh`, `lib/parse-report.sh`.
  - [skill/prompts/](skill/prompts/) — 13 шаблонов промтов (errors/missing/review/security × find/prove/apply, плюс final_check) + `phase_generate.md`.
  - [skill/templates/](skill/templates/) — `state.json`, `plan.md` для бутстрапа проекта.
  - [skill/tests/smoke/](skill/tests/smoke/) — smoke-тесты: парсер маркеров, init-project, dry-run всего пайплайна.
- [docs/workflow.md](docs/workflow.md) — исходная спецификация workflow (бывший `orchestrator_workflow.md`). Сохранена как обоснование текущей реализации.
- [Chat.md](Chat.md) — транскрипт проектного обсуждения. Перед нетривиальными правками прочитай — там зафиксировано, **почему** выбран bash-путь, а не LLM-оркестратор / SDK / фреймворк.

## Архитектура реализации

LLM-оркестратор не вытягивает ~100 итераций в одном контексте — упрётся в автокомпакт. Поэтому:

- **Оркестрация — в bash.** `run-phase.sh` гоняет цикл по 5 блокам (ERRORS → MISSING → REVIEW → SECURITY → FINAL CHECK), каждый блок — 3 шага (find/prove/apply).
- **Шаги — отдельные `claude -p`-вызовы.** Каждый суб-агент стартует с чистым контекстом, использует подписку Claude Max (никакого API-ключа).
- **Память между шагами — файлы отчётов** с маркерами секций (`## FOUND` / `## PROVEN` / `## APPLIED` / `## REGRESSION` / `## SMOKE`), append-only.
- **Ветвления — через grep этих маркеров** в [skill/scripts/lib/parse-report.sh](skill/scripts/lib/parse-report.sh). Не через LLM.
- **State — `state.json`** в корне проекта пользователя (`phase`, `step`, `status`). Редактируется через [skill/scripts/lib/state.sh](skill/scripts/lib/state.sh).

### Инварианты, которые легко нарушить

- **Append-only отчёты.** Каждый шаг **добавляет** секцию, не перезаписывает файл. `## REGRESSION` и `## SMOKE` читают `## APPLIED` из предыдущих блоков — если затереть, обратной связи не будет.
- **Условные пропуски — на стороне bash, не LLM.** `## FOUND: пусто` → скрипт пропускает prove/apply. Без `РЕАЛЬНАЯ` в `## PROVEN` → скрипт пропускает apply. Не вкладывай эту логику в промты.
- **ESCALATE-стоп.** `ESCALATE: ...` в `## APPLIED` ИЛИ smoke fail / regression непуст в `final_check_phase{N}.md` → фаза не закрывается, exit code 2 (escalate) или 3 (smoke fail).
- **Самодостаточные промты.** Каждый промт стартует с `Прочитай {файл} секцию {маркер}` — иначе суб-агент в чистом контексте не понимает, к чему привязываться.
- **Двойной фильтр реальности.** Шаг `prove` отсеивает «теоретически может, но не критично» с учётом `CLAUDE.md`, аудитории, объёмов и приоритета `запустить → продать → масштабировать`. Это центральная защита от шумных AI-ревью, не формальность.
- **Только подписка, никакого API.** `claude -p` через подписку Claude Max. Никаких прямых вызовов `anthropic.Anthropic()` или `ANTHROPIC_API_KEY`.

## Команды разработки

Smoke-тесты (запускаются из корня репо):

```bash
bash skill/tests/smoke/test-parse-report.sh        # парсер маркеров на фикстурах (12 ассертов)
bash skill/tests/smoke/test-init-project.sh        # init-project в tmp-каталоге (17 ассертов)
bash skill/tests/smoke/test-run-phase-dry.sh       # весь пайплайн в --dry-run (15 ассертов)
bash skill/tests/smoke/test-git-helpers.sh         # phase_description, git_available, git_commit_phase + state после провала autocommit (32 ассерта)
bash skill/tests/smoke/test-prompts-preamble.sh    # каждый промт ссылается на CLAUDE.md, idea/, architecture/, plans/ (70 ассертов)
bash skill/tests/smoke/test-summary.sh             # phase_summary_block, applied_summary, insert_summary_into_plan (21 ассерт)
```

Всего **167 ассертов**. После любых правок в `skill/scripts/lib/` или `skill/prompts/` — прогнать всё.

Sanity-проверка синтаксиса всех bash-скриптов:

```bash
for f in skill/scripts/*.sh skill/scripts/lib/*.sh skill/tests/smoke/*.sh install.sh; do
  bash -n "$f" && echo "  ✓ $f" || echo "  ✗ $f"
done
```

Установка локально для тестирования:

```bash
bash install.sh --local /tmp/test-project
```

Деинсталляция:

```bash
bash install.sh --uninstall global
bash install.sh --uninstall local /tmp/test-project
```

## Соглашения по правкам

- Язык: **русский** в SKILL.md, промтах, README, спецификации. Английские технические термины (bash, prompt, escalate, smoke) — оставляй как есть.
- Имена файлов отчётов: `errors_phase{N}.md`, `missing_phase{N}.md`, `review_phase{N}.md`, `security_phase{N}.md`, `final_check_phase{N}.md`. Промт фазы: `plans/promts/phase{N}.md` — **именно `promts`** (так в исторической спецификации). Опечатка `reivew` была и исправлена — не возвращай.
- Любая правка `parse-report.sh` или формата маркеров требует обновить промт-шаблоны (которые этот формат генерируют) **и** smoke-тесты (которые на этот формат завязаны). Иначе пайплайн молча начнёт ловить ложные срабатывания.
- Не вкладывай оркестрационную логику в LLM-промт. Условные пропуски, парсинг маркеров, переход между блоками и закрытие фазы — работа скрипта.
- Для всех новых скриптов: `set -euo pipefail`, BASH_SOURCE[0]-самопозиционирование, поддержка macOS sed (`sed -i ''`) И GNU sed (`sed -i`) через `if sed --version`.

## Поведение autocommit

После закрытой фазы (smoke pass, regression clean) скрипт делает один git-коммит — реализовано в [skill/scripts/lib/git.sh](skill/scripts/lib/git.sh).

- **Стартовая проверка:** перед фазой `git_tree_clean` должен вернуть true. Иначе abort. Это гарантирует, что в фазовый коммит попадает ровно то, что наоркестрировал пайплайн.
- **Коммит:** заголовок `phase N: <phase_description из plan>`, тело — список отчётов. Сообщение собирает скрипт, не LLM.
- **Когда не коммитим:** не git-репо / `--no-commit` / ESCALATE / smoke fail. На двух последних — намеренно: пользователь должен разобраться сам, а не получить замаскированную проблему в коммите.
- **`git commit` может упасть** (типично — гонка на `.git/index.lock` от IDE/watch-скрипта). `git_commit_phase` делает до 3 попыток с экспоненциальной паузой ТОЛЬКО при наличии index.lock; на детерминированных ошибках (нечего коммитить, hook отказал) — выходит сразу. При окончательном провале возвращает non-zero и **ничего не печатает в stdout** — вызывающий код в `run-phase.sh` не должен видеть «успешный SHA» при провальном коммите. State: `status=done, commit=failed, error=autocommit failed`, exit 5 — `status` остаётся `done`, потому что фаза по сути закрыта (галочка в плане, summary, отчёты), отдельное поле `.commit` отмечает только пропущенный git-шаг. Это держит `state_already_done` в true и защищает от случайного перезапуска уже сделанной фазы. `state_init` обязан удалять `.commit` (и `.error`) при переходе на следующую фазу — иначе старая отметка протекает в state.json. В тестах паузу можно занулить через `ORCHESTRATOR_LOCK_RETRY_SLEEP=0`.
- **Опт-аут грязного дерева:** `--allow-dirty` — autocommit засосёт всё подряд, использовать редко.

Если правишь логику autocommit — `test-git-helpers.sh` обязательно прогнать перед коммитом.

## Привязка промтов к источникам правды

Каждый из 14 промтов начинается с единой секции **«Контекст проекта (читай ВСЕГДА перед работой)»**, перечисляющей четыре источника:
1. `CLAUDE.md` — продукт и приоритеты
2. `idea/` — продуктовое видение и принципы (`01-idea/`, `02-vision/`, `05-principles/`, `09-mvp/` и т.д.)
3. `architecture/` — техническое устройство и инварианты (`02-ядро/`, `03-данные/`, `07-решения/`)
4. `plans/promts/phase{N}.md` — цель и критерий «сделано» текущей фазы

Дальше идёт шаг-специфичный список «Что ещё прочитать» с отчётами и кодом. Цель такого построения — снять дрейф: суб-агент не сможет «выдумать решение из воздуха», потому что каждый раз заземляется на источниках.

Регрессионная защита — `test-prompts-preamble.sh` (70 ассертов). Любое удаление ссылки на `idea/`, `architecture/`, `CLAUDE.md` или `plans/` из любого промта тест поймает.

Этот подход заменяет идею отдельного branch-guard-шага. Branch-guard был бы костылём поверх дрейфующих агентов; здесь дрейф снимается на уровне каждого промта.

## Известные ограничения и направления развития

- `claude -p` имеет таймаут на один вызов. Тяжёлые шаги фазы (много кода) могут отвалиться — пока решение «дроби фазу на подфазы».
- Параллельный прогон фаз в текущей реализации не поддерживается (driver `run-all.sh` строго последовательный). Намеренно: фазы редко независимы и параллель приведёт к merge-конфликтам.

Любая идея «добавить умную логику в оркестратор» — сначала проверь, не означает ли это «добавить LLM-вызов туда, где сейчас grep». Если да — это шаг в неправильную сторону.
