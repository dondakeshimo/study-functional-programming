-- | DTO (Data Transfer Object): ドメインオブジェクトと外部 I/F の間の変換層。
--
-- == なぜ DTO が必要か
--
-- ドメイン層の型（BacklogTask, InProgressTask 等）は内部構造に最適化されている。
-- しかし API のリクエスト/レスポンスでは異なる形式が求められる:
--   * リクエスト: priority が省略可能（Maybe Int）、tags も省略可能
--   * レスポンス: 全状態を統一的な形式で返す（startedAt 等は Maybe）
--
-- DTO を介することで、ドメイン層の型を API の都合に合わせて変更する必要がなくなる。
-- これは DDD の「Anti-Corruption Layer（腐敗防止層）」の考え方に通じる。
--
-- == Generic と DeriveGeneric
--
-- Haskell の Generic は、データ型の構造を自動的に解析する仕組み。
-- DeriveGeneric 拡張を有効にすると、@deriving (Generic)@ で Generic インスタンスを
-- 自動導出できる。aeson は Generic を使って、レコードフィールド名から
-- JSON のキー名を自動的に導出する。
--
-- == fieldLabelModifier
--
-- フィールド名の変換ルールを指定する。
-- @camelTo2 '_' . drop 3@ は:
--   1. 先頭3文字を除去（プレフィックス "ctr", "utr", "tr" を除去）
--   2. camelCase を snake_case に変換（camelTo2 '_'）
-- 例: ctrPriority → "priority", trCreatedAt → "created_at"

{-# LANGUAGE DeriveGeneric #-}
  -- ^ deriving (Generic) を使うために必要な GHC 拡張。
{-# LANGUAGE OverloadedStrings #-}

module Web.Dto
  ( CreateTaskRequest (..)
  , UpdateTaskRequest (..)
  , TaskResponse (..)
  , taskToResponse
  , parseTransitionCommand
  ) where

import Data.Aeson (FromJSON (..), ToJSON (..), genericParseJSON, genericToJSON, defaultOptions, fieldLabelModifier, camelTo2)
import Data.Text (Text)
import Data.Time (UTCTime)
import GHC.Generics (Generic)

import Domain.Task.Types
import Domain.Task.Workflow (TransitionCommand (..))

-- ============================================================================
-- Request DTO（リクエスト用データ型）
-- ============================================================================

-- | タスク新規作成リクエスト。
--
-- ctrPriority と ctrTags は省略可能（Maybe 型）。
-- 省略された場合のデフォルト値はハンドラ側で処理する。
--
-- JSON 例:
-- @
-- { "content": "買い物に行く", "priority": 1, "tags": ["日常", "買い物"] }
-- { "content": "最小限のリクエスト" }  -- priority, tags は省略可能
-- @
data CreateTaskRequest = CreateTaskRequest
  { ctrContent  :: Text        -- ^ タスク内容（必須）
  , ctrPriority :: Maybe Int   -- ^ 優先度（省略時はデフォルト3）
  , ctrTags     :: Maybe [Text] -- ^ タグリスト（省略時は空リスト）
  } deriving (Show, Generic)

-- | genericParseJSON: Generic を使って自動的に FromJSON を実装する。
--   fieldLabelModifier でフィールド名 → JSON キー名の変換ルールを指定。
--   camelTo2 '_' . drop 3: "ctrContent" → drop 3 → "Content" → camelTo2 → "content"
instance FromJSON CreateTaskRequest where
  parseJSON = genericParseJSON defaultOptions { fieldLabelModifier = camelTo2 '_' . drop 3 }

-- | 状態遷移リクエスト。
--
-- JSON 例:
-- @
-- { "transition": "start" }     -- Backlog → InProgress
-- { "transition": "complete" }  -- InProgress → Done
-- { "transition": "revert" }    -- InProgress → Backlog
-- @
data UpdateTaskRequest = UpdateTaskRequest
  { utrTransition :: Text  -- ^ 遷移コマンド文字列
  } deriving (Show, Generic)

instance FromJSON UpdateTaskRequest where
  parseJSON = genericParseJSON defaultOptions { fieldLabelModifier = camelTo2 '_' . drop 3 }

-- ============================================================================
-- Response DTO（レスポンス用データ型）
-- ============================================================================

-- | タスクレスポンス。全状態を統一的な形式で返す。
--
-- ドメイン層では状態ごとに異なる型（BacklogTask, InProgressTask 等）を使うが、
-- API レスポンスでは統一的な JSON 形式で返す必要がある。
-- 状態によって存在しないフィールド（startedAt 等）は Maybe で表現する。
--
-- JSON 例（Backlog 状態）:
-- @
-- {
--   "id": "abc12345",
--   "content": "買い物に行く",
--   "priority": 1,
--   "tags": ["日常"],
--   "status": "backlog",
--   "created_at": "2026-01-01T00:00:00Z",
--   "started_at": null,
--   "completed_at": null,
--   "closed_at": null
-- }
-- @
data TaskResponse = TaskResponse
  { trId          :: Text
  , trContent     :: Text
  , trPriority    :: Int
  , trTags        :: [Text]
  , trStatus      :: Text
  , trCreatedAt   :: UTCTime
  , trStartedAt   :: Maybe UTCTime  -- ^ InProgress, Done の場合に値がある
  , trCompletedAt :: Maybe UTCTime  -- ^ Done の場合のみ値がある
  , trClosedAt    :: Maybe UTCTime  -- ^ Closed の場合のみ値がある
  } deriving (Show, Generic)

-- | genericToJSON: Generic を使って自動的に ToJSON を実装する。
--   "trId" → drop 2 → "Id" → camelTo2 '_' → "id"
instance ToJSON TaskResponse where
  toJSON = genericToJSON defaultOptions { fieldLabelModifier = camelTo2 '_' . drop 2 }

-- ============================================================================
-- 変換関数
-- ============================================================================

-- | ドメインの Task 型を API レスポンス用の TaskResponse に変換する。
--
-- パターンマッチで各状態を処理し、状態に応じて
-- startedAt, completedAt, closedAt の値を設定する。
-- unXxx 関数群（unTaskId, unContent 等）で newtype を剥がして
-- 原始型（Text, Int）に変換している。
taskToResponse :: Task -> TaskResponse
taskToResponse (TaskBacklog t) = TaskResponse
  { trId          = unTaskId (backlogId t)
  , trContent     = unContent (backlogContent t)
  , trPriority    = unPriority (backlogPriority t)
  , trTags        = map unTag (unTags (backlogTags t))
  , trStatus      = "backlog"
  , trCreatedAt   = backlogCreatedAt t
  , trStartedAt   = Nothing    -- Backlog では未開始
  , trCompletedAt = Nothing
  , trClosedAt    = Nothing
  }
taskToResponse (TaskInProgress t) = TaskResponse
  { trId          = unTaskId (inProgressId t)
  , trContent     = unContent (inProgressContent t)
  , trPriority    = unPriority (inProgressPriority t)
  , trTags        = map unTag (unTags (inProgressTags t))
  , trStatus      = "in_progress"
  , trCreatedAt   = inProgressCreatedAt t
  , trStartedAt   = Just (inProgressStartedAt t)  -- InProgress なので開始済み
  , trCompletedAt = Nothing
  , trClosedAt    = Nothing
  }
taskToResponse (TaskDone t) = TaskResponse
  { trId          = unTaskId (doneId t)
  , trContent     = unContent (doneContent t)
  , trPriority    = unPriority (donePriority t)
  , trTags        = map unTag (unTags (doneTags t))
  , trStatus      = "done"
  , trCreatedAt   = doneCreatedAt t
  , trStartedAt   = Just (doneStartedAt t)       -- 完了前に開始しているので値がある
  , trCompletedAt = Just (doneCompletedAt t)      -- Done なので完了済み
  , trClosedAt    = Nothing
  }
taskToResponse (TaskClosed t) = TaskResponse
  { trId          = unTaskId (closedId t)
  , trContent     = unContent (closedContent t)
  , trPriority    = unPriority (closedPriority t)
  , trTags        = map unTag (unTags (closedTags t))
  , trStatus      = "closed"
  , trCreatedAt   = closedCreatedAt t
  , trStartedAt   = Nothing
  , trCompletedAt = Nothing
  , trClosedAt    = Just (closedClosedAt t)       -- Closed なのでクローズ済み
  }

-- | 文字列から TransitionCommand への変換。
--
-- 該当しない文字列の場合は Nothing を返す。
-- API ハンドラ側で Nothing の場合に 400 Bad Request を返す。
parseTransitionCommand :: Text -> Maybe TransitionCommand
parseTransitionCommand "start"    = Just Start
parseTransitionCommand "complete" = Just Complete
parseTransitionCommand "revert"   = Just Revert
parseTransitionCommand _          = Nothing
