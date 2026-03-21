# TODO管理アプリ実装計画 — Domain Modeling Made Functional

## Context

README.mdに定義した機能要件に基づき、HaskellでTODO管理アプリを実装する。「Domain Modeling Made Functional」のDDDアプローチに従い、型の力を最大限に活用して不正な状態を型レベルで表現不可能にする設計を目指す。

## モジュール構成

```
src/
  Domain/
    Task/
      Types.hs          -- Value Objects, 状態別Task型, Task Sum Type
      Validation.hs     -- スマートコンストラクタ（バリデーション）
      Workflow.hs        -- 状態遷移関数（純粋）
      Error.hs           -- ドメインエラー型
  Infrastructure/
    Persistence.hs       -- JSONファイル永続化
    IdGen.hs             -- TaskId生成（ハッシュ）
  Web/
    App.hs               -- Scottyルーティング（既存を拡張）
    Dto.hs               -- リクエスト/レスポンスDTO、JSON変換
app/
  Main.hs                -- エントリーポイント（既存を拡張）
test/
  Domain/
    Task/
      ValidationSpec.hs
      WorkflowSpec.hs
  Spec.hs                -- テストランナー
```

## 核心設計: 状態別の型で不正状態を排除

GADTsではなくSum Typeを採用。理由: Aesonとの統合が素直、学習しやすい、パターンマッチの明示性。

```haskell
-- 各状態で持つフィールドが型レベルで決まる（Maybeフィールド不要）
data BacklogTask = BacklogTask
  { backlogId, backlogContent, backlogPriority, backlogTags, backlogCreatedAt }

data InProgressTask = InProgressTask
  { ..., inProgressStartedAt :: UTCTime }  -- startedAtが必須

data DoneTask = DoneTask
  { ..., doneStartedAt, doneCompletedAt :: UTCTime }  -- 両方必須

data ClosedTask = ClosedTask
  { ..., closedClosedAt :: UTCTime }

-- 全状態を束ねるSum Type（永続化・API応答で使用）
data Task = TaskBacklog BacklogTask | TaskInProgress InProgressTask | TaskDone DoneTask | TaskClosed ClosedTask
```

## 型安全な状態遷移

```haskell
-- 個別関数: 型シグネチャが許可された遷移のみを表現
startTask       :: UTCTime -> BacklogTask    -> InProgressTask
completeTask    :: UTCTime -> InProgressTask -> DoneTask
revertTask      ::            InProgressTask -> BacklogTask
closeBacklog    :: UTCTime -> BacklogTask    -> ClosedTask
closeInProgress :: UTCTime -> InProgressTask -> ClosedTask

-- API層向けラッパー: Task Sum Type上でパターンマッチ → 不正遷移はLeft
transitionTask :: TransitionCommand -> UTCTime -> Task -> Either DomainError Task
closeTask      :: UTCTime -> Task -> Either DomainError Task
```

## Value Objects（スマートコンストラクタ）

```haskell
mkContent  :: Text -> Either DomainError Content   -- 1〜1024文字
mkPriority :: Int  -> Either DomainError Priority   -- 0〜5
mkTag      :: Text -> Either DomainError Tag        -- 1〜64文字
mkTags     :: [Text] -> Either DomainError Tags     -- 最大10個、各要素をmkTagで検証
```

## API エンドポイント

| メソッド | パス | ハンドラ | ステータス |
|---------|------|---------|-----------|
| POST | `/tasks` | createTaskHandler | 201 / 400 |
| GET | `/tasks` | listTasksHandler (?tag=, ?sort=priority) | 200 |
| GET | `/tasks/:id` | getTaskHandler | 200 / 404 |
| PUT | `/tasks/:id` | updateTaskHandler (body: {"transition": "start"/"complete"/"revert"}) | 200 / 400 / 404 / 409 |
| DELETE | `/tasks/:id` | deleteTaskHandler | 200 / 400 / 404 |

## 追加Cabal依存

| パッケージ | 用途 |
|-----------|------|
| aeson | JSON エンコード/デコード |
| time | UTCTime |
| bytestring | JSON I/O |
| directory | ファイル存在チェック |
| cryptohash-sha256 + base16-bytestring | TaskIdハッシュ生成 |
| http-types | HTTPステータスコード |
| hspec (test) | テストフレームワーク |
| wai-extra (test) | WAIテストユーティリティ |

## 実装順序

| Step | 対象 | 内容 |
|------|------|------|
| 1 | `study-fp.cabal` | 依存パッケージ追加、モジュール一覧更新、test-suite追加 |
| 2 | `Domain.Task.Error` | DomainError型定義 |
| 3 | `Domain.Task.Types` | Value Objects (TaskId, Content, Priority, Tag, Tags) + 状態別Task型 + Task Sum Type + taskIdヘルパー |
| 4 | `Domain.Task.Validation` | スマートコンストラクタ (mkContent, mkPriority, mkTag, mkTags) + UnvalidatedTask + validateTask |
| 5 | `Domain.Task.Workflow` | 純粋な遷移関数 (startTask, completeTask, revertTask, closeBacklog, closeInProgress) + transitionTask, closeTask ラッパー + createTask |
| 6 | `Infrastructure.IdGen` | SHA256ベースのTaskId生成 |
| 7 | `Infrastructure.Persistence` | Task用Aeson ToJSON/FromJSON インスタンス + loadTasks, saveTasks, findTask |
| 8 | `Web.Dto` | CreateTaskRequest, UpdateTaskRequest, TaskResponse DTO + Domain↔DTO変換 |
| 9 | `Web.App` | 5つのAPIハンドラ実装 + ルーティング定義 |
| 10 | `app/Main.hs` | データディレクトリの初期化処理追加 |
| 11 | テスト | Validation, Workflow のユニットテスト |

## 修正対象ファイル一覧

- `study-fp.cabal` — 依存・モジュール追加
- `src/Web/App.hs` — ルーティング拡張（既存）
- `app/Main.hs` — データディレクトリ初期化追加（既存）
- `src/MyLib.hs` — 削除（不要）

## 検証方法

1. `cabal build` で全モジュールのコンパイルが通ること
2. `cabal test` でドメイン層のユニットテストがパスすること
3. `cabal run study-fp` でサーバー起動後、curl で各エンドポイントを手動確認:
   - `curl -X POST -H "Content-Type: application/json" -d '{"content":"test task"}' localhost:3000/tasks`
   - `curl localhost:3000/tasks`
   - `curl -X PUT -H "Content-Type: application/json" -d '{"transition":"start"}' localhost:3000/tasks/<id>`
   - `curl -X DELETE localhost:3000/tasks/<id>`
