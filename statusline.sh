#!/usr/bin/env bash
# Claude Code Statusline — macOS / Linux
# Reads session JSON from stdin, outputs 10-line statusline.
# Requires: bash, python3 (stdlib only), git

set -o pipefail
export LANG=en_US.UTF-8

# ── Read JSON from stdin ──────────────────────────────────────────────────────
json=$(cat)

# ── Python helper: parse JSON + compute all derived values ───────────────────
# We do all heavy lifting in one python3 call to avoid spawning many processes.
read -r -d '' _py_main <<'PYEOF'
import sys, json, os
from datetime import datetime, timezone, timedelta
from pathlib import Path

# ── args ──────────────────────────────────────────────────────────────────────
raw_json   = sys.argv[1]
claude_dir = sys.argv[2]

# ── parse input JSON ──────────────────────────────────────────────────────────
try:
    d = json.loads(raw_json)
except Exception:
    d = {}

def jget(obj, *keys):
    for k in keys:
        if not isinstance(obj, dict):
            return None
        obj = obj.get(k)
    return obj

# ── format_tok ────────────────────────────────────────────────────────────────
def fmt(n):
    try:
        n = float(n or 0)
    except Exception:
        n = 0.0
    if n >= 1_000_000:
        v = round(n / 1_000_000, 1)
        return f"{v:g}M"
    if n >= 1_000:
        v = round(n / 1_000, 1)
        return f"{v:g}k"
    return str(int(n))

# ── date / time ───────────────────────────────────────────────────────────────
utc = datetime.now(timezone.utc)
cst = utc + timedelta(hours=8)
date_part = utc.strftime("%Y-%m-%d")
utc_time  = utc.strftime("%H:%M")
cst_time  = cst.strftime("%H:%M")
today_str = cst.strftime("%Y-%m-%d")

version = jget(d, "version") or "?"
dt_line = f"{date_part} {utc_time} UTC  |  {cst_time} CST  |  v{version}"

# ── model & context ───────────────────────────────────────────────────────────
model   = jget(d, "model", "display_name") or "Unknown"
ctx_raw = jget(d, "context_window", "used_percentage")
if ctx_raw is not None:
    ctx_pct = min(100, max(0, round(float(ctx_raw))))
else:
    size = jget(d, "context_window", "context_window_size") or 0
    if size > 0:
        usage = jget(d, "context_window", "current_usage") or {}
        total = (usage.get("input_tokens", 0) or 0) + \
                (usage.get("cache_creation_input_tokens", 0) or 0) + \
                (usage.get("cache_read_input_tokens", 0) or 0)
        ctx_pct = min(100, round(total / size * 100))
    else:
        ctx_pct = 0

# ANSI context bar
BAR_W = 10
filled = max(0, min(BAR_W, round(ctx_pct / 100 * BAR_W)))
empty = BAR_W - filled
if ctx_pct >= 85:
    ctx_color = "\033[31m"      # red
elif ctx_pct >= 70:
    ctx_color = "\033[33m"      # yellow
else:
    ctx_color = "\033[32m"      # green
ctx_bar = f"{ctx_color}{'█' * filled}\033[2m{'░' * empty}\033[0m"

model_line = f"\033[36m[{model}]\033[0m  \033[2mContext\033[0m {ctx_bar} {ctx_color}{ctx_pct}%\033[0m"

# ── cwd ───────────────────────────────────────────────────────────────────────
cwd = jget(d, "cwd") or jget(d, "workspace", "current_dir") or "?"
dir_line = f"\033[2mDir:\033[0m   \033[33m{cwd}\033[0m"

# ── session tokens ────────────────────────────────────────────────────────────
ses_in  = int(jget(d, "context_window", "total_input_tokens")  or 0)
ses_out = int(jget(d, "context_window", "total_output_tokens") or 0)
ses_cr  = int(jget(d, "context_window", "current_usage", "cache_read_input_tokens")     or 0)
ses_cw  = int(jget(d, "context_window", "current_usage", "cache_creation_input_tokens") or 0)
ses_cost    = float(jget(d, "cost", "total_cost_usd")      or 0)
ses_dur_ms  = int(  jget(d, "cost", "total_duration_ms")   or 0)
ses_added   = int(  jget(d, "cost", "total_lines_added")   or 0)
ses_removed = int(  jget(d, "cost", "total_lines_removed") or 0)

dur_str = ""
if ses_dur_ms > 0:
    ts = ses_dur_ms // 1000
    h, rem = divmod(ts, 3600)
    m, s   = divmod(rem, 60)
    dur_str = f"{h}h{m}m" if h >= 1 else f"{m}m{s}s"

token_line = (
    f"Current: in:{fmt(ses_in)}  out:{fmt(ses_out)}  "
    f"rcache:{fmt(ses_cr)}  wcache:{fmt(ses_cw)}  |  Cost: ${round(ses_cost,3)}"
)
if dur_str:
    token_line += f"  |  duration: {dur_str}"
if ses_added > 0 or ses_removed > 0:
    token_line += f"  Changes: +{ses_added}/-{ses_removed}"

# ── quota (Anthropic) ──────────────────────────────────────────────────────────
q5h_raw = jget(d, "rate_limits", "five_hour",  "used_percentage")
q7d_raw = jget(d, "rate_limits", "seven_day",  "used_percentage")
q5h = f"{round(float(q5h_raw))}%" if q5h_raw is not None else "?"
q7d = f"{round(float(q7d_raw))}%" if q7d_raw is not None else "?"
quota_line = f"Quota:   5h:{q5h}  7d:{q7d}"

# ── DeepSeek status ───────────────────────────────────────────────────────────
ds_raw = sys.argv[3] if len(sys.argv) > 3 else '{}'
model_name = (jget(d, "model", "display_name") or "").lower()
is_deepseek = "deepseek" in model_name

deepseek_line = "DeepSeek: -"
if is_deepseek and ds_raw:
    try:
        ds = json.loads(ds_raw)
    except Exception:
        ds = {}
    if ds:
        ds_cost   = float(ds.get("period_cost", 0) or 0)
        if ds_cost == 0.0:
            ds_cost = 0.0  # normalize -0.0
        ds_total  = int(ds.get("period_tokens", 0) or 0)
        ds_hit    = int(ds.get("period_cache_hit", 0) or 0)
        ds_miss   = int(ds.get("period_cache_miss", 0) or 0)
        ds_out    = int(ds.get("period_output_tokens", 0) or 0)
        ds_rate   = float(ds.get("cache_hit_rate", 0) or 0)
        deepseek_line = (
            f"DeepSeek: today \033[33m¥{ds_cost:.4f}\033[0m  |  "
            f"tok:\033[36m{fmt(ds_total)}\033[0m "
            f"(in:\033[36m{fmt(ds_miss)}\033[0m "
            f"hit:\033[36m{fmt(ds_hit)}\033[0m "
            f"out:\033[36m{fmt(ds_out)}\033[0m)  |  "
            f"hit_rate:\033[35m{ds_rate*100:.1f}%\033[0m"
        )

# ── session id ────────────────────────────────────────────────────────────────
sid = jget(d, "session_id") or "?"
session_line = f"Session: {sid}"

# ── token stats (proj / today / total) with mtime cache ──────────────────────
cache_file   = Path(claude_dir) / "statusline-tok-cache.json"
projects_dir = Path(claude_dir) / "projects"
stats_file   = Path(claude_dir) / "stats-cache.json"
cwd_norm     = cwd.replace(":", "-").replace("\\", "-").replace("/", "-")
proj_dir     = projects_dir / cwd_norm

proj_in=proj_out=proj_cr=proj_cw=0
today_in=today_out=today_cr=today_cw=0
total_in=total_out=total_cr=total_cw=0

cache = {}
try:
    with open(cache_file) as f:
        cache = json.load(f)
except Exception:
    pass

def parse_ts(s):
    try:
        return datetime.fromisoformat(str(s).replace("Z", "+00:00"))
    except Exception:
        return None

def newest_mtime(path, min_epoch=None):
    best = None
    try:
        for f in Path(path).rglob("*.jsonl"):
            mt = f.stat().st_mtime
            if min_epoch is None or mt >= min_epoch:
                best = mt if best is None else max(best, mt)
    except Exception:
        pass
    return best

now_ts = utc.isoformat()

# ── project ───────────────────────────────────────────────────────────────────
proj_valid = False
try:
    cp = cache.get("proj", {})
    if cp.get("cwd") == cwd and cp.get("ts"):
        ct = parse_ts(cp["ts"])
        if ct:
            nm = newest_mtime(proj_dir)
            proj_valid = nm is None or nm <= ct.timestamp()
except Exception:
    pass

if proj_valid:
    proj_in  = int(cache["proj"].get("in",  0))
    proj_out = int(cache["proj"].get("out", 0))
    proj_cr  = int(cache["proj"].get("cR",  0))
    proj_cw  = int(cache["proj"].get("cW",  0))
elif proj_dir.exists():
    for jf in proj_dir.rglob("*.jsonl"):
        try:
            with open(jf) as f:
                for line in f:
                    if "input_tokens" not in line:
                        continue
                    try:
                        obj = json.loads(line)
                        if obj.get("type") == "assistant":
                            u = (obj.get("message") or {}).get("usage") or {}
                            proj_in  += int(u.get("input_tokens", 0) or 0)
                            proj_out += int(u.get("output_tokens", 0) or 0)
                            proj_cr  += int(u.get("cache_read_input_tokens", 0) or 0)
                            proj_cw  += int(u.get("cache_creation_input_tokens", 0) or 0)
                    except Exception:
                        pass
        except Exception:
            pass

# ── today ─────────────────────────────────────────────────────────────────────
today_valid = False
try:
    ct2 = cache.get("today", {})
    if ct2.get("date") == today_str and ct2.get("ts"):
        ct = parse_ts(ct2["ts"])
        if ct:
            cutoff = (utc - timedelta(hours=25)).timestamp()
            nm = newest_mtime(projects_dir, min_epoch=cutoff)
            today_valid = nm is None or nm <= ct.timestamp()
except Exception:
    pass

if today_valid:
    today_in  = int(cache["today"].get("in",  0))
    today_out = int(cache["today"].get("out", 0))
    today_cr  = int(cache["today"].get("cR",  0))
    today_cw  = int(cache["today"].get("cW",  0))
else:
    cutoff = (utc - timedelta(hours=25)).timestamp()
    for jf in projects_dir.rglob("*.jsonl"):
        try:
            if jf.stat().st_mtime < cutoff:
                continue
            with open(jf) as f:
                for line in f:
                    if "input_tokens" not in line:
                        continue
                    try:
                        obj = json.loads(line)
                        if obj.get("type") == "assistant":
                            u = (obj.get("message") or {}).get("usage") or {}
                            ts_raw = obj.get("timestamp")
                            if ts_raw:
                                ts_utc = parse_ts(ts_raw)
                                if ts_utc:
                                    ts_cst = (ts_utc + timedelta(hours=8)).strftime("%Y-%m-%d")
                                    if ts_cst >= today_str:
                                        today_in  += int(u.get("input_tokens", 0) or 0)
                                        today_out += int(u.get("output_tokens", 0) or 0)
                                        today_cr  += int(u.get("cache_read_input_tokens", 0) or 0)
                                        today_cw  += int(u.get("cache_creation_input_tokens", 0) or 0)
                    except Exception:
                        pass
        except Exception:
            pass

# ── total ─────────────────────────────────────────────────────────────────────
total_valid = False
try:
    cto = cache.get("total", {})
    if cto.get("ts"):
        ct = parse_ts(cto["ts"])
        if ct and stats_file.exists():
            total_valid = stats_file.stat().st_mtime <= ct.timestamp()
except Exception:
    pass

if total_valid:
    total_in  = int(cache["total"].get("in",  0))
    total_out = int(cache["total"].get("out", 0))
    total_cr  = int(cache["total"].get("cR",  0))
    total_cw  = int(cache["total"].get("cW",  0))
else:
    last_computed = "1970-01-01"
    try:
        with open(stats_file) as f:
            stats = json.load(f)
        for m in (stats.get("modelUsage") or {}).values():
            total_in  += int(m.get("inputTokens", 0) or 0)
            total_out += int(m.get("outputTokens", 0) or 0)
            total_cr  += int(m.get("cacheReadInputTokens", 0) or 0)
            total_cw  += int(m.get("cacheCreationInputTokens", 0) or 0)
        last_computed = stats.get("lastComputedDate") or "1970-01-01"
    except Exception:
        pass
    try:
        lc_epoch = datetime.fromisoformat(last_computed).replace(tzinfo=timezone.utc).timestamp()
        for jf in projects_dir.rglob("*.jsonl"):
            try:
                if jf.stat().st_mtime <= lc_epoch:
                    continue
                with open(jf) as f:
                    for line in f:
                        if "input_tokens" not in line:
                            continue
                        try:
                            obj = json.loads(line)
                            if obj.get("type") == "assistant":
                                u = (obj.get("message") or {}).get("usage") or {}
                                ts_raw = obj.get("timestamp")
                                if ts_raw:
                                    ts_utc = parse_ts(ts_raw)
                                    if ts_utc and ts_utc.strftime("%Y-%m-%d") > last_computed:
                                        total_in  += int(u.get("input_tokens", 0) or 0)
                                        total_out += int(u.get("output_tokens", 0) or 0)
                                        total_cr  += int(u.get("cache_read_input_tokens", 0) or 0)
                                        total_cw  += int(u.get("cache_creation_input_tokens", 0) or 0)
                        except Exception:
                            pass
            except Exception:
                pass
    except Exception:
        pass

# ── save cache ────────────────────────────────────────────────────────────────
try:
    with open(cache_file, "w") as f:
        json.dump({
            "proj":  {"cwd": cwd, "ts": now_ts, "in": proj_in,  "out": proj_out,  "cR": proj_cr,  "cW": proj_cw},
            "today": {"date": today_str, "ts": now_ts, "in": today_in, "out": today_out, "cR": today_cr, "cW": today_cw},
            "total": {"ts": now_ts, "in": total_in, "out": total_out, "cR": total_cr, "cW": total_cw},
        }, f)
except Exception:
    pass

# ── build remaining lines ─────────────────────────────────────────────────────
proj_line  = (f"Project: in:{fmt(proj_in)}  out:{fmt(proj_out)}  "
              f"rcache:{fmt(proj_cr)}  wcache:{fmt(proj_cw)}")
today_line = (f"Today:   in:{fmt(today_in)}  out:{fmt(today_out)}  "
              f"rcache:{fmt(today_cr)}  wcache:{fmt(today_cw)}")
total_line = (f"Total:   in:{fmt(total_in)}  out:{fmt(total_out)}  "
              f"rcache:{fmt(total_cr)}  wcache:{fmt(total_cw)}")

# ── print all 10 lines ────────────────────────────────────────────────────────
# Line 1 (git) is printed by bash; we print lines 2-10 here.
# To keep it simple, we print ALL lines from python and bash just calls python.
print("__MODEL__"   + model_line)
print("__DIR__"     + dir_line)
if is_deepseek:
    print("__DEEPSEEK__" + deepseek_line)
else:
    print("__QUOTA__"   + quota_line)
print("__CURRENT__" + token_line)
print("__PROJ__"    + proj_line)
print("__TODAY__"   + today_line)
print("__TOTAL__"   + total_line)
print("__SESSION__" + session_line)
print("__DT__"      + dt_line)
PYEOF

# ── Motto (user-customizable) ─────────────────────────────────────────────────
motto_file="$HOME/.claude/statusline-motto.txt"
motto_line=""
if [ -f "$motto_file" ]; then
    _motto=$(cat "$motto_file" 2>/dev/null | head -1 | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
    if [ -n "$_motto" ]; then
        motto_line=$(printf '\033[2;30;103m ✦ %s \033[0m' "$_motto")
    fi
fi

# ── Git status (bash, runs in current directory) ──────────────────────────────
git_modified=0; git_deleted=0; git_staged=0; git_untracked=0
git_ahead=0; git_behind=0; git_diverged=0; git_conflicts=0
branch="-"

if git -c core.fsmonitor=false rev-parse --git-dir &>/dev/null 2>&1; then
    branch=$(git -c core.fsmonitor=false rev-parse --abbrev-ref HEAD 2>/dev/null)
    [ -z "$branch" ] && branch="-"

    while IFS= read -r line; do
        [ "${#line}" -lt 2 ] && continue
        x="${line:0:1}"
        y="${line:1:1}"
        if [ "$x" = "?" ] && [ "$y" = "?" ]; then
            (( git_untracked++ )); continue
        fi
        if [ "$x" = "U" ] || [ "$y" = "U" ] || \
           { [ "$x" = "A" ] && [ "$y" = "A" ]; } || \
           { [ "$x" = "D" ] && [ "$y" = "D" ]; }; then
            (( git_conflicts++ )); continue
        fi
        if [ "$x" != " " ] && [ "$x" != "?" ]; then
            (( git_staged++ ))
        fi
        [ "$y" = "M" ] && (( git_modified++ ))
        [ "$y" = "D" ] && (( git_deleted++ ))
    done < <(git -c core.fsmonitor=false status --porcelain=v1 -u 2>/dev/null)

    ab_line=$(git -c core.fsmonitor=false rev-list --left-right --count '@{upstream}...HEAD' 2>/dev/null)
    if [ -n "$ab_line" ]; then
        git_behind=$(awk '{print $1}' <<< "$ab_line")
        git_ahead=$(awk  '{print $2}' <<< "$ab_line")
        git_behind=${git_behind:-0}; git_ahead=${git_ahead:-0}
        if [ "$git_ahead" -gt 0 ] && [ "$git_behind" -gt 0 ]; then
            git_diverged=1
        fi
    fi
fi

git_line="Git [$branch]  M:$git_modified  D:$git_deleted  S:$git_staged  U:$git_untracked   A:$git_ahead  B:$git_behind  V:$git_diverged  C:$git_conflicts"

# ── DeepSeek status (only for deepseek models) ────────────────────────────────
ds_json='{}'
model_name=$(echo "$json" | jq -r '.model.display_name // ""' 2>/dev/null)
if [[ "$model_name" == *[Dd][Ee][Ee][Pp][Ss][Ee][Ee][Kk]* ]]; then
    ds_json=$(timeout 2 deepseek status --json 2>/dev/null || echo '{}')
fi

# ── Run python for everything else ────────────────────────────────────────────
py_out=$(python3 -c "$_py_main" "$json" "$HOME/.claude" "$ds_json" 2>/dev/null)

# ── Extract lines by prefix and strip prefix ─────────────────────────────────
_line() { grep "^__${1}__" <<< "$py_out" | sed "s/^__${1}__//"; }

# ── Output all lines ──────────────────────────────────────────────────────────
if [ -n "$motto_line" ]; then
    printf '%s\n' "$motto_line"
fi
printf '%s\n' "$git_line"
_line MODEL
_line DIR
# Line 4: DeepSeek (for deepseek models) or Quota (for Anthropic models)
ds_line=$(_line DEEPSEEK)
if [ -n "$ds_line" ]; then
    printf '%s\n' "$ds_line"
else
    _line QUOTA
fi
_line CURRENT
_line PROJ
_line TODAY
_line TOTAL
_line SESSION
_line DT
