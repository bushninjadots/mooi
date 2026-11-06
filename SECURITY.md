# Security

mooi is a local desktop shell. It has no server, no account and no telemetry. The sensitive things
it touches are local files and the commands it runs:

- `wallhaven.key` (mooi's data folder, mode 0600; `~/.config/mooi/wallhaven.key` as a fallback) —
  the Wallhaven API key, sent to Wallhaven only, never written to `settings.json`.
- `settings.json`, `notes.json`, `board.json`, `stash.json`, `nexus-weather.json` and the identity
  pictures — user state read and written through the scene permission allowlists.
- `claude`/`gh` — invoked as signed-in command-line tools; mooi does not store their credentials.
- Network egress: `ipinfo.io` (one cached lookup), `api.open-meteo.com`, `wallhaven.cc` /
  `w.wallhaven.cc` / `th.wallhaven.cc`, and GitHub through `gh`. Wallhaven requests are restricted
  to those hosts; weather and location answers are validated and bounded before use.

- Other egress: `lrclib.net` (lyrics), Steam's store search and CDN (game pictures), and — only
  when Settings → Nexus → Claude → *Free models when Claude can't* is on (`claude.free_fallback`,
  off by default) — opencode's free models, which then receive the question and the last few
  turns of the chat. opencode is run with every tool permission denied, in an empty folder.
- The lock screen (`shell/mooi-lock.plm`) holds the session through ext-session-lock and checks
  the password with PAM; `mooi lock` succeeds only once the compositor confirms the lock, and
  hypridle (`inhibit_sleep = 3`) waits for it before sleeping. `mooi unlock` opens it without a
  password: it is the way back from a tty, and anything running as you can do the same.

## What the scene allowlists are, and are not

Each scene's `permissions { run: … }` names the programs its logic may start, argv only, no shell.
That narrows mistakes; it is **not a sandbox**. Several entries can start any other program —
`env`, `timeout`, `find` (`-exec`), `kitty`, `xdg-open`, `gtk-launch`, `mooi` and `pleamar` — and
every scene except the lock shares one data folder (`~/.local/share/pleamar/mooi`, so each can
read `wallhaven.key`). Treat a scene's logic as code running as you. The lock scene is the
exception: its own folder, and only `systemctl` to run.

## Reporting

Do not open a public issue for a vulnerability that exposes user data or executes commands.
Contact the repository owner privately (the address on the owner's GitHub profile) with the
affected file, the reproduction, and the impact. Please allow a few days for a reply.

There is no bug bounty. Fixes are applied on `main`; releases are tagged when the author cuts one.
