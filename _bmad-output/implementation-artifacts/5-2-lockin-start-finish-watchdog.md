# Story 5.2: Start, finish, and 59:30 watchdog

Status: done

## Story

As a **member**,
I want **to start and finish sessions from the panel with auto-submit before the 60-minute cap**,
so that **I do not lose Sparkles because I forgot to stop**.

## Acceptance Criteria

1. **Given** no live session
   **When** I start with an optional title
   **Then** `lockIn/start` runs and state shows a new current session

2. **Given** a live session
   **When** I finish
   **Then** `lockIn/finish` runs with `current.id` and state clears or updates

3. **Given** a live session at T-30s before `expiresAt`
   **When** the watchdog fires
   **Then** it auto-finishes and auto-starts a new session with the same title

4. **Given** Finish is clicked
   **When** elapsed is under 30 minutes
   **Then** Finish still runs and reward copy explains the 30-60 minute window

## Tasks / Subtasks

- [x] **Task 1 — Helper `lockin start` and `lockin finish`** (AC: 1, 2)
  - [x] 1.1 Extend `usage()` with `lockin start [title…]` and `lockin finish ID`.
  - [x] 1.2 `cmd_lockin_start`: join optional title args, truncate to 160, POST `lockIn/start` with `{}` or `{title}`, print `{ok:true}` via `unwrap_ok`.
  - [x] 1.3 `cmd_lockin_finish`: require non-empty id, POST `lockIn/finish` with `{id}`, print `{ok:true}` via `unwrap_ok`.
  - [x] 1.4 Dispatch `start` and `finish` under `lockin` case. Never print the key.

- [x] **Task 2 — Panel Start / Finish UI** (AC: 1, 2, 4)
  - [x] 2.1 Add `startProc` / `finishProc`, `lockinTitleDraft`, `lockinStart(title)`, `lockinFinish()`, `applyLockinStart` / `applyLockinFinish`.
  - [x] 2.2 Idle: title field + Start button. Live: Finish button. Refetch state after success.
  - [x] 2.3 When elapsed < 30 min and live, show reward copy for the 30–60 minute Sparkles window. Finish always enabled.

- [x] **Task 3 — T-30s watchdog** (AC: 3)
  - [x] 3.1 At `lockinRemainingMs <= 30000`, auto finish then auto start same title (once per session id).
  - [x] 3.2 Quiet notification via `lockinStatusHint`. Works when panel is closed.

- [x] **Task 4 — Tests** (AC: 1–4)
  - [x] 4.1 `tests/lockin-session.sh` + fixtures for start/finish.
  - [x] 4.2 Update `tests/lockin-state.sh` and `tests/all.sh`.
  - [x] 4.3 Run all tests until pass.

Benji todo: `c9e3452b-9f5d-4d07-8f3a-c61e4e802cca`

## File List

- `bin/tinkerer` — `lockin start`, `lockin finish`
- `Panel.qml` — Start/Finish UI, watchdog, mutation procs
- `README.md` — start/finish/watchdog usage
- `tests/lockin-session.sh` — new
- `tests/fixtures/lockin-start-*.json`, `lockin-finish.*`, `lockin-start-401.in.json`
- `tests/lockin-state.sh` — allow start/finish in helper; still ban todos
- `tests/all.sh` — run lockin-session.sh
