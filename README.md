# Claude Code カスタムステータスライン (Windows PowerShell)

Claude Code CLI のステータスラインをカスタマイズする PowerShell スクリプトです。  
モデル名・コンテキスト使用率・レートリミット・Extra Usage（追加クレジット）をリアルタイムに表示します。

---

## 表示内容

### 通常時の表示例

```
[Opus 4.7] Ctx: 25% | cwd: C:\Users\<USERNAME>\Desktop\project
5h █████----- 50%(2h30m) | 7d ████------ 41%(3d12h)
```

### Extra Usage 発動時の表示例

レートリミット到達後に追加クレジットが有効な場合、自動で表示が切り替わります:

```
[Opus 4.7] Ctx: 25% |[EX]| cwd: C:\Users\<USERNAME>\Desktop\project
5h ██████████ 100%(--) | 7d ████------ 41%(3d12h) | EX ███------- 30%($1.50/$5.00)
```

> レートリミットが回復すると、自動で通常表示に戻ります。

### 各要素の説明

| `[Opus 4.7]` | 現在選択中のモデル名
| `Ctx: 25%` | コンテキストウィンドウの使用率
| `\|[EX]\|` | Extra Usage が有効であることを示すインジケータ | 通常時は非表示
| `cwd:` | 現在の作業ディレクトリ
| `5h █████----- 50%(2h30m)` | 5時間ローリングウィンドウの使用率とリセットまでの残り時間
| `7d ████------ 41%(3d12h)` | 7日間ウィンドウの使用率とリセットまでの残り時間
| `EX ███------- 30%($1.50/$5.00)` | Extra Usage の使用率と使用額/上限額 | 通常時は非表示

---

## 動作要件

| OS | Windows 10 / 11 |
| PowerShell | 5.1 以上（Windows 標準搭載） |
| Claude Code | CLI インストール済み、OAuth ログイン済み |
| プラン | Claude.ai Pro / Max（レートリミット・Extra Usage 表示に必要） |

---

## リポジトリ構成

```
├── statusline.ps1          # 本体スクリプト（~/.claude/ にコピーして使用）
├── test_statusline.ps1     # テストスクリプト（動作確認用、任意）
└── README.md               # このファイル
```

| ファイル | 説明 |
| `statusline.ps1` | Claude Code が stdin で渡す JSON を解析し、2行のステータスを出力するメインスクリプト。Extra Usage 情報は Anthropic OAuth API から自動取得します。 |
| `test_statusline.ps1` | 8パターンのモック入力でスクリプトの出力を検証するテストスイート。セットアップ後の動作確認に使えます。 |

---

## セットアップ手順

### ステップ 1: スクリプトをダウンロード

このリポジトリの `statusline.ps1` をダウンロードしてください。

### ステップ 2: スクリプトを配置

ダウンロードした `statusline.ps1` を以下のフォルダにコピーします:

```
C:\Users\<USERNAME>\.claude\statusline.ps1
```

`<USERNAME>` はお使いのPCのWindowsユーザー名に置き換えてください。

> `.claude` フォルダが存在しない場合は、事前に作成してください。

### ステップ 3: settings.json を編集

`C:\Users\<USERNAME>\.claude\settings.json` を開き、以下の `statusLine` キーを追加します。

**settings.json が存在しない場合** — 新規作成:

```json
{
  "statusLine": {
    "type": "command",
    "command": "powershell -NoProfile -ExecutionPolicy Bypass -File C:/Users/<USERNAME>/.claude/statusline.ps1"
  }
}
```

**settings.json が既にある場合** — 既存の設定に追記:

```json
{
  "既存のキー": "既存の値",
  "statusLine": {
    "type": "command",
    "command": "powershell -NoProfile -ExecutionPolicy Bypass -File C:/Users/<USERNAME>/.claude/statusline.ps1"
  }
}
```

> **重要**: `command` 内の `<USERNAME>` を実際のユーザー名に書き換えてください。パス区切りはスラッシュ `/` を使用します。

### ステップ 4: Claude Code を再起動

設定変更後、Claude Code を再起動するとステータスラインが表示されます。

### ステップ 5: 動作確認

ステータスラインが表示されたら成功です。初回は以下のように表示されます（最初のAPIレスポンス前はレートリミット情報が空です）:

```
[?] Ctx: 0% | cwd: C:\your\project\path
5h ---------- --%(--) | 7d ---------- --%(--) 
```

一度プロンプトを送信すると、モデル名やレートリミットが自動で更新されます。

---

## テスト（任意）

`test_statusline.ps1` をダウンロードし、以下を実行するとスクリプトが正しく動作するか確認できます:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\test_statusline.ps1
```

> テストは `statusline.ps1` が `~/.claude/` に配置済みであることが前提です。

---

## トラブルシューティング

| 症状 | 原因 | 対処 |
|---|---|---|
| ステータスラインが表示されない | ワークスペース信頼ダイアログが未承認 | Claude Code を再起動して信頼を承認する |
| `statusline skipped` と表示される | 同上 | 同上 |
| `--` だけ表示される | 最初の API レスポンス前 | 一度プロンプトを送信すると更新される |
| パスエラー | settings.json のユーザー名が間違い | `command` 内のパスを確認する |
| `[EX]` が表示されない | Extra Usage が未有効 / OAuth 認証情報なし | Anthropic アカウントで Extra Usage を有効にする |
| Extra Usage の金額が更新されない | キャッシュ期間中（60秒） | 最大60秒待つと自動更新される |

---

## 技術仕様

| 項目 | 詳細 |
|---|---|
| 外部ツール | 不使用（`jq` 等は不要、PowerShell 標準の `ConvertFrom-Json` のみ） |
| 入力 | Claude Code が stdin 経由で送信する JSON |
| 出力 | `Write-Output` による2行のプレーンテキスト |
| null 安全 | 各フィールドの欠損・null に対してフォールバック表示 (`--`) を使用 |
| Extra Usage | Anthropic OAuth API (`/api/oauth/usage`) から取得（60秒キャッシュ、課金なし） |
| 認証情報 | `~/.claude/.credentials.json` から OAuth トークンを自動取得 |

---

## ライセンス

MIT License
