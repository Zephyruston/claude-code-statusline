# Claude Code Statusline

A feature-rich statusline script for [Claude Code](https://docs.anthropic.com/en/docs/claude-code), displaying real-time session info, token usage, quota, git status, and historical statistics.

**Platform support:**
- ✅ Windows — `statusline.ps1` (PowerShell)
- ✅ macOS — `statusline.sh` (bash + python3)
- ✅ Linux — `statusline.sh` (bash + python3)

## Preview

```
✦ Stay hungry, stay foolish
Git [main]  M:2  D:0  S:1  U:3   A:0  B:1  V:0  C:0
[Opus 4.7]  Context ████░░░░░░ 45%
Dir:   /your/project
DeepSeek: today ¥0.0120  |  tok:1.5k (in:800 hit:200 out:500)  |  hit_rate:20.0%
Current: in:86.3k  out:59k  ↑cache:0  ✎cache:125.7k  |  Cost: $0.383  |  1h24m  +120/-45
Project: in:302k  out:81k  ↑cache:0  ✎cache:16.8M
Today:   in:375k  out:115k  ↑cache:0  ✎cache:35M
Total:   in:98M  out:2M  ↑cache:104.8M  ✎cache:307.8M
Session: a5363bfe-1234-5678-abcd-ef0123456789
2026-04-16 04:27 UTC  |  12:27 CST  |  v2.1.110
```

> **Motto** line (optional) uses dim white text on dark green background with a `✦` marker. **Model** line uses ANSI colors: model name in cyan, context bar in green/yellow/red depending on usage. **Dir** line highlights the path in yellow. **DeepSeek** line (shown automatically for deepseek models) highlights cost in yellow, token counts in cyan, and cache hit rate in magenta.

## What Each Line Shows

| Line | Description |
|------|-------------|
| **Motto** | User-customizable motto, read from `~/.claude/statusline-motto.txt` (dim white on dark green, optional) |
| **Git** | Branch name, modified/deleted/staged/untracked files, ahead/behind/diverged/conflicts vs remote |
| **Model** | Active model name and context window usage % |
| **Dir** | Current working directory |
| **Quota** | Claude Max subscription quota — 5-hour window and 7-day window usage % (Anthropic models only) |
| **DeepSeek** | Today's API cost (CNY), token usage (input cache miss/hit, output, total), cache hit rate % (deepseek models only) |
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

### Motto

Create `~/.claude/statusline-motto.txt` with your personal motto (one line). It will appear as the first line of the statusline with dim white text on dark green background:

```bash
echo "Stay hungry, stay foolish" > ~/.claude/statusline-motto.txt
```

Delete the file (or leave it empty) to hide the motto line.

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

## DeepSeek Integration

When using DeepSeek models (e.g. `deepseek-v4-pro`, `deepseek-v4-flash`), the statusline automatically detects the model and replaces the Quota line with real-time DeepSeek API status.

### Requirements

Install [deepseek-cli](https://github.com/Zephyruston/deepseek-cli) and authenticate:

```bash
# Install from source (Rust ≥1.85)
git clone https://github.com/Zephyruston/deepseek-cli.git
cd deepseek-cli
cargo install --path .

# Authenticate (WeChat QR)
deepseek login
```

The CLI stores the token at `~/.config/deepseek-cli/config.toml`. No environment variable needed.

The statusline calls `deepseek status --json` with a 2-second timeout. If the CLI is unavailable or the model is not a DeepSeek model, it silently falls back to the standard Quota line.

### Fields displayed

| Field | Source path |
|-------|-------------|
| today cost | `period_cost` |
| total tokens | `period_tokens` |
| input (cache miss) | `period_cache_miss` |
| input (cache hit) | `period_cache_hit` |
| output | `period_output_tokens` |
| cache hit rate | `cache_hit_rate` |

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
