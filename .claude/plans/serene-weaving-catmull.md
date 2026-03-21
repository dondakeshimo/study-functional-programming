# リファクタリング: コンストラクタを隠蔽して不変条件を型で強制する

## Context

現在 `Domain.Task.Types` は全ての型で `(..)` エクスポートしており、コンストラクタが外部に公開されている。
これにより以下の問題がある:

1. `Content ""` のようにバリデーションをバイパスして不正な値を作れる
2. `DoneTask {...}` を直接構築でき、`completeTask` 経由の遷移を迂回できる

Internal モジュールパターンを導入し、コンストラクタの公開範囲を制限する。

## 変更対象ファイル

### 1. `src/Domain/Task/Types/Internal.hs`（新規作成）

- 現在の `src/Domain/Task/Types.hs` の内容をそのまま移動
- 全てのコンストラクタを `(..)` で公開（Internal なので制限なし）

### 2. `src/Domain/Task/Types.hs`（書き換え）

Internal を再エクスポートするファサードモジュールに変更:

```haskell
module Domain.Task.Types
  ( -- Value Objects（コンストラクタは隠し、アクセサのみ公開）
    TaskId (unTaskId)
  , Content (unContent)
  , Priority (unPriority)
  , Tag (unTag)
  , Tags (unTags)
    -- State-specific Task types（アクセサのみ公開、コンストラクタは隠す）
  , BacklogTask (backlogId, backlogContent, backlogPriority, backlogTags, backlogCreatedAt)
  , InProgressTask (inProgressId, inProgressContent, inProgressPriority, inProgressTags, inProgressCreatedAt, inProgressStartedAt)
  , DoneTask (doneId, doneContent, donePriority, doneTags, doneCreatedAt, doneStartedAt, doneCompletedAt)
  , ClosedTask (closedId, closedContent, closedPriority, closedTags, closedCreatedAt, closedClosedAt)
    -- Sum Type（コンストラクタは公開 — パターンマッチで必要）
  , Task (..)
    -- Helpers
  , taskId
  , taskStatus
  ) where

import Domain.Task.Types.Internal
```

**ポイント:**
- Value Object: コンストラクタを隠し、アクセサ（`unXxx`）のみ公開 → `mkContent` 等のスマートコンストラクタ経由でのみ作成可能
- 状態別タスク型: コンストラクタを隠し、アクセサのみ公開 → `createTask`, `completeTask` 等の Workflow 関数経由でのみ作成可能
- `Task` Sum Type: コンストラクタは公開のまま（パターンマッチで各状態を処理するために必要）

### 3. `src/Domain/Task/Validation.hs`（変更）

Internal からコンストラクタをインポート:

```haskell
import Domain.Task.Types.Internal (Content (..), Priority (..), Tag (..), Tags (..))
```

### 4. `src/Domain/Task/Workflow.hs`（変更）

Internal からコンストラクタをインポート:

```haskell
import Domain.Task.Types.Internal
```

### 5. `src/Infrastructure/Persistence.hs`（変更）

Internal からコンストラクタをインポート:

```haskell
import Domain.Task.Types.Internal
```

### 6. `src/Infrastructure/IdGen.hs`（変更）

Internal からコンストラクタをインポート:

```haskell
import Domain.Task.Types.Internal (TaskId (..))
```

### 7. `test/Domain/Task/ValidationSpec.hs`（変更）

テストではコンストラクタが必要（`Right (Content "Hello")` との比較等）なので Internal をインポート:

```haskell
import Domain.Task.Types.Internal (Content (..), Priority (..), Tag (..), Tags (..))
```

### 8. `test/Domain/Task/WorkflowSpec.hs`（変更）

同様に Internal をインポート:

```haskell
import Domain.Task.Types.Internal
```

### 9. `study-fp.cabal`（変更）

`exposed-modules` に `Domain.Task.Types.Internal` を追加。

## 変更不要なファイル

- `src/Web/App.hs` — コンストラクタを直接使わずアクセサのみ使用しており、`Task(..)` のパターンマッチだけ必要。現在 `import Domain.Task.Types` で全インポートしているが、Types の再エクスポートで `Task(..)` は含まれるので変更不要。
- `src/Web/Dto.hs` — 同様にアクセサとパターンマッチのみ。変更不要。

## 検証

```bash
cabal clean && cabal build   # コンパイルが通ること
cabal test                   # 全テストがパスすること
```
