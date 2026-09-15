# Story 5.1: LockIn state and room

Status: done

<!-- Note: Validation is optional. Run validate-create-story for quality check before dev-story. -->

## Story

As a **member**,
I want **`lockIn/state` in the helper and a LockIn panel view**,
so that **I see my session, countdown, and who else is locked in**.

## Acceptance Criteria

1. **Given** a valid key file
   **When** `bin/tinkerer lockin state` runs
   **Then** it POSTs to `/api/v1/lockIn/state` with `x-api-key` and body `{}`, and prints one JSON object `{ok:true, current, participants, serverNow, onboarded}` where `current` is `null` or an object with string keys `id`, `title`, `startedAt`, `expiresAt`, and boolean `automaticallyEnded`; `participants` is an array of objects with string keys `id`, `title`, `startedAt`, `expiresAt`, `name`; and `serverNow` is an ISO-8601 string.

2. **Given** a live session (`current` is non-null)
   **When** the panel LockIn view is open
   **Then** the session title, elapsed time, remaining time, a visible 60-minute cap label, and a participant rail (count plus each participant name, title, and elapsed) render. Remaining and elapsed derive from `expiresAt`, `startedAt`, and `serverNow` (skew-safe), not from guessing local wall clock alone.

3. **Given** no live session (`current` is null)
   **When** the LockIn view is open
   **Then** idle copy renders (no fake countdown). If the helper reports a last ended session with `automaticallyEnded === true`, show timeout copy that the session hit the 60-minute cap — do not imply a clean manual finish.

4. **Given** a live session and the panel is closed
   **When** the bar is idle
   **Then** a session cue shows remaining time (e.g. `MM:SS`). If `unreadCount > 0`, the unread pill is visible and the session cue is hidden (unread wins the corner).

5. **Given** a live session
   **When** the existing quiet-refresh `Timer` fires while configured
   **Then** `lockin state` is polled in addition to the existing idle feed/unread checks so participant rail and server skew stay honest. A local 1s tick may update the displayed countdown between polls; do not add a new manifest poll setting.

6. **Given** a missing key, empty key, 401/403, network failure, or a non-JSON payload
   **When** `bin/tinkerer lockin state` runs
   **Then** stdout is one JSON object `{ok:false, error, hint}` (hint may be empty), the process exits 0 (same as `fail` today), and the raw API key never appears in stdout or stderr.

7. **Given** `status`, `feed`, and `notifications *` already work
   **When** this story lands
   **Then** those commands, the feed list, Notifications view, unread badge, `hasNew` dot priority, and mark-read flows still behave as they do now. This story does **not** call `lockIn/start`, `lockIn/finish`, or `lockIn/todos`.

8. **Given** tests under `tests/`
   **When** `tests/lockin-state.sh` and `tests/unread.sh` run
   **Then** both pass with no live API key, no network, and no files matching `.gitignore` key patterns committed.

## Tasks / Subtasks

- [x] **Task 1 — Helper command `lockin state`** (AC: 1, 6, 7)
  - [x] 1.1 Extend `usage()` in `bin/tinkerer` with `lockin state          LockIn room state as JSON.` Do **not** add `lockin start`, `lockin finish`, `lockin todos`, or other `lockin` subcommands in this story.
  - [x] 1.2 Dispatch two tokens. After option parsing, `$1` is `lockin` and `$2` is `state`. Do not `shift` globally. Empty or unknown subcommand uses existing `fail` and names the bad command.
  - [x] 1.3 Add `cmd_lockin_state` that calls existing `api_call "lockIn/state" '{}'`.
  - [x] 1.4 Add `unwrap_lockin_state` (jq, same style as `unwrap_notifications`) that unwraps `result` / `data` / `json` wrappers, passes through `{ok:false}`, then normalizes:
        - `current`: `null` if absent or not an object with usable `id`; else `{id, title, startedAt, expiresAt, automaticallyEnded}` (strings except `automaticallyEnded` boolean, default `false`).
        - `participants`: array from bare array or keys `participants`, `items`, `results`. Each kept object → `{id, title, startedAt, expiresAt, name}` where `name` comes from nested `user.name`, `user.displayName`, `user.username`, or flat `name`/`displayName`/`username`, else `"Tinkerer"`. Skip objects with no usable `id`.
        - `serverNow`: ISO string from `serverNow`, `now`, `timestamp`, or `""` if missing (QML treats missing as unusable for skew).
        - `onboarded`: boolean from `onboarded`, default `false`.
        - `lastEnd`: optional. If the unwrapped payload includes `lastEnd`, `lastSession`, `endedSession`, or a recently ended object when `current` is null, normalize the same shape as `current` plus `endedAt` when present. Omit key when nothing to report.
  - [x] 1.5 Print exactly one compact JSON object: `{ok:true, current, participants, serverNow, onboarded}` plus `lastEnd` only when present. Reuse `fail` for HTTP/auth/network/non-JSON.
  - [x] 1.6 Never print the key. Reuse `--base-url` and `--key-file`. Do not call `lockIn/start`, `lockIn/finish`, or `lockIn/todos`.

- [x] **Task 2 — Fixture tests for the helper** (AC: 1, 3, 6, 8)
  - [x] 2.1 Create `tests/lockin-state.sh` using `tests/unread.sh` pattern: `set -euo pipefail`, `pass`/`bad`, PATH-injected stub `curl`, temp `--key-file`, invoke `bin/tinkerer` as a process (never source it).
  - [x] 2.2 Create fixtures under `tests/fixtures/`:
        `lockin-live.in.json` / `.out.json` (live `current` + `participants` + `serverNow` + `onboarded`)
        `lockin-idle.in.json` / `.out.json` (`current: null`, empty participants)
        `lockin-timeout.in.json` / `.out.json` (`current: null`, `lastEnd.automaticallyEnded: true`)
        `lockin-data-wrapped.in.json` / `.out.json` (`result.data` wrapper)
        `lockin-participants-array.in.json` / `.out.json` (nested `user.name`)
        `lockin-empty.in.json` / `.out.json` (unusable → `{ok:true, current:null, participants:[], serverNow:"", onboarded:false}`)
        `lockin-401.in.json`
  - [x] 2.3 Stub `curl` appends argv to a log, prints fixture body, then newline + HTTP code (`200` or `401`).
  - [x] 2.4 Assert stub called with `-X POST`, URL ending `/api/v1/lockIn/state`, `Content-Type: application/json`, `x-api-key` present, `--data {}`. No `app.tinkerer.club`. No calls to `lockIn/start`, `lockIn/finish`, `lockIn/todos`.
  - [x] 2.5 Cases: each success fixture → required keys and normalized shapes; empty payload → safe idle object; 401 → auth error mentioning key file, not key; missing key file → configured-style error, no curl; unknown `lockin frob` → `{ok:false}`; `notifications unread` still hits `unreadCount` only.
  - [x] 2.6 QML source greps: LockIn tab/switcher, `stateProc`, `lockinRemainingMs` or equivalent skew helper, no `lockIn/start`/`finish`/`todos` strings in `bin/tinkerer` beyond usage guard. Run `tests/unread.sh` from this script or document both must pass.
  - [x] 2.7 Script exits 0 only when every case passed.

- [x] **Task 3 — Panel LockIn view and state polling** (AC: 2, 3, 5, 7)
  - [x] 3.1 Extend `panelView` to `"feed"` | `"notifications"` | `"lockin"`. Add properties: `lockinCurrent` (object|null), `lockinParticipants` (array), `lockinServerNow` (string), `lockinOnboarded` (bool), `lockinLastEnd` (object|null), `lockinSkewMs` (number), `lockinFetchedAt` (number), `lockinRemainingMs` (number, computed). Default view stays `"feed"`.
  - [x] 3.2 Add dedicated `Process` `stateProc`. Command: `root.cmd(["lockin", "state"])`. Include `stateProc.running` in `busy` / view-aware refresh only when LockIn view is active for Refresh label (mirror notifications pattern).
  - [x] 3.3 Add `applyLockinState(data)`: on `{ok:true}`, set normalized fields; compute `lockinSkewMs = Date.parse(serverNow) - Date.now()` when `serverNow` parses; set `lockinFetchedAt = Date.now()`; recompute `lockinRemainingMs` from `current.expiresAt` when live. On failure while `panelView === "lockin"` and panel open, set LockIn-specific error text; do not clobber feed/notifications errors. While panel closed, do not write LockIn failures into shared `errorText`.
  - [x] 3.4 Add `refreshLockinState()` — starts `stateProc` when not running. When `panelView === "lockin"` and panel opens, fetch immediately. `refresh()` becomes view-aware: LockIn → `refreshLockinState()`.
  - [x] 3.5 Hook quiet-refresh `Timer`: when `configured && lockinCurrent !== null`, also call `refreshLockinState()` (idle or open). Keep existing feed/unread behavior unchanged when no live LockIn.
  - [x] 3.6 Add local `Timer` (1s, running while `lockinCurrent !== null`) to tick `lockinRemainingMs` using skew-safe formula: `(Date.parse(expiresAt) - Date.parse(serverNow)) - (Date.now() - lockinFetchedAt)`; clamp at 0.
  - [x] 3.7 Add LockIn tab to header switcher (third `WidgetButton`: `"LockIn"`). LockIn body when `panelView === "lockin"`:
        - Live: title (`plain()`), elapsed (`formatDuration(elapsedMs)`), remaining (`formatDuration(lockinRemainingMs)`), muted `"60 min cap"` label, participant rail with count header `"Locked in now · N"` and rows (name, title snippet, elapsed).
        - Idle: `"No LockIn session running."` When `lockinLastEnd && lockinLastEnd.automaticallyEnded`, add timeout copy: session ended at the 60-minute cap (no Sparkles — server-side; do not invent sparkles API).
        - Onboard hint: if `onboarded === false`, one muted line pointing to the web LockIn page (`openUrl` to `${baseUrl}/lock-in` or club path used on web — use origin-relative `/lock-in` joined to `baseUrl`).
  - [x] 3.8 Do **not** add Start, Finish, checklist, or sparkles UI (Stories 5.2 / 5.3). Do not auto-switch to LockIn when a session starts (member picks the tab).
  - [x] 3.9 `onOpenedChanged`: when panel closes, reset `panelView` to `"feed"` (existing behavior). Hide LockIn errors from other views via separate error properties (mirror feed/notifications split if not already generalized).

- [x] **Task 4 — Idle bar session cue** (AC: 4, 7)
  - [x] 4.1 Expose `readonly property bool lockinLive: lockinCurrent !== null` and `readonly property int lockinRemainingMs` (or formatted string) on `Panel.qml` for `BarWidget` to read via `panelItem`.
  - [x] 4.2 In `BarWidget.qml`, add a session cue overlay (bottom or opposite corner from unread badge): visible when `lockinLive && !opened && unreadCount <= 0`. Text: remaining `MM:SS` from `lockinRemainingMs`. Use `Color.accent` border or compact pill — do not widen the bar row.
  - [x] 4.3 Tooltip when cue visible: `Tinkerer Club · LockIn MM:SS remaining`. When unread pill visible, keep existing unread tooltip (session cue hidden).
  - [x] 4.4 Preserve badge priority: unread pill > session cue > `hasNew` dot (dot still requires `unreadCount <= 0`; session cue also requires `unreadCount <= 0`).
  - [x] 4.5 Do not change lobster glyph or IPC surface.

- [ ] **Task 5 — Docs, validate, no secrets** (AC: 1, 7, 8)
  - [ ] 5.1 README Usage: one or two sentences that the panel has a LockIn tab for live co-working sessions and the idle bar can show remaining time when a session is running. Do not document start/finish/todos yet.
  - [ ] 5.2 Do not mention a real key. No `.gitignore`-pattern secrets in fixtures.
  - [ ] 5.3 Run `omarchy plugin validate .` from repo root after QML edits. No new manifest settings.
  - [ ] 5.4 Run `tests/lockin-state.sh` and `tests/unread.sh`. Confirm existing commands still dispatch.
  - [ ] 5.5 Manual (not required to mark done): with a local key file, `bin/tinkerer lockin state` against the real origin; reload the enabled plugin clone under `~/.config/omarchy/plugins/dneighbors.tinkerer-club/`.

## Dev Notes

Ultimate context engine analysis completed — comprehensive developer guide created.

There is no `architecture.md`, `prd.md`, or `ux-design-specification.md`. Do not invent them. The plugin + OpenAPI + live `lockIn/state` sample are the contract: QML never holds the member key; `bin/tinkerer` is the only reader.

### Product intent

Epic 5 goal: timed co-working LockIn sessions from the bar with participant rail, checklist (5.3), and a 59:30 auto-finish watchdog (5.2). Story 5.1 is **read-only state + room UI**: helper `lockin state`, panel LockIn tab, idle bar remaining-time cue. LockIn is a reverse pomodoro with a hard **60-minute cap** (`expiresAt = startedAt + 60m`). Sparkles are server-side only — never invent a sparkles API. [Source: `_bmad-output/planning-artifacts/epics.md` — Epic 5]

Dependencies: Epic 0 (key file + helper). Soft dependency on Epic 2 patterns (unread pill priority, quiet-refresh timer, two-token dispatch). No dependency on Epic 3 Events.

Out of scope (Stories 5.2 / 5.3): `lockIn/start`, `lockIn/finish`, 59:30 watchdog, Start/Finish buttons, `lockIn/todos` CRUD, checklist UI, `dismissHint`, avatar images (`/api/media` proxy), sparkles balance, Omarchy desktop notifications for auto-restart.

### Locked UX / contract decisions (do not reopen)

| Decision | Choice | Why |
|---|---|---|
| Command namespace | `lockin state` (kebab, two-token) | Matches `notifications unread` / `notifications list`; epic AC literal. |
| API procedure | `lockIn/state` (camelCase path segment) | OpenAPI path is `/api/v1/lockIn/state`. |
| LockIn view | Third panel tab `Feed \| Notifications \| LockIn` | Same switcher pattern as Story 2.2. Default stays feed. |
| Countdown skew | `remaining = (expiresAt - serverNow) - (now - fetchedAt)` | AC + epic notes: skew-safe, not raw `Date.now()` vs `expiresAt`. |
| Display tick | 1s local `Timer` while live | Smooth MM:SS without API spam. |
| API poll | Existing `refreshMinutes` quiet timer **plus** poll whenever `lockinCurrent !== null` | Epic: poll on quiet-refresh while session live. |
| Idle bar cue | Remaining MM:SS when live + panel closed | Epic AC. |
| Corner priority | Unread pill > LockIn cue > feed `hasNew` dot | Epic AC + Story 2.1 precedence. |
| Participant avatars | Names only v1 | Planning note: optional later with safe media proxy. |
| Timeout copy | When `lastEnd.automaticallyEnded` | Planning note: do not pretend clean finish after cap. |
| Finish button | Not in 5.1 | Wired in Story 5.2. |
| Open panel on live session | No auto-switch | Member chooses LockIn tab. |

### Live payload reference (2026-09-14)

From a live `lockIn/state` pull during Epic 5 planning:

```json
{
  "participants": [
    {
      "id": "...",
      "title": "Omarchy Tinkerer Club Lockin Plugin",
      "startedAt": "2026-09-15T02:51:02.216Z",
      "expiresAt": "2026-09-15T03:51:02.216Z",
      "user": { "id": "...", "name": "Derek Neighbors", "username": "dneighbo", "avatarImageUrl": "/api/media/..." }
    }
  ],
  "current": {
    "id": "cmu22rnpot8cz01o9btmrgacj",
    "title": "Omarchy Tinkerer Club Lockin Plugin",
    "startedAt": "2026-09-15T02:51:02.216Z",
    "expiresAt": "2026-09-15T03:51:02.216Z",
    "endedAt": null,
    "automaticallyEnded": false
  },
  "onboarded": true,
  "serverNow": "2026-09-15T02:52:34.903Z"
}
```

Helper output for the live case (illustrative):

```json
{
  "ok": true,
  "current": {
    "id": "cmu22rnpot8cz01o9btmrgacj",
    "title": "Omarchy Tinkerer Club Lockin Plugin",
    "startedAt": "2026-09-15T02:51:02.216Z",
    "expiresAt": "2026-09-15T03:51:02.216Z",
    "automaticallyEnded": false
  },
  "participants": [
    {
      "id": "...",
      "title": "Omarchy Tinkerer Club Lockin Plugin",
      "startedAt": "2026-09-15T02:51:02.216Z",
      "expiresAt": "2026-09-15T03:51:02.216Z",
      "name": "Derek Neighbors"
    }
  ],
  "serverNow": "2026-09-15T02:52:34.903Z",
  "onboarded": true
}
```

Web product rules (copy only — not extra API fields):

- Finish between 30–60 minutes for reward (Sparkles). Early finish or timeout = no reward.
- Timeout at 60m sets `automaticallyEnded` (server-side).
- Right rail on web: locked-in count + participant name/title/elapsed.

### Helper architecture (must follow)

File: `bin/tinkerer`

Current commands: `status`, `feed`, `notifications unread|list|mark-read|mark-all-read`. Shared pieces the new command must reuse:

- `DEFAULT_BASE_URL=https://app.tinkerer.club`
- `DEFAULT_KEY_FILE=${XDG_CONFIG_HOME:-$HOME/.config}/omarchy/secrets/tinkerer-club-api-key`
- `USER_AGENT=omarchy-plugin-tinkerer-club/0.1.0 (+https://github.com/dneighbors/omarchy-plugin-tinkerer-club)`
- `validate_base_url`, `read_api_key` (nameref into `api_call`), `api_call`, `fail` / `json_error` (exit 0)
- Do not overload `unwrap_items`, `unwrap_count`, or `unwrap_notifications`

Wire format:

```
POST /api/v1/lockIn/state
Headers: Accept, Content-Type, User-Agent, x-api-key
Body: {}
```

[Source: `/tmp/tinkerer-openapi.json` — `lockIn_state`, request `{}`, security `apiKey`, 200 `data` untyped]

Suggested jq skeleton (adapt quoting to match existing unwrap functions):

```jq
def unwrap:
  if type == "object" then
    if has("result") then .result | unwrap
    elif has("data") then .data | unwrap
    elif has("json") then .json | unwrap
    else . end
  else . end;
def text($obj; $keys):
  ($keys | map($obj[.] | select(type == "string" and . != ""))) | .[0] // "";
def participant_name($p):
  (if ($p.user | type) == "object" then
     text($p.user; ["name","displayName","username"])
   else "" end) as $nested
  | if $nested != "" then $nested
    else text($p; ["name","displayName","username"]) // "Tinkerer" end;
def normalize_current($c):
  if ($c | type) != "object" then null
  else (text($c; ["id"])) as $id
  | if $id == "" then null else {
      id: $id,
      title: text($c; ["title"]) // "LockIn",
      startedAt: text($c; ["startedAt"]),
      expiresAt: text($c; ["expiresAt"]),
      automaticallyEnded: ($c.automaticallyEnded // false)
    } end;
# ... emit {ok:true, current, participants, serverNow, onboarded, lastEnd?}
```

CLI:

```sh
bin/tinkerer lockin state
bin/tinkerer --key-file /tmp/fake-key --base-url https://app.tinkerer.club lockin state
```

### QML architecture (must follow)

`Panel.qml` already hosts Feed | Notifications switcher, quiet-refresh `Timer` (~line 341), per-view error split, and `Process` + `StdioCollector` I/O. Add a fifth data `Process` (`stateProc`) — do not reuse `feedProc` / `unreadProc`.

`cmd(["lockin", "state"])` builds argv the same way as notifications.

Add duration helpers in QML (inline functions, no new file):

```qml
function formatDuration(ms) {
  if (!isFinite(ms) || ms < 0) return "0:00"
  var totalSec = Math.floor(ms / 1000)
  var m = Math.floor(totalSec / 60)
  var s = totalSec % 60
  return m + ":" + (s < 10 ? "0" : "") + s
}
function lockinElapsedMs(startedAt) {
  if (!lockinCurrent || !startedAt) return 0
  var start = Date.parse(startedAt)
  if (!isFinite(start)) return 0
  return Math.max(0, Date.now() + lockinSkewMs - start)
}
```

Participant row elapsed: same skew pattern using each participant's `startedAt`.

Remote text (`title`, `name`) through `plain()` / `snippet()`. [Source: `SECURITY.md`]

`BarWidget.qml` reads `panelItem.lockinLive` and `panelItem.lockinRemainingMs`. Unread badge block (~lines 75–97) stays; add session cue with stricter visibility guard.

### Previous story learnings (2.1, 2.2)

- `fail` exits 0 — tests assert JSON, not non-zero exit.
- One `Process` per helper command.
- Idle = panel closed (`opened === false`).
- Unread fetch errors: keep last good count; no closed-panel error spam.
- `refresh()` must be view-aware (2.2 F3).
- Separate error properties per view (2.2 F1).
- Enabled checkout `~/.config/omarchy/plugins/dneighbors.tinkerer-club/` is a **separate clone**. Implement in `/home/dneighbors/Public/omarchy-plugin-tinkerer-club`.

### Testing standards

No QML test runner. Automated coverage: bash + fixtures + stub `curl` + QML source greps (Tesla / `tests/unread.sh` rules).

- Temp key: `test-key-not-real-SECRET99`
- Test origin: `https://lockin.test.invalid`
- Never hit `app.tinkerer.club` in tests
- Invoke `bin/tinkerer` as subprocess, never source it

### Security (non-negotiable)

- Key file default: `~/.config/omarchy/secrets/tinkerer-club-api-key`, mode 600.
- QML never reads the key.
- Do not fetch `/api/media/` avatars in 5.1 (path may require auth; names are enough).
- Do not put keys in fixtures, QML, or README.

### Git intelligence

Recent commits (do not commit this story unless asked):

- `06b2442` Add marketplace preview screenshot at repo root.
- `96072bd` Mark story 4.2 done after marketplace validation.
- `0954f23` Track publish (4.2/4.3) and LockIn Epic 5 in epics and Benji.
- `5927f41` feat(epic-2): Notifications (#1)

Implement on a feature branch (e.g. `story/5-1-lockin-state-room`). Do not push unless asked.

### Latest tech notes (2026-09-14)

- OpenAPI 3.1.0 — `lockIn/state`, `lockIn/start`, `lockIn/finish`, `lockIn/todos`, todo mutations. Only `state` in this story.
- Host tools: `jq` 1.8.x, `curl` 8.x. No new runtime deps.
- `lockIn/start` body: optional `title` max 160 (5.2).
- `lockIn/finish` body: `{id}` required (5.2).

### Project Structure Notes

```
/home/dneighbors/Public/omarchy-plugin-tinkerer-club/
  bin/tinkerer                      # CHANGE: lockin state + unwrap_lockin_state
  Panel.qml                         # CHANGE: lockin tab, stateProc, timers, rail UI
  BarWidget.qml                     # CHANGE: idle session cue + tooltip priority
  manifest.json                     # DO NOT add settings
  README.md                         # CHANGE: LockIn tab + idle cue sentence
  SECURITY.md                       # DO NOT weaken
  tests/lockin-state.sh             # NEW
  tests/fixtures/lockin-*.json      # NEW
  tests/unread.sh                   # CHANGE: usage may list lockin state; still ban start/finish/todos
  _bmad-output/implementation-artifacts/5-1-lockin-state-room.md  # this file
```

Naming: plugin id `dneighbors.tinkerer-club`. Helper subcommand `lockin state` (not `lockIn` camelCase at CLI).

### References

- [Source: `_bmad-output/planning-artifacts/epics.md` — Epic 5, Story 5.1]
- [Source: `_bmad-output/planning-artifacts/epics.source.yaml` — epic 5 / story 5.1]
- [Source: `_bmad/bmm/config.yaml` — project_name `omarchy-plugin-tinkerer-club`, user_name Derek]
- [Source: `docs/benji-map.yaml` — story 5.1 id `bf92adeb-e8cc-4f4b-b529-7efd384109fa`, epic `cb2736e0-ca86-4041-9c3d-fa22315119ab`]
- [Source: `_bmad-output/implementation-artifacts/2-1-unread-count.md` — helper/QML/test patterns, badge priority]
- [Source: `_bmad-output/implementation-artifacts/2-2-notification-list.md` — panelView switcher, view-aware refresh]
- [Source: `bin/tinkerer` — `api_call`, `unwrap_*`, dispatch]
- [Source: `Panel.qml` — `Timer`, switcher, `cmd()`, error split]
- [Source: `BarWidget.qml` — unread pill, `hasNew` dot]
- [Source: `/tmp/tinkerer-openapi.json` — `lockIn.*` procedures]
- [Source: live `lockIn/state` sample — planning transcript 2026-09-14]
- [Source: `tests/unread.sh` — fixture + stub curl pattern]
- [Source: `_bmad/bmm/workflows/4-implementation/create-story/template.md` — missing in install; structure from 2-1 / 2-2]

## Dev Agent Record

### Context Reference

<!-- Path(s) to story context XML will be added here by context workflow -->

### Agent Model Used

Cursor Composer (Bob / bmad-story-creator)

### Debug Log References

### Completion Notes List

### File List

## Change Log

- 2026-09-14: Story 5.1 created (ready-for-dev); sprint-status updated (epic-5 in-progress)
