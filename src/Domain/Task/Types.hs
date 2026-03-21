-- | "Domain Modeling Made Functional" の核心: 型でドメインをモデリングする。
--
-- == 設計思想: "Make illegal states unrepresentable"
--
-- このモジュールでは、タスクの各状態（Backlog, InProgress, Done, Closed）を
-- それぞれ独立したデータ型として定義している。こうすることで：
--
--   * BacklogTask に startedAt フィールドは存在しない
--     → 「開始していないのに開始時刻がある」という不正状態が型レベルで不可能
--   * DoneTask には startedAt と completedAt が必須（Maybe ではない）
--     → 「完了したのに完了時刻がない」という不正状態が型レベルで不可能
--
-- == newtype パターン（Value Object）
--
-- Content, Priority, Tag 等はすべて newtype で定義している。
-- newtype は実行時のオーバーヘッドがゼロ（コンパイル時に除去される）でありながら、
-- 型の区別を提供する。例えば Content と Tag はどちらも中身は Text だが、
-- 型が異なるため取り違えるとコンパイルエラーになる。
--
-- これは DDD の「Value Object」に対応する概念で、
-- ドメインの意味を持った値を原始型（Text, Int）から区別する。
--
-- == Sum Type（直和型）
--
-- Task 型は4つの状態を Sum Type で束ねている。
-- これにより、永続化やAPI応答では統一的に扱いつつ、
-- パターンマッチで全ての状態を網羅的に処理することが強制される。
-- GHC の -Wall オプションにより、パターンマッチの漏れは警告される。

{-# LANGUAGE GeneralizedNewtypeDeriving #-}
  -- ^ newtype の deriving を拡張する。
  --   通常の deriving は限られた型クラスしか導出できないが、
  --   GeneralizedNewtypeDeriving を使うと、内部の型が持つ
  --   型クラスインスタンスを newtype にも自動的に導出できる。
  --   例: Priority の Ord は内部の Int の Ord をそのまま使う。

{-# LANGUAGE OverloadedStrings #-}
  -- ^ 文字列リテラル "..." を String 以外の型（ここでは Text）としても
  --   使えるようにする GHC 拡張。
  --   内部的には fromString 関数が暗黙的に適用される。

module Domain.Task.Types
  ( -- * Value Objects
    -- | DDD の Value Object に対応する newtype 群。
    --   スマートコンストラクタ（Validation モジュール）を通じて生成される。
    TaskId (..)
  , Content (..)
  , Priority (..)
  , Tag (..)
  , Tags (..)
    -- * State-specific Task types
    -- | 各状態に固有のフィールドを持つ型。
    --   状態遷移の正当性は Workflow モジュールの関数の型シグネチャで保証される。
  , BacklogTask (..)
  , InProgressTask (..)
  , DoneTask (..)
  , ClosedTask (..)
    -- * Sum Type
    -- | 全状態を束ねる型。永続化やAPIレスポンスで使用する。
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
-- newtype は「既存の型に新しい名前と型安全性を与える」仕組み。
-- data との違い: newtype は実行時コストがゼロ（コンパイル時に消える）。
-- record syntax { unXxx :: 型 } でアンラップ用の関数が自動生成される。
-- 例: unTaskId :: TaskId -> Text
-- ============================================================================

-- | タスクの一意な識別子（commit hash のようなハッシュ文字列）。
--   サーバー側で生成され、クライアントには読み取り専用で公開される。
newtype TaskId = TaskId { unTaskId :: Text }
  deriving (Show, Eq, Ord)
  -- ^ Show: 文字列表現（デバッグ用）
  --   Eq:   等値比較（タスク検索で使用）
  --   Ord:  順序比較（Map のキー等で必要になる場合に備えて）

-- | タスクの内容（1〜1024文字、空文字不可）。
--   コンストラクタは公開されているが、バリデーション付きの生成は
--   Validation.mkContent を使うべき。
newtype Content = Content { unContent :: Text }
  deriving (Show, Eq)

-- | 優先度（0〜5の整数、0が最も緊急、デフォルトは3）。
newtype Priority = Priority { unPriority :: Int }
  deriving (Show, Eq, Ord)
  -- ^ Ord を導出しているので、Priority 同士の比較が可能。
  --   タスク一覧の優先度ソートで使用される。

-- | タグ（1〜64文字の文字列、空文字不可）。
newtype Tag = Tag { unTag :: Text }
  deriving (Show, Eq)

-- | タグのリスト（最大10個）。
--   空リストは許可される（タグなしのタスクも有効）。
newtype Tags = Tags { unTags :: [Tag] }
  deriving (Show, Eq)

-- ============================================================================
-- 状態別のタスク型
-- ============================================================================
-- "Make illegal states unrepresentable" の実践。
-- 各状態で保持するタイムスタンプフィールドが異なる:
--   Backlog:    createdAt のみ
--   InProgress: createdAt + startedAt
--   Done:       createdAt + startedAt + completedAt
--   Closed:     createdAt + closedAt
--
-- Maybe を使わずに、状態ごとに必要なフィールドだけを持たせることで、
-- 「InProgress なのに startedAt が Nothing」のような不正状態を
-- 型レベルで排除している。
--
-- フィールド名に状態のプレフィックス（backlog〜, inProgress〜 等）を
-- 付けているのは、Haskell のレコードフィールドがモジュール内で
-- グローバルな関数として定義されるため、名前衝突を避ける必要があるため。
-- ============================================================================

-- | Backlog 状態のタスク — 起票済み、未着手。
--   startedAt, completedAt, closedAt は構造的に存在しない。
--
-- フィールドの ! は正格性注釈（Strictness Annotation）。
-- Haskell はデフォルトで遅延評価だが、! を付けるとそのフィールドは
-- データ構築時に即座に評価される。レコード型では一般的に ! を付けて
-- 不要なサンク（未評価の計算）の蓄積を防ぐ。
data BacklogTask = BacklogTask
  { backlogId        :: !TaskId
  , backlogContent   :: !Content
  , backlogPriority  :: !Priority
  , backlogTags      :: !Tags
  , backlogCreatedAt :: !UTCTime   -- ^ 起票時刻
  } deriving (Show, Eq)

-- | InProgress 状態のタスク — 作業中。
--   startedAt が必須フィールドとして追加されている（Maybe ではない）。
data InProgressTask = InProgressTask
  { inProgressId        :: !TaskId
  , inProgressContent   :: !Content
  , inProgressPriority  :: !Priority
  , inProgressTags      :: !Tags
  , inProgressCreatedAt :: !UTCTime   -- ^ 起票時刻
  , inProgressStartedAt :: !UTCTime   -- ^ 作業開始時刻（InProgress 遷移時に記録）
  } deriving (Show, Eq)

-- | Done 状態のタスク — 完了済み（終端状態、以降の遷移不可）。
--   startedAt と completedAt の両方が必須。
data DoneTask = DoneTask
  { doneId          :: !TaskId
  , doneContent     :: !Content
  , donePriority    :: !Priority
  , doneTags        :: !Tags
  , doneCreatedAt   :: !UTCTime   -- ^ 起票時刻
  , doneStartedAt   :: !UTCTime   -- ^ 作業開始時刻
  , doneCompletedAt :: !UTCTime   -- ^ 完了時刻（Done 遷移時に記録）
  } deriving (Show, Eq)

-- | Closed 状態のタスク — 未完了のまま打ち切り（終端状態、以降の遷移不可）。
--   closedAt が必須。startedAt は保持しない（Backlog から直接 Close もありうるため）。
data ClosedTask = ClosedTask
  { closedId        :: !TaskId
  , closedContent   :: !Content
  , closedPriority  :: !Priority
  , closedTags      :: !Tags
  , closedCreatedAt :: !UTCTime   -- ^ 起票時刻
  , closedClosedAt  :: !UTCTime   -- ^ クローズ時刻（Closed 遷移時に記録）
  } deriving (Show, Eq)

-- ============================================================================
-- Sum Type（直和型）
-- ============================================================================

-- | 全ての状態を束ねる Sum Type（直和型）。
--
-- Sum Type は「A または B または C または D」を表現する型。
-- 永続化（JSONファイルへの保存）やAPI応答ではこの型を使うことで、
-- 異なる状態のタスクを統一的にリストに格納できる。
--
-- パターンマッチで各状態を処理する際、GHC の -Wall オプションが有効なら
-- 処理し忘れた状態があると警告が出るため、網羅性が保証される。
--
-- 使い方の例:
--
-- @
-- case task of
--   TaskBacklog t    -> ...  -- Backlog 固有の処理
--   TaskInProgress t -> ...  -- InProgress 固有の処理
--   TaskDone t       -> ...  -- Done 固有の処理
--   TaskClosed t     -> ...  -- Closed 固有の処理
-- @
data Task
  = TaskBacklog    !BacklogTask
  | TaskInProgress !InProgressTask
  | TaskDone       !DoneTask
  | TaskClosed     !ClosedTask
  deriving (Show, Eq)

-- ============================================================================
-- ヘルパー関数
-- ============================================================================

-- | 任意の Task から TaskId を取得するヘルパー関数。
--
-- パターンマッチで全コンストラクタを網羅し、
-- どの状態でも同じ TaskId を返す。
-- 永続化やAPI層で、状態を意識せずにIDを取得したい場合に使う。
taskId :: Task -> TaskId
taskId (TaskBacklog    t) = backlogId t
taskId (TaskInProgress t) = inProgressId t
taskId (TaskDone       t) = doneId t
taskId (TaskClosed     t) = closedId t

-- | 任意の Task からステータス文字列を取得するヘルパー関数。
--
-- エラーメッセージやJSON出力でステータスを文字列として扱う場面で使用。
taskStatus :: Task -> Text
taskStatus (TaskBacklog    _) = "backlog"
taskStatus (TaskInProgress _) = "in_progress"
taskStatus (TaskDone       _) = "done"
taskStatus (TaskClosed     _) = "closed"
