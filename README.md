# claude-switcher

Switch between Claude desktop accounts on a Mac without signing in again, and without losing your Code or Cowork sessions.

`claude-sync` is one small command-line script (Python, no dependencies). It does two things:

1. **Saves each account's sign-in** so switching takes one command. Claude restarts already signed in as the other account.
2. **Shares your sessions between accounts.** The Claude desktop app keeps the session list for each account separately, so after switching accounts your sidebar looks empty, even though the conversations are still on disk. `claude-sync` merges the lists so every account sees everything.

> Unofficial and not affiliated with Anthropic. It works with files the Claude desktop app keeps on your Mac, so an app update could change things. Everything it changes is backed up first.

## Install

```bash
curl -fsSL https://raw.githubusercontent.com/Bot-Rakshit/claude-switcher/main/install.sh | bash
```

This puts `claude-sync` in `~/.local/bin`. Run the same command again to update.

**Needs:** macOS, the [Claude desktop app](https://claude.ai/download), and Python 3.8 or newer. Most Macs with developer tools already have it. If yours doesn't, the installer tells you to run `xcode-select --install`.

## Use

```bash
claude-sync add            # Claude restarts at sign-in: sign in with your other account
claude-sync accounts       # list accounts
claude-sync use 2          # switch (by number, name or id)
claude-sync rename 1 Work  # give an account a friendly name
```

The account you're signed into now is saved automatically the first time you switch away from it. After that, every account is one `use` away.

To keep sessions shared automatically:

```bash
claude-sync install        # background sync every 2 minutes and on every account switch
claude-sync uninstall      # turn it off
```

Other commands:

```bash
claude-sync                # status: what's shared and what would change (changes nothing)
claude-sync --apply        # sync everything now (quits and reopens Claude)
claude-sync restore        # list backups; `claude-sync restore <name>` puts one back
claude-sync forget 2       # delete a saved sign-in (its sessions stay)
claude-sync --help
```

### Important

- **Don't use "Log out" inside Claude.** Logging out ends that sign-in on Anthropic's side, so the saved copy stops working too. Use `claude-sync add` to get to the sign-in screen instead.
- Switching quits Claude, so any session that's running is stopped. macOS may ask once whether your terminal can control Claude: allow it.
- If a saved sign-in expires after a long time unused, sign in once more and it's saved again.

## What gets shared

| | |
|---|---|
| Code tab sessions | merged across accounts; the newest copy of each one wins |
| Cowork sessions | merged; large session data is linked, not copied |
| Session presets, MCP tool toggles | merged |
| Deleting a session | deleted from every account |
| Transcripts, memory, `CLAUDE.md`, skills | already shared: they live in `~/.claude`, which every account uses |

claude.ai chats, projects and chat memory are stored on Anthropic's servers per account, so they can't be shared.

## How it works

The Claude desktop app keeps its data in `~/Library/Application Support/Claude`:

- **Session lists:** `claude-code-sessions/<account>/<org>/` and `local-agent-mode-sessions/<account>/<org>/` hold one small JSON file per session. `claude-sync` copies the newest version of each file into every account's folder. Sessions whose transcript no longer exists aren't spread.
- **While Claude is open,** it only writes into the accounts you're *not* signed into, so the app never has its files changed underneath it. Your current account catches up when you switch or quit.
- **Deletions** are remembered, so a deleted session isn't copied back. If a whole account folder empties at once, as after a sign-out, that's treated as a reset: the folder gets refilled and nothing is deleted from other accounts.
- **Sign-ins:** `claude-sync use` quits Claude and saves the current account's sign-in files into `~/.claude-sync/profiles/<account>/`. Those files are the stored sign-in fields from `config.json`, plus the app's cookies and web storage. It then puts the other account's files in place and reopens Claude. The files are copied as they are and never read; they stay encrypted by macOS the same way the app stores them. The folder is readable only by you.

**Backups:** removed files, and files replaced while Claude is closed, go to `~/.claude-sync-backups/<timestamp>/` first. The last 30 are kept, and the log is `~/.claude-sync-backups/sync.log`.

## Uninstall

```bash
claude-sync uninstall
rm ~/.local/bin/claude-sync
rm -rf ~/.claude-sync ~/.claude-sync-backups   # saved sign-ins and backups
```

## Development

```bash
tests/run.sh                 # end-to-end tests on a fake Claude folder (never touches the real app)
tests/run.sh /usr/bin/python3
```

Environment overrides used by the tests: `CLAUDE_SYNC_APP_DIR`, `CLAUDE_SYNC_PROJECTS`, `CLAUDE_SYNC_BACKUPS`, `CLAUDE_SYNC_PROFILES`, and `CLAUDE_SYNC_NO_APP` (`1` acts as if Claude is closed, `running` as if it's open). `CLAUDE_CONFIG_DIR` is respected the same way Claude Code respects it.

## License

MIT
