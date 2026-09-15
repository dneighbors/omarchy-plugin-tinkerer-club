# Tinkerer Club for Omarchy

Bar widget for [Tinkerer Club](https://tinkerer.club): recent feed items, a details panel, and a one-click jump into the club.

This is unofficial. Not affiliated with or endorsed by Tinkerer Club.

## Install

```sh
omarchy plugin add https://github.com/dneighbors/omarchy-plugin-tinkerer-club.git --enable
```

Then put your member API key in a file the plugin can read:

```sh
mkdir -p ~/.config/omarchy/secrets
printf '%s\n' "YOUR_MEMBER_KEY" > ~/.config/omarchy/secrets/tinkerer-club-api-key
chmod 600 ~/.config/omarchy/secrets/tinkerer-club-api-key
```

Do not add `Bearer`. The helper sends the raw key as `x-api-key`.

Issue a key from Tinkerer Club. The Raycast extension uses the same key and the same default origin, `https://app.tinkerer.club`.

## Usage

Click the lobster in the bar to open or close the panel. Escape closes it.

The panel has Feed, Notifications, and LockIn. Click a post or a notification with a target URL to open it in the browser. Refresh updates whichever view is showing. On Notifications, Mark read and Mark all read are explicit; the unread badge updates after those succeed. LockIn shows your live co-working session, who else is locked in, and a skew-safe countdown toward the 60-minute cap. Start a session with an optional title or finish anytime; finishing before 30 minutes is allowed but does not earn Sparkles (the reward window is 30–60 minutes). At 30 seconds before the cap, the plugin auto-finishes and restarts with the same title. The LockIn tab also lists your private checklist: add items, toggle complete, or delete; it works with or without a live session and stays in sync with the web LockIn page. When the panel is closed during a LockIn session, the bar can show remaining time; the unread badge still wins if both apply. The bar shows a dot when something newer than your last open arrives. When the panel is closed and there are unread notifications, a count badge replaces that dot. The dot comes back when the count is 0.

```sh
omarchy bar move dneighbors.tinkerer-club --section right
```

## Configure

Omarchy settings for this widget:

| Setting | Default | Purpose |
| --- | --- | --- |
| API key file | `~/.config/omarchy/secrets/tinkerer-club-api-key` | Path to the member key |
| Platform URL | `https://app.tinkerer.club` | HTTPS API origin |
| Feed items | 20 | First page size for the feed and the Notifications list |
| Panel width | 380 | Panel size in shell spacing units |
| Quiet refresh | 5 minutes | How often the bar checks for new activity |

## Remove

```sh
omarchy plugin remove dneighbors.tinkerer-club
```

That removes the plugin checkout. It does not delete your API key file.

## Requirements

- Omarchy 4.x / Quattro shell
- `curl` and `jq`
- A Tinkerer Club member API key

## Develop

BMAD Method is installed. Write epics in `_bmad-output/planning-artifacts/epics.md` and status in `_bmad-output/implementation-artifacts/sprint-status.yaml`. Benji list is Products -> Omarchy Plugins -> Tinkerer Club. Map: `docs/benji-map.yaml`.

Add a story: append it to `epics.md` and `epics.source.yaml`, then:

```sh
node ~/Public/domain-buildplans/scripts/benji/benji_sync.mjs _bmad-output/planning-artifacts/epics.source.yaml
```

Paste the new Benji todo id onto the story and into `sprint-status.yaml`.

```sh
omarchy plugin validate .
npx bmad-method@latest status
```

QML changes under `~/.config/omarchy/plugins/dneighbors.tinkerer-club/` reload on save. Force discovery with:

```sh
omarchy-shell shell rescanPlugins
```

## License

[MIT](LICENSE) © 2026 Derek Neighbors
