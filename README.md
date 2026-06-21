# Claude Code カスタムステータスライン (Windows PowerShell)

Claude Code CLI のステータスラインをカスタマイズする PowerShell スクリプトです。
モデル名・コンテキスト使用率・レートリミット・Extra Usage（追加クレジット）をリアルタイムに表示します。

> 別PCへ移す場合は、まず必ず [⚠️ 最重要: 文字エンコーディング](#️-最重要-文字エンコーディング) を読んでください。

---

## ⚠️ 最重要: 文字エンコーディング

**`.ps1` ファイルは必ず「UTF-8 (BOM付き)」で保存してください。**

### なぜか

- 本スクリプトは日本語コメントと罫線文字（`──`）など、ASCII以外の文字を含みます。
- Windows PowerShell 5.1 は、**BOMのない** `.ps1` を「OSのANSIコードページ」で読み込みます。
- 日本語環境ではANSIコードページが **Shift-JIS (cp932)** のため、UTF-8(BOMなし)で保存されたファイルは文字化けし、構文解析が壊れて次のエラーが出ます:

  ```
  Unexpected token '}' in expression or statement.
  ```

- **BOM（先頭3バイト `EF BB BF`）があれば、PowerShell はロケールに関係なく正しくUTF-8と認識し**、この問題は起きません。

> 💡 **別PCで「動いた／動かない」が分かれる理由**: 欧米ロケール（ANSI = Windows-1252 等）のPCでは、BOMなしでも1バイト=1文字として読まれ構文が壊れず偶然動きます。日本語ロケールのPCでは壊れます。**BOM付きにしておけば、どのロケールでも確実に動きます。**

### 配置前に必ず実行: BOMへの変換

`git clone` やコピー直後のファイルはBOMがない可能性があります。配置前に以下を実行して、`.ps1` をBOM付きに変換してください（**コードの中身は一切変わりません**）:

```powershell
# このリポジトリのフォルダで実行（カレントに statusline.ps1 / test_statusline.ps1 がある前提）
foreach ($f in @('.\statusline.ps1', '.\test_statusline.ps1')) {
    $text = [System.IO.File]::ReadAllText($f, (New-Object System.Text.UTF8Encoding($false)))
    [System.IO.File]::WriteAllText($f, $text, (New-Object System.Text.UTF8Encoding($true)))
    Write-Host "BOM付きに変換: $f"
}
```

### BOMの確認方法

```powershell
$b = [System.IO.File]::ReadAllBytes('.\statusline.ps1')
if ($b[0] -eq 0xEF -and $b[1] -eq 0xBB -and $b[2] -eq 0xBF) { 'UTF-8 BOM 付き (OK)' } else { 'BOMなし (要変換)' }
```

> **エディタで保存する場合**: VS Code なら右下のエンコード表示をクリック →「エンコード付きで保存」→「UTF-8 with BOM」。
> PowerShell ISE は既定でBOM付きUTF-8で保存されます。

---

## 表示内容

### 通常時の表示例

```
[Opus 4.8] Ctx: 25% | cwd: C:\Users\<USERNAME>\Desktop\project
5h █████----- 50%(2h30m) | 7d ████------ 41%(3d12h)
```

### Extra Usage 使用時の表示例

**追加クレジットを実際に使い始めた（使用額が $0 を超えた）場合のみ**、自動で表示が切り替わります:

```
[Opus 4.8] Ctx: 25% |[EX]| cwd: C:\Users\<USERNAME>\Desktop\project
5h ██████████ 100%(--) | 7d ████------ 41%(3d12h) | EX ███------- 30%($1.50/$5.00)
```

> - 使用額が **$0.00 の間は `[EX]` も `EX ...` も表示されません**（Extra Usage機能を有効にしているだけでは出ません）。
> - 追加クレジットを使い切る／月次でリセットされると、自動で通常表示に戻ります。

### 各要素の説明

| 要素 | 説明 | 例 |
|---|---|---|
| `[Opus 4.8]` | 現在選択中のモデル名 | `[Sonnet]`, `[Haiku]` |
| `Ctx: 25%` | コンテキストウィンドウの使用率 | `Ctx: 0%` 〜 `Ctx: 100%` |
| `\|[EX]\|` | 追加クレジットを実際に使用中であることを示すインジケータ | 使用額$0の時は非表示 |
| `cwd:` | 現在の作業ディレクトリ | |
| `5h █████----- 50%(2h30m)` | 5時間ローリングウィンドウの使用率とリセットまでの残り時間 | |
| `7d ████------ 41%(3d12h)` | 7日間ウィンドウの使用率とリセットまでの残り時間 | |
| `EX ███------- 30%($1.50/$5.00)` | Extra Usage の使用率と使用額/上限額 | 使用額$0の時は非表示 |

---

## 動作要件

| 項目 | 条件 |
|---|---|
| OS | Windows 10 / 11 |
| PowerShell | 5.1 以上（Windows 標準搭載） |
| Claude Code | CLI インストール済み、OAuth ログイン済み |
| プラン | Claude.ai Pro / Max（レートリミット・Extra Usage 表示に必要） |
| ファイルエンコード | `.ps1` は **UTF-8 (BOM付き)** 必須（[上記参照](#️-最重要-文字エンコーディング)） |

---

## リポジトリ構成

```
├── statusline.ps1          # 本体スクリプト（~/.claude/ にコピーして使用）
├── test_statusline.ps1     # テストスクリプト（動作確認用、任意）
└── README.md               # このファイル
```

| ファイル | 説明 |
|---|---|
| `statusline.ps1` | Claude Code が stdin で渡す JSON を解析し、2行のステータスを出力するメインスクリプト。Extra Usage 情報は Anthropic OAuth API から自動取得します。 |
| `test_statusline.ps1` | 8パターンのモック入力でスクリプトの出力を検証するテストスイート。入力はパイプで渡し、認証情報・キャッシュを遮断した隔離環境で実行することで Extra Usage の有無に左右されず判定します。 |

---

## セットアップ手順（手動）

> 各ステップの `<USERNAME>` はお使いのPCのWindowsユーザー名に置き換えてください。

### ステップ 1: `.claude` フォルダを用意

```
C:\Users\<USERNAME>\.claude\
```

存在しない場合は作成してください（Claude Code を一度起動すると自動生成されます）。

### ステップ 2: スクリプトをBOM付きで配置

[⚠️ 最重要: 文字エンコーディング](#️-最重要-文字エンコーディング) の変換を実行してから、`statusline.ps1` を以下にコピーします:

```
C:\Users\<USERNAME>\.claude\statusline.ps1
```

> コピー後、配置先ファイルもBOM付きであることを[確認](#bomの確認方法)してください。

### ステップ 3: settings.json を編集

`C:\Users\<USERNAME>\.claude\settings.json` に `statusLine` キーを追加します。

**新規作成の場合:**

```json
{
  "statusLine": {
    "type": "command",
    "command": "powershell -NoProfile -ExecutionPolicy Bypass -File C:/Users/<USERNAME>/.claude/statusline.ps1"
  }
}
```

**既存ファイルに追記する場合** — 既存のキーは残し、`statusLine` を追加:

```json
{
  "既存のキー": "既存の値",
  "statusLine": {
    "type": "command",
    "command": "powershell -NoProfile -ExecutionPolicy Bypass -File C:/Users/<USERNAME>/.claude/statusline.ps1"
  }
}
```

> **重要**: `command` 内の `<USERNAME>` を実際のユーザー名に書き換え、パス区切りはスラッシュ `/` を使用してください。

### ステップ 4: Claude Code を再起動

設定変更後に再起動するとステータスラインが表示されます。

### ステップ 5: 動作確認

初回は以下のように表示されます（最初のAPIレスポンス前はレートリミット情報が空）:

```
[?] Ctx: 0% | cwd: C:\your\project\path
5h ---------- --%(--) | 7d ---------- --%(--)
```

一度プロンプトを送信すると、モデル名やレートリミットが自動更新されます。

---

## セットアップ手順（自動 / AIエージェント向け）

以下を **このリポジトリのフォルダ内で** PowerShell で実行すると、BOM変換・配置・settings.json への追記・テストまで一括で行います。冪等（再実行可能）です。

```powershell
$ErrorActionPreference = 'Stop'
$claudeDir = Join-Path $env:USERPROFILE '.claude'
$dest      = Join-Path $claudeDir 'statusline.ps1'

# 1) .claude フォルダを確保
if (-not (Test-Path $claudeDir)) { New-Item -ItemType Directory -Path $claudeDir -Force | Out-Null }

# 2) statusline.ps1 を UTF-8(BOM付き) で配置（中身は不変）
$text = [System.IO.File]::ReadAllText('.\statusline.ps1', (New-Object System.Text.UTF8Encoding($false)))
[System.IO.File]::WriteAllText($dest, $text, (New-Object System.Text.UTF8Encoding($true)))
Write-Host "配置完了 (UTF-8 BOM): $dest"

# 3) settings.json に statusLine を追加（既存設定は保持）
$settingsPath = Join-Path $claudeDir 'settings.json'
$cmd = "powershell -NoProfile -ExecutionPolicy Bypass -File " + ($dest -replace '\\','/')
if (Test-Path $settingsPath) {
    $json = Get-Content $settingsPath -Raw | ConvertFrom-Json
} else {
    $json = [PSCustomObject]@{}
}
$statusLine = [PSCustomObject]@{ type = 'command'; command = $cmd }
$json | Add-Member -NotePropertyName 'statusLine' -NotePropertyValue $statusLine -Force
$json | ConvertTo-Json -Depth 10 | Set-Content $settingsPath -Encoding UTF8
Write-Host "settings.json 更新完了: $settingsPath"

# 4) 動作確認（モックJSONを流す）
$sample = '{"cwd":"C:\\test","model":{"display_name":"Opus 4.8"},"context_window":{"used_percentage":25},"rate_limits":{"five_hour":{"used_percentage":50,"resets_at":9999999999},"seven_day":{"used_percentage":41,"resets_at":9999999999}}}'
Write-Host "=== 動作確認 ==="
$sample | powershell -NoProfile -ExecutionPolicy Bypass -File $dest
```

期待される出力（おおむね次の2行。`[EX]` は追加クレジット使用時のみ付く）:

```
[Opus 4.8] Ctx: 25% | cwd: C:\test
5h █████----- 50%(...) | 7d ████------ 41%(...)
```

完了後、Claude Code を再起動してください。

---

## テスト（任意）

```powershell
# 事前に test_statusline.ps1 を BOM付きに変換しておくこと（最重要セクション参照）
powershell -NoProfile -ExecutionPolicy Bypass -File .\test_statusline.ps1
```

`8 PASSED / 0 FAILED / 8 TOTAL` と表示されれば成功です。

> テストは `~/.claude/statusline.ps1` を対象に実行します。配置済みであることが前提です。
> テストは入力をパイプで渡し、認証情報・キャッシュを遮断した隔離環境で本体を起動するため、実アカウントの Extra Usage 状態に左右されず安定して判定します。

---

## トラブルシューティング

| 症状 | 原因 | 対処 |
|---|---|---|
| `Unexpected token '}'` 等の構文エラーで起動しない | `.ps1` がBOMなしUTF-8で、Shift-JIS環境で文字化け | [最重要セクション](#️-最重要-文字エンコーディング)の手順でBOM付きに変換 |
| ステータスラインが表示されない | ワークスペース信頼ダイアログが未承認 | Claude Code を再起動して信頼を承認する |
| `statusline skipped` と表示される | 同上 | 同上 |
| `--` だけ表示される | 最初の API レスポンス前 | 一度プロンプトを送信すると更新される |
| パスエラー | settings.json のユーザー名が間違い | `command` 内のパスを確認する |
| `[EX]` が表示されない | 追加クレジットの使用額が $0.00 | 仕様です（使用額が$0超になると自動表示）。Extra Usage 自体が未有効/認証情報なしの場合も非表示 |
| Extra Usage の金額が更新されない | キャッシュ期間中（60秒） | 最大60秒待つと自動更新される |
| **構文エラーは出ないのに `[?] Ctx: --% \| cwd: --` だけ表示される（日本語環境）** | PowerShell 5.1 が stdin を OS の ANSI コードページ（cp932 / Shift-JIS）で読んでしまい、Claude Code が UTF-8 で送る JSON 中の日本語フィールド（`session_name` 等）が壊れて `ConvertFrom-Json` が失敗 | 本体先頭で `[Console]::InputEncoding = [System.Text.UTF8Encoding]::new($false)` を設定済み（v2 以降）。古いバージョンを使っている場合は最新を取得 |

### デバッグログ（自己診断用）

「以前は動いていたのに急にフォールバック表示になった」場合、Claude Code の statusline JSON スキーマ変更などが疑われます。環境変数 `CLAUDE_STATUSLINE_DEBUG=1` を設定して Claude Code を再起動すると、`%TEMP%\claude\statusline-debug.log` に **stdin の生 JSON とフォールバック理由** が記録され、原因を切り分けられます（通常運用では設定不要）。

```powershell
# PowerShellで有効化（このセッションのみ）
$env:CLAUDE_STATUSLINE_DEBUG = '1'
# 永続化する場合
[Environment]::SetEnvironmentVariable('CLAUDE_STATUSLINE_DEBUG', '1', 'User')
```

ログ確認:

```powershell
Get-Content (Join-Path $env:TEMP 'claude\statusline-debug.log') -Tail 30
```

---

## 将来の Claude Code 更新で壊れる可能性と対策

本スクリプトは Claude Code の **非公開仕様**（statusline に渡される JSON、および `/api/oauth/usage` エンドポイント）に依存しています。Anthropic 側の変更で表示が崩れる可能性があるため、以下の挙動・対策を理解しておくと安心です。

| リスク | 影響 | 設計上の備え |
|---|---|---|
| statusline JSON のフィールド名変更（例: `model.display_name` → 別名） | モデル名が `?`、コンテキストや cwd が `--` に化ける | 各フィールドを null セーフに参照し、欠損時は `?` / `--` にフォールバックして本体は落とさない |
| `rate_limits.five_hour` / `seven_day` の構造変更 | レートリミット行が `--%(--)` 表示に | `Format-RateLimit` で `$null` チェック済み |
| `/api/oauth/usage` のレスポンス形式変更 | `[EX]` / `EX ...` が出なくなる（または金額が `0.00` 固定に） | `extra_usage.used_credits` と `monthly_limit` の存在を都度確認、無ければ Extra Usage 表示自体を抑止 |
| OAuth トークン保存場所の変更 | Extra Usage 表示が出なくなる | 2箇所（`%LOCALAPPDATA%\Claude Code\credentials.json` / `~/.claude/.credentials.json`）と環境変数 `CLAUDE_CODE_OAUTH_TOKEN` をフォールバックで参照 |
| User-Agent ベースのアクセス制限導入 | `/api/oauth/usage` が 4xx で返り `[EX]` が出なくなる | 現状 `claude-code/2.1.34` をハードコード。問題が起きたら本体先頭付近の `User-Agent` を Claude Code 最新バージョン文字列に書き換える |
| stdin エンコーディング周りの仕様変更 | 日本語環境で再びフォールバック表示 | `[Console]::InputEncoding` を UTF-8 に明示固定済み |

### 切り分け手順（フォールバック表示になったとき）

1. **構文エラーが出ているか確認** → 出ていれば文字エンコーディング問題（[最重要セクション](#️-最重要-文字エンコーディング)）
2. **`CLAUDE_STATUSLINE_DEBUG=1` を設定して再起動** → ログを取得
3. ログの `[stdin len=...]` 行をチェック:
   - `len=0` → Claude Code が stdin を渡していない（Claude Code 側の問題、または settings.json のコマンド誤り）
   - `len>0` でも `fallback: ConvertFrom-Json failed:` が記録 → JSON が壊れている（エンコーディング起因、または Claude Code が不正な JSON を送っている）
   - `len>0` で fallback ログ無しなのに `[?] / --` 表示 → JSON は parse 成功するがフィールド名が変わっている。ログ中の生 JSON を見て新しいフィールド名を確認し、本体を修正
4. **`test_statusline.ps1` を実行** → 9 件全て PASS なら本体ロジックは正常。Claude Code 側の問題に絞り込める

---

## 技術仕様

| 項目 | 詳細 |
|---|---|
| 外部ツール | 不使用（`jq` 等は不要、PowerShell 標準の `ConvertFrom-Json` のみ） |
| ファイルエンコード | UTF-8 (BOM付き)。PowerShell 5.1 がロケール非依存で正しく読み込むため必須 |
| stdin エンコード | 本体先頭で `[Console]::InputEncoding` を **UTF-8 に明示固定**。日本語ロケールで Shift-JIS と誤読されて日本語フィールドが壊れる問題への対策 |
| 入力 | Claude Code が stdin 経由で送信する JSON |
| 出力 | `Write-Output` による2行のプレーンテキスト |
| null 安全 | 各フィールドの欠損・null に対してフォールバック表示 (`--`) を使用 |
| Extra Usage | Anthropic OAuth API (`/api/oauth/usage`) から取得（60秒キャッシュ、課金なし）。`is_enabled` が true かつ使用額 > $0 の時のみ表示。**非公開エンドポイントのため Anthropic 側の変更で停止する可能性あり** |
| 認証情報 | `%LOCALAPPDATA%\Claude Code\credentials.json` または `~/.claude/.credentials.json` から OAuth トークンを自動取得。Anthropic 公式 API への問い合わせ以外には一切送信・保存しない |
| デバッグ | `CLAUDE_STATUSLINE_DEBUG=1` で `%TEMP%\claude\statusline-debug.log` に動作ログ出力（任意） |

---

## ライセンス

MIT License
