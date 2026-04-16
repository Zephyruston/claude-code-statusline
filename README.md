# Claude Code Statusline

A feature-rich statusline script for [Claude Code](https://docs.anthropic.com/en/docs/claude-code), displaying real-time session info, token usage, quota, git status, and historical statistics.

**Platform support:**
- ✅ Windows — `statusline.ps1` (PowerShell)
- 🔜 macOS — coming soon
- 🔜 Linux — coming soon

## Preview

```
Git [main]  M:2  D:0  S:1  U:3   A:0  B:1  V:0  C:0
Model: Sonnet 4.6  |  ctx:45%
Dir:   /your/project
Quota:   5h:30%  7d:15%
Current: in:86.3k  out:59k  ↑cache:0  ✎cache:125.7k  |  Cost: $48.383  |  1h24m  +120/-45
Project: in:302k  out:81k  ↑cache:0  ✎cache:16.8M
Today:   in:375k  out:115k  ↑cache:0  ✎cache:35M
Total:   in:98M  out:2M  ↑cache:104.8M  ✎cache:307.8M
Session: a5363bfe-1234-5678-abcd-ef0123456789
2026-04-16 04:27 UTC  |  12:27 CST  |  v2.1.110
```

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

## Windows (PowerShell)

### Requirements

- PowerShell 5.1+
- [Claude Code](https://docs.anthropic.com/en/docs/claude-code) CLI
- Git (optional, for git status)

### Installation

**1. Download the script**

```powershell
Invoke-WebRequest -Uri "https://raw.githubusercontent.com/PeterCang/claude-code-statusline/master/statusline.ps1" -OutFile "$env:USERPROFILE\.claude\statusline.ps1"
```

Or clone and copy manually:

```powershell
git clone https://github.com/PeterCang/claude-code-statusline.git
Copy-Item claude-code-statusline\statusline.ps1 "$env:USERPROFILE\.claude\statusline.ps1"
```

**2. Edit the script — set your username**

Open `statusline.ps1` and update line 19:

```powershell
$claudeDir = 'C:/Users/YOUR_USERNAME/.claude'
```

**3. Configure Claude Code**

Add to `%USERPROFILE%\.claude\settings.json`:

```json
{
  "statusLine": {
    "type": "command",
    "command": "powershell -NoProfile -ExecutionPolicy Bypass -File 'C:/Users/YOUR_USERNAME/.claude/statusline.ps1'"
  }
}
```

**4. Restart Claude Code**

---

## Customization

### Timezone

The script defaults to **CST (UTC+8)**. To use a different timezone, update the `+8` offset in two places:

```powershell
# clock display (~line 52)
$cstNow = $utcNow.AddHours(8)

# today's token filter (~line 102)
$cstNow = [System.DateTime]::UtcNow.AddHours(8)
```

## Performance

Token stats (Project / Today / Total) are cached in `~/.claude/statusline-tok-cache.json` and auto-invalidated when new session files appear.

| Scenario | Time |
|----------|------|
| Warm cache | ~200ms |
| Cold / cache miss | ~600ms–2s |

## License

MIT
