-- | ワークフロー: ドメインの状態遷移を純粋関数として表現する。
--
-- == "Domain Modeling Made Functional" におけるワークフロー
--
-- ワークフローはビジネスプロセスの一連のステップを関数として表現したもの。
-- このモジュールでは、タスクの状態遷移を以下の2層で実装している:
--
-- === 1. 型安全な個別遷移関数（コンパイル時保証）
--
-- @
-- startTask    :: UTCTime -> BacklogTask    -> InProgressTask
-- completeTask :: UTCTime -> InProgressTask -> DoneTask
-- @
--
-- これらの関数は型シグネチャ自体が「許可された遷移」を表現している。
-- 例えば startTask に DoneTask を渡すとコンパイルエラーになるため、
-- 不正な遷移はプログラムを実行する前に検出される。
--
-- === 2. Sum Type ラッパー（実行時チェック）
--
-- @
-- transitionTask :: TransitionCommand -> UTCTime -> Task -> Either DomainError Task
-- @
--
-- API 層では JSON からパースした TaskId でストレージから Task を取得するが、
-- この時点ではタスクがどの状態かは実行時にしかわからない。
-- そのため Sum Type（Task）上でパターンマッチし、適切な個別遷移関数に委譲する。
-- 不正な遷移は Either の Left（エラー）として返される。
--
-- == 純粋関数の意義
--
-- このモジュールの関数はすべて純粋（IO を含まない）。
-- 時刻（UTCTime）は引数として外部から注入される。
-- これにより:
--   * テストが容易（固定時刻を渡せる）
--   * 副作用がないことが型で保証される
--   * 関数の振る舞いが入力のみで決まる（参照透過性）

{-# LANGUAGE OverloadedStrings #-}

module Domain.Task.Workflow
  ( -- * Task creation
    createTask
    -- * Type-safe transition functions
    -- | 個別の遷移関数。型シグネチャが遷移の正当性をコンパイル時に保証する。
  , startTask
  , completeTask
  , revertTask
  , closeBacklog
  , closeInProgress
    -- * Sum Type wrappers for API layer
    -- | API 層で使用するラッパー。実行時にパターンマッチで遷移の正当性を検査する。
  , TransitionCommand (..)
  , transitionTask
  , closeTask
  ) where

import Data.Time (UTCTime)

import Data.Text (Text)

import Domain.Task.Error (DomainError (..))
import Domain.Task.Types.Internal

-- ============================================================================
-- タスク作成
-- ============================================================================

-- | 新規タスクを Backlog 状態で作成する純粋関数。
--
-- 引数の TaskId と UTCTime は呼び出し側（IO 層）で生成して渡す。
-- これにより、この関数自体は副作用を持たない。
--
-- "Domain Modeling Made Functional" では、副作用（ID生成、時刻取得）を
-- ワークフローの外側に押し出し、純粋なドメインロジックと分離することを推奨している。
createTask :: TaskId -> UTCTime -> Content -> Priority -> Tags -> BacklogTask
createTask tid now content priority tags =
  BacklogTask
    { backlogId        = tid
    , backlogContent   = content
    , backlogPriority  = priority
    , backlogTags      = tags
    , backlogCreatedAt = now
    }

-- ============================================================================
-- 型安全な状態遷移関数
-- ============================================================================
-- これらの関数の型シグネチャは、許可された遷移のみを表現している。
-- 例: startTask は BacklogTask しか受け付けないため、
--     InProgressTask や DoneTask を渡すとコンパイルエラーになる。
--
-- 許可されている遷移:
--   Backlog    → InProgress  (startTask)
--   InProgress → Done        (completeTask)
--   InProgress → Backlog     (revertTask)
--   Backlog    → Closed      (closeBacklog)
--   InProgress → Closed      (closeInProgress)
-- ============================================================================

-- | Backlog → InProgress への遷移。
--
-- 型シグネチャ @BacklogTask -> InProgressTask@ が遷移の正当性を保証する。
-- InProgressTask には startedAt フィールドが追加される。
startTask :: UTCTime -> BacklogTask -> InProgressTask
startTask now t =
  InProgressTask
    { inProgressId        = backlogId t
    , inProgressContent   = backlogContent t
    , inProgressPriority  = backlogPriority t
    , inProgressTags      = backlogTags t
    , inProgressCreatedAt = backlogCreatedAt t
    , inProgressStartedAt = now
    }

-- | InProgress → Done への遷移。
--
-- DoneTask には startedAt（InProgress 時に記録済み）と
-- completedAt（この遷移時に記録）の両方が必須。
completeTask :: UTCTime -> InProgressTask -> DoneTask
completeTask now t =
  DoneTask
    { doneId          = inProgressId t
    , doneContent     = inProgressContent t
    , donePriority    = inProgressPriority t
    , doneTags        = inProgressTags t
    , doneCreatedAt   = inProgressCreatedAt t
    , doneStartedAt   = inProgressStartedAt t
    , doneCompletedAt = now
    }

-- | InProgress → Backlog への差し戻し。
--
-- 時刻を受け取らない（startedAt は破棄される）。
-- 再度 startTask すると新しい startedAt が記録される。
revertTask :: InProgressTask -> BacklogTask
revertTask t =
  BacklogTask
    { backlogId        = inProgressId t
    , backlogContent   = inProgressContent t
    , backlogPriority  = inProgressPriority t
    , backlogTags      = inProgressTags t
    , backlogCreatedAt = inProgressCreatedAt t
    }

-- | Backlog → Closed への遷移（未着手のままキャンセル）。
closeBacklog :: UTCTime -> BacklogTask -> ClosedTask
closeBacklog now t =
  ClosedTask
    { closedId        = backlogId t
    , closedContent   = backlogContent t
    , closedPriority  = backlogPriority t
    , closedTags      = backlogTags t
    , closedCreatedAt = backlogCreatedAt t
    , closedClosedAt  = now
    }

-- | InProgress → Closed への遷移（作業中にキャンセル）。
closeInProgress :: UTCTime -> InProgressTask -> ClosedTask
closeInProgress now t =
  ClosedTask
    { closedId        = inProgressId t
    , closedContent   = inProgressContent t
    , closedPriority  = inProgressPriority t
    , closedTags      = inProgressTags t
    , closedCreatedAt = inProgressCreatedAt t
    , closedClosedAt  = now
    }

-- ============================================================================
-- API 層向けラッパー
-- ============================================================================

-- | 状態遷移コマンド。API リクエストの "transition" フィールドに対応する。
data TransitionCommand = Start | Complete | Revert
  deriving (Show, Eq)

-- | Task Sum Type 上でパターンマッチし、適切な個別遷移関数に委譲する。
--
-- API 層では Task がどの状態かは実行時にしかわからないため、
-- パターンマッチで状態を判定し、正当な遷移なら Right を、
-- 不正な遷移なら Left（DomainError）を返す。
--
-- ワイルドカードパターン @transitionTask cmd _ task@ が
-- 上記の正当なパターンにマッチしなかった全ての組み合わせを捕捉する。
--
-- @
-- transitionTask Start t (TaskBacklog b)       -- OK: Right (TaskInProgress ...)
-- transitionTask Start t (TaskDone d)          -- NG: Left (InvalidTransition ...)
-- transitionTask Complete t (TaskInProgress i)  -- OK: Right (TaskDone ...)
-- transitionTask Complete t (TaskBacklog b)     -- NG: Left (InvalidTransition ...)
-- @
transitionTask :: TransitionCommand -> UTCTime -> Task -> Either DomainError Task
transitionTask Start now (TaskBacklog t) =
  Right $ TaskInProgress (startTask now t)
transitionTask Complete now (TaskInProgress t) =
  Right $ TaskDone (completeTask now t)
transitionTask Revert _ (TaskInProgress t) =
  Right $ TaskBacklog (revertTask t)
transitionTask cmd _ task =
  Left $ InvalidTransition $
    "Cannot " <> commandName cmd <> " task in " <> taskStatus task <> " status"

-- | Close 処理。Backlog または InProgress からのみ実行可能。
--
-- Done からの Close は要件で禁止されている（Done は最終完了状態）。
-- Closed からの Close も無意味なので禁止。
closeTask :: UTCTime -> Task -> Either DomainError Task
closeTask now (TaskBacklog t) =
  Right $ TaskClosed (closeBacklog now t)
closeTask now (TaskInProgress t) =
  Right $ TaskClosed (closeInProgress now t)
closeTask _ task =
  Left $ InvalidTransition $
    "Cannot close task in " <> taskStatus task <> " status"

-- | TransitionCommand をエラーメッセージ用の文字列に変換する内部関数。
commandName :: TransitionCommand -> Text
commandName Start    = "start"
commandName Complete = "complete"
commandName Revert   = "revert"
