# study-functional-programming

関数型プログラミングを学習するためのリポジトリ。
Haskell で Web アプリケーションを作成しながら学ぶ。

## 環境構築

[lessons/0001-setup_environment.md](lessons/0001-setup_environment.md) を参照。

## 必要なツール

- [GHCup](https://www.haskell.org/ghcup/) — Haskell ツールチェインマネージャ
- GHC 9.6.7
- Cabal 3.14.2.0

## 学習記録

- [0001: 環境構築](lessons/0001-setup_environment.md)
- [0002: Hello World Web サーバー](lessons/0002-hello_world_web_server.md)

## 機能要件: TODO 管理アプリ

ファイルベース（JSON）で永続化を行う TODO 管理アプリケーション。

### Task Entity

| フィールド | 型 | 説明 |
|---|---|---|
| Id | Hash 文字列 | commit hash のような一意な識別子（サーバー側で生成） |
| Content | 文字列 | タスクの内容。1〜1024 文字（空文字不可） |
| Priority | 整数 (0–5) | 優先度。0 が最も緊急、デフォルトは 3 |
| Tags | 文字列リスト | 各文字列 1〜64 文字、最大 10 個。空リストは許可、空文字は不可 |
| Status | Enum | Backlog / InProgress / Done / Closed |
| CreatedAt | タイムスタンプ | 起票時刻 |
| StartedAt | タイムスタンプ (nullable) | InProgress への遷移時刻 |
| CompletedAt | タイムスタンプ (nullable) | Done への遷移時刻 |
| ClosedAt | タイムスタンプ (nullable) | Closed への遷移時刻 |

### 状態遷移

```
Backlog ──→ InProgress ──→ Done（最終完了・遷移不可）
  │    ←──      │
  │              │
  └──→ Closed ←─┘（未完了での打ち切り・遷移不可）
```

- **順方向**: Backlog → InProgress → Done
- **逆方向**: InProgress → Backlog のみ許可
- **キャンセル（Close）**: Backlog または InProgress からのみ可能。Done からは不可
- Done は最終完了状態であり、以降の遷移はできない
- Closed は未完了のまま打ち切る状態であり、以降の遷移はできない

### API エンドポイント

| メソッド | パス | 説明 |
|---|---|---|
| POST | `/tasks` | タスクの新規作成 |
| GET | `/tasks` | タスク一覧の取得（tags によるフィルター、priority によるソート対応） |
| GET | `/tasks/:id` | タスクの個別取得 |
| PUT | `/tasks/:id` | 状態遷移（進行・完了・差し戻し） |
| DELETE | `/tasks/:id` | Close 処理（Backlog / InProgress からのみ実行可能） |

### データ永続化

- JSON ファイルにタスク一覧を保存

## ビルド・実行

```bash
cabal build
cabal run study-fp   # ポート3000でWebサーバーが起動
```
