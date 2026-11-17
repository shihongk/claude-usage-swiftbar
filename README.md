# claude-usage-swiftbar

Your Claude Pro/Max plan usage in the macOS menu bar, in the same stacked label-over-value style as the [Stats](https://github.com/exelban/stats) app:

```
✳  5H   7D
  28%  39%
```

Shows your 5-hour session % and weekly %. Each number turns orange at 70% and red at 90%. The dropdown shows reset times (local time), last-updated time, and a link to your usage page.

> **Unofficial.** Not affiliated with Anthropic. It uses a private usage endpoint that can change or break without notice.

## Requirements

- macOS, [SwiftBar](https://github.com/swiftbar/SwiftBar) (`brew install --cask swiftbar`)
- [Claude Code](https://claude.com/claude-code) logged in with your Claude subscription (`claude` → `/login`, choose the subscription account, not the API console). Google SSO works.
- Only built-in macOS tools (`curl`, `security`, `jq` on macOS 15+, falls back to `osascript`)

## Install

```bash
git clone <this repo's URL> claude-usage-swiftbar
cd claude-usage-swiftbar
./install.sh
```

`install.sh` copies the plugin into your SwiftBar plugins folder. Then SwiftBar menu → Refresh All. The first Keychain read prompts you; choose **Always Allow**.

Manual install: copy `claude-usage.5m.sh` into your SwiftBar plugins folder and `chmod +x` it. The `5m` in the filename is the refresh interval.

## How it works

1. Reads your Claude Code OAuth token from the macOS Keychain (item `Claude Code-credentials`, read-only; the token is never printed or logged).
2. Calls `https://api.anthropic.com/api/oauth/usage` and shows `five_hour` and `seven_day`.
3. If the token has expired, it runs a tiny headless `claude -p` call, which makes Claude Code refresh its own login (uses a trivial amount of usage). There is also a "Refresh Claude Code login" dropdown item.
4. Network failure: last good values are kept (`~/Library/Caches/claude-usage/`) and marked `(stale)`.

Everything stays on your Mac; the only requests go to Anthropic.

### Fallback: claude.ai cookie

If you don't use Claude Code, `./setup.sh` stores a claude.ai `sessionKey` cookie in the Keychain (service `claude-usage`). Note that claude.ai's Cloudflare protection often blocks plain `curl`, so this route may fail with `(stale)`.

## Troubleshooting

- `◔ re-login`: log in again with `claude` → `/login`.
- `◔ ?`: unexpected response; the raw response is shown in the dropdown.
- Text is hard to read: the icon colors follow macOS light/dark appearance, not your wallpaper.

## Credits

Endpoints verified against [Claude-Usage-Tracker](https://github.com/hamed-elfayome/Claude-Usage-Tracker).

MIT licensed.
