# Story 4.2: Publish to Omarchy marketplace

Status: review

## Story

As a **developer**,
I want **`dneighbors.tinkerer-club` listed on plugins.omarchy.org**,
so that **members can install from the catalog**.

## Acceptance Criteria

1. **Given** a public GitHub repository at `https://github.com/dneighbors/omarchy-plugin-tinkerer-club` with root `manifest.json`, `README.md`, and `LICENSE`
   **When** a maintainer or CI inspects repository readiness
   **Then** install and removal instructions, license, and external dependencies (`curl`, `jq`) are documented and no secrets or `.gitignore`-pattern key files are committed.

2. **Given** the repository root on `main`
   **When** `omarchy plugin validate .` runs (or the pinned `omarchy-plugin-validate` binary against the repo)
   **Then** it exits 0 for plugin id `dneighbors.tinkerer-club`, kinds `bar-widget`, and entry point `BarWidget.qml`.

3. **Given** no `.github/workflows/` exist yet
   **When** this story lands on `main`
   **Then** a GitHub Actions workflow on `push`/`pull_request` to `main` runs fixture tests and Omarchy Quattro validation so marketplace compatibility is continuously checked on the branch head.

4. **Given** the helper and QML sources at the validated commit
   **When** the marketplace Automated Security Baseline scans them statically
   **Then** the result is `passed` or `review-required` with no selectively blocking `needs-fixes` findings (no `curl-pipe-shell`, unpinned remote git execution, dangerous sudoers, or privileged `/tmp` PID control).

5. **Given** a completed preflight on current `main`
   **When** the publish issue is opened at `omacom/omarchy-plugin-marketplace` with title `[Plugin]: Tinkerer Club`, correct category/tags, repository URL, and all five checklist items checked
   **Then** the `github-actions[bot]` validation comment reports ✅ for public repo, valid manifest, README/license, and Quattro compatibility at the current `main` commit.

6. **Given** Story 4.3 scope
   **When** this story is marked done
   **Then** README still documents GitHub `omarchy plugin add` install only — no catalog install path, no maintainer-approval copy, and no post-listing README edits.

## Tasks / Subtasks

- [x] **Task 1 — Fixture test runner for CI** (AC: 3)
  - [x] 1.1 Add `tests/all.sh`: `set -euo pipefail`, run `tests/unread.sh`, `tests/list.sh`, and `tests/mark.sh` in that order; exit non-zero on first failure; print a one-line pass summary at the end.
  - [x] 1.2 Ensure each script remains self-contained (PATH-injected stub `curl`, temp key file, no live origin). Do not source `bin/tinkerer`.
  - [x] 1.3 Document in Dev Notes only (not README — 4.3 owns install docs): CI invokes `./tests/all.sh`.

- [ ] **Task 2 — GitHub Actions validate-on-main** (AC: 2, 3)
  - [x] 2.1 Create `.github/workflows/ci.yml` triggered on `push` to `main`, `pull_request`, and `workflow_dispatch`. Use `permissions: contents: read`, concurrency group, `ubuntu-24.04`, 5-minute timeout.
  - [x] 2.2 Check out this plugin to `plugin/` with pinned `actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1` (# v7.0.1).
  - [x] 2.3 Sparse-checkout Omarchy validator only: `basecamp/omarchy` ref `7be59e1f4b7451d352d4673c560168290792590f` (quattro, 2026-08-16) path `bin/omarchy-plugin-validate` into `omarchy/` — same pin as `ssupt/omarchy-media-controls`.
  - [x] 2.4 Install `jq` (tests depend on it). Run `./plugin/tests/all.sh` then `./omarchy/bin/omarchy-plugin-validate ./plugin`.
  - [ ] 2.5 Push to `main` and confirm the workflow is green before marketplace submission (AC5 depends on green `main`).

- [x] **Task 3 — Marketplace preflight audit** (AC: 1, 2, 4)
  - [x] 3.1 Confirm repo is public and default branch is `main`.
  - [x] 3.2 Re-run locally: `omarchy plugin validate .` (already exit 0 — record commit SHA in Dev Agent Record).
  - [x] 3.3 Verify root files: `manifest.json`, `README.md`, `LICENSE`, `BarWidget.qml`, `Panel.qml`, `bin/tinkerer`. No symlinks under plugin root.
  - [x] 3.4 README audit: Install (`omarchy plugin add … --enable`), Remove (`omarchy plugin remove dneighbors.tinkerer-club`), Requirements (`curl`, `jq`), license reference. No real API keys.
  - [x] 3.5 Manifest audit: `schemaVersion` 1, id `dneighbors.tinkerer-club`, `license` MIT, `kinds` includes `bar-widget`, `entryPoints.barWidget` → `BarWidget.qml`. `barWidget.category` `Social` is shell UI grouping only — do not use `Social` as marketplace category (not in allowed list).
  - [x] 3.6 Security baseline self-check: grep repo for `curl.*\|`, `wget.*\|`, unpinned `cargo install --git`, `NOPASSWD`, `pkexec`, `/tmp/*.pid` patterns in runtime paths (`bin/`, `*.qml`, root README). Tests/fixtures mentioning curl argv are expected and excluded from runtime concern.
  - [ ] 3.7 Optional: add root `preview.png` (screenshot of bar/panel). Marketplace auto-optimizes; not required for validation pass.

- [ ] **Task 4 — Open marketplace submission issue** (AC: 5)
  - [ ] 4.1 Use issue form https://github.com/omacom/omarchy-plugin-marketplace/issues/new?template=submit-plugin.yml or CLI per `SUBMISSION.md`. Title: `[Plugin]: Tinkerer Club`.
  - [ ] 4.2 Body must preserve all six headings in order (`Repository URL`, `Category`, `Tags`, `Suggest a missing tag`, `Maintainer notes`, `Submission checklist`) and exact checklist text from `SUBMISSION.md`.
  - [ ] 4.3 Locked listing metadata for this plugin:
        - Repository URL: `https://github.com/dneighbors/omarchy-plugin-tinkerer-club` (no trailing slash, no `/tree/main`)
        - Category: `Widgets` (bar widget; `Social` is not an allowed marketplace category)
        - Tags: `bar`, `system` (one to three from allowed list; both apply)
        - Maintainer notes: unofficial Tinkerer Club integration; requires member API key file documented in README
  - [ ] 4.4 All five checklist boxes checked only after Tasks 1–3 are merged to `main` and CI is green.
  - [ ] 4.5 Record marketplace issue URL and validated commit SHA in Dev Agent Record. Do not open duplicate issues on retry — edit the existing issue to re-run validation.

- [ ] **Task 5 — Confirm automated validation** (AC: 5, 6)
  - [ ] 5.1 Wait for `github-actions[bot]` **Marketplace validation** comment on the submission issue. Required ✅ lines: public repo, valid manifest, README/license, Quattro compatibility at commit matching current `main`.
  - [ ] 5.2 **Automated security baseline** comment should be `passed` or acceptable `review-required` without `security-needs-fixes` / selectively blocking findings. If `needs-fixes`, fix on `main`, let CI go green, edit issue to re-validate — do not duplicate the issue.
  - [ ] 5.3 Do **not** add README catalog install instructions (Story 4.3). Do **not** wait for maintainer `approved-and-verified` or listing URL — out of scope for 4.2.
  - [ ] 5.4 Update story status to `done` and sprint-status only after AC5 bot comment is green. Record issue link in Completion Notes.

## Dev Notes

Ultimate context engine analysis completed — comprehensive developer guide created.

There is no `architecture.md`, `prd.md`, or `ux-design-specification.md`. Epic 4 is ops/chores; this story is marketplace submission mechanics, not feature work.

### Product intent

Epic 4 goal: standing place for bugs, chores, and marketplace listing work. Story 4.2 submits the plugin for catalog listing and proves automated validation passes on `main`. Story 4.3 (separate) updates README after maintainer approval — **do not touch README install path for catalog in this story**. [Source: `_bmad-output/planning-artifacts/epics.md` — Epic 4, Stories 4.2 / 4.3]

Dependencies: Epic 0 (public repo, valid manifest, helper). Feature epics 1–2 are done; plugin surface is stable for listing.

Out of scope (Story 4.3): README `plugins.omarchy.org` install path, catalog badge copy, post-approval documentation, maintainer approval itself, listing URL verification on omarchyplugins.com.

### Locked decisions (do not reopen)

| Decision | Choice | Why |
|---|---|---|
| Marketplace category | `Widgets` | Bar widget plugin; `Social` is manifest shell grouping only, not an allowed marketplace category |
| Marketplace tags | `bar`, `system` | Allowed tags; describes bar placement and quiet refresh behavior |
| CI validator pin | `basecamp/omarchy@7be59e1f4b7451d352d4673c560168290792590f` | Same ref as established community plugin CI; matches Quattro compatibility check marketplace runs |
| README install docs | GitHub `omarchy plugin add` only | Story 4.3 owns catalog path after approval |
| Story done gate | Bot validation ✅ on submission issue | AC is automated validation pass, not maintainer publish |
| Submission target | `omacom/omarchy-plugin-marketplace` | Canonical marketplace repo per plugins.omarchy.org/publish.html |

### Marketplace validation pipeline (what AC5 means)

When the submission issue opens (or is edited), marketplace GitHub Actions:

1. **Intake** — title starts with `[Plugin]:`, body has six headings in order, category matches allowed spelling, checklist checked.
2. **Repository validation** — public GitHub repo reachable; one root `manifest.json`; unique plugin id; README + license at root; Quattro compatibility via `omarchy-plugin-validate` at exact commit SHA of `main` HEAD.
3. **Automated Security Baseline** — static scan of helper, QML entry points, README; reports `passed`, `review-required`, or `needs-fixes`. Selectively blocking findings block publication.

Expected success comment pattern (from published plugins):

```
✅ Repository is public and reachable
✅ Found 1 valid, uniquely identified plugin manifest
✅ Root README and license files detected
✅ Quattro compatibility passed at commit `<sha>`
```

[Source: https://plugins.omarchy.org/publish.html, https://github.com/omacom/omarchy-plugin-marketplace/blob/main/SUBMISSION.md]

### Allowed marketplace metadata (submission form)

Categories (case-sensitive, pick one): `Appearance`, `Desktop`, `Developer Tools`, `Hardware`, `Kids`, `Productivity`, `System`, `Widgets`, `Other`.

Tags (one to three): `ai`, `bar`, `education`, `games`, `hyprland`, `kids`, `launcher`, `media`, `power-management`, `quickshell`, `security`, `system`, `workspaces`.

Plugin IDs are globally unique and permanent. This plugin id `dneighbors.tinkerer-club` must not collide with existing listings — search marketplace before submit.

### Current manifest snapshot (already valid locally)

```json
{
  "schemaVersion": 1,
  "id": "dneighbors.tinkerer-club",
  "name": "Tinkerer Club",
  "version": "0.1.0",
  "author": "Derek Neighbors",
  "license": "MIT",
  "kinds": ["bar-widget"],
  "entryPoints": { "barWidget": "BarWidget.qml" },
  "barWidget": { "category": "Social", ... }
}
```

`omarchy plugin validate .` already exits 0 locally. Do not change manifest id, kinds, or entry points unless validation fails in CI.

[Source: `manifest.json`]

### Security baseline expectations for this repo

Runtime paths (`bin/tinkerer`, `BarWidget.qml`, `Panel.qml`, README) should not trigger:

- `curl-pipe-shell` — helper uses `curl` for API POST only, not piped to shell
- `sudo` / `pkexec` — plugin does not elevate privileges [Source: `SECURITY.md`]
- unpinned remote git execution — no install hooks
- dangerous sudoers or `/tmp` PID privilege patterns

Test fixtures under `tests/fixtures/` that mention curl in stub logs are not runtime code — baseline excludes test directories unless an entry point lives there.

[Source: https://github.com/omacom/omarchy-plugin-marketplace/blob/main/SECURITY.md#automated-security-baseline]

### CI workflow reference (copy pattern, adapt paths)

Follow `ssupt/omarchy-media-controls` `.github/workflows/ci.yml`:

- Checkout plugin to `plugin/`
- Sparse-checkout `bin/omarchy-plugin-validate` from pinned Omarchy quattro ref
- Run `./plugin/tests/all.sh` (new in Task 1)
- Run `./omarchy/bin/omarchy-plugin-validate ./plugin`

Do not add qmllint to CI unless Omarchy shell imports are available — marketplace validation uses `omarchy-plugin-validate`, not qmllint. Local dev may still run `qmllint` manually per plugins.omarchy.org/develop.html.

### Submission issue body template

```markdown
### Repository URL

https://github.com/dneighbors/omarchy-plugin-tinkerer-club

### Category

Widgets

### Tags

bar, system

### Suggest a missing tag

_No response_

### Maintainer notes

Unofficial Tinkerer Club bar widget. Requires a member API key file documented in README; key is never stored in the repo.

### Submission checklist

- [x] The repository is public and contains installation and removal instructions.
- [x] I have documented the plugin license and any external dependencies.
- [x] I confirm that I own or have permission to submit this plugin and its preview assets.
- [x] The plugin does not overwrite user configuration without explicit consent.
- [x] I understand that approval is for listing and is not a security review.
```

Create via:

```sh
gh issue create \
  --repo omacom/omarchy-plugin-marketplace \
  --title "[Plugin]: Tinkerer Club" \
  --body-file /tmp/omarchy-plugin-submission.md
```

Requires `gh auth login`. Show body to owner before creating if not in yolo/autonomous dev mode with pre-approval.

### Git intelligence

Recent commits:

- `0954f23` Track publish (4.2/4.3) and LockIn Epic 5 in epics and Benji.
- `5927f41` feat(epic-2): Notifications (#1)
- `44b4452` Add Tinkerer Club Omarchy bar plugin scaffold.

No `.github/workflows/` yet — this story introduces CI. Default branch `main`. Public remote: `https://github.com/dneighbors/omarchy-plugin-tinkerer-club.git`.

### Project Structure Notes

```
/home/dneighbors/Public/omarchy-plugin-tinkerer-club/
  .github/workflows/ci.yml          # NEW — validate + tests on main
  tests/all.sh                      # NEW — CI entrypoint
  tests/unread.sh                   # EXISTS — run in all.sh
  tests/list.sh                     # EXISTS — run in all.sh
  tests/mark.sh                     # EXISTS — run in all.sh
  manifest.json                     # NO CHANGE unless CI validation fails
  README.md                         # NO catalog install edits (Story 4.3)
  LICENSE                           # EXISTS — MIT at root
  preview.png                       # OPTIONAL — marketplace card image
  _bmad-output/implementation-artifacts/4-2-publish-marketplace.md  # this file
```

### Parallel dev task groups

| Group | Tasks | Can start together | Blockers |
|---|---|---|---|
| A — CI harness | Task 1 (`tests/all.sh`) | Yes | None |
| B — CI workflow | Task 2 (`.github/workflows/ci.yml`) | After Task 1 or stub `tests/all.sh` | Merge to `main` + green CI before Task 4 |
| C — Preflight | Task 3 (audit checklist) | Yes | None |
| D — Submission | Tasks 4–5 (issue + bot confirmation) | No | Tasks 1–3 on `main`, CI green |

Groups A, B (with stub), and C can run in parallel. Group D is sequential after merge.

### References

- [Source: `_bmad-output/planning-artifacts/epics.md` — Epic 4, Story 4.2]
- [Source: `_bmad-output/planning-artifacts/epics.source.yaml` — epic 4 / story 4.2]
- [Source: `_bmad/bmm/config.yaml` — project_name `omarchy-plugin-tinkerer-club`, user_name Derek]
- [Source: `docs/benji-map.yaml` — story 4.2 id `4a261c53-ffac-43dc-aec4-78f57d202516`]
- [Source: `manifest.json` — id `dneighbors.tinkerer-club`, category Social (shell), license MIT]
- [Source: `README.md` — install, remove, Requirements curl/jq]
- [Source: `LICENSE` — MIT root license]
- [Source: `SECURITY.md` — key file, HTTPS, no privilege escalation]
- [Source: https://plugins.omarchy.org/publish.html — publish steps]
- [Source: https://github.com/omacom/omarchy-plugin-marketplace/blob/main/SUBMISSION.md — issue format, categories, tags]
- [Source: https://github.com/omacom/omarchy-plugin-marketplace/blob/main/SECURITY.md — baseline patterns]
- [Source: https://github.com/ssupt/omarchy-media-controls/blob/main/.github/workflows/ci.yml — CI pattern]
- [Source: `_bmad-output/implementation-artifacts/2-1-unread-count.md` — story structure reference]

## Dev Agent Record

### Context Reference

<!-- Path(s) to story context XML will be added here by context workflow -->

### Agent Model Used

claude-opus-4-6 (Task 3 preflight audit); composer (Task 1 CI harness, Task 2 CI workflow)

### Debug Log References

- Preflight audit run 2026-09-14 on commit `0954f230596f0ccc80be7cf7d751ce7e12be952b` (local branch `story/4-2-publish-marketplace`; remote default branch `main`).

### Completion Notes List

**Task 1 — Fixture test runner for CI (2026-09-14)**

| Subtask | Result | Notes |
|---|---|---|
| 1.1 `tests/all.sh` | PASS | `set -euo pipefail`; runs `unread.sh` → `list.sh` → `mark.sh`; one-line summary on success. |
| 1.2 Self-contained scripts | PASS | Child scripts unchanged; each uses PATH-injected stub `curl`, temp key file, no live origin; `all.sh` does not source `bin/tinkerer`. |
| 1.3 Dev Notes | PASS | CI invocation documented in Dev Notes (`./plugin/tests/all.sh` / `./tests/all.sh`). README untouched. |

**Test results:** `./tests/all.sh` exit 0 — unread 121 ok, list 352 ok, mark 501 ok (974 total assertions).

**Task 3 — Marketplace preflight audit (2026-09-14)**

| Subtask | Result | Notes |
|---|---|---|
| 3.1 Public repo / `main` | PASS | `gh repo view`: visibility `PUBLIC`, default branch `main`. Remote: `https://github.com/dneighbors/omarchy-plugin-tinkerer-club.git`. |
| 3.2 `omarchy plugin validate .` | PASS | Exit 0 at commit `0954f230596f0ccc80be7cf7d751ce7e12be952b`. |
| 3.3 Root files / symlinks | PASS | All six required files present (`manifest.json`, `README.md`, `LICENSE`, `BarWidget.qml`, `Panel.qml`, `bin/tinkerer`). No symlinks at plugin root. |
| 3.4 README audit | PASS | Install: `omarchy plugin add … --enable`. Remove: `omarchy plugin remove dneighbors.tinkerer-club`. Requirements: `curl`, `jq`. License: `[MIT](LICENSE)`. Placeholder `YOUR_MEMBER_KEY` only — no real keys. No catalog install path (Story 4.3 scope preserved). |
| 3.5 Manifest audit | PASS | `schemaVersion` 1, id `dneighbors.tinkerer-club`, `license` MIT, `kinds` `["bar-widget"]`, `entryPoints.barWidget` → `BarWidget.qml`. Shell category `Social` noted — marketplace submission will use `Widgets` (Task 4). |
| 3.6 Security baseline | PASS | No matches in runtime paths (`bin/`, `*.qml`, `README.md`) for `curl\|`, `wget\|`, `cargo install --git`, `NOPASSWD`, `pkexec`, `/tmp/*.pid`. No tracked files matching `.gitignore` secret patterns (`*api-key*`, `*apikey*`, `*token*`, `.env`). |
| 3.7 `preview.png` | SKIPPED | Optional; not present. Not required for validation pass. |

**Blocking issues:** None. No fixes applied.

**Validated commit SHA:** `0954f230596f0ccc80be7cf7d751ce7e12be952b`

**Task 2 — GitHub Actions validate-on-main (2026-09-14)**

| Subtask | Result | Notes |
|---|---|---|
| 2.1 `ci.yml` scaffold | PASS | Triggers: `push`/`main`, `pull_request`, `workflow_dispatch`. `permissions: contents: read`, concurrency group, `ubuntu-24.04`, 5-minute timeout. |
| 2.2 Plugin checkout | PASS | Pinned `actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1` (# v7.0.1) → `plugin/`. |
| 2.3 Omarchy validator sparse-checkout | PASS | `basecamp/omarchy@7be59e1f4b7451d352d4673c560168290792590f` → `omarchy/bin/omarchy-plugin-validate`. |
| 2.4 Test + validate steps | PASS | `apt-get install jq`; `./plugin/tests/all.sh` then `./omarchy/bin/omarchy-plugin-validate ./plugin`. Local `./tests/all.sh` exit 0; pinned validator exit 0. |
| 2.5 Push + green CI | DEFERRED | Push to `main` not performed per dev instructions; required before Task 4 submission. |

### File List

- `.github/workflows/ci.yml` (new — Task 2 CI workflow)
- `tests/all.sh` (Task 1 CI entrypoint; used by Task 2 workflow)
- `tests/unread.sh` (review fix — unset live key env vars)
- `_bmad-output/implementation-artifacts/sprint-status.yaml` (story status tracking)
- `_bmad-output/implementation-artifacts/4-2-publish-marketplace.md` (Task 1 + Task 2 + Task 3 audit notes)

## Senior Developer Review (AI)

Review date: 2026-09-14. Findings: 7 (0 critical, 2 high, 4 medium, 1 low). Recommendation: changes requested → addressed before merge.

| ID | Severity | Resolution |
|---|---|---|
| F1 | HIGH | Commit + merge CI to `main`; confirm green Actions run (Task 2.5) |
| F2 | HIGH | Open marketplace submission issue after green CI (Tasks 4–5) |
| F3 | MEDIUM | Fixed: `pull_request.branches: [main]` in `ci.yml` |
| F4 | MEDIUM | Accepted: nested test invocations in list/mark; `all.sh` remains canonical CI entry |
| F5 | MEDIUM | Fixed: story status → `review`; sprint-status aligned |
| F6 | MEDIUM | Fixed: `unset TINKERER_*` added to `tests/unread.sh` |
| F7 | LOW | Fixed: `sprint-status.yaml` in File List |

### Review Follow-ups (AI)

- [x] F3 — narrow PR trigger to `main`
- [x] F5 — update story + sprint status to `review`
- [x] F6 — env key unset in `unread.sh`
- [x] F7 — File List includes sprint-status
- [ ] F1/F2 — merge to `main`, green CI, marketplace bot validation (Tasks 2.5, 4, 5)

## Change Log

- 2026-09-14: Code review — 4 fixes applied (ci.yml PR filter, unread.sh unset, status tracking).
- 2026-09-14: Task 1 — add `tests/all.sh` fixture test runner for CI (AC3).
- 2026-09-14: Task 2.1–2.4 — add `.github/workflows/ci.yml` validate-on-main workflow (AC2, AC3).
- 2026-09-14: Task 3 preflight audit complete — all required subtasks pass; no blocking fixes.
