# statusline.ps1 - Claude Code カスタムステータスライン (Windows PowerShell)
# 配置先: ~/.claude/statusline.ps1
# コンテキスト・レートリミット・Extra Usage を表示

# stdin/stdout を UTF-8 に固定する（重要）。
# Claude Code は JSON を UTF-8 で stdin に書き込むが、
# PowerShell 5.1 のデフォルト [Console]::InputEncoding は OS の ANSI
# コードページ（日本語環境では cp932 / Shift-JIS）。このままだと
# UTF-8 バイト列を Shift-JIS として誤読し、日本語フィールド
# （session_name 等）の "ダメ文字" で `\` (0x5C) などが混入して
# JSON エスケープが壊れ、ConvertFrom-Json が失敗してフォールバック表示になる。
[Console]::InputEncoding  = [System.Text.UTF8Encoding]::new($false)
[Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false)

# ── ヘルパー関数 ──────────────────────────────────────────

# 使用率をプログレスバーに変換
function Get-ProgressBar {
    param([object]$Percentage)
    if ($null -eq $Percentage) { return '-' * 10 }
    $pct = [Math]::Max(0, [Math]::Min(100, [double]$Percentage))
    $filled = [int][Math]::Floor($pct / 10)
    $empty = 10 - $filled
    return (([string][char]0x2588) * $filled) + ('-' * $empty)
}

# Unixエポック秒のリセット時刻から残り時間を生成
function Get-TimeRemaining {
    param([object]$ResetsAt)
    if ($null -eq $ResetsAt) { return "--" }
    try {
        $resetTime = [DateTimeOffset]::FromUnixTimeSeconds([long]$ResetsAt).LocalDateTime
        $diff = $resetTime - (Get-Date)
        if ($diff.TotalSeconds -le 0) { return "--" }
        if ($diff.TotalHours -lt 1) {
            return "{0}m" -f [Math]::Floor($diff.TotalMinutes)
        }
        if ($diff.TotalHours -lt 24) {
            return "{0}h{1}m" -f [int][Math]::Floor($diff.TotalHours), $diff.Minutes
        }
        return "{0}d{1}h" -f [int][Math]::Floor($diff.TotalDays), $diff.Hours
    }
    catch { return "--" }
}

# ラベル付きレートリミット表示行を組み立て
function Format-RateLimit {
    param([string]$Label, [object]$LimitObj)
    if ($null -eq $LimitObj) {
        $bar = Get-ProgressBar -Percentage $null
        return "{0} {1} --%(--)" -f $Label, $bar
    }
    $pct = $LimitObj.used_percentage
    $resetAt = $LimitObj.resets_at
    $bar = Get-ProgressBar -Percentage $pct
    $time = Get-TimeRemaining -ResetsAt $resetAt
    if ($null -eq $pct) { return "{0} {1} --%(--)" -f $Label, $bar }
    $pctInt = [int][Math]::Floor([double]$pct)
    return "{0} {1} {2}%({3})" -f $Label, $bar, $pctInt, $time
}

# JSONからモデル名を取得
function Get-ModelName {
    param([object]$Json)
    $defaultName = [string][char]0x3F  # "?" フォールバック
    if ($null -eq $Json) { return $defaultName }
    $props = $Json.PSObject.Properties.Name
    if ($props -notcontains 'model') { return $defaultName }
    $m = $Json.model
    if ($null -eq $m) { return $defaultName }
    if ($m -is [string]) {
        if ($m -ne "") { return $m }
        return $defaultName
    }
    $mProps = $m.PSObject.Properties.Name
    if ($mProps -contains 'display_name' -and $null -ne $m.display_name -and $m.display_name -ne "") {
        return $m.display_name
    }
    if ($mProps -contains 'id' -and $null -ne $m.id -and $m.id -ne "") {
        return $m.id
    }
    return $defaultName
}

# ── OAuth & Extra Usage ───────────────────────────────────

# OAuthトークンを取得
function Get-OAuthToken {
    if ($env:CLAUDE_CODE_OAUTH_TOKEN) { return $env:CLAUDE_CODE_OAUTH_TOKEN }

    $configDir = if ($env:CLAUDE_CONFIG_DIR) { $env:CLAUDE_CONFIG_DIR } else { Join-Path $env:USERPROFILE ".claude" }

    # Windows: %LOCALAPPDATA%\Claude Code\credentials.json
    try {
        $winCredPath = Join-Path $env:LOCALAPPDATA "Claude Code\credentials.json"
        if (Test-Path $winCredPath) {
            $creds = Get-Content $winCredPath -Raw -Encoding UTF8 | ConvertFrom-Json
            $token = $creds.claudeAiOauth.accessToken
            if ($token -and $token -ne "null") { return $token }
        }
    }
    catch {}

    # Cross-platform: ~/.claude/.credentials.json
    try {
        $credFile = Join-Path $configDir ".credentials.json"
        if (Test-Path $credFile) {
            $creds = Get-Content $credFile -Raw -Encoding UTF8 | ConvertFrom-Json
            $token = $creds.claudeAiOauth.accessToken
            if ($token -and $token -ne "null") { return $token }
        }
    }
    catch {}

    return $null
}

# Anthropic APIからExtra Usage情報を取得
function Get-ExtraUsageData {
    $cacheDir = Join-Path $env:TEMP "claude"
    $cacheFile = Join-Path $cacheDir "statusline-usage-cache.json"
    $cacheMaxAge = 60  # キャッシュ有効期間（秒）

    if (-not (Test-Path $cacheDir)) {
        New-Item -ItemType Directory -Path $cacheDir -Force | Out-Null
    }

    $needsRefresh = $true
    $usageData = $null

    if (Test-Path $cacheFile) {
        $cacheAge = ((Get-Date) - (Get-Item $cacheFile).LastWriteTime).TotalSeconds
        if ($cacheAge -lt $cacheMaxAge) { $needsRefresh = $false }
        try { $usageData = Get-Content $cacheFile -Raw -Encoding UTF8 } catch {}
    }

    if ($needsRefresh) {
        # 同時実行防止: キャッシュファイルのタイムスタンプを即更新
        if (Test-Path $cacheFile) {
            (Get-Item $cacheFile).LastWriteTime = Get-Date
        }
        else {
            New-Item -ItemType File -Path $cacheFile -Force | Out-Null
        }

        $token = Get-OAuthToken
        if ($token) {
            try {
                $headers = @{
                    "Accept"         = "application/json"
                    "Content-Type"   = "application/json"
                    "Authorization"  = "Bearer $token"
                    "anthropic-beta" = "oauth-2025-04-20"
                    "User-Agent"     = "claude-code/2.1.34"
                }
                $response = Invoke-RestMethod -Uri "https://api.anthropic.com/api/oauth/usage" `
                    -Headers $headers -Method Get -TimeoutSec 10 -ErrorAction Stop
                $usageData = $response | ConvertTo-Json -Depth 10
                $usageData | Set-Content $cacheFile -Force -Encoding UTF8
            }
            catch {}
        }

        # Clean up empty cache file
        if ((Test-Path $cacheFile) -and (Get-Item $cacheFile).Length -eq 0) {
            Remove-Item $cacheFile -Force -ErrorAction SilentlyContinue
        }
    }

    if ($usageData) {
        try {
            $parsed = if ($usageData -is [string]) { $usageData | ConvertFrom-Json } else { $usageData }
            return $parsed
        }
        catch {}
    }
    return $null
}

# ── メイン処理 ────────────────────────────────────────────

# Claude Code が stdin 経由で送信する JSON を読み取り
try { $inputString = [Console]::In.ReadToEnd() }
catch { $inputString = "" }

# 任意のデバッグログ。環境変数 CLAUDE_STATUSLINE_DEBUG=1 を設定すると
# %TEMP%\claude\statusline-debug.log に stdin / フォールバック理由を記録する。
# Claude Code の JSON スキーマ変更などで「フォールバック表示になる」現象を
# 利用者自身が切り分けられるようにするためのもの。通常は無効。
function Write-StatuslineDebug {
    param([string]$Tag, [string]$Body = '')
    if ($env:CLAUDE_STATUSLINE_DEBUG -ne '1') { return }
    try {
        $logPath = Join-Path $env:TEMP "claude\statusline-debug.log"
        $logDir = Split-Path $logPath -Parent
        if (-not (Test-Path $logDir)) { New-Item -ItemType Directory -Path $logDir -Force | Out-Null }
        $line = "[{0}] {1}" -f (Get-Date).ToString('o'), $Tag
        Add-Content -Path $logPath -Value $line -Encoding UTF8
        if ($Body -ne '') { Add-Content -Path $logPath -Value $Body -Encoding UTF8 }
    } catch {}
}

$inputLen = if ($null -eq $inputString) { 'null' } else { $inputString.Length.ToString() }
Write-StatuslineDebug -Tag ("stdin len=" + $inputLen) -Body $inputString

# JSON が取得できなかった場合のフォールバック出力
$fallbackBar = '-' * 10
$fallbackModel = [string][char]0x3F
$fallbackLine1 = "[{0}] Ctx: --% | cwd: --" -f $fallbackModel
$fallbackLine2 = "5h {0} --%(--) | 7d {0} --%(--)" -f $fallbackBar

if ([string]::IsNullOrWhiteSpace($inputString)) {
    Write-StatuslineDebug -Tag 'fallback: empty stdin'
    Write-Output $fallbackLine1
    Write-Output $fallbackLine2
    exit 0
}

try { $json = $inputString | ConvertFrom-Json }
catch {
    Write-StatuslineDebug -Tag ('fallback: ConvertFrom-Json failed: ' + $_.Exception.Message)
    Write-Output $fallbackLine1
    Write-Output $fallbackLine2
    exit 0
}

# ── モデル名・コンテキスト・cwd ──────────────────────────

$modelName = Get-ModelName -Json $json

$ctxPct = $null
if ($null -ne $json.context_window) { $ctxPct = $json.context_window.used_percentage }
if ($null -ne $ctxPct) {
    $ctxDisplay = [string]([int][Math]::Floor([double]$ctxPct))
}
else {
    $ctxDisplay = "--"
}

$cwd = "--"
if ($null -ne $json.cwd -and $json.cwd -ne "") {
    $cwd = $json.cwd
}
elseif ($null -ne $json.workspace -and $null -ne $json.workspace.current_dir -and $json.workspace.current_dir -ne "") {
    $cwd = $json.workspace.current_dir
}

# ── Extra Usage 判定 ──────────────────────────────────────

$isExtraActive = $false   # Extra Usageが有効かどうか
$extraSection = ""        # 2行目に追加するExtra Usage表示文字列

$usageApiData = Get-ExtraUsageData  # API経由でExtra Usage情報を取得
if ($null -ne $usageApiData) {
    $exProps = $usageApiData.PSObject.Properties.Name
    if ($exProps -contains 'extra_usage' -and $null -ne $usageApiData.extra_usage) {
        $eu = $usageApiData.extra_usage
        $euProps = $eu.PSObject.Properties.Name
        # 実際に追加クレジットを使った分 (used_credits はセント単位)
        $usedCredits = 0
        if ($euProps -contains 'used_credits' -and $null -ne $eu.used_credits) {
            $usedCredits = [double]$eu.used_credits
        }
        # Extra Usage が有効、かつ実際に使用額が発生している時だけ表示する
        if ($euProps -contains 'is_enabled' -and $eu.is_enabled -eq $true -and $usedCredits -gt 0) {
            $isExtraActive = $true
            $euPct = 0
            if ($euProps -contains 'utilization') {
                $euPct = [int][Math]::Floor([double]$eu.utilization)
            }
            $euBar = Get-ProgressBar -Percentage $euPct
            $ds = [string][char]0x24  # "$" character
            if ($euProps -contains 'used_credits' -and $euProps -contains 'monthly_limit' -and
                $null -ne $eu.used_credits -and $null -ne $eu.monthly_limit) {
                $usedD = "{0:F2}" -f ([double]$eu.used_credits / 100)
                $limD = "{0:F2}" -f ([double]$eu.monthly_limit / 100)
                $extraSection = "EX " + $euBar + " " + $euPct + "%(" + $ds + $usedD + "/" + $ds + $limD + ")"
            }
            else {
                $extraSection = "EX " + $euBar + " " + $euPct + "%"
            }
        }
    }
}

# ── 1行目: モデル名 + コンテキスト ───────

if ($isExtraActive) {
    # Extra Usage有効時: |[EX]| インジケータを挿入
    $line1 = "[{0}] Ctx: {1}% |[EX]| cwd: {2}" -f $modelName, $ctxDisplay, $cwd
}
else {
    $line1 = "[{0}] Ctx: {1}% | cwd: {2}" -f $modelName, $ctxDisplay, $cwd
}

# ── 2行目: レートリミット + Extra Usage ───────────────────

$fiveHour = $null
$sevenDay = $null
if ($null -ne $json.rate_limits) {
    $fiveHour = $json.rate_limits.five_hour
    $sevenDay = $json.rate_limits.seven_day
}

$part5h = Format-RateLimit -Label "5h" -LimitObj $fiveHour
$part7d = Format-RateLimit -Label "7d" -LimitObj $sevenDay

if ($isExtraActive -and $extraSection -ne "") {
    $line2 = "{0} | {1} | {2}" -f $part5h, $part7d, $extraSection
}
else {
    $line2 = "{0} | {1}" -f $part5h, $part7d
}

# ── 出力 ──────────────────────────────────────────────────

Write-Output $line1
Write-Output $line2
