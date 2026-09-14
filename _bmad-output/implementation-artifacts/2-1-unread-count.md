# Story 2.1: Unread notification count

Status: done

## Story

As a **member**,
I want **the helper and bar to show `notification.unreadCount`**,
so that **I can see if the club is waiting on me**.

## Acceptance Criteria

1. **Given** a valid key file
   **When** `bin/tinkerer notifications unread` runs
   **Then** it POSTs to `/api/v1/notification/unreadCount` with `x-api-key` and prints JSON `{ok:true, count:<integer>=0}`.

2. **Given** an unread count greater than zero
   **When** the bar is idle (panel closed)
   **Then** the lobster widget shows that count as a badge (display `99+` when count > 99).

3. **Given** unread count is 0, or unread has never successfully loaded
   **When** the bar is idle
   **Then** no unread badge is shown. Do not render `"0"`.

4. **Given** a missing key, empty key, 401/403, network failure, or a payload with no extractable count
   **When** `bin/tinkerer notifications unread` runs
   **Then** stdout is one JSON object with `{ok:false, error, hint}` (hint may be empty), the process exits 0 (same as `fail` today), and the raw API key never appears in stdout or stderr.

5. **Given** `status` and `feed` already work
   **When** this story lands
   **Then** those commands, the feed list, Refresh, and the Story 1.3 `hasNew` dot still behave as they do now, except the feed dot is hidden while the unread badge is visible (see Dev Notes: badge priority).

6. **Given** tests under `tests/`
   **When** `tests/unread.sh` runs
   **Then** it passes with no live API key, no network, and no files matching `.gitignore` key patterns committed.

## Tasks / Subtasks

- [x] **Task 1 — Helper command `notifications unread`** (AC: 1, 4, 5)
  - [x] 1.1 Extend `usage()` in `bin/tinkerer` with `notifications unread   Unread notification count as JSON.` Do not invent other `notifications` subcommands in this story.
  - [x] 1.2 Dispatch two tokens. After option parsing, `$1` is `notifications` and `$2` is `unread`. Do not `shift` globally (feed/status take no extra args; keep that). Empty or unknown subcommand uses existing `fail` and names the bad command.
  - [x] 1.3 Add `cmd_notifications_unread` that calls existing `api_call "notification/unreadCount" '{}'` — empty JSON object, POST, same headers, 15s timeout, User-Agent unchanged.
  - [x] 1.4 Add `unwrap_count` (jq, same style as `unwrap_items`) that unwraps `result` / `data` wrappers, then reads a number from a bare number, a digit string, or object keys `count`, `unreadCount`, `unread`, `total` in that order. Negative numbers become 0. Missing/unusable payload calls `fail "Tinkerer Club returned no unread count."`.
  - [x] 1.5 Print exactly one compact JSON object: `{"ok":true,"count":<int>}`. Integer, not string. Reuse `fail` for HTTP/auth/network/non-JSON so the envelope stays `{ok:false,error,hint}`.
  - [x] 1.6 Never print the key. Do not add a new `--` flag. Reuse `--base-url` and `--key-file`. HTTPS-unless-localhost stays as-is.

- [x] **Task 2 — Fixture tests for the helper** (AC: 1, 4, 6)
  - [x] 2.1 Create `tests/unread.sh` using the Tesla plugin pattern at `~/.config/omarchy/plugins/jankeesvw.tesla/tests/place.sh`: `set -euo pipefail`, `pass`/`bad`, PATH-injected stub `curl`, temp `--key-file`, no sourcing of `bin/tinkerer`.
  - [x] 2.2 Create fixtures under `tests/fixtures/`:
        `unread-bare-number.in.json` / `.out.json`
        `unread-count-object.in.json` / `.out.json`
        `unread-data-wrapped.in.json` / `.out.json`
        `unread-result-data.in.json` / `.out.json`
        `unread-zero.in.json` / `.out.json`
        `unread-string-count.in.json` / `.out.json`
        `unread-empty.in.json` (unusable payload)
        `unread-401.in.json`
  - [x] 2.3 Stub `curl` must append argv to a log, print fixture body, then a newline and HTTP code (`200` or `401`) because `api_call` uses `curl -w '\n%{http_code}'`.
  - [x] 2.4 Assert the stub was called with `-X POST`, URL ending `/api/v1/notification/unreadCount`, `Content-Type: application/json`, and `x-api-key` present. Helper stdout/stderr must not contain the temp key value.
  - [x] 2.5 Cases: each successful fixture → `{ok:true,count:N}`; empty payload → `{ok:false}`; 401 → auth error mentioning the key file, not the key; missing key file → configured-style error, no curl; unknown `notifications` subcommand → `{ok:false}`; `status` still reports `configured` without calling unread.
  - [x] 2.6 Script exits 0 only when every case passed. No live `TINKERER` key. No `curl` to `app.tinkerer.club`.

- [x] **Task 3 — Panel polls unread while idle** (AC: 2, 3, 5)
  - [x] 3.1 In `Panel.qml` add `property int unreadCount: 0`. BarWidget reads this via `panelItem` the same way it reads `hasNew`.
  - [x] 3.2 Add a dedicated `Process` `unreadProc` (do not reuse `feedProc` / `statusProc`). Command: `root.cmd(["notifications", "unread"])`.
  - [x] 3.3 Add `applyUnread(data)`: if `data.ok === true` and `count` is a finite number ≥ 0, set `unreadCount` to `Math.floor(count)`; otherwise leave the last successful count (initial 0). Do not write unread failures into `errorText` while the panel is closed. Do not clear a feed error because unread failed.
  - [x] 3.4 Add `refreshUnread()` that starts `unreadProc` only when not already running.
  - [x] 3.5 Existing `Timer` (`refreshMinutes`, default 5, `triggeredOnStart: true`): when `configured && !opened`, also `refreshUnread()`. When opened, this story does not require unread polling (idle = panel closed).
  - [x] 3.6 `refresh()` stays feed-first. After a successful `applyFeed` while configured, call `refreshUnread()` so a manual Refresh does not leave a stale badge. Do not block feed on unread.
  - [x] 3.7 Include `unreadProc.running` in `busy` so the Refresh label can show `…` while unread is in flight.
  - [x] 3.8 Do not add panel list UI, mark-read, or a new `manifest.json` setting.

- [x] **Task 4 — Bar unread badge** (AC: 2, 3, 5)
  - [x] 4.1 In `BarWidget.qml` add `readonly property int unreadCount: panelItem && panelItem.unreadCount !== undefined ? Number(panelItem.unreadCount) : 0`. Guard NaN as 0.
  - [x] 4.2 Draw a count pill over the lobster, top-right, overlay not extra row width. Follow `jankeesvw.notification-center` Count badge: `Color.accent` fill, `Color.background` text, `99+` when `unreadCount > 99`, `Style.space` sizes, `Text.PlainText`.
  - [x] 4.3 Visible only when `unreadCount > 0 && !root.opened`. Hidden at 0 and while the panel is open (opening is not idle).
  - [x] 4.4 Badge priority: when the unread pill is visible, hide the existing 6px `hasNew` dot so two markers do not share the same corner. When unread is 0, the Story 1.3 dot is unchanged.
  - [x] 4.5 Tooltip when closed and `unreadCount > 0`: `Tinkerer Club · N unread` (or `1 unread`). Otherwise keep `Tinkerer Club` / `Close Tinkerer Club`.
  - [x] 4.6 Do not put the API key, key path, or raw helper JSON into tooltip or button text. Keep the lobster glyph as the existing `\ud83e\udd9e` escapes.

- [x] **Task 5 — Docs, validate, no secrets** (AC: 1, 5, 6)
  - [x] 5.1 README Usage: one sentence that the idle lobster shows an unread count when the club has waiting notifications. Do not document `notification.list` or mark-read.
  - [x] 5.2 Do not mention a real key. Do not add files matching `.gitignore` (`*api-key*`, `*apikey*`, `*token*`, `.env`).
  - [x] 5.3 Run `omarchy plugin validate .` from repo root after QML/manifest-adjacent edits. Manifest defaults stay as they are; no new schema key.
  - [x] 5.4 Run `tests/unread.sh`. Confirm `status` and `feed` dispatch still exist in `bin/tinkerer`.
  - [ ] 5.5 Manual (not required to mark the story done): with a local key file, `bin/tinkerer notifications unread` against the real origin; reload the enabled plugin (`~/.config/omarchy/plugins/dneighbors.tinkerer-club/` is a separate clone — copy or pull before judging the bar).

## Dev Notes

Ultimate context engine analysis completed — comprehensive developer guide created.

There is no `architecture.md`, `prd.md`, or `ux-design-specification.md`. The plugin itself is the architecture: QML never holds the member key; `bin/tinkerer` is the only reader.

### Product intent

Epic 2 goal: unread club notifications on the bar, then a list and mark-read. Story 2.1 is the badge only. The feed is what happened; notifications are what wants you. [Source: `_bmad-output/planning-artifacts/epics.md` — Epic 2]

Dependencies: Epic 0 (key file + helper) and Epic 1 (feed panel + idle timer + `hasNew` dot). Epic 1 stories are still `in-progress` in sprint-status. Treat feed behavior as already shipped in this tree and do not regress it.

Out of scope (Stories 2.2 / 2.3): `notification.list`, `notification.markRead`, `notification.markAllRead`, a notifications view in the panel, badge-style settings (Dot vs Count), clearing the count on panel open.

### Locked UX decisions (do not reopen)

| Decision | Choice | Why |
|---|---|---|
| AC “count or a badge” | Numeric count pill | Story is unread **count**; a second identical 6px dot would collide with `hasNew`. |
| Idle | Panel closed (`opened === false`) | Matches the existing quiet-refresh timer. Not Hyprland/Omarchy lock idle. |
| Cap | `99+` | Same as `jankeesvw.notification-center` Count badge. |
| Two markers | Unread pill wins; hide feed dot while pill is visible | One corner, one meaning. Feed dot returns when count is 0. |
| Poll interval | Reuse `refreshMinutes` (default 5) | No new manifest setting. |
| Open panel | Hide unread pill; no unread poll required | AC is idle bar. |
| Unread fetch error | Keep last good count; no closed-panel `errorText` | Transient fail must not look like an empty club or a feed outage. |

### Helper architecture (must follow)

File: `bin/tinkerer`

Current commands: `status`, `feed`. Shared pieces the new command must reuse:

- `DEFAULT_BASE_URL=https://app.tinkerer.club`
- `DEFAULT_KEY_FILE=${XDG_CONFIG_HOME:-$HOME/.config}/omarchy/secrets/tinkerer-club-api-key`
- `USER_AGENT=omarchy-plugin-tinkerer-club/0.1.0 (+https://github.com/dneighbors/omarchy-plugin-tinkerer-club)`
- `validate_base_url` — HTTPS required except `localhost` / `127.0.0.1` / `[::1]`
- `read_api_key` — first line, trim, never echo
- `api_call <procedure> <body>` — `POST ${origin}/api/v1/${procedure}`, headers `Accept`, `Content-Type: application/json`, `User-Agent`, `x-api-key`, `--max-time 15`, parses trailing HTTP code
- `fail` / `json_error` — `{ok:false,error,hint}`, **exit 0** so QML always gets a parseable line
- `unwrap_items` — feed-only; do not overload it for counts

Wire format for this story:

```
POST /api/v1/notification/unreadCount
Headers: Accept: application/json, Content-Type: application/json, User-Agent: <existing>, x-api-key: <file>
Body: {}
```

[Source: `/tmp/tinkerer-openapi.json` — `POST /api/v1/notification/unreadCount`, operationId `notification_unreadCount`, request schema `{ additionalProperties: false, properties: {}, type: object }`, security scheme `apiKey` header `x-api-key`]

OpenAPI 200 schema is only `{ data: {}, path: string }` — `data` is untyped. Live payloads may be tRPC-shaped. `unwrap_count` MUST accept all of these and emit `{ok:true,count:3}`:

```json
3
{"count":3}
{"unreadCount":3}
{"data":3}
{"data":{"count":3}}
{"result":{"data":{"count":3}}}
{"result":{"data":{"unreadCount":3}}}
"3"
```

Zero is success: `{ok:true,count:0}`. QML hides the badge; the helper still returns 0.

Suggested jq (adapt to match `unwrap_items` quoting style; keep it inside the script, no extra `.jq` file unless tests get cleaner that way):

```jq
def unwrap:
  if type == "object" then
    if has("result") then .result | unwrap
    elif has("data") then .data | unwrap
    else . end
  else . end;
def as_count:
  if type == "number" then .
  elif type == "string" and test("^[0-9]+$") then tonumber
  elif type == "object" then
    (.count // .unreadCount // .unread // .total // empty) | as_count
  else empty end;
(unwrap | as_count) as $n
| if $n == null then error("no count")
  else {ok:true, count: (if $n < 0 then 0 else ($n|floor) end)}
  end
```

CLI examples:

```sh
bin/tinkerer notifications unread
bin/tinkerer --key-file /tmp/fake-key --base-url https://app.tinkerer.club notifications unread
```

### QML architecture (must follow)

`BarWidget.qml` hosts `Panel.qml` via `Loader`, injects `bar` / `settings` / `anchorItem` / `hostWidget`, and mirrors panel state (`opened`, `hasNew`). IPC target: `dneighbors.tinkerer-club`. Existing IPC `refresh()` already calls `panelItem.refresh()`.

`Panel.qml` builds helper argv with `cmd(args)`:

```qml
[script, "--base-url", baseUrl, "--limit", feedLimit, optional "--key-file", apiKeyFile, ...args]
```

Unread argv is therefore `cmd(["notifications", "unread"])`.

Quiet refresh already lives in `Timer` at line ~158: `interval: refreshMinutes * 60000`, `triggeredOnStart: true`. Idle path already calls `checkStatus()` and `feed` when configured. Add unread on that same idle path.

`Process` + `StdioCollector` + `JSON.parse` in `try/catch` is the only I/O pattern. One `Process` object cannot run two commands at once — hence a third `unreadProc`.

Remote club text is untrusted. Count is a number, not HTML. Badge text is `String(n)` or `"99+"`. [Source: `SECURITY.md` — Network]

### Visual reference

Do **not** copy notification-center’s archive/DND service. Copy only the Count pill metrics and colors from `~/.config/omarchy/plugins/jankeesvw.notification-center/Panel.qml` (approx. lines 357–381): overlay on the icon, accent fill, background text, `99+`.

Existing `hasNew` dot in `BarWidget.qml` (6×6, `Color.accent`, top-right, visible when `hasNew && !opened`) stays for feed-only novelty.

### Testing standards

No QML test runner in this repo (Tesla documents the same in `tests/MANUAL.md`). Automated coverage is bash + fixtures + stub `curl`.

Tesla rules that apply here:

- Never source the production script in a way that executes commands at import; invoke `bin/tinkerer` as a process.
- Isolate dirs / PATH.
- Record curl argv.
- One JSON line on stdout for success paths.
- Fail the script if any case fails.

Helper `fail` exits 0. Tests must assert JSON, not a non-zero exit, for API errors.

Do not run live `bin/tinkerer notifications unread` as a required CI/story check. Optional manual only.

### Security (non-negotiable)

- Key file default: `~/.config/omarchy/secrets/tinkerer-club-api-key`, mode 600. [Source: `README.md`, `SECURITY.md`, Story 0.4]
- QML never reads the key. Empty `apiKeyFile` setting means the helper default path.
- Do not put the key in the repo, `shell.json`, QML, fixtures, or issue text. Tests use a temp file containing `test-key-not-real` or similar.
- Send raw key as `x-api-key`. No `Bearer`.
- HTTP only for localhost. Default origin stays `https://app.tinkerer.club`.

### Git intelligence

Recent commits on this repo (do not commit this story unless asked):

- `24afb7d` Add BMAD epics, sprint status, and Benji story map.
- `4b246f2` Install BMAD Method for plugin planning and implementation.
- `44b4452` Add Tinkerer Club Omarchy bar plugin scaffold.

Patterns: imperative title + why paragraph; plugin surface is `manifest.json`, `BarWidget.qml`, `Panel.qml`, `bin/tinkerer`, `README.md`, `SECURITY.md`. No test tree yet — this story introduces `tests/`. Stay on `epic-2/notifications`. Do not push.

The enabled checkout `~/.config/omarchy/plugins/dneighbors.tinkerer-club/` is a **separate clone** (https remote, typically `main`). Implement in `{project-root}` `/home/dneighbors/Public/omarchy-plugin-tinkerer-club`. QML hot-reload applies only to the enabled plugin directory.

### Latest tech notes (2026-09-14 OpenAPI pull)

- Spec: OpenAPI 3.1.0, title “Tinkerer Club Platform API”, version 1.0.0, cached at `/tmp/tinkerer-openapi.json`.
- Auth: `components.securitySchemes.apiKey` — header `x-api-key`, member key from Settings.
- Related later endpoints (do not call now):
  - `POST /api/v1/notification/list` body `{cursor?, limit? 1–50}`
  - `POST /api/v1/notification/markRead` body `{id}` required
  - `POST /api/v1/notification/markAllRead` body `{}`
- Feed already uses the same POST-`/api/v1/{router}/{procedure}` convention (`post/timeline`).

### Project Structure Notes

```
/home/dneighbors/Public/omarchy-plugin-tinkerer-club/
  bin/tinkerer                 # CHANGE: notifications unread + unwrap_count
  BarWidget.qml                # CHANGE: unreadCount + count pill + tooltip + dot priority
  Panel.qml                    # CHANGE: unreadCount, unreadProc, applyUnread, timer/refresh hook
  manifest.json                # DO NOT add settings
  README.md                    # CHANGE: one Usage sentence
  SECURITY.md                  # DO NOT weaken
  tests/unread.sh              # NEW
  tests/fixtures/unread-*.json # NEW
  _bmad-output/implementation-artifacts/2-1-unread-count.md  # this file
```

Naming: plugin id `dneighbors.tinkerer-club`. Helper name `tinkerer`. Command is `notifications unread` (epic AC), not `unread` alone.

Variance: Tesla keeps jq in `bin/place.jq`. This plugin inlines jq in `bin/tinkerer` (`unwrap_items`). Keep count unwrap inline unless extracting both would be a drive-by refactor — do not refactor feed unwrap in this story.

### References

- [Source: `_bmad-output/planning-artifacts/epics.md` — Epic 2, Story 2.1]
- [Source: `_bmad-output/planning-artifacts/epics.source.yaml` — epic 2 / story 2.1]
- [Source: `_bmad/bmm/config.yaml` — project_name `omarchy-plugin-tinkerer-club`, user_name Derek]
- [Source: `docs/benji-map.yaml` — story 2.1 id `9e45c450-5a32-440f-af1f-f737d03f091f`, epic `5fadc0f9-085b-414a-bb0c-10068a84c93b`]
- [Source: `bin/tinkerer` — `api_call`, `unwrap_items`, `cmd_feed`, `cmd_status`, `fail` exit 0]
- [Source: `BarWidget.qml` — `hasNew` dot, `IpcHandler`, lobster `\ud83e\udd9e`]
- [Source: `Panel.qml` — `cmd()`, `Timer`, `feedProc`, `statusProc`, `hasNew`]
- [Source: `manifest.json` — defaults `apiKeyFile`, `baseUrl`, `refreshMinutes`]
- [Source: `README.md` — key file setup, Usage]
- [Source: `SECURITY.md` — key file, no print, HTTPS, untrusted remote text]
- [Source: `/tmp/tinkerer-openapi.json` — `notification.unreadCount` / `list` / `markRead` / `markAllRead`]
- [Source: `~/.config/omarchy/plugins/jankeesvw.tesla/tests/place.sh` — fixture + stub curl]
- [Source: `~/.config/omarchy/plugins/jankeesvw.notification-center/Panel.qml` — Count badge]

## Dev Agent Record

### Context Reference

<!-- Path(s) to story context XML will be added here by context workflow -->

### Agent Model Used

Cursor Grok 4.6 (Amelia / bmad-story-dev)

### Debug Log References

- RED: `tests/unread.sh` failed with `Unknown command: notifications` before helper dispatch existed.
- GREEN blocker: `fail` exits 0, so `key="$(read_api_key)"` swallowed missing-key / 401 and continued. `read_api_key` now nameref-writes into `api_call`; `unwrap_count` passes through `{ok:false}` envelopes.

### Completion Notes List

- AC1/4/5: `bin/tinkerer notifications unread` → POST `/api/v1/notification/unreadCount` body `{}`. `unwrap_count` accepts bare / wrapped / string / negative→0. `fail` still exit 0.
- AC2/3/5: `Panel.qml` `unreadProc` + idle timer + post-`applyFeed` refresh. Badge overlay; `hasNew` hidden while pill visible.
- AC6: `tests/unread.sh` stub curl, temp key `test-key-not-real-SECRET99`, no live origin. Post-review suite green.
- Review F1–F7 applied: idle `applyStatus` starts unread, `applyFeed` unread only when open, extra AC4 cases, badge-priority and POST `{}` asserts, README dot/badge wording.
- `omarchy plugin validate .` exit 0. No new manifest key. 5.5 not run (optional live / installed clone).

### File List

- `/home/dneighbors/Public/omarchy-plugin-tinkerer-club/bin/tinkerer`
- `/home/dneighbors/Public/omarchy-plugin-tinkerer-club/BarWidget.qml`
- `/home/dneighbors/Public/omarchy-plugin-tinkerer-club/Panel.qml`
- `/home/dneighbors/Public/omarchy-plugin-tinkerer-club/README.md`
- `/home/dneighbors/Public/omarchy-plugin-tinkerer-club/tests/unread.sh`
- `/home/dneighbors/Public/omarchy-plugin-tinkerer-club/tests/fixtures/unread-bare-number.in.json`
- `/home/dneighbors/Public/omarchy-plugin-tinkerer-club/tests/fixtures/unread-bare-number.out.json`
- `/home/dneighbors/Public/omarchy-plugin-tinkerer-club/tests/fixtures/unread-count-object.in.json`
- `/home/dneighbors/Public/omarchy-plugin-tinkerer-club/tests/fixtures/unread-count-object.out.json`
- `/home/dneighbors/Public/omarchy-plugin-tinkerer-club/tests/fixtures/unread-data-wrapped.in.json`
- `/home/dneighbors/Public/omarchy-plugin-tinkerer-club/tests/fixtures/unread-data-wrapped.out.json`
- `/home/dneighbors/Public/omarchy-plugin-tinkerer-club/tests/fixtures/unread-result-data.in.json`
- `/home/dneighbors/Public/omarchy-plugin-tinkerer-club/tests/fixtures/unread-result-data.out.json`
- `/home/dneighbors/Public/omarchy-plugin-tinkerer-club/tests/fixtures/unread-zero.in.json`
- `/home/dneighbors/Public/omarchy-plugin-tinkerer-club/tests/fixtures/unread-zero.out.json`
- `/home/dneighbors/Public/omarchy-plugin-tinkerer-club/tests/fixtures/unread-string-count.in.json`
- `/home/dneighbors/Public/omarchy-plugin-tinkerer-club/tests/fixtures/unread-string-count.out.json`
- `/home/dneighbors/Public/omarchy-plugin-tinkerer-club/tests/fixtures/unread-empty.in.json`
- `/home/dneighbors/Public/omarchy-plugin-tinkerer-club/tests/fixtures/unread-401.in.json`
- `/home/dneighbors/Public/omarchy-plugin-tinkerer-club/_bmad-output/implementation-artifacts/2-1-unread-count.md`
- `/home/dneighbors/Public/omarchy-plugin-tinkerer-club/_bmad-output/implementation-artifacts/sprint-status.yaml`

## Senior Developer Review (AI)

7 findings. CHANGES_REQUESTED. No criticals.

- F1 HIGH AC2: idle first cycle never fetched unread
- F2 HIGH AC5: hasNew grep did not require `unreadCount <= 0`
- F3 HIGH AC4: empty key / 403 / network untested
- F4 MEDIUM: idle path double-fetched unread
- F5 MEDIUM: POST body `{}` untested
- F6 MEDIUM: README implied both markers
- F7 LOW: story status still ready-for-dev

## Review Follow-ups (AI)

- [x] F1 After `applyStatus`, if configured and panel closed, call `refreshUnread()`
- [x] F2 Assert hasNew visibility includes `unreadCount <= 0` and unread badge is idle-only
- [x] F3 Empty key file, 403, curl-fail cases; every `ok:false` has `error` and `hint`
- [x] F4 `applyFeed` calls `refreshUnread` only when opened
- [x] F5 Assert `--data {}` on unread POSTs
- [x] F6 README: unread badge replaces the feed-newness dot while count > 0
- [x] F7 Story status `done`; sprint-status on File List

## Change Log

- 2026-09-14: Implemented unread helper, idle badge, and fixture tests
- 2026-09-14: Applied review F1–F7
