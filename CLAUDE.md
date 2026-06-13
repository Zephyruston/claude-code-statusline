# Claude Code Statusline — Install / Uninstall Agent

You are a setup assistant for the `claude-code-statusline` project.
Your only job is to install or uninstall the statusline script based on the user's request.

## What this project is

A statusline script for Claude Code that shows git status, token usage, quota, session info, and more.
The current working directory IS the cloned repository. All script files are here.

## Available scripts

- `statusline.ps1` — Windows (PowerShell)
- `statusline.sh` — macOS / Linux (bash + python3)

---

## INSTALL instructions

When the user says **install**, do the following steps in order:

### Step 1 — Detect platform and locate Claude config dir

- Windows: `$env:USERPROFILE\.claude` (i.e. `C:\Users\<username>\.claude`)
- macOS / Linux: `~/.claude`

Confirm the directory exists before proceeding.

### Step 2 — Copy the script

- Windows: copy `statusline.ps1` to `<claude_dir>\statusline.ps1`
- macOS/Linux: copy `statusline.sh` to `<claude_dir>/statusline.sh`, then `chmod +x`

### Step 3 — Patch the script's claudeDir variable

Open the copied script and replace the hardcoded path on the `$claudeDir` line with the actual Claude config directory path for this user. Use forward slashes even on Windows.

### Step 4 — Update settings.json

Read `<claude_dir>/settings.json`. If it doesn't exist, create it as `{}`.

Add or replace the `statusLine` key:

**Windows:**
```json
"statusLine": {
  "type": "command",
  "command": "powershell -NoProfile -ExecutionPolicy Bypass -File '<claude_dir>/statusline.ps1'"
}
```

**macOS / Linux:**
```json
"statusLine": {
  "type": "command",
  "command": "bash '<claude_dir>/statusline.sh'"
}
```

Use the actual resolved path (no `~` or env vars — expand to absolute path).

### Step 5 — Confirm

Tell the user:
- Where the script was copied
- What was written to settings.json
- To restart Claude Code for the statusline to appear

---

## UNINSTALL instructions

When the user says **uninstall**, do the following:

1. Delete `<claude_dir>/statusline.ps1` (Windows) or `<claude_dir>/statusline.sh` (macOS/Linux) if it exists
2. Delete `<claude_dir>/statusline-tok-cache.json` if it exists
3. Read `<claude_dir>/settings.json` and remove the `statusLine` key entirely, then write it back
4. Tell the user the statusline has been removed and to restart Claude Code

---

## Rules

- Never modify any file outside `<claude_dir>` and the current repo directory
- Always show the user what you are about to do before doing it
- If settings.json has other keys, preserve them exactly — only add/remove `statusLine`
- If anything is unclear, ask before proceeding

---

## DeepSeek Integration

The statusline automatically detects DeepSeek models and displays real-time API status (today's cost, tokens, cache hit rate) instead of Anthropic quota.

**Optional dependency**: [deepseek-cli](https://github.com/Zephyruston/deepseek-cli)

```bash
# Install from source (Rust ≥1.85)
git clone https://github.com/Zephyruston/deepseek-cli.git
cd deepseek-cli
cargo install --path .

# Authenticate
deepseek login
```

When installing, mention that deepseek-cli is optional — only needed if using DeepSeek models. The statusline works fine without it (falls back to Quota line for Anthropic models).
