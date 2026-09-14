# Story 2.2: Notification list

Status: done

<!-- Note: Validation is optional. Run validate-create-story for quality check before dev-story. -->

## Story

As a **member**,
I want **the panel to list `notification.list` items**,
so that **I can read them without leaving the bar**.

## Acceptance Criteria

1. **Given** a valid key file
   **When** `bin/tinkerer notifications list` runs
   **Then** it POSTs to `/api/v1/notification/list` with `x-api-key` and a JSON body `{limit:<int 1–50>}` (no `cursor` this story), and prints one JSON object `{ok:true, notifications:[…]}`. Each item has string keys `id`, `sender`, `title`, `createdAt`, `url`.

2. **Given** notifications exist
   **When** I open the panel and switch to the Notifications view
   **Then** each row lists sender, title, and age (from `createdAt` via existing `relativeTime`).

3. **Given** a notification whose helper `url` is a non-empty `http`/`https` URL
   **When** I click that row
   **Then** the existing `openUrl` path runs `xdg-open` on that URL.

4. **Given** a notification with an empty `url`
   **When** I click that row
   **Then** no browser process starts. The row still lists sender, title, and age.

5. **Given** a missing key, empty key, 401/403, network failure, or a non-JSON payload
   **When** `bin/tinkerer notifications list` runs
   **Then** stdout is one JSON object `{ok:false, error, hint}` (hint may be empty), the process exits 0 (same as `fail` today), and the raw API key never appears in stdout or stderr.

6. **Given** `status`, `feed`, and `notifications unread` already work
   **When** this story lands
   **Then** those commands, the feed list, Refresh-on-feed, the Story 1.3 `hasNew` dot, and the Story 2.1 unread pill still behave as they do now. Opening the Notifications view does **not** call `notification.markRead` or `notification.markAllRead` and does **not** change `unreadCount`.

7. **Given** tests under `tests/`
   **When** `tests/list.sh` and `tests/unread.sh` run
   **Then** both pass with no live API key, no network, and no files matching `.gitignore` key patterns committed.

## Tasks / Subtasks

- [x] **Task 1 — Helper command `notifications list`** (AC: 1, 5, 6)
  - [x] 1.1 Extend `usage()` in `bin/tinkerer` with `notifications list     Recent notifications as JSON.` Keep `notifications unread`. Do **not** add `mark`, `markRead`, `markAllRead`, or any other `notifications` subcommand.
  - [x] 1.2 Dispatch two tokens. After option parsing, `$1` is `notifications` and `$2` is `list`. Do not `shift` globally. Empty or unknown subcommand uses existing `fail` and names the bad command (today: `Unknown command: notifications` / `Unknown command: $2`).
  - [x] 1.3 Add `cmd_notifications_list` that calls existing `api_call "notification/list" "<body>"`. Reuse `--base-url`, `--key-file`, `--limit`, HTTPS-unless-localhost, 15s timeout, User-Agent, `x-api-key`. Do not add a new flag.
  - [x] 1.4 Build the POST body with jq as `{limit:$n}` only. Clamp `$feed_limit` to OpenAPI bounds: `n = feed_limit`; if `n < 1` then `1`; if `n > 50` then `50`. Do **not** send `cursor`. Do **not** send `additionalProperties` keys. Default `--limit` stays 20 (same as feed).
  - [x] 1.5 Add `unwrap_notifications` (jq, same style as `unwrap_items` / `unwrap_count`) that unwraps `result` / `data` / `json` wrappers, then reads an array from a bare array or object keys `items`, `notifications`, `results` in that order. Skip non-objects and objects with no usable `id`/`notificationId`. Do not overload `unwrap_items`.
  - [x] 1.6 Normalize each kept item to exactly:
        `{id, sender, title, createdAt, url}`
        all strings. See Dev Notes for key order and fallbacks. Print `{ok:true, notifications:[…]}` compact JSON, one line. Pass through `{ok:false}` envelopes from `api_call`/`fail`.
  - [x] 1.7 `url` is empty unless it resolves to `http://` or `https://` (absolute, or relative joined to the validated origin). Do **not** invent `/posts/{id}` (feed-only fallback).
  - [x] 1.8 Never print the key. Do not call `notification/unreadCount`, `notification/markRead`, or `notification/markAllRead` from this command.

- [x] **Task 2 — Fixture tests for the helper** (AC: 1, 4, 5, 6, 7)
  - [x] 2.1 Create `tests/list.sh` using `tests/unread.sh` + Tesla `~/.config/omarchy/plugins/jankeesvw.tesla/tests/place.sh`: `set -euo pipefail`, `pass`/`bad`, PATH-injected stub `curl`, temp `--key-file`, invoke `bin/tinkerer` as a process (never source it).
  - [x] 2.2 Create fixtures under `tests/fixtures/` (see Dev Notes for exact shapes):
        `list-items-array.in.json` / `.out.json`
        `list-notifications-key.in.json` / `.out.json`
        `list-data-wrapped.in.json` / `.out.json`
        `list-result-data.in.json` / `.out.json`
        `list-actor-nested.in.json` / `.out.json`
        `list-target-url.in.json` / `.out.json`
        `list-relative-url.in.json` / `.out.json`
        `list-empty.in.json` / `.out.json`
        `list-no-url.in.json` / `.out.json`
        `list-skip-no-id.in.json` / `.out.json`
        `list-unusable.in.json` (treat as success empty list)
        `list-401.in.json`
  - [x] 2.3 Stub `curl` must append argv to a log, print fixture body, then a newline and HTTP code (`200` or `401`) because `api_call` uses `curl -w '\n%{http_code}'`.
  - [x] 2.4 Assert the stub was called with `-X POST`, URL ending `/api/v1/notification/list`, `Content-Type: application/json`, `x-api-key` present, and `--data` containing `"limit"` (integer 1–50). Helper stdout/stderr must not contain the temp key value. Must not hit `app.tinkerer.club`. Must not call `notification/unreadCount`, `notification/markRead`, or `notification/markAllRead`.
  - [x] 2.5 Cases: each successful fixture → `{ok:true, notifications:[…]}` with required string keys; empty / unusable → `{ok:true, notifications:[]}`; 401 → auth error mentioning the key file, not the key; 403; empty key file (no curl); network fail; missing key file (no curl); unknown `notifications` subcommand `frob` and `mark` / `markRead` → `{ok:false}`, no curl; `notifications unread` still hits `unreadCount` only; `status` still reports `configured` without curl; `feed` still hits `post/timeline` only.
  - [x] 2.6 Clamp: `--limit 0` and `--limit 99` still POST a body whose `limit` is 1 and 50 respectively.
  - [x] 2.7 QML source assertions (no QML runner): Notifications view switcher, `listProc`, `notifications` model, sender/title/`relativeTime`, click → `openUrl`, no `markRead`/`markAllRead` strings in `bin/tinkerer` / `Panel.qml` / `BarWidget.qml`. Feed + unread contracts from `tests/unread.sh` remain. Run `tests/unread.sh` from this script or document that both must pass.
  - [x] 2.8 Script exits 0 only when every case passed. No live `TINKERER` key. No `curl` to `app.tinkerer.club`.

- [x] **Task 3 — Panel notifications view** (AC: 2, 3, 4, 6)
  - [x] 3.1 In `Panel.qml` add `property string panelView: "feed"` (`"feed"` | `"notifications"`) and `property var notifications: []`. Default remains feed so Stories 1.2 / 1.4 do not regress.
  - [x] 3.2 Add a dedicated `Process` `listProc` (do not reuse `feedProc` / `statusProc` / `unreadProc`). Command: `root.cmd(["notifications", "list"])`.
  - [x] 3.3 Add `applyNotifications(data)`: if `data.ok === true` and `notifications` is an array, replace `root.notifications` with that array and, **only when `panelView === "notifications"`**, clear `errorText`/`statusHint` the same way `applyFeed` does on success. If `ok !== true` and `panelView === "notifications"`, set `errorText`/`statusHint` from the envelope; do not clear `posts` or `unreadCount`. If the panel is closed, do not write list failures into `errorText`.
  - [x] 3.4 Add `refreshNotifications()` that starts `listProc` only when not already running. Include `listProc.running` in `busy`.
  - [x] 3.5 Add a Feed | Notifications switcher in the header (two `WidgetButton`s or equivalent text controls). Active view is visually distinct (bold or accent). Switching to `notifications` calls `refreshNotifications()`. Switching to `feed` shows the existing feed list; do not refetch feed on every tab click if `posts` already loaded.
  - [x] 3.6 `refresh()` stays feed-first when `panelView === "feed"`. When `panelView === "notifications"`, Refresh (and IPC `refresh()` via existing `panelItem.refresh`) calls `refreshNotifications()` instead. Do not block one view on the other.
  - [x] 3.7 `onOpenedChanged`: keep today’s feed/`checkStatus`/`markSeen` behavior. Do **not** auto-switch to Notifications when `unreadCount > 0`. Do **not** fetch the list while the panel is closed. Idle `Timer` stays feed + unread only (Story 2.1).
  - [x] 3.8 Notifications `Flickable` + `Repeater` mirrors the feed row: muted sender, body title (`plain(snippet(title, 90))`, fallback `"Notification"` if empty after normalize), caption `relativeTime(createdAt)`. Reuse `plain`, `snippet`, `relativeTime`, hover fill, `Text.PlainText` or `plain()` so remote text is never HTML. Visible when `panelView === "notifications"` and `notifications.length > 0`.
  - [x] 3.9 Click: `onClicked: root.openUrl(modelData.url)` — `openUrl` already no-ops on a falsy url. Do not call mark-read. Do not change `unreadCount`.
  - [x] 3.10 Empty copy when `panelView === "notifications" && configured && notifications.length === 0 && !busy && errorText === ""`: `"No notifications yet."` Hide feed empty copy and feed list while on the notifications view (and vice versa).
  - [x] 3.11 Do not add mark-read buttons, per-row unread styling, cursor pagination, a new `manifest.json` setting, or BarWidget badge changes.

- [x] **Task 4 — Click-to-open URL contract** (AC: 3, 4, 6)
  - [x] 4.1 Reuse `openUrl` + `browserProc` + `xdg-open`. Do not add a second browser process.
  - [x] 4.2 Helper emits `url: ""` when there is no safe target. QML must not concatenate `baseUrl` onto an empty url.
  - [x] 4.3 Do not `xdg-open` `javascript:`, `file:`, or other non-http(s) schemes — helper must not emit them. QML may keep today’s `if (!url) return`.
  - [x] 4.4 `tests/list.sh` asserts relative `/posts/abc` becomes `https://<test-origin>/posts/abc` and that a missing/non-http url becomes `""`.

- [x] **Task 5 — Docs, validate, no secrets** (AC: 1, 6, 7)
  - [x] 5.1 README Usage: one or two sentences that the panel has Feed and Notifications, and that a notification row with a target URL opens in the browser. Do not document `notification.markRead` / `markAllRead`.
  - [x] 5.2 Do not mention a real key. Do not add files matching `.gitignore` (`*api-key*`, `*apikey*`, `*token*`, `.env`).
  - [x] 5.3 Run `omarchy plugin validate .` from repo root after QML/manifest-adjacent edits. Manifest defaults stay as they are; no new schema key. Reuse `feedLimit` as the list page size.
  - [x] 5.4 Run `tests/list.sh` and `tests/unread.sh`. Confirm `status`, `feed`, and `notifications unread` dispatch still exist in `bin/tinkerer`.
  - [ ] 5.5 Manual (not required to mark the story done): with a local key file, `bin/tinkerer notifications list` against the real origin; reload the enabled plugin (`~/.config/omarchy/plugins/dneighbors.tinkerer-club/` is a separate clone — copy or pull before judging the panel).

## Dev Notes

Ultimate context engine analysis completed — comprehensive developer guide created.

There is no `architecture.md`, `prd.md`, or `ux-design-specification.md`. Do not invent them. The plugin + OpenAPI are the contract: QML never holds the member key; `bin/tinkerer` is the only reader.

### Product intent

Epic 2 goal: unread club notifications on the bar, then a list and mark-read. Story 2.1 (DONE on `epic-2/notifications`) is the idle count badge. Story 2.2 is the list + click-through. Story 2.3 (mark-read) is **out of scope** — do not add helper commands, QML buttons, or API calls for `notification.markRead` / `notification.markAllRead`. [Source: `_bmad-output/planning-artifacts/epics.md` — Epic 2]

Dependencies: Epic 0 (key file + helper), Epic 1 (feed panel + `openUrl` + `relativeTime`), Story 2.1 (`notifications` dispatch + unread badge). Epic 1 stories are still `in-progress` in sprint-status. Treat feed + unread behavior as already shipped in this tree and do not regress them.

The feed is what happened. Notifications are what wants you. Members must be able to read sender / title / age in the bar and open a target URL without leaving the panel.

### Out of scope (Story 2.3 and later)

- `notification.markRead`, `notification.markAllRead`
- Clearing or decrementing `unreadCount` when the list opens or a row is clicked
- Per-row read/unread styling, “Mark all read”, swipe-to-dismiss
- Cursor / next-page / infinite scroll (OpenAPI `cursor` exists; do not send it)
- New manifest settings (no `notificationLimit`, no badge-style enum)
- Auto-switching to Notifications because `unreadCount > 0`
- Changing BarWidget lobster glyph, pill metrics, or tooltip (2.1 stays)

### Locked UX / contract decisions (do not reopen)

| Decision | Choice | Why |
|---|---|---|
| Command name | `notifications list` | Matches shipped `notifications unread`; epic names `notification.list`. |
| Notifications view | In-panel `panelView` toggle Feed \| Notifications | Epic AC says “open the notifications view”, not a second window. Default `feed`. |
| Open panel | Stay on feed; do not auto-jump | AC is the view, not “open panel when badged”. |
| List fetch | Only when Notifications is selected (or Refresh/IPC while on that view) | Idle timer stays 2.1 unread + quiet feed. |
| Row fields | sender, title, age | Epic AC 1. Age = existing `relativeTime(createdAt)`. |
| Click | `xdg-open` via existing `openUrl` if `url` non-empty | Epic AC 2. Empty url = list but no navigation. |
| URL fallback | None | Feed invents `/posts/{id}`. Notifications are not posts. |
| Limit | Reuse `--limit` / `feedLimit`, clamp 1–50 in the list body | OpenAPI max 50; no new setting. |
| Pagination | First page only | No cursor UI this story. |
| List errors | Same `{ok:false,error,hint}` + exit 0 | QML always gets a parseable line. |
| Empty list | Success `{ok:true, notifications:[]}` + “No notifications yet.” | Empty club ≠ helper failure. |
| Unusable payload (`{}`, no array) | Success empty list | List unwrap follows feed (`[]`), not unread (`fail`). |
| `read` / `unread` fields from API | Ignore | Story 2.3. |
| Two Process objects | New `listProc` | One `Process` cannot run two commands. |

### Helper architecture (must follow)

File: `bin/tinkerer`

Current commands after Story 2.1: `status`, `feed`, `notifications unread`. Shared pieces the new command must reuse:

- `DEFAULT_BASE_URL=https://app.tinkerer.club`
- `DEFAULT_KEY_FILE=${XDG_CONFIG_HOME:-$HOME/.config}/omarchy/secrets/tinkerer-club-api-key`
- `USER_AGENT=omarchy-plugin-tinkerer-club/0.1.0 (+https://github.com/dneighbors/omarchy-plugin-tinkerer-club)`
- `validate_base_url` — HTTPS required except `localhost` / `127.0.0.1` / `[::1]`
- `read_api_key` — first line, trim, never echo; nameref into `api_call` (2.1 lesson: `key="$(read_api_key)"` swallowed `fail` because `fail` exits 0)
- `api_call <procedure> <body>` — `POST ${origin}/api/v1/${procedure}`, headers `Accept`, `Content-Type: application/json`, `User-Agent`, `x-api-key`, `--max-time 15`, parses trailing HTTP code
- `fail` / `json_error` — `{ok:false,error,hint}`, **exit 0** so QML always gets a parseable line
- `unwrap_items` — feed-only; do not overload it
- `unwrap_count` — unread-only; do not overload it
- `--limit` already parsed into `feed_limit` (default 20). Reuse it. Do not add `--cursor`.

Wire format for this story:

```
POST /api/v1/notification/list
Headers: Accept: application/json, Content-Type: application/json, User-Agent: <existing>, x-api-key: <file>
Body: {"limit":20}
```

[Source: `/tmp/tinkerer-openapi.json` and live `https://app.tinkerer.club/api/v1/openapi.json` — `POST /api/v1/notification/list`, operationId `notification_list`, request `{cursor?: string, limit?: integer 1–50, additionalProperties: false}`, security `apiKey` header `x-api-key`]

OpenAPI 200 schema is only `{ data: {}, path: string }` — `data` is untyped. Live payloads may be tRPC-shaped (`result.data`, `result.data.json`). `unwrap_notifications` MUST accept the fixtures below and emit the matching `.out.json`.

Normalized item (always these five string keys, this order):

```json
{"id":"n1","sender":"Kitze","title":"Commented on your post","createdAt":"2026-09-14T12:00:00.000Z","url":"https://app.tinkerer.club/posts/abc"}
```

Field mapping (first non-empty string wins). Mirror Raycast `src/lib/feed.ts` + `src/lib/results.ts` plus the epic’s word **sender**:

| Output | Source keys / objects |
|---|---|
| `id` | `id`, `notificationId` — required or skip the item |
| `sender` | Nested object `sender` / `actor` / `from` / `user` / `member` / `author` → `name`, `displayName`, `username`, `handle`. Else flat `senderName`, `actorName`, `fromName`, `authorName`. Else `"Tinkerer"` |
| `title` | `title`, `headline`, `message`, `body`, `content`, `text`, `summary`. Else `"Notification"` |
| `createdAt` | `createdAt`, `publishedAt`, `sentAt`, `timestamp`, `date`, `updatedAt`. Else `""` |
| `url` | `href`, `url`, `webUrl`, `permalink`, `targetUrl`, `link`. Else nested object `target` → those same keys. Resolve with the same `http`/`https` (or origin + relative path) rule as `unwrap_items` `resolve`. Else `""` |

Collection after unwrap: if the payload is an array, use it. If object, `items` then `notifications` then `results`. Otherwise `[]`.

Pass through `{ok:false}` the same way `unwrap_count` does (`if type == "object" and .ok == false then .`).

Suggested jq (adapt to match `unwrap_items` quoting style; keep it inside the script, no extra `.jq` file):

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
def sender($item):
  ([$item.sender, $item.actor, $item.from, $item.user, $item.member, $item.author]
    | map(select(type == "object")) | .[0] // {}) as $src
  | (text($src; ["name","displayName","username","handle"])
      // text($item; ["senderName","actorName","fromName","authorName"])
      // "Tinkerer");
def resolve($value):
  if ($value | type) != "string" or $value == "" then empty
  else
    if ($value | test("^https?://")) then $value
    elif ($value | test("^[a-zA-Z][a-zA-Z0-9+.-]*:")) then empty
    else ($origin + "/" + ($value | ltrimstr("/"))) end
  end;
def item_url($item):
  (text($item; ["href","url","webUrl","permalink","targetUrl","link"])) as $direct
  | (if ($item.target | type) == "object" then
       text($item.target; ["href","url","webUrl","permalink","targetUrl","link"])
     else "" end) as $nested
  | ([ $direct, $nested ] | map(select(. != "")) | .[0] // "") as $raw
  | ([$raw] | map(resolve(.)) | .[0] // "");
def items:
  (unwrap) as $p
  | if ($p | type) == "array" then $p
    elif ($p | type) == "object" then
      ($p.items // $p.notifications // $p.results // [])
    else [] end;
{
  ok: true,
  notifications: [
    items[]
    | select(type == "object")
    | . as $item
    | (text($item; ["id","notificationId"])) as $id
    | select($id != "")
    | {
        id: $id,
        sender: sender($item),
        title: (text($item; ["title","headline","message","body","content","text","summary"]) // "Notification"),
        createdAt: text($item; ["createdAt","publishedAt","sentAt","timestamp","date","updatedAt"]),
        url: item_url($item)
      }
  ]
}
```

CLI examples:

```sh
bin/tinkerer notifications list
bin/tinkerer --key-file /tmp/fake-key --base-url https://app.tinkerer.club --limit 20 notifications list
```

### Fixture shapes (lock these)

Base origin in tests: `https://list.test.invalid` (must not appear as a live call). Temp key: `test-key-not-real-SECRET99` (same distinctive dummy as `tests/unread.sh`).

`list-items-array.in.json` — bare array:

```json
[{"id":"n1","sender":{"name":"Kitze"},"title":"Welcome","createdAt":"2026-09-14T12:00:00.000Z","url":"https://app.tinkerer.club/posts/abc"}]
```

`.out.json`:

```json
{"ok":true,"notifications":[{"id":"n1","sender":"Kitze","title":"Welcome","createdAt":"2026-09-14T12:00:00.000Z","url":"https://app.tinkerer.club/posts/abc"}]}
```

`list-notifications-key.in.json` — `{notifications:[…]}` with flat `senderName`.

`list-data-wrapped.in.json` — `{data:{items:[…]}}`.

`list-result-data.in.json` — `{result:{data:{items:[…]}}}` (tRPC).

`list-actor-nested.in.json` — `actor.displayName` + `headline` + `publishedAt` (no `sender`/`title`/`createdAt`).

`list-target-url.in.json` — `target.url` only (no top-level url).

`list-relative-url.in.json` — `href: "/posts/abc"` → `url` is `https://list.test.invalid/posts/abc`.

`list-empty.in.json` — `{items:[]}` → `{ok:true,notifications:[]}`.

`list-no-url.in.json` — valid id/sender/title/createdAt, no url keys → `url:""`. Still listed.

`list-skip-no-id.in.json` — one object without id plus one with id → only the id’d item.

`list-unusable.in.json` — `{}` → `{ok:true,notifications:[]}`.

`list-401.in.json` — any JSON body; HTTP 401.

Also assert inline (no extra fixture required): `javascript:alert(1)` and `file:///etc/passwd` as `url` → emitted `url` is `""`.

### QML architecture (must follow)

`BarWidget.qml` hosts `Panel.qml` via `Loader`, injects `bar` / `settings` / `anchorItem` / `hostWidget`, and mirrors panel state (`opened`, `hasNew`, `unreadCount`). IPC target: `dneighbors.tinkerer-club`. Existing IPC `refresh()` calls `panelItem.refresh()`. **Change `refresh()` in Panel so it is view-aware.** Do not add new IPC methods. Do not change BarWidget badge/tooltip unless a grep assertion would otherwise break — they should not need edits.

`Panel.qml` builds helper argv with `cmd(args)`:

```qml
[script, "--base-url", baseUrl, "--limit", feedLimit, optional "--key-file", apiKeyFile, ...args]
```

List argv is therefore `cmd(["notifications", "list"])`.

`Process` + `StdioCollector` + `JSON.parse` in `try/catch` is the only I/O pattern. Fourth process: `listProc`.

Remote club text is untrusted. Sender and title go through `plain()` (strips `<>`). Do not assign remote strings to QML/JS eval. [Source: `SECURITY.md` — Network]

Visual: copy the **feed row** in `Panel.qml` (author / snippet / age), not notification-center’s archive/DND service. Switcher sits in the existing header `RowLayout` next to the title / Refresh. Keep “Open Tinkerer Club” at the bottom on both views.

`openUrl` today:

```qml
function openUrl(url) {
  if (!url) return
  browserProc.command = ["xdg-open", String(url)]
  browserProc.running = true
}
```

Reuse it. Helper is responsible for refusing non-http(s).

### Raycast field-name research (2026-09-14)

Unofficial extension [Olli0103/tinkerer-club](https://github.com/Olli0103/tinkerer-club) (Raycast, MIT) has **no** `notification.list` command, types, or tests. Useful reuse is the generic unwrap + display mapping:

- `src/lib/json.ts` `unwrapPayload`: `result.data.json` → `result.data` → `data` → `json`
- `src/lib/feed.ts` `parseAuthor`: nested `author`/`user`/`member`; name `name`/`displayName`/`username`; URLs only `http`/`https`
- `src/lib/results.ts`: title `title`/`name`/`displayName`; url `url`/`href`/`webUrl`/`permalink`; collections `items`/`results`

Do not copy Raycast UI, AI tools, or comment/react mutations. Auth is the same: raw `x-api-key`, no `Bearer`, default origin `https://app.tinkerer.club`.

### Previous story learnings (2.1)

- `fail` exits 0 — tests assert JSON, not a non-zero exit. Do not write `key="$(read_api_key)"`.
- `tests/unread.sh` already forbids extra `notifications` commands in `-h`. **Update that assertion**: usage may list `notifications list` and `notifications unread` only. Keep the ban on `mark`.
- Idle unread + badge-over-dot stay. List must not start `unreadProc` except through existing 2.1 paths.
- Enabled checkout `~/.config/omarchy/plugins/dneighbors.tinkerer-club/` is a **separate clone**. Implement here: `/home/dneighbors/Public/omarchy-plugin-tinkerer-club`.

### Testing standards

No QML test runner (Tesla `tests/MANUAL.md` same constraint). Automated coverage is bash + fixtures + stub `curl` + QML source greps.

Tesla / unread.sh rules that apply:

- Never source the production script in a way that executes commands at import; invoke `bin/tinkerer` as a process.
- Isolate dirs / PATH.
- Record curl argv.
- One JSON line on stdout for success paths.
- Fail the script if any case fails.

Do not run live `bin/tinkerer notifications list` as a required CI/story check. Optional manual only (Task 5.5).

### Security (non-negotiable)

- Key file default: `~/.config/omarchy/secrets/tinkerer-club-api-key`, mode 600. [Source: `README.md`, `SECURITY.md`, Story 0.4]
- QML never reads the key. Empty `apiKeyFile` setting means the helper default path.
- Do not put the key in the repo, `shell.json`, QML, fixtures, or issue text. Tests use a temp file containing `test-key-not-real-SECRET99` or similar.
- Send raw key as `x-api-key`. No `Bearer`.
- HTTP only for localhost. Default origin stays `https://app.tinkerer.club`.
- Do not `xdg-open` a remote-provided non-http(s) URL. Do not treat title/sender as a command.

### Git intelligence

Recent commits (do not commit this story unless asked):

- `34eb897` feat(epic-2): Unread notification count (Story 2-1-unread-count)
- `24afb7d` Add BMAD epics, sprint status, and Benji story map.
- `4b246f2` Install BMAD Method for plugin planning and implementation.
- `44b4452` Add Tinkerer Club Omarchy bar plugin scaffold.

Patterns: imperative title + why paragraph; plugin surface is `manifest.json`, `BarWidget.qml`, `Panel.qml`, `bin/tinkerer`, `README.md`, `SECURITY.md`, `tests/`. Stay on `epic-2/notifications`. Do not push. Do not implement this story in the same turn as creating it.

### Latest tech notes (2026-09-14)

- Spec: OpenAPI 3.1.0, title “Tinkerer Club Platform API”, version 1.0.0. Cached `/tmp/tinkerer-openapi.json` matches live `https://app.tinkerer.club/api/v1/openapi.json` for `notification.list` (request `cursor`/`limit` 1–50; 200 `data` untyped).
- Auth: `components.securitySchemes.apiKey` — header `x-api-key`.
- Related later endpoints (do not call now):
  - `POST /api/v1/notification/markRead` body `{id}` required
  - `POST /api/v1/notification/markAllRead` body `{}`
- Host tools used by the helper today: `jq` 1.8.2, `curl` 8.22.0. No new runtime deps. Do not add Node/Python to the plugin path.
- Raycast extension deps (`@raycast/api` 2.3.0, React 19.3) are irrelevant to this QML plugin except as a field-name reference.
- tRPC list payloads commonly wrap `{items, nextCursor}`. Unwrap `items`/`notifications`/`results`; ignore `nextCursor` this story.

### Project Structure Notes

```
/home/dneighbors/Public/omarchy-plugin-tinkerer-club/
  bin/tinkerer                 # CHANGE: notifications list + unwrap_notifications
  Panel.qml                    # CHANGE: panelView, notifications, listProc, switcher, rows
  BarWidget.qml                # DO NOT change unless a 2.1 grep would break (should not)
  manifest.json                # DO NOT add settings
  README.md                    # CHANGE: Feed / Notifications + click-to-open
  SECURITY.md                  # DO NOT weaken
  tests/list.sh                # NEW
  tests/unread.sh              # CHANGE: usage may include notifications list; still ban mark
  tests/fixtures/list-*.json   # NEW
  _bmad-output/implementation-artifacts/2-2-notification-list.md  # this file
```

Naming: plugin id `dneighbors.tinkerer-club`. Helper name `tinkerer`. Command is `notifications list` (epic AC), not `list` alone.

Variance: Tesla keeps jq in `bin/place.jq`. This plugin inlines jq in `bin/tinkerer`. Keep list unwrap inline. Do not refactor feed or unread unwrap in this story.

### References

- [Source: `_bmad-output/planning-artifacts/epics.md` — Epic 2, Story 2.2]
- [Source: `_bmad-output/planning-artifacts/epics.source.yaml` — epic 2 / story 2.2]
- [Source: `_bmad/bmm/config.yaml` — project_name `omarchy-plugin-tinkerer-club`, user_name Derek]
- [Source: `docs/benji-map.yaml` — story 2.2 id `a3d95cad-4ae0-427f-8d89-25971ccccd7c`, epic `5fadc0f9-085b-414a-bb0c-10068a84c93b`]
- [Source: `_bmad-output/implementation-artifacts/2-1-unread-count.md` — done helper/QML/test patterns]
- [Source: `bin/tinkerer` — `api_call`, `unwrap_items`, `unwrap_count`, `cmd_notifications_unread`, `fail` exit 0]
- [Source: `Panel.qml` — `cmd()`, `openUrl`, `relativeTime`, `plain`, `feedProc`, `unreadProc`, feed rows]
- [Source: `BarWidget.qml` — unread pill, `hasNew` priority, IPC `refresh()`]
- [Source: `manifest.json` — defaults `apiKeyFile`, `baseUrl`, `feedLimit`, `refreshMinutes`]
- [Source: `README.md` — key file setup, Usage]
- [Source: `SECURITY.md` — key file, no print, HTTPS, untrusted remote text]
- [Source: `/tmp/tinkerer-openapi.json` and live OpenAPI — `notification.list` / `unreadCount` / `markRead` / `markAllRead`]
- [Source: `https://github.com/Olli0103/tinkerer-club` — `src/lib/json.ts`, `src/lib/feed.ts`, `src/lib/results.ts` field names; no notification.list UI]
- [Source: `tests/unread.sh` — fixture + stub curl + QML greps]
- [Source: `~/.config/omarchy/plugins/jankeesvw.tesla/tests/place.sh` — fixture + stub curl]
- [Source: `_bmad/bmm/workflows/4-implementation/create-story/template.md` — missing in this install; used BMAD v6 `bmad-create-story/template.md` sections]

## Dev Agent Record

### Context Reference

<!-- Path(s) to story context XML will be added here by context workflow -->

### Agent Model Used

Cursor Grok 4.6 (Amelia / bmad-story-dev) — helper/fixtures (Tasks 1, 2.1–2.6, 2.8, 4.4) and QML (Tasks 3, 4.1–4.3)

### Debug Log References

- RED: `tests/list.sh` failed with `Unknown command: list` before helper dispatch existed.
- GREEN: jq `"" // fallback` does not treat empty string as empty; `sender`/`title` use explicit `!= ""` checks so flat `senderName` and missing title map correctly.
- `tests/unread.sh` fails `usage invented other notifications commands` — that script still bans `notifications list`. File ownership excluded `tests/unread.sh`; Task 2.7 / that file must allow list+unread and keep the mark ban.

### Completion Notes List

- AC1/5/6 helper: `bin/tinkerer notifications list` → POST `/api/v1/notification/list` body `{limit:N}` clamped 1–50, no cursor. `unwrap_notifications` accepts bare/items/notifications/results plus result/data/json wrappers. Empty/unusable → `{ok:true,notifications:[]}`. `{ok:false}` pass-through. `fail` still exit 0. No mark-read.
- AC4/5 URL: relative `/posts/abc` → `https://list.test.invalid/posts/abc`. Missing / `javascript:` / `file:` → `url:""`. Never invent `/posts/{id}`.
- AC7 tests: `tests/list.sh` 218 pass / 0 fail. Stub curl + temp key `test-key-not-real-SECRET99`. Task 2.7 QML greps left as comment placeholder.
- Task 3 + 4.1–4.3: `Panel.qml` adds `panelView` (default `"feed"`), `notifications`, dedicated `listProc`, `applyNotifications`, `refreshNotifications`, Feed | Notifications switcher (`WidgetButton.active` + accent), view-aware `refresh()`, notifications `Flickable`+`Repeater` (sender / `plain(snippet(title, 90))` fallback `"Notification"` / `relativeTime(createdAt)`), click → existing `openUrl`/`browserProc`. Idle `Timer` still calls `refreshFeed()` + unread only; `onOpenedChanged` unchanged (no auto-switch, no closed-panel list fetch). List errors write `errorText` only when `panelView === "notifications"` AND panel is open; success on that view clears `errorText`/`statusHint` like `applyFeed`. Does not touch `unreadCount`, mark-read, README, manifest, or BarWidget.
- QML-only work: no QML test runner in this repo. Tasks marked [x] after self-review against ACs 2, 3, 4, 6 in `Panel.qml`. Automated QML source assertions are Task 2.7 (other agent).
- Task 5 / 2.7 not this helper-agent group.

### File List

- `/home/dneighbors/Public/omarchy-plugin-tinkerer-club/bin/tinkerer`
- `/home/dneighbors/Public/omarchy-plugin-tinkerer-club/tests/list.sh`
- `/home/dneighbors/Public/omarchy-plugin-tinkerer-club/tests/fixtures/list-items-array.in.json`
- `/home/dneighbors/Public/omarchy-plugin-tinkerer-club/tests/fixtures/list-items-array.out.json`
- `/home/dneighbors/Public/omarchy-plugin-tinkerer-club/tests/fixtures/list-notifications-key.in.json`
- `/home/dneighbors/Public/omarchy-plugin-tinkerer-club/tests/fixtures/list-notifications-key.out.json`
- `/home/dneighbors/Public/omarchy-plugin-tinkerer-club/tests/fixtures/list-data-wrapped.in.json`
- `/home/dneighbors/Public/omarchy-plugin-tinkerer-club/tests/fixtures/list-data-wrapped.out.json`
- `/home/dneighbors/Public/omarchy-plugin-tinkerer-club/tests/fixtures/list-result-data.in.json`
- `/home/dneighbors/Public/omarchy-plugin-tinkerer-club/tests/fixtures/list-result-data.out.json`
- `/home/dneighbors/Public/omarchy-plugin-tinkerer-club/tests/fixtures/list-actor-nested.in.json`
- `/home/dneighbors/Public/omarchy-plugin-tinkerer-club/tests/fixtures/list-actor-nested.out.json`
- `/home/dneighbors/Public/omarchy-plugin-tinkerer-club/tests/fixtures/list-target-url.in.json`
- `/home/dneighbors/Public/omarchy-plugin-tinkerer-club/tests/fixtures/list-target-url.out.json`
- `/home/dneighbors/Public/omarchy-plugin-tinkerer-club/tests/fixtures/list-relative-url.in.json`
- `/home/dneighbors/Public/omarchy-plugin-tinkerer-club/tests/fixtures/list-relative-url.out.json`
- `/home/dneighbors/Public/omarchy-plugin-tinkerer-club/tests/fixtures/list-empty.in.json`
- `/home/dneighbors/Public/omarchy-plugin-tinkerer-club/tests/fixtures/list-empty.out.json`
- `/home/dneighbors/Public/omarchy-plugin-tinkerer-club/tests/fixtures/list-no-url.in.json`
- `/home/dneighbors/Public/omarchy-plugin-tinkerer-club/tests/fixtures/list-no-url.out.json`
- `/home/dneighbors/Public/omarchy-plugin-tinkerer-club/tests/fixtures/list-skip-no-id.in.json`
- `/home/dneighbors/Public/omarchy-plugin-tinkerer-club/tests/fixtures/list-skip-no-id.out.json`
- `/home/dneighbors/Public/omarchy-plugin-tinkerer-club/tests/fixtures/list-unusable.in.json`
- `/home/dneighbors/Public/omarchy-plugin-tinkerer-club/tests/fixtures/list-401.in.json`
- `/home/dneighbors/Public/omarchy-plugin-tinkerer-club/Panel.qml`
- `/home/dneighbors/Public/omarchy-plugin-tinkerer-club/README.md`
- `/home/dneighbors/Public/omarchy-plugin-tinkerer-club/manifest.json`
- `/home/dneighbors/Public/omarchy-plugin-tinkerer-club/tests/unread.sh`
- `/home/dneighbors/Public/omarchy-plugin-tinkerer-club/_bmad-output/implementation-artifacts/2-2-notification-list.md`
- `/home/dneighbors/Public/omarchy-plugin-tinkerer-club/_bmad-output/implementation-artifacts/sprint-status.yaml`

## Senior Developer Review (AI)

7 findings. CHANGES_REQUESTED. No criticals.

- F1 HIGH AC2/6: applyFeed wrote shared errorText on the notifications view
- F2 HIGH Task 3.6: shared `busy` blocked Refresh across views
- F3 HIGH Task 3.7: IPC refresh while closed could fetch the list; panelView persisted after close
- F4 HIGH Task 2.7: list.sh did not run unread.sh
- F5 MEDIUM: QML greps did not lock AC6 isolation
- F6 MEDIUM: header clip at panelWidth 300
- F7 LOW: feedLimit docs still said posts-only

## Review Follow-ups (AI)

- [x] F1 applyFeed writes/clears errors only when `panelView === "feed"`
- [x] F2 Refresh uses `viewBusy` (active view Process only)
- [x] F3 `refreshNotifications` requires `opened`; close resets `panelView` to feed; `refresh()` list only when opened
- [x] F4 `tests/list.sh` invokes `tests/unread.sh`
- [x] F5 AC6 isolation greps (Timer, applyFeed gate, opened guard)
- [x] F6 Switcher on a second header row
- [x] F7 README + manifest: feedLimit is first-page size for feed and notifications

## Change Log

- 2026-09-14: Story 2.2 created (ready-for-dev); sprint-status updated
- 2026-09-14: Tasks 3 and 4.1–4.3 — panel notifications view + click-to-open (QML only)
- 2026-09-14: Helper `notifications list` + fixture tests (Tasks 1, 2.1–2.6, 2.8, 4.4)
- 2026-09-14: Applied review F1–F7
