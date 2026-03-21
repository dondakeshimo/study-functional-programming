-- | 公開モジュール: コンストラクタを隠蔽し、アクセサのみ公開する。
--
-- == コンストラクタ隠蔽の目的
--
-- Value Object（Content, Priority 等）のコンストラクタを隠すことで、
-- スマートコンストラクタ（mkContent, mkPriority 等）経由でのみ値を作成可能にする。
-- これにより @Content ""@ のような不正な値の構築をコンパイル時に防止できる。
--
-- 同様に、状態別タスク型（DoneTask 等）のコンストラクタを隠すことで、
-- Workflow モジュールの遷移関数（completeTask 等）経由でのみ状態遷移が行われ、
-- 不正な状態のタスクが直接構築されることを防ぐ。
--
-- == エクスポートリストの読み方
--
-- @TaskId (unTaskId)@ は「TaskId 型と unTaskId アクセサを公開するが、
-- TaskId コンストラクタは公開しない」という意味。
-- @Task (..)@ は「Task 型と全コンストラクタを公開する」という意味。
--
-- Task Sum Type のコンストラクタ（TaskBacklog, TaskInProgress 等）は
-- パターンマッチで各状態を処理するために公開する必要がある。
--
-- == Internal モジュールとの関係
--
-- コンストラクタへの直接アクセスが必要なモジュール（Validation, Workflow,
-- Persistence, テスト）は Domain.Task.Types.Internal をインポートする。
-- それ以外のモジュール（Web.App, Web.Dto 等）はこのモジュールをインポートする。

module Domain.Task.Types
  ( -- * Value Objects（コンストラクタは隠蔽、アクセサのみ公開）
    -- | スマートコンストラクタ（Validation モジュール）を通じて生成する。
    TaskId (unTaskId)
  , Content (unContent)
  , Priority (unPriority)
  , Tag (unTag)
  , Tags (unTags)
    -- * State-specific Task types（コンストラクタは隠蔽、アクセサのみ公開）
    -- | Workflow モジュールの遷移関数を通じて生成する。
  , BacklogTask (backlogId, backlogContent, backlogPriority, backlogTags, backlogCreatedAt)
  , InProgressTask (inProgressId, inProgressContent, inProgressPriority, inProgressTags, inProgressCreatedAt, inProgressStartedAt)
  , DoneTask (doneId, doneContent, donePriority, doneTags, doneCreatedAt, doneStartedAt, doneCompletedAt)
  , ClosedTask (closedId, closedContent, closedPriority, closedTags, closedCreatedAt, closedClosedAt)
    -- * Sum Type（コンストラクタは公開 — パターンマッチで必要）
  , Task (..)
    -- * Helpers
  , taskId
  , taskStatus
  ) where

import Domain.Task.Types.Internal
