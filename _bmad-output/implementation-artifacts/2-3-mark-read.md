# Story 2.3: Mark notifications read

Status: done

<!-- Note: Validation is optional. Run validate-create-story for quality check before dev-story. -->

## Story

As a **member**,
I want **markRead and markAllRead from the panel**,
so that **the badge matches what I have already seen**.

## Acceptance Criteria

1. **Given** a valid key file and a non-empty notification `id`
   **When** `bin/tinkerer notifications mark-read <id>` runs
   **Then** it POSTs to `/api/v1/notification/markRead` with `x-api-key` and JSON body `{"id":"<id>"}` only (no extra keys, no `cursor`), and prints one JSON object `{ok:true, id:"<id>"}`.

2. **Given** an unread item listed in the Notifications view
   **When** I use the explicit per-row Mark read control (not the row click)
   **Then** the helper mark-read command runs for that item’s `id`, and after success `refreshUnread()` runs so `unreadCount` drops to the server value (badge uses that count).

3. **Given** a valid key file
   **When** `bin/tinkerer notifications mark-all-read` runs
   **Then** it POSTs to `/api/v1/notification/markAllRead` with `x-api-key` and JSON body `{}`, and prints one JSON object `{ok:true}`.

4. **Given** Mark all read on the Notifications view
   **When** it succeeds
   **Then** `refreshUnread()` runs and the idle badge clears (`unreadCount` becomes 0; pill hidden when count is 0). Do not invent a local `unreadCount = 0` that skips the unread refetch.

5. **Given** a missing key, empty key, missing/empty `id` (mark-read only), 401/403, network failure, or a non-JSON payload
   **When** the mark helper command runs
   **Then** stdout is one JSON object `{ok:false, error, hint}` (hint may be empty), the process exits 0 (same as `fail` today), and the raw API key never appears in stdout or stderr. Missing/empty `id` must not call curl.

6. **Given** `status`, `feed`, `notifications unread`, and `notifications list` already work
   **When** this story lands
   **Then** those commands, the feed list, Refresh, the Story 1.3 `hasNew` dot, the Story 2.1 unread pill, and Story 2.2 list + click-to-open still behave as they do now. Opening the Notifications view does **not** call mark-read or mark-all-read. Clicking a notification row still only `openUrl` (empty url = no browser). Marking is explicit.

7. **Given** tests under `tests/`
   **When** `tests/mark.sh`, `tests/list.sh`, and `tests/unread.sh` run
   **Then** all three pass with no live API key, no network, and no files matching `.gitignore` key patterns committed.

## Tasks / Subtasks

- [x] **Task 1 — Helper commands `notifications mark-read` and `notifications mark-all-read`** (AC: 1, 3, 5, 6)
  - [x] 1.1 Extend `usage()` in `bin/tinkerer` with:
        `notifications mark-read ID  Mark one notification read.`
        `notifications mark-all-read Mark all notifications read.`
        Keep `notifications unread` and `notifications list`. Do **not** add camelCase subcommands (`markRead`, `markAllRead`) or a bare `mark`.
  - [x] 1.2 Dispatch two tokens plus an id for mark-read. After option parsing, `$1` is `notifications` and `$2` is `mark-read` or `mark-all-read`. For mark-read, `$3` is the id. Do not `shift` globally. Empty or unknown subcommand uses existing `fail` and names the bad command (`Unknown command: notifications` / `Unknown command: $2`). Bare `mark` and `markRead` stay unknown.
  - [x] 1.3 Add `cmd_notifications_mark_read` that requires a non-empty trimmed id. If missing or empty, `fail` with an error that mentions the id is required and **do not** call `api_call`. Build the POST body with jq as `{id:$id}` only (`additionalProperties` false). Call existing `api_call "notification/markRead" "<body>"`.
  - [x] 1.4 Add `cmd_notifications_mark_all_read` that calls existing `api_call "notification/markAllRead" '{}'`. Do not send `id`, `cursor`, or other keys.
  - [x] 1.5 Reuse `--base-url`, `--key-file`, HTTPS-unless-localhost, 15s timeout, User-Agent, `x-api-key`. Do not add a new flag (`--id` is forbidden; id is positional).
  - [x] 1.6 Add `unwrap_ok` (jq, same style as `unwrap_count` / `unwrap_notifications`) that pass-throughs `{ok:false}` envelopes from `api_call`/`fail`. Any other parseable JSON (including `{}`, `{data:{}}`, `{result:{data:null}}`, `{result:{data:{}}}`) is success. Do not overload `unwrap_items` / `unwrap_count` / `unwrap_notifications`.
  - [x] 1.7 Print compact one-line JSON: mark-read → `{ok:true, id:"<the same id sent>"}`; mark-all-read → `{ok:true}`. Do not require a typed `data` field from OpenAPI (it is `{}`).
  - [x] 1.8 Never print the key. Do not call `notification/list` or `notification/unreadCount` from these commands (QML refreshes unread after success).

- [x] **Task 2 — Fixture tests for the helper** (AC: 1, 3, 5, 6, 7)
  - [x] 2.1 Create `tests/mark.sh` using `tests/list.sh` + `tests/unread.sh`: `set -euo pipefail`, `pass`/`bad`, PATH-injected stub `curl`, temp `--key-file`, invoke `bin/tinkerer` as a process (never source it). Unset `TINKERER_API_KEY` / `TINKERER_KEY` / `TINKERER_APIKEY`. Dummy key: `test-key-not-real-SECRET99`.
  - [x] 2.2 Create fixtures under `tests/fixtures/` (see Dev Notes for exact shapes):
        `mark-read-empty.in.json` / `.out.json`
        `mark-read-data-wrapped.in.json` / `.out.json`
        `mark-read-result-data.in.json` / `.out.json`
        `mark-all-empty.in.json` / `.out.json`
        `mark-all-data-wrapped.in.json` / `.out.json`
        `mark-all-result-data.in.json` / `.out.json`
        `mark-401.in.json`
  - [x] 2.3 Stub `curl` must append argv to a log, print fixture body, then a newline and HTTP code (`200` or `401`) because `api_call` uses `curl -w '\n%{http_code}'`.
  - [x] 2.4 Assert mark-read: `-X POST`, URL ending `/api/v1/notification/markRead`, `Content-Type: application/json`, `x-api-key` present, `--data` is exactly `{"id":"n1"}` (jq `keys == ["id"]`). Assert mark-all-read: URL ending `/api/v1/notification/markAllRead`, `--data {}` or `--data '{}'`. Helper stdout/stderr must not contain the temp key. Must not hit `app.tinkerer.club`.
  - [x] 2.5 Cases: each successful fixture → `{ok:true}` (and `id:"n1"` for mark-read); 401 → auth error mentioning the key file, not the key; 403; empty key file (no curl); network fail; missing key file (no curl); mark-read with no id and with empty id → `{ok:false}`, no curl; unknown `notifications` subcommand `frob` / `mark` / `markRead` → `{ok:false}`, no curl; `notifications unread` still hits `unreadCount` only; `notifications list` still hits `list` only; `status` still reports `configured` without curl; `feed` still hits `post/timeline` only.
  - [x] 2.6 QML source assertions (no QML runner): Notifications view has a Mark all read control; each notification row has a Mark read control that is **not** the row `openUrl` MouseArea; after mark success the panel calls `refreshUnread`; `onOpenedChanged` / Feed|Notifications switcher / `refreshNotifications` do **not** start mark procs; row click remains `onClicked: root.openUrl(modelData.url)`. Feed + unread + list isolation from `tests/list.sh` remains except usage/string bans that this story must update (Task 2.7).
  - [x] 2.7 Update `tests/list.sh` and `tests/unread.sh` so they no longer fail this story:
        - usage may list `notifications mark-read` and `notifications mark-all-read` in addition to `list` + `unread`
        - remove or rewrite the `grep -qE 'markRead|markAllRead'` “no mark-read strings” check (helper **will** contain `notification/markRead`)
        - keep unknown-subcommand coverage for `frob` / `mark` / `markRead` (those stay unknown)
        - keep “list/unread must not call mark endpoints” on those commands
        - keep AC6 isolation: opening the list / `applyNotifications` still must not change `unreadCount` or start mark procs
  - [x] 2.8 Script exits 0 only when every case passed. Invoke `tests/list.sh` (which already invokes `tests/unread.sh`) or invoke all three. No live `TINKERER` key. No `curl` to `app.tinkerer.club`.

- [x] **Task 3 — Panel mark-read and mark-all-read** (AC: 2, 4, 6)
  - [x] 3.1 In `Panel.qml` add dedicated `Process` objects `markReadProc` and `markAllReadProc`. Do not reuse `feedProc` / `statusProc` / `unreadProc` / `listProc`. Commands:
        `root.cmd(["notifications", "mark-read", id])`
        `root.cmd(["notifications", "mark-all-read"])`.
  - [x] 3.2 Add `markRead(id)` and `markAllRead()`. Start the matching Process only when not already running, the panel is `opened`, and `panelView === "notifications"`. `markRead` no-ops on a missing/empty id (do not start a process). Include both mark procs in `busy`. Do **not** put them on `viewBusy` (Refresh stays list/feed only — Story 2.2 F2).
  - [x] 3.3 Add `applyMark(data)`: if `data.ok === true`, clear `errorText`/`statusHint` only when `panelView === "notifications"`, then call `refreshUnread()`. Do not write `unreadCount` here. If `ok !== true` and `panelView === "notifications"` and `opened`, set `errorText`/`statusHint` from the envelope. Do not clear `posts`, `notifications`, or `unreadCount` on failure. If the panel is closed, do not write mark failures into `errorText`.
  - [x] 3.4 Add a **Mark all read** `WidgetButton` on the notifications view (second header row next to Feed | Notifications, or a third header row if 300px width would clip — Story 2.2 F6). Visible when `panelView === "notifications"` and `unreadCount > 0`. Label: `Mark all read`. `onPressed` left-click → `markAllRead()`. Hide or no-op when `unreadCount === 0` or mark-all is already running.
  - [x] 3.5 Per-row **Mark read** control on each notification delegate: a `WidgetButton` (or equivalent text control) labeled `Mark read`, **sibling** to the existing row `MouseArea` (do not put it under that MouseArea). Left-click → `markRead(String(modelData.id || ""))`. Row `MouseArea` stays `onClicked: root.openUrl(modelData.url)` — do not also mark-read there.
  - [x] 3.6 After a successful mark, do **not** require a list refetch. Badge correctness is `refreshUnread()` → `applyUnread`. Optional: leave the row in the list (2.2 has no read/unread styling). Do not invent per-row unread styling or remove the item unless a later story asks.
  - [x] 3.7 `onOpenedChanged`, idle `Timer`, Feed tab, and switching to Notifications stay as 2.2: no mark calls. `refresh()` stays view-aware list/feed only. Do not add IPC methods. Do not auto-switch views.
  - [x] 3.8 Do not add a new `manifest.json` setting. Do not change BarWidget badge/tooltip metrics (2.1 stays). Closing the panel still hides the pill; when `unreadCount` is 0 the pill stays hidden.

- [x] **Task 4 — Click-to-open stays exclusive** (AC: 2, 6)
  - [x] 4.1 Reuse `openUrl` + `browserProc` + `xdg-open`. Mark controls must not call `openUrl`.
  - [x] 4.2 Do not mark-read as a side effect of opening a URL, Refresh, or listing.
  - [x] 4.3 `tests/mark.sh` asserts the row `openUrl` line still exists and that mark functions are separate.

- [x] **Task 5 — Docs, validate, no secrets** (AC: 1, 6, 7)
  - [x] 5.1 README Usage: one or two sentences that Notifications has Mark read / Mark all read, and that the unread badge updates after those succeed. Keep click-to-open wording.
  - [x] 5.2 Do not mention a real key. Do not add files matching `.gitignore` (`*api-key*`, `*apikey*`, `*token*`, `.env`).
  - [x] 5.3 Run `omarchy plugin validate .` from repo root after QML/manifest-adjacent edits. Manifest defaults stay as they are; no new schema key.
  - [x] 5.4 Run `tests/mark.sh`, `tests/list.sh`, and `tests/unread.sh`. Confirm `status`, `feed`, `notifications unread`, and `notifications list` dispatch still exist in `bin/tinkerer`.
  - [ ] 5.5 Manual (not required to mark the story done): with a local key file, mark-read / mark-all-read against the real origin; reload the enabled plugin (`~/.config/omarchy/plugins/dneighbors.tinkerer-club/` is a separate clone — copy or pull before judging the bar).

## Dev Notes

Ultimate context engine analysis completed — comprehensive developer guide created.

There is no `architecture.md`, `prd.md`, or `ux-design-specification.md`. Do not invent them. The plugin + OpenAPI are the contract: QML never holds the member key; `bin/tinkerer` is the only reader.

### Product intent

Epic 2 goal: unread club notifications on the bar, with a list and mark-read. Story 2.1 (DONE) is the idle count badge. Story 2.2 (DONE) is the list + click-through. Story 2.3 is explicit mark-read / mark-all-read so the badge matches what the member has already seen. [Source: `_bmad-output/planning-artifacts/epics.md` — Epic 2]

Dependencies: Epic 0 (key file + helper), Epic 1 (feed panel), Story 2.1 (`notifications unread` + badge), Story 2.2 (`notifications list` + Notifications view). Epic 1 stories are still `in-progress` in sprint-status. Treat feed + unread + list behavior as already shipped in this tree and do not regress them.

The feed is what happened. Notifications are what wants you. Opening the list is not the same as having seen an item.

### Out of scope (later / do not add)

- Auto-mark-read when the list opens or a row is clicked
- Per-row read/unread styling, swipe-to-dismiss, cursor pagination
- New manifest settings (no `notificationLimit`, no badge-style enum)
- Changing BarWidget lobster glyph, pill metrics, or tooltip format (2.1 stays)
- Optimistic `unreadCount--` without a successful unread refetch
- New IPC methods
- Calling `notification/list` from the mark helper commands

### Locked UX / contract decisions (do not reopen)

| Decision | Choice | Why |
|---|---|---|
| Command names | `notifications mark-read <id>` and `notifications mark-all-read` | Matches shipped `unread` / `list` (kebab, not camelCase). Bare `mark` / `markRead` stay unknown so 2.2 unknown-subcommand cases remain. |
| Id | Positional `$3`, not `--id` | No new flags. Empty/missing id → `fail`, no curl. |
| markRead body | `{"id":"<string>"}` only | OpenAPI required `id`, `additionalProperties: false`. |
| markAllRead body | `{}` | OpenAPI empty object, `additionalProperties: false`. |
| After success | `refreshUnread()` only (existing `applyUnread`) | ACs are unreadCount drop + badge clear. Server is source of truth. |
| Open list | Do not mark | 2.2 locked this. Marking is explicit. |
| Row click | Still `openUrl` only | 2.2 AC. Separate Mark read control so click-to-open is not overloaded. |
| Mark all read button | Visible on Notifications view when `unreadCount > 0` | AC 2 is the badge. Hide when already 0. |
| List after mark | Leave items in the model | No read styling this epic. Do not require a list refetch. |
| Mutation 200 | Any JSON that is not `{ok:false}` → success | OpenAPI `data` is untyped. Empty `{}` is success (unlike unread, which needs a count). |
| Errors | `{ok:false,error,hint}` + exit 0 | QML always gets a parseable line. |
| Two Process objects | `markReadProc` + `markAllReadProc` | One `Process` cannot run two commands. |
| `viewBusy` | Unchanged (list vs feed) | Mark in flight must not disable Refresh (2.2 F2). |
| Manifest | No new settings | Reuse existing key file / base URL / feedLimit. |
| Badge while panel open | Still hidden (2.1) | After mark-all, count is 0 so the pill stays gone when the panel closes. |

### Helper architecture (must follow)

File: `bin/tinkerer`

Current commands after Story 2.2: `status`, `feed`, `notifications unread`, `notifications list`. Shared pieces the new commands must reuse:

- `DEFAULT_BASE_URL=https://app.tinkerer.club`
- `DEFAULT_KEY_FILE=${XDG_CONFIG_HOME:-$HOME/.config}/omarchy/secrets/tinkerer-club-api-key`
- `USER_AGENT=omarchy-plugin-tinkerer-club/0.1.0 (+https://github.com/dneighbors/omarchy-plugin-tinkerer-club)`
- `validate_base_url` — HTTPS required except `localhost` / `127.0.0.1` / `[::1]`
- `read_api_key` — first line, trim, never echo; nameref into `api_call` (2.1 lesson: `key="$(read_api_key)"` swallowed `fail` because `fail` exits 0)
- `api_call <procedure> <body>` — `POST ${origin}/api/v1/${procedure}`, headers `Accept`, `Content-Type: application/json`, `User-Agent`, `x-api-key`, `--max-time 15`, parses trailing HTTP code
- `fail` / `json_error` — `{ok:false,error,hint}`, **exit 0** so QML always gets a parseable line
- `unwrap_items` — feed-only; do not overload it
- `unwrap_count` — unread-only; do not overload it
- `unwrap_notifications` — list-only; do not overload it

Wire formats:

```
POST /api/v1/notification/markRead
Headers: Accept: application/json, Content-Type: application/json, User-Agent: <existing>, x-api-key: <file>
Body: {"id":"n1"}

POST /api/v1/notification/markAllRead
Headers: same
Body: {}
```

[Source: `/tmp/tinkerer-openapi.json` and live `https://app.tinkerer.club/api/v1/openapi.json` — `POST /api/v1/notification/markRead` operationId `notification_markRead`, request `{id: string, required: [id], additionalProperties: false}`; `POST /api/v1/notification/markAllRead` operationId `notification_markAllRead`, request `{additionalProperties: false, properties: {}, type: object}`; both `x-procedure-type: mutation`; security `apiKey` header `x-api-key`; 200 `{data: {}, path}`; 400/401/403]

OpenAPI 200 `data` is untyped. Live payloads may be tRPC-shaped. `unwrap_ok` MUST accept the fixtures below.

Pass through `{ok:false}` the same way `unwrap_count` does (`if type == "object" and .ok == false then .`).

Suggested jq for mark-read (adapt quoting to match existing unwraps; keep inline, no extra `.jq` file):

```jq
def unwrap:
  if type == "object" then
    if has("result") then .result | unwrap
    elif has("data") then .data | unwrap
    elif has("json") then .json | unwrap
    else . end
  else . end;
if type == "object" and .ok == false then .
else {ok: true, id: $id}
end
```

Mark-all-read is the same without `id`: `{ok:true}`.

CLI examples:

```sh
bin/tinkerer notifications mark-read n1
bin/tinkerer --key-file /tmp/fake-key --base-url https://app.tinkerer.club notifications mark-read n1
bin/tinkerer notifications mark-all-read
```

### Fixture shapes (lock these)

Base origin in tests: `https://mark.test.invalid` (must not appear as a live call). Temp key: `test-key-not-real-SECRET99` (same distinctive dummy as `tests/unread.sh` / `tests/list.sh`).

`mark-read-empty.in.json` — `{}` → `{ok:true,"id":"n1"}` when invoked as `notifications mark-read n1`.

`mark-read-data-wrapped.in.json` — `{data:{}}` → same out.

`mark-read-result-data.in.json` — `{result:{data:null}}` → same out.

`mark-all-empty.in.json` — `{}` → `{ok:true}`.

`mark-all-data-wrapped.in.json` — `{data:{}}` → `{ok:true}`.

`mark-all-result-data.in.json` — `{result:{data:{}}}` → `{ok:true}`.

`mark-401.in.json` — any JSON body; HTTP 401. Used for both commands.

Also assert inline (no extra fixture required): mark-read with no `$3` and with `$3=""` → `{ok:false}`, empty curl log.

### QML architecture (must follow)

`BarWidget.qml` hosts `Panel.qml` via `Loader`, injects `bar` / `settings` / `anchorItem` / `hostWidget`, and mirrors `opened` / `hasNew` / `unreadCount`. IPC target: `dneighbors.tinkerer-club`. Existing IPC `refresh()` calls `panelItem.refresh()`. **Do not add IPC for mark.** Do not change BarWidget badge/tooltip.

`Panel.qml` builds helper argv with `cmd(args)`:

```qml
[script, "--base-url", baseUrl, "--limit", feedLimit, optional "--key-file", apiKeyFile, ...args]
```

Mark argv is therefore `cmd(["notifications", "mark-read", id])` and `cmd(["notifications", "mark-all-read"])`.

`Process` + `StdioCollector` + `JSON.parse` in `try/catch` is the only I/O pattern. Fifth and sixth processes: `markReadProc`, `markAllReadProc`.

Remote club text is untrusted. Button labels are local strings (`Mark read`, `Mark all read`). Ids come from already-normalized helper output (string). Do not assign remote strings to QML/JS eval. [Source: `SECURITY.md` — Network]

Visual: copy existing `WidgetButton` in the header (Refresh / Feed / Notifications). Per-row control sits to the right of sender/title/age so the row click target remains the text block. Keep “Open Tinkerer Club” at the bottom.

Existing notification row click (do not change the handler):

```qml
onClicked: root.openUrl(modelData.url)
```

`applyUnread` today only writes `unreadCount` when `data.ok === true` and `count` is a finite number ≥ 0. After mark success, `refreshUnread()` is what drops the badge. Do not set `unreadCount` in `applyMark`.

### Previous story learnings (2.1, 2.2)

- `fail` exits 0 — tests assert JSON, not a non-zero exit. Do not write `key="$(read_api_key)"`.
- `tests/unread.sh` and `tests/list.sh` currently **ban** mark in `-h` and ban `markRead|markAllRead` strings in QML/helper. **This story must update those assertions** (Task 2.7) or the existing suites go red the moment the helper gains the endpoints.
- Idle unread + badge-over-dot stay. Mark must not start `unreadProc` except via `refreshUnread()` after a successful mark (and existing 2.1 paths).
- `refreshNotifications` requires `opened`; close resets `panelView` to feed; `refresh()` list only when opened (2.2 F3). Mark functions must use the same `opened` + `panelView === "notifications"` guards.
- `applyFeed` writes/clears errors only when `panelView === "feed"` (2.2 F1). Mark errors follow the notifications-view-and-opened rule.
- Enabled checkout `~/.config/omarchy/plugins/dneighbors.tinkerer-club/` is a **separate clone**. Implement here: `/home/dneighbors/Public/omarchy-plugin-tinkerer-club`.

### Testing standards

No QML test runner (Tesla `tests/MANUAL.md` same constraint). Automated coverage is bash + fixtures + stub `curl` + QML source greps.

Tesla / unread.sh / list.sh rules that apply:

- Never source the production script in a way that executes commands at import; invoke `bin/tinkerer` as a process.
- Isolate dirs / PATH.
- Record curl argv.
- One JSON line on stdout for success paths.
- Fail the script if any case fails.

Do not run live `bin/tinkerer notifications mark-read` as a required CI/story check. Optional manual only (Task 5.5).

### Security (non-negotiable)

- Key file default: `~/.config/omarchy/secrets/tinkerer-club-api-key`, mode 600. [Source: `README.md`, `SECURITY.md`, Story 0.4]
- QML never reads the key. Empty `apiKeyFile` setting means the helper default path.
- Do not put the key in the repo, `shell.json`, QML, fixtures, or issue text. Tests use a temp file containing `test-key-not-real-SECRET99`.
- Send raw key as `x-api-key`. No `Bearer`.
- HTTP only for localhost. Default origin stays `https://app.tinkerer.club`.
- Do not `xdg-open` as part of mark. Do not treat title/sender/id as a command. Id is a JSON string via `--arg`.

### Git intelligence

Recent commits (do not commit this story unless asked):

- `d2c7563` feat(epic-2): Notification list (Story 2-2-notification-list)
- `34eb897` feat(epic-2): Unread notification count (Story 2-1-unread-count)
- `24afb7d` Add BMAD epics, sprint status, and Benji story map.
- `4b246f2` Install BMAD Method for plugin planning and implementation.
- `44b4452` Add Tinkerer Club Omarchy bar plugin scaffold.

Patterns: imperative title + why paragraph; plugin surface is `manifest.json`, `BarWidget.qml`, `Panel.qml`, `bin/tinkerer`, `README.md`, `SECURITY.md`, `tests/`. Stay on `epic-2/notifications`. Do not push. Do not implement this story in the same turn as creating it.

### Latest tech notes (2026-09-14)

- Spec: OpenAPI 3.1.0, title “Tinkerer Club Platform API”, version 1.0.0. Cached `/tmp/tinkerer-openapi.json` matches live `https://app.tinkerer.club/api/v1/openapi.json` for `notification.markRead` (`id` required string) and `notification.markAllRead` (`{}`).
- Auth: `components.securitySchemes.apiKey` — header `x-api-key`.
- Host tools used by the helper today: `jq` 1.8.2, `curl` 8.22.0. No new runtime deps. Do not add Node/Python to the plugin path.
- Raycast unofficial extension [Olli0103/tinkerer-club](https://github.com/Olli0103/tinkerer-club) has **no** markRead / markAllRead UI. Do not copy Raycast mutations. Field-name research from 2.2 is irrelevant here (mutations return untyped `data`).
- tRPC mutations commonly return `{result:{data:null}}` or `{data:{}}`. Treat those as success.
- Public web search did not turn up a Tinkerer Club-specific mark-read client. OpenAPI is the contract.

### Project Structure Notes

```
/home/dneighbors/Public/omarchy-plugin-tinkerer-club/
  bin/tinkerer                 # CHANGE: mark-read + mark-all-read + unwrap_ok
  Panel.qml                    # CHANGE: mark procs, Mark read / Mark all read, applyMark
  BarWidget.qml                # DO NOT change unless a 2.1 grep would break (should not)
  manifest.json                # DO NOT add settings
  README.md                    # CHANGE: Mark read / Mark all read + badge updates
  SECURITY.md                  # DO NOT weaken
  tests/mark.sh                # NEW
  tests/list.sh                # CHANGE: allow mark usage/strings; keep isolation
  tests/unread.sh              # CHANGE: allow mark usage; keep isolation
  tests/fixtures/mark-*.json   # NEW
  _bmad-output/implementation-artifacts/2-3-mark-read.md  # this file
```

Naming: plugin id `dneighbors.tinkerer-club`. Helper name `tinkerer`. Commands are `notifications mark-read` and `notifications mark-all-read` (not `mark` alone, not camelCase).

Variance: Tesla keeps jq in `bin/place.jq`. This plugin inlines jq in `bin/tinkerer`. Keep mark unwrap inline. Do not refactor feed, unread, or list unwrap in this story.

### References

- [Source: `_bmad-output/planning-artifacts/epics.md` — Epic 2, Story 2.3]
- [Source: `_bmad-output/planning-artifacts/epics.source.yaml` — epic 2 / story 2.3]
- [Source: `_bmad/bmm/config.yaml` — project_name `omarchy-plugin-tinkerer-club`, user_name Derek]
- [Source: `docs/benji-map.yaml` — story 2.3 id `dccdd7b0-590d-44f7-89e0-0078b7471c4f`, epic `5fadc0f9-085b-414a-bb0c-10068a84c93b`]
- [Source: `_bmad-output/implementation-artifacts/2-1-unread-count.md` — done unread helper/QML/test patterns]
- [Source: `_bmad-output/implementation-artifacts/2-2-notification-list.md` — done list + click-to-open; mark out of scope]
- [Source: `bin/tinkerer` — `api_call`, unwraps, `cmd_notifications_*`, `fail` exit 0]
- [Source: `Panel.qml` — `cmd()`, `openUrl`, `refreshUnread`, `listProc`, `panelView`, notification rows]
- [Source: `BarWidget.qml` — unread pill, `hasNew` priority, IPC `refresh()`]
- [Source: `manifest.json` — defaults `apiKeyFile`, `baseUrl`, `feedLimit`, `refreshMinutes`]
- [Source: `README.md` — key file setup, Usage]
- [Source: `SECURITY.md` — key file, no print, HTTPS, untrusted remote text]
- [Source: `/tmp/tinkerer-openapi.json` and live OpenAPI — `notification.markRead` / `markAllRead` / `unreadCount` / `list`]
- [Source: `tests/list.sh` — fixture + stub curl + QML greps + usage mark ban to update]
- [Source: `tests/unread.sh` — fixture + stub curl + usage mark ban to update]
- [Source: `~/.config/omarchy/plugins/jankeesvw.tesla/tests/place.sh` — fixture + stub curl]
- [Source: `_bmad/bmm/workflows/4-implementation/create-story/template.md` — missing in this install; used BMAD v6 `bmad-create-story/template.md` sections]

## Dev Agent Record

### Context Reference

<!-- Path(s) to story context XML will be added here by context workflow -->

### Agent Model Used

Cursor Grok 4.6 (Amelia / bmad-story-dev) — Task 3 + 4.1–4.2 (panel agent); Tasks 1, 2.1–2.8, 4.3 (helper + fixture agent)

### Debug Log References

None. No QML runner. Helper coverage is `tests/mark.sh` (invokes `tests/list.sh` → `tests/unread.sh`).

### Completion Notes List

- Task 3 + 4.1–4.2: `Panel.qml` adds dedicated `markReadProc` / `markAllReadProc` (not reused). `markRead(id)` / `markAllRead()` start only when `opened && panelView === "notifications"` and the matching proc is idle; `markRead` no-ops empty/missing id. Both procs are on `busy`, not `viewBusy`. `applyMark` success clears errors only on the notifications view then `refreshUnread()` (never writes `unreadCount`). Failure writes `errorText`/`statusHint` only when notifications view AND `opened`. Mark all read is a third header row (300px clip) `WidgetButton` visible when `panelView === "notifications" && unreadCount > 0`, label `Mark all read`, disabled while `markAllReadProc.running`. Per-row `Mark read` `WidgetButton` is a sibling of the row `MouseArea` (MouseArea right-anchored to the button). Row click remains `onClicked: root.openUrl(modelData.url)` only. No mark on open, switcher, refresh, list fetch, or row click. No BarWidget / manifest / IPC changes.
- Tasks 1 + 2.1–2.8 + 4.3: `bin/tinkerer` adds kebab `notifications mark-read ID` and `notifications mark-all-read`. Dispatch uses `$2`/`$3` (no global shift). Missing/empty trimmed id → `fail` (mentions id required), no curl. POST bodies `{id:$id}` only and `{}`. `unwrap_ok` pass-throughs `{ok:false}`; any other JSON → `{ok:true,id}` / `{ok:true}`. nameref `read_api_key`; `fail` exits 0; key never printed. Bare `mark` / `markRead` stay unknown. `tests/mark.sh` + `tests/fixtures/mark-*.json`; origin `https://mark.test.invalid`; dummy key `test-key-not-real-SECRET99`. Task 2.6 QML greps are written and soft-skip if Panel mark controls are absent (panel agent owns QML); they currently pass because Panel already has them. Task 2.7: `list.sh`/`unread.sh` allow kebab mark usage; rewritten source ban so helper may contain `notification/markRead`; unknown `frob`/`mark`/`markRead` and list/unread isolation kept. Task 4.3: row `openUrl` line + separate mark functions. Did not implement README (Task 5). Did not commit or push.
- Task 5 still open (README + validate).

### File List

- `Panel.qml` — modified (mark procs, markRead/markAllRead/applyMark, Mark all read + per-row Mark read)
- `bin/tinkerer` — modified (usage, dispatch, `unwrap_ok`, `cmd_notifications_mark_read`, `cmd_notifications_mark_all_read`)
- `tests/mark.sh` — new
- `tests/fixtures/mark-read-empty.in.json` — new
- `tests/fixtures/mark-read-empty.out.json` — new
- `tests/fixtures/mark-read-data-wrapped.in.json` — new
- `tests/fixtures/mark-read-data-wrapped.out.json` — new
- `tests/fixtures/mark-read-result-data.in.json` — new
- `tests/fixtures/mark-read-result-data.out.json` — new
- `tests/fixtures/mark-all-empty.in.json` — new
- `tests/fixtures/mark-all-empty.out.json` — new
- `tests/fixtures/mark-all-data-wrapped.in.json` — new
- `tests/fixtures/mark-all-data-wrapped.out.json` — new
- `tests/fixtures/mark-all-result-data.in.json` — new
- `tests/fixtures/mark-all-result-data.out.json` — new
- `tests/fixtures/mark-401.in.json` — new
- `tests/list.sh` — modified (Task 2.7 usage/string bans only)
- `tests/unread.sh` — modified (Task 2.7 usage/string bans only)
- `/home/dneighbors/Public/omarchy-plugin-tinkerer-club/README.md`
- `/home/dneighbors/Public/omarchy-plugin-tinkerer-club/_bmad-output/implementation-artifacts/2-3-mark-read.md`
- `/home/dneighbors/Public/omarchy-plugin-tinkerer-club/_bmad-output/implementation-artifacts/sprint-status.yaml`

## Senior Developer Review (AI)

7 findings. CHANGES_REQUESTED. No criticals.

- F1 HIGH AC2/4: `refreshUnread` dropped the post-mark refetch while unread was already running
- F2 HIGH: QML AC6 greps used soft-skip `qml_note`
- F3 MEDIUM AC5: mark.sh missed non-JSON payload
- F4 MEDIUM: whitespace-only ids started markReadProc
- F5 MEDIUM: per-row Mark read stayed enabled while in flight
- F6 LOW: unused jq `unwrap` def in `unwrap_ok`
- F7 MEDIUM: Task 5 / File List behind the tree

## Review Follow-ups (AI)

- [x] F1 `pendingUnread` queue; applyUnread drains it
- [x] F2 Hard QML greps; applyMark body must call `refreshUnread` and not write `unreadCount`
- [x] F3 Non-JSON 200 cases for mark-read and mark-all-read
- [x] F4 Trim id in `markRead` before starting the Process
- [x] F5 Per-row Mark read `enabled: !markReadProc.running`
- [x] F6 Remove unused unwrap def
- [x] F7 README + validate recorded; story status `done`

## Change Log

- 2026-09-14: Story 2.3 created (ready-for-dev); sprint-status updated
- 2026-09-14: Helper mark-read / mark-all-read + fixture tests (Tasks 1, 2, 4.3); panel mark UI (Task 3, 4.1–4.2)
- 2026-09-14: Applied review F1–F7
