# Story 5.3: LockIn checklist todos

Status: done

## Story

As a **member**,
I want **my private LockIn checklist in the panel**,
so that **I can track focus tasks across sessions**.

## Acceptance Criteria

1. **Given** a valid key
   **When** `bin/tinkerer lockin todos` runs
   **Then** it POSTs to `/api/v1/lockIn/todos` with `{}` and prints `{ok:true, todos:[...]}` where each todo has string keys `id`, `title`, `createdAt`, and booleans `completed`, `deleted`; items with `deleted:true` are omitted from `todos`.

2. **Given** a title
   **When** `bin/tinkerer lockin todo-add TITLE` runs
   **Then** it POSTs to `/api/v1/lockIn/createTodo` with a client-generated UUID (`uuidgen`) and `{id, title}` (title trimmed, max 200) and prints `{ok:true}`.

3. **Given** a todo id
   **When** `bin/tinkerer lockin todo-done ID` or `lockin todo-update ID true|false` runs
   **Then** it POSTs to `/api/v1/lockIn/updateTodo` with `{id, completed}` and prints `{ok:true}`.

4. **Given** a todo id
   **When** `bin/tinkerer lockin todo-delete ID` runs
   **Then** it POSTs to `/api/v1/lockIn/deleteTodo` with `{id}` and prints `{ok:true}`.

5. **Given** the LockIn view
   **When** I add, toggle complete, or delete a todo
   **Then** the matching helper command runs and the checklist refetches; deleted items are hidden.

6. **Given** todos exist and no live session
   **When** the LockIn view is open
   **Then** the checklist still lists items (same as web).

7. **Given** existing lockin tests
   **When** `tests/all.sh` runs
   **Then** all pass including new `tests/lockin-todos.sh`.

Benji todo: `d43c9625-bea9-4e70-9290-9e807a825cdf`

## Tasks / Subtasks

- [x] **Task 1 — Helper todo commands** (AC: 1–4)
  - [x] 1.1 Extend `usage()` with `lockin todos`, `todo-add`, `todo-done`, `todo-update`, `todo-delete`.
  - [x] 1.2 Add `unwrap_lockin_todos` (jq): unwrap `result`/`data`, normalize `{id, title, completed, deleted, createdAt}`, filter `deleted:true`.
  - [x] 1.3 `cmd_lockin_todos`: POST `lockIn/todos` `{}`, print `{ok:true, todos}`.
  - [x] 1.4 `cmd_lockin_todo_add`: join title args, trim, max 200, `uuidgen` for id, POST `lockIn/createTodo`.
  - [x] 1.5 `cmd_lockin_todo_update`: POST `lockIn/updateTodo` `{id, completed}`; `todo-done` → `completed:true`.
  - [x] 1.6 `cmd_lockin_todo_delete`: POST `lockIn/deleteTodo` `{id}`.
  - [x] 1.7 Dispatch under `lockin` case. Never print the key.

- [x] **Task 2 — Panel checklist UI** (AC: 5, 6)
  - [x] 2.1 Add `lockinTodos`, `lockinTodoDraft`, `todosProc`, `todoAddProc`, `todoUpdateProc`, `todoDeleteProc`.
  - [x] 2.2 `refreshLockinTodos()` on LockIn view open and manual Refresh; include in `viewBusy`/`busy`.
  - [x] 2.3 Checklist section: add field, rows with checkbox toggle, delete; hide deleted; works idle or live.
  - [x] 2.4 Refetch todos after successful mutations.

- [x] **Task 3 — Tests** (AC: 7)
  - [x] 3.1 `tests/lockin-todos.sh` + fixtures for list/add/update/delete.
  - [x] 3.2 Update `tests/lockin-state.sh`, `tests/lockin-session.sh`, `tests/all.sh`.
  - [x] 3.3 Run all tests until pass.

- [x] **Task 4 — Docs and status** (AC: 7)
  - [x] 4.1 README: LockIn checklist sentence.
  - [x] 4.2 Mark story done; sprint-status `5-3-lockin-todos: done`; epic-5 done.

## File List

- `bin/tinkerer` — todos list/add/update/delete helpers
- `Panel.qml` — LockIn checklist UI and mutation procs
- `README.md` — checklist usage
- `tests/lockin-todos.sh` — new
- `tests/fixtures/lockin-todos-*.json` — new
- `tests/lockin-state.sh` — allow todos in usage; state still isolated
- `tests/lockin-session.sh` — allow todos; fix start/finish isolation bounds
- `tests/all.sh` — run lockin-todos.sh
- `_bmad-output/implementation-artifacts/sprint-status.yaml`

## Dev Agent Record

### Completion Notes List

- Helper uses `uuidgen` (or `/proc/sys/kernel/random/uuid`) for client ids on add; tests pin id via `TINKERER_TODO_UUID`.
- Panel toggle uncheck uses `lockin todo-update ID false`; check uses `lockin todo-done ID`.
- `tests/all.sh` passes (1148 assertions).
