$ErrorActionPreference = 'SilentlyContinue'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

# Read JSON from stdin
try {
    $jsonText = [Console]::In.ReadToEnd()
    $d = ConvertFrom-Json $jsonText
} catch {
    $d = @{}
}

# Helper: format token count as k/M
function Format-Tok([long]$n) {
    if ($n -ge 1000000) { return "$([math]::Round($n/1000000,1))M" }
    if ($n -ge 1000)    { return "$([math]::Round($n/1000,1))k" }
    return "$n"
}

$claudeDir = 'C:/Users/Murphy/.claude'

# --- Git status ---
$gitModified  = 0; $gitDeleted = 0; $gitStaged = 0; $gitUntracked = 0
$gitAhead = 0; $gitBehind = 0; $gitDiverged = 0; $gitConflicts = 0
try {
    $gitStatus = git -c core.fsmonitor=false status --porcelain=v1 -u 2>$null
    if ($LASTEXITCODE -eq 0 -and $gitStatus) {
        foreach ($line in ($gitStatus -split "`n")) {
            if ($line.Length -lt 2) { continue }
            $x = $line[0]; $y = $line[1]
            if ($x -eq '?' -and $y -eq '?') { $gitUntracked++; continue }
            if (($x -eq 'U' -or $y -eq 'U') -or ($x -eq 'A' -and $y -eq 'A') -or ($x -eq 'D' -and $y -eq 'D')) { $gitConflicts++; continue }
            if ($x -ne ' ' -and $x -ne '?') { $gitStaged++ }
            if ($y -eq 'M') { $gitModified++ }
            if ($y -eq 'D') { $gitDeleted++ }
        }
    }
    $abLine = git -c core.fsmonitor=false rev-list --left-right --count '@{upstream}...HEAD' 2>$null
    if ($LASTEXITCODE -eq 0 -and $abLine) {
        $parts = ($abLine -split '\s+')
        if ($parts.Count -ge 2) {
            $gitBehind = [int]$parts[0]; $gitAhead = [int]$parts[1]
            if ($gitAhead -gt 0 -and $gitBehind -gt 0) { $gitDiverged = 1 }
        }
    }
    $branch = git -c core.fsmonitor=false rev-parse --abbrev-ref HEAD 2>$null
    if (-not $branch) { $branch = '-' }
} catch {}
$gitLine = "Git [$branch]  M:$gitModified  D:$gitDeleted  S:$gitStaged  U:$gitUntracked   A:$gitAhead  B:$gitBehind  V:$gitDiverged  C:$gitConflicts"

# --- DeepSeek status (only for deepseek models) ---
$isDeepseek = $false
$dsJson = '{}'
try {
    $modelName = if ($d.model -and $d.model.display_name) { $d.model.display_name } else { '' }
    if ($modelName -match 'deepseek') {
        $isDeepseek = $true
        $dsOutput = deepseek status --json 2>$null
        if ($LASTEXITCODE -eq 0 -and $dsOutput) {
            $dsJson = $dsOutput
        }
    }
} catch {}

# --- Date / Time ---
$utcNow   = [System.DateTime]::UtcNow
$cstNow   = $utcNow.AddHours(8)
$datePart = $utcNow.ToString("yyyy-MM-dd")
$utcTime  = $utcNow.ToString("HH:mm")
$cstTime  = $cstNow.ToString("HH:mm")
$version  = if ($d.version) { $d.version } else { "?" }
$dtLine   = "$datePart $utcTime UTC  |  $cstTime CST  |  v$version"

# --- Model & context ---
$model   = if ($d.model -and $d.model.display_name) { $d.model.display_name } else { "Unknown" }

# Context percentage
if ($d.context_window -and $null -ne $d.context_window.used_percentage -and $d.context_window.used_percentage -gt 0) {
    $ctxPct = [math]::Max(0, [math]::Min(100, [math]::Round($d.context_window.used_percentage)))
} else {
    $size = if ($d.context_window -and $d.context_window.context_window_size) { $d.context_window.context_window_size } else { 0 }
    if ($size -gt 0) {
        $usage = if ($d.context_window -and $d.context_window.current_usage) { $d.context_window.current_usage } else { $null }
        $total = 0
        if ($usage) {
            if ($usage.input_tokens) { $total += $usage.input_tokens }
            if ($usage.cache_creation_input_tokens) { $total += $usage.cache_creation_input_tokens }
            if ($usage.cache_read_input_tokens) { $total += $usage.cache_read_input_tokens }
        }
        $ctxPct = [math]::Min(100, [math]::Round($total / $size * 100))
    } else { $ctxPct = 0 }
}

# ANSI colors
$reset   = [char]0x1B + '[0m'
$dim     = [char]0x1B + '[2m'
$red     = [char]0x1B + '[31m'
$green   = [char]0x1B + '[32m'
$yellow  = [char]0x1B + '[33m'
$magenta = [char]0x1B + '[35m'
$cyan    = [char]0x1B + '[36m'

# Context bar
$barW = 10
$filled = [math]::Max(0, [math]::Min($barW, [math]::Round($ctxPct / 100 * $barW)))
$empty = $barW - $filled
if ($ctxPct -ge 85) { $ctxColor = $red }
elseif ($ctxPct -ge 70) { $ctxColor = $yellow }
else { $ctxColor = $green }
$ctxBar = "$ctxColor$([char]0x2588 * $filled)$dim$([char]0x2591 * $empty)$reset"

$modelLine = "$cyan[$model]$reset  ${dim}Context$reset $ctxBar $ctxColor${ctxPct}%$reset"

# --- CWD ---
$cwd = "?"
if ($d.cwd) { $cwd = $d.cwd }
elseif ($d.workspace -and $d.workspace.current_dir) { $cwd = $d.workspace.current_dir }
$dirLine = "${dim}Dir:$reset   $yellow$cwd$reset"

# --- Session tokens (from statusline JSON) ---
# Fields: context_window.total_input_tokens / total_output_tokens (session cumulative)
#         context_window.current_usage.* (current turn)
#         cost.total_cost_usd (session cumulative cost)
$sesIn    = 0; $sesOut = 0; $sesCR = 0; $sesCW = 0; $sesCost = 0.0
try {
    if ($d.context_window) {
        $sesIn  = if ($d.context_window.total_input_tokens)  { [long]$d.context_window.total_input_tokens }  else { 0 }
        $sesOut = if ($d.context_window.total_output_tokens) { [long]$d.context_window.total_output_tokens } else { 0 }
        if ($d.context_window.current_usage) {
            $sesCR = if ($d.context_window.current_usage.cache_read_input_tokens)     { [long]$d.context_window.current_usage.cache_read_input_tokens }     else { 0 }
            $sesCW = if ($d.context_window.current_usage.cache_creation_input_tokens) { [long]$d.context_window.current_usage.cache_creation_input_tokens } else { 0 }
        }
    }
    if ($d.cost -and $d.cost.total_cost_usd) { $sesCost = [double]$d.cost.total_cost_usd }
    $sesDurMs = if ($d.cost -and $d.cost.total_duration_ms) { [long]$d.cost.total_duration_ms } else { 0 }
    $sesAdded   = if ($d.cost -and $d.cost.total_lines_added)   { [long]$d.cost.total_lines_added }   else { 0 }
    $sesRemoved = if ($d.cost -and $d.cost.total_lines_removed) { [long]$d.cost.total_lines_removed } else { 0 }
} catch {}
$sesDurStr = ''
if ($sesDurMs -gt 0) {
    $ts = [TimeSpan]::FromMilliseconds($sesDurMs)
    if ($ts.TotalHours -ge 1) { $sesDurStr = "$([int]$ts.TotalHours)h$($ts.Minutes)m" }
    else { $sesDurStr = "$($ts.Minutes)m$($ts.Seconds)s" }
}
$tokenLine = "Current: in:$(Format-Tok $sesIn)  out:$(Format-Tok $sesOut)  " +
             [char]0x2191 + "cache:$(Format-Tok $sesCR)  " +
             [char]0x270E + "cache:$(Format-Tok $sesCW)  |  Cost: `$$([math]::Round($sesCost,3))" +
             $(if ($sesDurStr) { "  |  $sesDurStr" } else { "" }) +
             $(if ($sesAdded -gt 0 -or $sesRemoved -gt 0) { "  +$sesAdded/-$sesRemoved" } else { "" })

# --- Rate limits / Quota ---
$quota5h = '?'; $quota7d = '?'
try {
    if ($d.rate_limits) {
        if ($d.rate_limits.five_hour -and $null -ne $d.rate_limits.five_hour.used_percentage) {
            $quota5h = "$([math]::Round($d.rate_limits.five_hour.used_percentage, 0))%"
        }
        if ($d.rate_limits.seven_day -and $null -ne $d.rate_limits.seven_day.used_percentage) {
            $quota7d = "$([math]::Round($d.rate_limits.seven_day.used_percentage, 0))%"
        }
    }
} catch {}
$quotaLine = "Quota:   5h:$quota5h  7d:$quota7d"

# --- DeepSeek status ---
$deepseekLine = "DeepSeek: -"
if ($isDeepseek -and $dsJson -ne '{}') {
    try {
        $ds = ConvertFrom-Json $dsJson
        $dsCost   = if ($ds.today_cost) { [double]$ds.today_cost } else { 0.0 }
        $dsTokens = if ($ds.today_tokens) { $ds.today_tokens } else { $null }
        $dsHit    = if ($dsTokens -and $dsTokens.input_cache_hit) { [long]$dsTokens.input_cache_hit } else { 0 }
        $dsMiss   = if ($dsTokens -and $dsTokens.input_cache_miss) { [long]$dsTokens.input_cache_miss } else { 0 }
        $dsOut    = if ($dsTokens -and $dsTokens.output) { [long]$dsTokens.output } else { 0 }
        $dsTotal  = if ($dsTokens -and $dsTokens.total) { [long]$dsTokens.total } else { 0 }
        $dsRate   = if ($dsTokens -and $null -ne $dsTokens.cache_hit_rate) { [double]$dsTokens.cache_hit_rate } else { 0.0 }
        $deepseekLine = "DeepSeek: today $yellow`$$([math]::Round($dsCost,4))$reset  |  " +
            "tok:$cyan$(Format-Tok $dsTotal)$reset " +
            "(in:$cyan$(Format-Tok $dsMiss)$reset " +
            "hit:$cyan$(Format-Tok $dsHit)$reset " +
            "out:$cyan$(Format-Tok $dsOut)$reset)  |  " +
            "hit_rate:$magenta$([math]::Round($dsRate,1))%$reset"
    } catch {}
}

# --- Project / Today / Total tokens (with file-mtime cache) ---
$cacheFile = $claudeDir + '/statusline-tok-cache.json'
$projIn=0; $projOut=0; $projCR=0; $projCW=0
$todayIn=0; $todayOut=0; $todayCR=0; $todayCW=0
$totalIn=0; $totalOut=0; $totalCR=0; $totalCW=0

try {
    # Load cache
    $c = $null
    if (Test-Path $cacheFile) { $c = Get-Content $cacheFile -Raw | ConvertFrom-Json }

    $cwdNorm = $cwd.Replace(':', '-').Replace('\', '-').Replace('/', '-')
    $projDir = $claudeDir + '/projects/' + $cwdNorm
    # Use CST (UTC+8) for "today" so late-night UTC records aren't missed
    $cstNow   = [System.DateTime]::UtcNow.AddHours(8)
    $today    = $cstNow.Date
    $todayStr = $today.ToString('yyyy-MM-dd')

    # --- Project cache check ---
    $projValid = $false
    if ($c -and $c.proj -and $c.proj.cwd -eq $cwd -and $c.proj.ts) {
        try {
            $projCacheTime = [System.DateTime]::Parse($c.proj.ts)
            if (Test-Path $projDir) {
                $newestProj = Get-ChildItem $projDir -Filter '*.jsonl' -Recurse |
                    Sort-Object LastWriteTime -Descending | Select-Object -First 1
                $projValid = (-not $newestProj) -or ($newestProj.LastWriteTime -le $projCacheTime)
            } else { $projValid = $true }
        } catch {}
    }
    if ($projValid) {
        $projIn = [long]$c.proj.in; $projOut = [long]$c.proj.out
        $projCR = [long]$c.proj.cR; $projCW  = [long]$c.proj.cW
    } elseif (Test-Path $projDir) {
        Get-ChildItem $projDir -Filter '*.jsonl' -Recurse | ForEach-Object {
            Get-Content $_.FullName | ForEach-Object {
                if ($_ -match 'input_tokens') {
                    try {
                        $obj = ConvertFrom-Json $_
                        if ($obj.type -eq 'assistant' -and $obj.message -and $obj.message.usage) {
                            $projIn += [long]$obj.message.usage.input_tokens
                            $projOut += [long]$obj.message.usage.output_tokens
                            $projCR  += [long]$obj.message.usage.cache_read_input_tokens
                            $projCW  += [long]$obj.message.usage.cache_creation_input_tokens
                        }
                    } catch {}
                }
            }
        }
    }

    # --- Today cache check ---
    $todayValid = $false
    if ($c -and $c.today -and $c.today.date -eq $todayStr -and $c.today.ts) {
        try {
            $todayCacheTime = [System.DateTime]::Parse($c.today.ts)
            $newestToday = Get-ChildItem ($claudeDir + '/projects') -Filter '*.jsonl' -Recurse |
                Where-Object { $_.LastWriteTime -ge $today.AddDays(-1) } |
                Sort-Object LastWriteTime -Descending | Select-Object -First 1
            $todayValid = (-not $newestToday) -or ($newestToday.LastWriteTime -le $todayCacheTime)
        } catch {}
    }
    if ($todayValid) {
        $todayIn = [long]$c.today.in; $todayOut = [long]$c.today.out
        $todayCR = [long]$c.today.cR; $todayCW  = [long]$c.today.cW
    } else {
        Get-ChildItem ($claudeDir + '/projects') -Filter '*.jsonl' -Recurse |
            Where-Object { $_.LastWriteTime -ge $today.AddDays(-1) } |
            ForEach-Object {
                Get-Content $_.FullName | ForEach-Object {
                    if ($_ -match 'input_tokens') {
                        try {
                            $obj = ConvertFrom-Json $_
                            if ($obj.type -eq 'assistant' -and $obj.message -and $obj.message.usage -and $obj.timestamp) {
                                # Convert UTC timestamp to CST for date comparison
                                $tsUtc = [System.DateTime]::Parse($obj.timestamp.ToString())
                                $tsCst = $tsUtc.AddHours(8).ToString('yyyy-MM-dd')
                                if ($tsCst -ge $todayStr) {
                                    $todayIn += [long]$obj.message.usage.input_tokens
                                    $todayOut += [long]$obj.message.usage.output_tokens
                                    $todayCR  += [long]$obj.message.usage.cache_read_input_tokens
                                    $todayCW  += [long]$obj.message.usage.cache_creation_input_tokens
                                }
                            }
                        } catch {}
                    }
                }
            }
    }

    # --- Total cache check (keyed on stats-cache.json mtime) ---
    $totalValid = $false
    if ($c -and $c.total -and $c.total.ts) {
        try {
            $statsItem = Get-Item ($claudeDir + '/stats-cache.json')
            $totalCacheTime = [System.DateTime]::Parse($c.total.ts)
            $totalValid = ($statsItem.LastWriteTime -le $totalCacheTime)
        } catch {}
    }
    if ($totalValid) {
        $totalIn = [long]$c.total.in; $totalOut = [long]$c.total.out
        $totalCR = [long]$c.total.cR; $totalCW  = [long]$c.total.cW
    } else {
        # Base: sum modelUsage from stats-cache.json
        $stats = Get-Content ($claudeDir + '/stats-cache.json') -Raw | ConvertFrom-Json
        foreach ($m in $stats.modelUsage.PSObject.Properties) {
            $totalIn  += [long]$m.Value.inputTokens
            $totalOut += [long]$m.Value.outputTokens
            $totalCR  += [long]$m.Value.cacheReadInputTokens
            $totalCW  += [long]$m.Value.cacheCreationInputTokens
        }
        # Supplement: add .jsonl records newer than lastComputedDate (stats-cache gap)
        $lastComputed = if ($stats.lastComputedDate) { $stats.lastComputedDate } else { '1970-01-01' }
        Get-ChildItem ($claudeDir + '/projects') -Filter '*.jsonl' -Recurse |
            Where-Object { $_.LastWriteTime -gt [System.DateTime]::Parse($lastComputed) } |
            ForEach-Object {
                Get-Content $_.FullName | ForEach-Object {
                    if ($_ -match 'input_tokens') {
                        try {
                            $obj = ConvertFrom-Json $_
                            if ($obj.type -eq 'assistant' -and $obj.message -and $obj.message.usage -and $obj.timestamp) {
                                $tsDate = [System.DateTime]::Parse($obj.timestamp.ToString()).ToString('yyyy-MM-dd')
                                if ($tsDate -gt $lastComputed) {
                                    $totalIn  += [long]$obj.message.usage.input_tokens
                                    $totalOut += [long]$obj.message.usage.output_tokens
                                    $totalCR  += [long]$obj.message.usage.cache_read_input_tokens
                                    $totalCW  += [long]$obj.message.usage.cache_creation_input_tokens
                                }
                            }
                        } catch {}
                    }
                }
            }
    }

    # Save updated cache
    $nowTs = (Get-Date).ToString('o')
    @{
        proj  = @{ cwd=$cwd; ts=$nowTs; in=$projIn;  out=$projOut;  cR=$projCR;  cW=$projCW  }
        today = @{ date=$todayStr; ts=$nowTs; in=$todayIn; out=$todayOut; cR=$todayCR; cW=$todayCW }
        total = @{ ts=$nowTs; in=$totalIn; out=$totalOut; cR=$totalCR; cW=$totalCW }
    } | ConvertTo-Json -Depth 3 | Set-Content $cacheFile

} catch {}

$projLine  = "Project: in:$(Format-Tok $projIn)  out:$(Format-Tok $projOut)  " +
             [char]0x2191 + "cache:$(Format-Tok $projCR)  " + [char]0x270E + "cache:$(Format-Tok $projCW)"
$todayLine = "Today:   in:$(Format-Tok $todayIn)  out:$(Format-Tok $todayOut)  " +
             [char]0x2191 + "cache:$(Format-Tok $todayCR)  " + [char]0x270E + "cache:$(Format-Tok $todayCW)"
$totalLine = "Total:   in:$(Format-Tok $totalIn)  out:$(Format-Tok $totalOut)  " +
             [char]0x2191 + "cache:$(Format-Tok $totalCR)  " + [char]0x270E + "cache:$(Format-Tok $totalCW)"

# --- Session ID ---
$sid = if ($d.session_id) { $d.session_id } else { "?" }
$sessionLine = "Session: $sid"

# --- Output ---
Write-Output $gitLine
Write-Output $modelLine
Write-Output $dirLine
# Line 4: DeepSeek (for deepseek models) or Quota (for Anthropic models)
if ($isDeepseek) {
    Write-Output $deepseekLine
} else {
    Write-Output $quotaLine
}
Write-Output $tokenLine
Write-Output $projLine
Write-Output $todayLine
Write-Output $totalLine
Write-Output $sessionLine
Write-Output $dtLine
