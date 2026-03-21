-- | Internal モジュール: 全てのコンストラクタを公開する。
--
-- == なぜ Internal モジュールが必要か
--
-- "Make illegal states unrepresentable" を徹底するため、
-- Value Object（Content, Priority 等）やタスク型（DoneTask 等）の
-- コンストラクタを外部に公開したくない。
--
-- しかし、以下のモジュールではコンストラクタへの直接アクセスが必要:
--   * Validation.hs — スマートコンストラクタで値を構築する
--   * Workflow.hs — 状態遷移で新しいタスク型を構築する
--   * Persistence.hs — JSON デシリアライズで値を復元する
--   * テスト — 期待値との比較でコンストラクタを使う
--
-- そこで Internal モジュールパターンを使う:
--   * Internal（このモジュール）: 全コンストラクタを公開
--   * Types（公開モジュール）: アクセサのみ公開、コンストラクタは隠蔽
--
-- 外部コードは Types をインポートし、信頼されたコードのみ Internal をインポートする。
-- Internal は「使ってもよいが、不変条件の維持は自己責任」という慣習的な契約。
-- Haskell エコシステムで広く使われているパターン（例: Data.Text.Internal）。

{-# LANGUAGE GeneralizedNewtypeDeriving #-}
{-# LANGUAGE OverloadedStrings #-}

module Domain.Task.Types.Internal
  ( -- * Value Objects
    TaskId (..)
  , Content (..)
  , Priority (..)
  , Tag (..)
  , Tags (..)
    -- * State-specific Task types
  , BacklogTask (..)
  , InProgressTask (..)
  , DoneTask (..)
  , ClosedTask (..)
    -- * Sum Type
  , Task (..)
    -- * Helpers
  , taskId
  , taskStatus
  ) where

import Data.Text (Text)
import Data.Time (UTCTime)

-- ============================================================================
-- Value Objects（値オブジェクト）
-- ============================================================================

newtype TaskId = TaskId { unTaskId :: Text }
  deriving (Show, Eq, Ord)

newtype Content = Content { unContent :: Text }
  deriving (Show, Eq)

newtype Priority = Priority { unPriority :: Int }
  deriving (Show, Eq, Ord)

newtype Tag = Tag { unTag :: Text }
  deriving (Show, Eq)

newtype Tags = Tags { unTags :: [Tag] }
  deriving (Show, Eq)

-- ============================================================================
-- 状態別のタスク型
-- ============================================================================

data BacklogTask = BacklogTask
  { backlogId        :: !TaskId
  , backlogContent   :: !Content
  , backlogPriority  :: !Priority
  , backlogTags      :: !Tags
  , backlogCreatedAt :: !UTCTime
  } deriving (Show, Eq)

data InProgressTask = InProgressTask
  { inProgressId        :: !TaskId
  , inProgressContent   :: !Content
  , inProgressPriority  :: !Priority
  , inProgressTags      :: !Tags
  , inProgressCreatedAt :: !UTCTime
  , inProgressStartedAt :: !UTCTime
  } deriving (Show, Eq)

data DoneTask = DoneTask
  { doneId          :: !TaskId
  , doneContent     :: !Content
  , donePriority    :: !Priority
  , doneTags        :: !Tags
  , doneCreatedAt   :: !UTCTime
  , doneStartedAt   :: !UTCTime
  , doneCompletedAt :: !UTCTime
  } deriving (Show, Eq)

data ClosedTask = ClosedTask
  { closedId        :: !TaskId
  , closedContent   :: !Content
  , closedPriority  :: !Priority
  , closedTags      :: !Tags
  , closedCreatedAt :: !UTCTime
  , closedClosedAt  :: !UTCTime
  } deriving (Show, Eq)

-- ============================================================================
-- Sum Type（直和型）
-- ============================================================================

data Task
  = TaskBacklog    !BacklogTask
  | TaskInProgress !InProgressTask
  | TaskDone       !DoneTask
  | TaskClosed     !ClosedTask
  deriving (Show, Eq)

-- ============================================================================
-- ヘルパー関数
-- ============================================================================

taskId :: Task -> TaskId
taskId (TaskBacklog    t) = backlogId t
taskId (TaskInProgress t) = inProgressId t
taskId (TaskDone       t) = doneId t
taskId (TaskClosed     t) = closedId t

taskStatus :: Task -> Text
taskStatus (TaskBacklog    _) = "backlog"
taskStatus (TaskInProgress _) = "in_progress"
taskStatus (TaskDone       _) = "done"
taskStatus (TaskClosed     _) = "closed"
