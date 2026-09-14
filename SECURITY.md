# Security

This plugin is unofficial. It is not affiliated with or endorsed by Tinkerer Club.

Plugins run unsandboxed inside `omarchy-shell`, with your user permissions.

## API key

Store the member key in a file only you can read:

```sh
mkdir -p ~/.config/omarchy/secrets
printf '%s\n' "$TINKERER_CLUB_API_KEY" > ~/.config/omarchy/secrets/tinkerer-club-api-key
chmod 600 ~/.config/omarchy/secrets/tinkerer-club-api-key
```

Do not put the key in this repository, in `shell.json`, or in an issue.

The helper reads that file and sends it only as `x-api-key` to the configured HTTPS origin. It never prints the key.

Revoke the key in Tinkerer Club immediately if you think it leaked.

## Network

The default origin is `https://app.tinkerer.club`. HTTP is accepted only for localhost. Remote content from the club is treated as untrusted text, never as QML or a command.
