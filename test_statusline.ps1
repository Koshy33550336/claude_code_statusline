<#
  test_statusline.ps1 - Test script for statusline.ps1
  Usage: powershell -NoProfile -ExecutionPolicy Bypass -File .\test_statusline.ps1
#>

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

$scriptPath = Join-Path $env:USERPROFILE '.claude\statusline.ps1'

if (-not (Test-Path $scriptPath)) {
    Write-Host '[ERROR] statusline.ps1 not found' -ForegroundColor Red
    exit 1
}

$passed = 0
$failed = 0

$FB   = [string][char]0x2588
$EB   = '-'
$PIPE = [string][char]0x7C

# 期待される1行目の文字列を生成（モデル名、コンテキスト使用率、パス）
function Build-Line1 {
    param(
        [string]$Model,
        [string]$Ctx,
        [string]$Cwd
    )
    return '[' + $Model + '] Ctx: ' + $Ctx + '% ' + $PIPE + ' cwd: ' + $Cwd
}

# 期待される2行目の文字列を生成（レートリミット用プログレスバーと時間）
function Build-Line2 {
    param(
        [int]$F5,
        [int]$E5,
        [string]$P5,
        [string]$T5,
        [int]$F7,
        [int]$E7,
        [string]$P7,
        [string]$T7
    )
    $bar5 = ($FB * $F5) + ($EB * $E5)
    $bar7 = ($FB * $F7) + ($EB * $E7)
    return '5h ' + $bar5 + ' ' + $P5 + '%(' + $T5 + ') ' + $PIPE + ' 7d ' + $bar7 + ' ' + $P7 + '%(' + $T7 + ')'
}

# エラー・欠損時用のフォールバック文字列を生成
function Build-FallbackLine2 {
    $bar = $EB * 10
    return '5h ' + $bar + ' --%(--) ' + $PIPE + ' 7d ' + $bar + ' --%(--)'  
}

# ハッシュテーブルをJSONに変換し、一時ファイルに保存してパスを返す
function Write-JsonToTempFile {
    param([hashtable]$Data)
    $tmpFile = [System.IO.Path]::GetTempFileName()
    $json = $Data | ConvertTo-Json -Depth 10 -Compress
    [System.IO.File]::WriteAllText($tmpFile, $json, [System.Text.Encoding]::UTF8)
    return $tmpFile
}

# 生の文字列（空文字など）を一時ファイルに保存してパスを返す
function Write-RawJsonToTempFile {
    param([string]$RawJson)
    $tmpFile = [System.IO.Path]::GetTempFileName()
    [System.IO.File]::WriteAllText($tmpFile, $RawJson, [System.Text.Encoding]::UTF8)
    return $tmpFile
}

# 一時ファイルの内容を標準入力としてスクリプトを実行し、期待値と比較するメイン処理
#
# 注意点:
#  - 入力はパイプ (`|`) で渡す。ProcessStartInfo + StandardInput.Write は
#    親子間のstdinエンコーディングが一致せず、日本語環境ではJSONが文字化けして
#    本体スクリプトがフォールバック表示になるため使わない。
#  - Extra Usage を確定的に無効化するため、隔離した環境変数で子を起動する。
#    認証情報 (CLAUDE_CONFIG_DIR / LOCALAPPDATA / CLAUDE_CODE_OAUTH_TOKEN) と
#    キャッシュ (TEMP) を遮断すると Get-ExtraUsageData が null を返し、
#    `|[EX]|` や `EX ...` が出力されなくなるので期待値と一致する。
function Run-TestFromFile {
    param(
        [string]$Name,
        [string]$TmpFile,
        [string[]]$ExpectedLines
    )
    Write-Host ''
    Write-Host ('=' * 60) -ForegroundColor DarkGray
    Write-Host ('TEST: ' + $Name) -ForegroundColor Cyan

    # 入力内容を読み取り (空入力の場合は空文字)
    $content = ''
    if (Test-Path $TmpFile) {
        $content = [System.IO.File]::ReadAllText($TmpFile, (New-Object System.Text.UTF8Encoding($false)))
        Remove-Item $TmpFile -Force
    }

    # Extra Usage を無効化するための隔離環境を用意
    $isoCfg = Join-Path ([System.IO.Path]::GetTempPath()) ('iso_cfg_' + [guid]::NewGuid().ToString('N'))
    $isoTmp = Join-Path ([System.IO.Path]::GetTempPath()) ('iso_tmp_' + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $isoCfg -Force | Out-Null
    New-Item -ItemType Directory -Path $isoTmp -Force | Out-Null

    $save = @{
        CFG = $env:CLAUDE_CONFIG_DIR; TOK = $env:CLAUDE_CODE_OAUTH_TOKEN
        TMP = $env:TEMP; TMP2 = $env:TMP; LAD = $env:LOCALAPPDATA
    }
    try {
        $env:CLAUDE_CONFIG_DIR       = $isoCfg
        $env:CLAUDE_CODE_OAUTH_TOKEN = $null
        $env:TEMP = $isoTmp; $env:TMP = $isoTmp
        $env:LOCALAPPDATA = $isoTmp
        $result = $content | powershell -NoProfile -ExecutionPolicy Bypass -File $scriptPath
    }
    finally {
        $env:CLAUDE_CONFIG_DIR = $save.CFG; $env:CLAUDE_CODE_OAUTH_TOKEN = $save.TOK
        $env:TEMP = $save.TMP; $env:TMP = $save.TMP2; $env:LOCALAPPDATA = $save.LAD
        Remove-Item $isoCfg, $isoTmp -Recurse -Force -ErrorAction SilentlyContinue
    }

    $lines = @($result | ForEach-Object { $_.TrimEnd("`r") } | Where-Object { $_ -ne '' })

    Write-Host ('  Lines: ' + $lines.Count) -ForegroundColor DarkGray
    for ($i = 0; $i -lt $lines.Count; $i++) {
        Write-Host ('  L' + ($i+1) + ': ' + $lines[$i]) -ForegroundColor White
    }

    $ok = $true
    if ($lines.Count -ne $ExpectedLines.Count) {
        Write-Host ('  [FAIL] Line count mismatch (expect: ' + $ExpectedLines.Count + ', actual: ' + $lines.Count + ')') -ForegroundColor Red
        $ok = $false
    }
    else {
        for ($i = 0; $i -lt $ExpectedLines.Count; $i++) {
            if ($lines[$i] -ne $ExpectedLines[$i]) {
                Write-Host ('  [FAIL] L' + ($i+1) + ' mismatch') -ForegroundColor Red
                Write-Host ('    expect: ' + $ExpectedLines[$i]) -ForegroundColor Yellow
                Write-Host ('    actual: ' + $lines[$i]) -ForegroundColor Yellow
                $ok = $false
            }
        }
    }

    if ($ok) {
        Write-Host '  [PASS]' -ForegroundColor Green
        $script:passed++
    }
    else {
        $script:failed++
    }
}

# -- Epoch seconds --

$future5h  = [long]([DateTimeOffset]::Now.AddHours(2).AddMinutes(30).ToUnixTimeSeconds())
$future7d  = [long]([DateTimeOffset]::Now.AddDays(3).AddHours(12).ToUnixTimeSeconds())
$pastEpoch = [long]([DateTimeOffset]::Now.AddHours(-1).ToUnixTimeSeconds())

# -- Helper: compute expected time string from epoch --

# エポック秒から期待される残り時間の文字列を計算
function Get-ExpectedTime {
    param([long]$Epoch)
    $resetTime = [DateTimeOffset]::FromUnixTimeSeconds($Epoch).LocalDateTime
    $diff = $resetTime - (Get-Date)
    if ($diff.TotalSeconds -le 0) { return '--' }
    if ($diff.TotalHours -lt 1) {
        return ([int][Math]::Floor($diff.TotalMinutes)).ToString() + 'm'
    }
    if ($diff.TotalHours -lt 24) {
        return ([int][Math]::Floor($diff.TotalHours)).ToString() + 'h' + $diff.Minutes.ToString() + 'm'
    }
    return ([int][Math]::Floor($diff.TotalDays)).ToString() + 'd' + $diff.Hours.ToString() + 'h'
}

# -- Test 1: Normal input --

$data1 = @{
    cwd = 'C:\Users\YourUserName\Desktop\project'
    workspace = @{ current_dir = 'C:\Users\YourUserName\Desktop\project' }
    model = @{ display_name = 'Opus'; id = 'claude-opus-4' }
    context_window = @{ used_percentage = 25; context_window_size = 200000 }
    rate_limits = @{
        five_hour = @{ used_percentage = 50.0; resets_at = $future5h }
        seven_day = @{ used_percentage = 41.2; resets_at = $future7d }
    }
}
$t1 = Write-JsonToTempFile $data1
$e1L1 = Build-Line1 'Opus' '25' 'C:\Users\YourUserName\Desktop\project'
# Time values are dynamic - compute expected from epoch
$e1t5 = Get-ExpectedTime $future5h
$e1t7 = Get-ExpectedTime $future7d
$e1L2 = Build-Line2 5 5 '50' $e1t5 4 6 '41' $e1t7
Run-TestFromFile 'Normal input' $t1 @($e1L1, $e1L2)

# -- Test 2: Empty input --

$t2 = Write-RawJsonToTempFile ''
$e2L1 = Build-Line1 '?' '--' '--'
$e2L2 = Build-FallbackLine2
Run-TestFromFile 'Empty input' $t2 @($e2L1, $e2L2)

# -- Test 3: No rate_limits --

$data3 = @{
    cwd = 'C:\test\project'
    context_window = @{ used_percentage = 60 }
}
$t3 = Write-JsonToTempFile $data3
$e3L1 = Build-Line1 '?' '60' 'C:\test\project'
$e3L2 = Build-FallbackLine2
Run-TestFromFile 'No rate_limits' $t3 @($e3L1, $e3L2)

# -- Test 4: used_percentage null --

$obj4 = [PSCustomObject]@{
    cwd = 'C:\test\project'
    context_window = [PSCustomObject]@{ used_percentage = $null }
    rate_limits = [PSCustomObject]@{
        five_hour = [PSCustomObject]@{ used_percentage = 10; resets_at = $future5h }
        seven_day = [PSCustomObject]@{ used_percentage = 20; resets_at = $future7d }
    }
}
$j4 = $obj4 | ConvertTo-Json -Depth 10 -Compress
$t4 = Write-RawJsonToTempFile $j4
$e4L1 = Build-Line1 '?' '--' 'C:\test\project'
$e4t5 = Get-ExpectedTime $future5h
$e4t7 = Get-ExpectedTime $future7d
$e4L2 = Build-Line2 1 9 '10' $e4t5 2 8 '20' $e4t7
Run-TestFromFile 'Ctx null' $t4 @($e4L1, $e4L2)

# -- Test 5: 0% usage --

$data5 = @{
    cwd = 'C:\test'
    context_window = @{ used_percentage = 0 }
    rate_limits = @{
        five_hour = @{ used_percentage = 0; resets_at = $future5h }
        seven_day = @{ used_percentage = 0; resets_at = $future7d }
    }
}
$t5 = Write-JsonToTempFile $data5
$e5L1 = Build-Line1 '?' '0' 'C:\test'
$e5t5 = Get-ExpectedTime $future5h
$e5t7 = Get-ExpectedTime $future7d
$e5L2 = Build-Line2 0 10 '0' $e5t5 0 10 '0' $e5t7
Run-TestFromFile '0 percent' $t5 @($e5L1, $e5L2)

# -- Test 6: 100% usage --

$data6 = @{
    cwd = 'C:\test'
    context_window = @{ used_percentage = 100 }
    rate_limits = @{
        five_hour = @{ used_percentage = 100; resets_at = $future5h }
        seven_day = @{ used_percentage = 100; resets_at = $future7d }
    }
}
$t6 = Write-JsonToTempFile $data6
$e6L1 = Build-Line1 '?' '100' 'C:\test'
$e6t5 = Get-ExpectedTime $future5h
$e6t7 = Get-ExpectedTime $future7d
$e6L2 = Build-Line2 10 0 '100' $e6t5 10 0 '100' $e6t7
Run-TestFromFile '100 percent' $t6 @($e6L1, $e6L2)

# -- Test 7: resets_at in past --

$data7 = @{
    cwd = 'C:\test'
    context_window = @{ used_percentage = 30 }
    rate_limits = @{
        five_hour = @{ used_percentage = 30; resets_at = $pastEpoch }
        seven_day = @{ used_percentage = 50; resets_at = $pastEpoch }
    }
}
$t7 = Write-JsonToTempFile $data7
$e7L1 = Build-Line1 '?' '30' 'C:\test'
$e7L2 = Build-Line2 3 7 '30' '--' 5 5 '50' '--'
Run-TestFromFile 'Past reset' $t7 @($e7L1, $e7L2)

# -- Test 8: five_hour missing --

$data8 = @{
    cwd = 'C:\test'
    context_window = @{ used_percentage = 15 }
    rate_limits = @{
        seven_day = @{ used_percentage = 25; resets_at = $future7d }
    }
}
$t8 = Write-JsonToTempFile $data8
$e8L1 = Build-Line1 '?' '15' 'C:\test'
$bar5fb = $EB * 10
$bar7p  = ($FB * 2) + ($EB * 8)
$e8t7 = Get-ExpectedTime $future7d
$e8L2 = '5h ' + $bar5fb + ' --%(--) ' + $PIPE + ' 7d ' + $bar7p + ' 25%(' + $e8t7 + ')'
Run-TestFromFile 'No five_hour' $t8 @($e8L1, $e8L2)

# -- Test 9: 日本語フィールドを含むJSON（Shift-JIS誤読リグレッション） --
#
# Claude Code 2.1.x の session_name に日本語が入るケース。
# 本体が stdin を Shift-JIS として読むと、UTF-8 の「業」「翻」等の
# 3バイト列のうち偶発的に 0x5C (`\`) が出現して JSON エスケープが壊れ、
# ConvertFrom-Json が失敗してフォールバック表示に落ちる。
# 本体先頭で [Console]::InputEncoding を UTF-8 に固定する修正の回帰防止。
$data9 = @{
    cwd          = 'C:\test\proj'
    session_name = '英語論文の翻訳作業計画書'
    model        = @{ display_name = 'Opus 4.8' }
    context_window = @{ used_percentage = 7 }
    rate_limits = @{
        five_hour = @{ used_percentage = 15; resets_at = $future5h }
        seven_day = @{ used_percentage = 2;  resets_at = $future7d }
    }
}
$t9 = Write-JsonToTempFile $data9
$e9L1 = Build-Line1 'Opus 4.8' '7' 'C:\test\proj'
$e9t5 = Get-ExpectedTime $future5h
$e9t7 = Get-ExpectedTime $future7d
$e9L2 = Build-Line2 1 9 '15' $e9t5 0 10 '2' $e9t7
Run-TestFromFile 'Japanese session_name (Shift-JIS regression)' $t9 @($e9L1, $e9L2)

# -- Summary --

Write-Host ''
Write-Host ('=' * 60) -ForegroundColor DarkGray
$color = if ($failed -eq 0) { 'Green' } else { 'Red' }
Write-Host ('Result: ' + $passed + ' PASSED / ' + $failed + ' FAILED / ' + ($passed + $failed) + ' TOTAL') -ForegroundColor $color
Write-Host ('=' * 60) -ForegroundColor DarkGray

if ($failed -gt 0) { exit 1 }
