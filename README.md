# Claude Code Statusline

A feature-rich statusline script for [Claude Code](https://docs.anthropic.com/en/docs/claude-code), displaying real-time session info, token usage, quota, git status, and historical statistics.

**Platform support:**
- ✅ Windows — `statusline.ps1` (PowerShell)
- ✅ macOS — `statusline.sh` (bash + python3)
- ✅ Linux — `statusline.sh` (bash + python3)

## Preview

```
Git [main]  M:2  D:0  S:1  U:3   A:0  B:1  V:0  C:0
[Opus 4.7]  Context ████░░░░░░ 45%
Dir:   /your/project
Quota:   5h:30%  7d:15%
Current: in:86.3k  out:59k  ↑cache:0  ✎cache:125.7k  |  Cost: $0.383  |  1h24m  +120/-45
Project: in:302k  out:81k  ↑cache:0  ✎cache:16.8M
Today:   in:375k  out:115k  ↑cache:0  ✎cache:35M
Total:   in:98M  out:2M  ↑cache:104.8M  ✎cache:307.8M
Session: a5363bfe-1234-5678-abcd-ef0123456789
2026-04-16 04:27 UTC  |  12:27 CST  |  v2.1.110
```

> **Model** line uses ANSI colors: model name in cyan, context bar in green/yellow/red depending on usage. **Dir** line highlights the path in yellow.

## What Each Line Shows

| Line | Description |
|------|-------------|
| **Git** | Branch name, modified/deleted/staged/untracked files, ahead/behind/diverged/conflicts vs remote |
| **Model** | Active model name and context window usage % |
| **Dir** | Current working directory |
| **Quota** | Claude Max subscription quota — 5-hour window and 7-day window usage % |
| **Current** | Session cumulative tokens (in/out), cache read/write, equivalent API cost, session duration, lines added/removed |
| **Project** | All-time token usage for the current project directory |
| **Today** | Token usage across all projects today (CST timezone) |
| **Total** | All-time token usage across all projects and all time |
| **Session** | Full session ID |
| **Date/Time** | UTC and CST (UTC+8) time, Claude Code version |

### Git field legend

```
M = Modified (unstaged)    D = Deleted (unstaged)
S = Staged                 U = Untracked
A = Ahead of remote        B = Behind remote
V = diVerged               C = Conflicts
```

### Token field legend

```
in      = input tokens          out     = output tokens
↑cache  = cache read            ✎cache  = cache write (creation)
```

> **Note on Cost:** The `Cost` value is Claude Code's internal estimate based on Anthropic's published API rates. If you use a Claude Max subscription (flat-rate), this reflects equivalent API cost, not actual billing.

---

## Installation

Installation is handled by Claude Code itself — no manual path editing required.

**Step 1 — Clone this repo**

```bash
git clone https://github.com/PeterCang/claude-code-statusline.git
cd claude-code-statusline
```

**Step 2 — Open Claude Code in this directory**

```bash
claude
```

**Step 3 — Type the install prompt**

```
install
```

Claude Code will automatically detect your OS, copy the script to the right location, patch the path, and update your `settings.json`.

**Step 4 — Restart Claude Code**

The statusline will appear in your next session.

---

## Uninstall

Open Claude Code in the cloned repo directory and type:

```
uninstall
```

Claude Code will remove the script and clean up `settings.json`.

---

## Customization

### Timezone

The script defaults to **CST (UTC+8)**. To change it, open the installed script and update the `+8` offset.

**Windows** (`~/.claude/statusline.ps1`):
```powershell
# clock display
$cstNow = $utcNow.AddHours(8)

# today's token filter
$cstNow = [System.DateTime]::UtcNow.AddHours(8)
```

**macOS / Linux** (`~/.claude/statusline.sh`):
```python
# Two occurrences of timedelta(hours=8) in the python block — change both:
cst = utc + timedelta(hours=8)          # clock display
ts_cst = (ts_utc + timedelta(hours=8))  # today's token filter
```

Change `8` to your UTC offset (e.g. `-5` for EST, `9` for JST).

---

## Performance

Token stats (Project / Today / Total) are cached in `~/.claude/statusline-tok-cache.json` and auto-invalidated when new session files appear.

| Scenario | Time |
|----------|------|
| Warm cache | ~200ms |
| Cold / cache miss | ~600ms–2s |

---

## License

MIT
