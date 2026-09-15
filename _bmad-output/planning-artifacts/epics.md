---
stepsCompleted: [1, 2, 3, 4]
inputDocuments:
  - prd.md
  - architecture.md
  - epics.source.yaml
---

# Tinkerer Club Omarchy Plugin - Epic Breakdown

## Overview

Living epic file. Write new stories here, then add the same story to `epics.source.yaml` and run `benji_sync.mjs` so a Benji todo lands on Products -> Omarchy Plugins -> Tinkerer Club. Paste the new Benji id back onto the story. Status lives in `sprint-status.yaml`. MVP is Epics 0, 1. 6 epics, 19 stories.

| Epic | Title | Stories | Source | MVP |
|---|---|---|---|---|
| 0 | Plugin Foundation | 4 | repo scaffold 2026-09-14 | yes |
| 1 | Club Feed | 4 | OpenAPI post.timeline; Raycast extension contract | yes |
| 2 | Notifications | 3 | OpenAPI notification.* |  |
| 3 | Events | 2 | OpenAPI event.calendar, event.liveBanner |  |
| 4 | Ops Hygiene | 3 | portfolio convention (RevivaGo Epic 58); plugins.omarchy.org/publish |  |
| 5 | LockIn | 3 | OpenAPI lockIn.* |  |


## Epic 0: Plugin Foundation

**Goal:** Public installable Omarchy plugin, BMAD tracking, and Benji wiring so new stories have a place to land.

**Why:** Nothing else ships until the plugin validates, installs, and has a writeable epic/sprint/Benji loop.

**Dependencies:** none

**Source:** repo scaffold 2026-09-14

**Notes:** Repo, BMAD install, and local enable already landed. Edit this YAML, not epics.md.

**Benji project:** `e87cea2c-4b57-4eea-bb41-3449803760c5` (Tinkerer Club Epic 0: Plugin Foundation)

### Story 0.1: Public repo and installable manifest

As a **developer**,
I want **a public GitHub repo with a valid Omarchy manifest, bar widget, panel, and helper**,
So that **anyone can install with omarchy plugin add**.

**Acceptance Criteria:**

**Given** the repo root
**When** omarchy plugin validate . runs
**Then** the manifest and entry points pass

**Given** https://github.com/dneighbors/omarchy-plugin-tinkerer-club.git
**When** a user runs omarchy plugin add with --enable
**Then** dneighbors.tinkerer-club appears on the bar

Benji todo: `57e4fbb2-3977-414f-9c45-35a373330bff`

### Story 0.2: BMAD Method install

As a **developer**,
I want **BMAD Method installed with Cursor and Claude Code skills**,
So that **planning and implementation use the same workflows as other repos**.

**Acceptance Criteria:**

**Given** the repo
**When** npx bmad-method@latest status runs
**Then** core and bmm 6.12.0 are present

**Given** _bmad/bmm/config.yaml
**When** read
**Then** user_name is Derek and user_skill_level is advanced

Benji todo: `c66d354c-09ff-4095-9448-23911140802f`

### Story 0.3: Epics, sprint status, and Benji list

As a **developer**,
I want **epics.source.yaml rendered to epics.md and sprint-status.yaml, synced to Benji**,
So that **new stories can be written and linked to tasks under Products -> Omarchy Plugins -> Tinkerer Club**.

**Acceptance Criteria:**

**Given** Products
**When** Omarchy Plugins and Tinkerer Club lists exist
**Then** Tinkerer Club is nested under Omarchy Plugins

**Given** epics.source.yaml
**When** epics_render.py and benji_sync.mjs run
**Then** epics.md, sprint-status.yaml, and docs/benji-map.yaml contain Benji project and todo ids

Benji todo: `11b6528b-d5a6-44d7-8814-56030e2e9ff1`

### Story 0.4: Member API key file and helper status

As a **member**,
I want **the helper to read a local API key file and report configured or not without printing the key**,
So that **the panel can tell me to add a key and never leak it**.

**Acceptance Criteria:**

**Given** ~/.config/omarchy/secrets/tinkerer-club-api-key is missing
**When** bin/tinkerer status runs
**Then** configured is false and the path is in the hint

**Given** a readable key file
**When** bin/tinkerer status runs
**Then** configured is true and the key is not printed

Benji todo: `fb38c781-d557-448a-b351-5d0edaa04fa0`


## Epic 1: Club Feed

**Goal:** Signed-in members see recent Tinkerer Club posts from the Omarchy bar and can open them in the browser.

**Why:** The feed is the first thing people come back for. Same API as the Raycast extension.

**Dependencies:** 0

**Source:** OpenAPI post.timeline; Raycast extension contract

**Notes:** post.timeline is POST /api/v1/post/timeline with x-api-key.

**Benji project:** `09bb0745-66ac-4f25-9c76-974097375e2e` (Tinkerer Club Epic 1: Club Feed)

### Story 1.1: Fetch the member timeline

As a **member**,
I want **bin/tinkerer feed to call post.timeline and return normalized posts**,
So that **the panel can render a list without holding the key**.

**Acceptance Criteria:**

**Given** a valid key file
**When** bin/tinkerer feed runs
**Then** it POSTs to /api/v1/post/timeline and prints ok true with posts

**Given** a 401
**When** feed runs
**Then** the JSON error tells me to check the key file

Benji todo: `58ff1d97-4ffc-4fe9-9e0c-7846505c4a4f`

### Story 1.2: Panel feed list

As a **member**,
I want **the bar panel to list recent posts with author, snippet, and age**,
So that **I can scan the club without opening a browser first**.

**Acceptance Criteria:**

**Given** a configured key
**When** I open the panel
**Then** recent posts render

**Given** a post row
**When** I click it
**Then** the post URL opens in the browser

Benji todo: `b9235430-28b9-4ab3-a732-ce1072020276`

### Story 1.3: New activity dot

As a **member**,
I want **a bar dot when a newer post arrives after I last opened the panel**,
So that **I know the club moved without staring at it**.

**Acceptance Criteria:**

**Given** a newer latestId than seenId
**When** the panel is closed
**Then** the bar shows a dot

**Given** I open the panel
**When** the feed loads
**Then** the dot clears

Benji todo: `86f9fcd5-1769-48c8-8a72-1302e34d7989`

### Story 1.4: Feed refresh and errors

As a **member**,
I want **a refresh action and readable errors when the API fails**,
So that **a dead key or network blip does not look like an empty club**.

**Acceptance Criteria:**

**Given** the panel is open
**When** I click Refresh
**Then** the feed reloads

**Given** an API error
**When** the helper returns ok false
**Then** the panel shows the error and hint

Benji todo: `e48079da-76e9-46f7-a98e-24cd443e83be`


## Epic 2: Notifications

**Goal:** Unread club notifications on the bar, with a list and mark-read.

**Why:** The feed is what happened. Notifications are what wants you.

**Dependencies:** 0, 1

**Source:** OpenAPI notification.*

**Benji project:** `5fadc0f9-085b-414a-bb0c-10068a84c93b` (Tinkerer Club Epic 2: Notifications)

### Story 2.1: Unread notification count

As a **member**,
I want **the helper and bar to show notification.unreadCount**,
So that **I can see if the club is waiting on me**.

**Acceptance Criteria:**

**Given** a valid key
**When** bin/tinkerer notifications unread runs
**Then** it returns a count

**Given** an unread count greater than zero
**When** the bar is idle
**Then** the widget shows that count or a badge

Benji todo: `9e45c450-5a32-440f-af1f-f737d03f091f`

### Story 2.2: Notification list

As a **member**,
I want **the panel to list notification.list items**,
So that **I can read them without leaving the bar**.

**Acceptance Criteria:**

**Given** notifications exist
**When** I open the notifications view
**Then** sender, title, and age are listed

**Given** a notification with a target URL
**When** I click it
**Then** the browser opens that URL

Benji todo: `a3d95cad-4ae0-427f-8d89-25971ccccd7c`

### Story 2.3: Mark notifications read

As a **member**,
I want **markRead and markAllRead from the panel**,
So that **the badge matches what I have already seen**.

**Acceptance Criteria:**

**Given** an unread item
**When** I mark it read
**Then** unreadCount drops

**Given** Mark all read
**When** it succeeds
**Then** the badge clears

Benji todo: `dccdd7b0-590d-44f7-89e0-0078b7471c4f`


## Epic 3: Events

**Goal:** Upcoming club events and a live banner when something is happening now.

**Why:** Calls and live sessions are the other half of the club.

**Dependencies:** 0

**Source:** OpenAPI event.calendar, event.liveBanner

**Benji project:** `bea1aeaf-fb5c-4383-81a8-b0b83a3bead6` (Tinkerer Club Epic 3: Events)

### Story 3.1: Upcoming events

As a **member**,
I want **event.calendar in the panel**,
So that **I can see what is next without opening the site**.

**Acceptance Criteria:**

**Given** upcoming events
**When** I open the events view
**Then** title, time, and link are listed

Benji todo: `46d82182-da93-4533-a728-11b5b5bda2bc`

### Story 3.2: Live event banner

As a **member**,
I want **event.liveBanner on the bar or panel when a session is live**,
So that **I do not miss a call that is already going**.

**Acceptance Criteria:**

**Given** a live event
**When** liveBanner returns one
**Then** the panel shows it and a click opens the event

Benji todo: `daa99253-10f7-4959-9de8-5d8f597489c9`


## Epic 4: Ops Hygiene

**Goal:** Standing place for bugs, chores, and marketplace listing work.

**Why:** Small fixes should not invent a new epic every time.

**Dependencies:** none

**Source:** portfolio convention (RevivaGo Epic 58)

**Benji project:** `3ee89ffa-e7a8-4847-9f55-11adfd909798` (Tinkerer Club Epic 4: Ops Hygiene)

### Story 4.1: Standing chores container

As a **developer**,
I want **this epic ready for one-off bugs and marketplace submission**,
So that **chores have a Benji project without a new epic each time**.

**Acceptance Criteria:**

**Given** a plugin bug or marketplace task
**When** it is added here
**Then** it gets a story in this YAML and a Benji todo after sync

Benji todo: `52c1c6f9-e879-4939-9233-33f9fa3c6c23`

### Story 4.2: Publish to Omarchy marketplace

As a **developer**,
I want **dneighbors.tinkerer-club listed on plugins.omarchy.org**,
So that **members can install from the catalog**.

**Acceptance Criteria:**

**Given** a public repo and valid manifest.json
**When** the publish issue form is submitted
**Then** automated validation passes on current main

Benji todo: `4a261c53-ffac-43dc-aec4-78f57d202516`

### Story 4.3: Marketplace listing live

As a **developer**,
I want **the README to document catalog install after maintainer approval**,
So that **new users find the official install path**.

**Acceptance Criteria:**

**Given** maintainer approval
**When** the listing is live
**Then** README documents the plugins.omarchy.org install path

Benji todo: `625248d6-05f9-45dc-b7ef-511679aac628`


## Epic 5: LockIn

**Goal:** Timed co-working sessions from the bar with participant rail, checklist, and a 59:30 auto-finish watchdog so members do not lose Sparkles past 60 minutes.

**Why:** LockIn is the other focus surface after notifications. The web UI is a reverse pomodoro with a hard 60-minute cap.

**Dependencies:** Epic 0

**Source:** OpenAPI lockIn.*; https://app.tinkerer.club/api/docs#/lockIn

**Notes:** `lockIn/state` returns `current`, `participants`, `serverNow`, `onboarded`. `expiresAt` is `startedAt + 60m`. Finish before `expiresAt` or `automaticallyEnded` loses the reward. Sparkles are server-side only.

**Benji project:** `cb2736e0-ca86-4041-9c3d-fa22315119ab` (Tinkerer Club Epic 5: LockIn)

### Story 5.1: LockIn state and room

As a **member**,
I want **lockIn/state in the helper and a LockIn panel view**,
So that **I see my session, countdown, and who else is locked in**.

**Acceptance Criteria:**

**Given** a valid key
**When** `bin/tinkerer lockin state` runs
**Then** it returns `current`, `participants`, and `serverNow`

**Given** a live session
**When** the panel LockIn view is open
**Then** title, elapsed, remaining, 60-minute cap, and participant rail render

**Given** a live session and the panel is closed
**When** the bar is idle
**Then** a session cue shows remaining time and the unread pill still wins if both are true

Benji todo: `bf92adeb-e8cc-4f4b-b529-7efd384109fa`

### Story 5.2: Start, finish, and 59:30 watchdog

As a **member**,
I want **to start and finish sessions from the panel with auto-submit before the 60-minute cap**,
So that **I do not lose Sparkles because I forgot to stop**.

**Acceptance Criteria:**

**Given** no live session
**When** I start with an optional title
**Then** `lockIn/start` runs and state shows a new current session

**Given** a live session
**When** I finish
**Then** `lockIn/finish` runs with `current.id` and state clears or updates

**Given** a live session at T-30s before `expiresAt`
**When** the watchdog fires
**Then** it auto-finishes and auto-starts a new session with the same title

**Given** Finish is clicked
**When** elapsed is under 30 minutes
**Then** Finish still runs and reward copy explains the 30-60 minute window

Benji todo: `c9e3452b-9f5d-4d07-8f3a-c61e4e802cca`

### Story 5.3: LockIn checklist todos

As a **member**,
I want **my private LockIn checklist in the panel**,
So that **I can track focus tasks across sessions**.

**Acceptance Criteria:**

**Given** a valid key
**When** `bin/tinkerer lockin todos` runs
**Then** it returns the checklist array

**Given** the LockIn view
**When** I add, complete, or delete a todo
**Then** createTodo, updateTodo, or deleteTodo runs with a client-generated UUID

**Given** todos exist
**When** no session is running
**Then** the checklist still lists items the same as on the web

Benji todo: `d43c9625-bea9-4e70-9290-9e807a825cdf`
