-- | JSON ファイルによるタスクの永続化と、Aeson 型クラスインスタンスの定義。
--
-- == インフラストラクチャ層の役割
--
-- DDD において、永続化はインフラストラクチャ層の責務。
-- ドメイン層（Types, Workflow）は永続化の方法を知らない。
-- このモジュールが「ドメインオブジェクト ↔ JSON」の変換を担う。
--
-- == Orphan Instance について
--
-- Haskell では、型クラスインスタンスは通常「型が定義されたモジュール」か
-- 「型クラスが定義されたモジュール」で定義すべきとされる。
-- それ以外の場所で定義すると「orphan instance（孤児インスタンス）」として警告される。
--
-- ここでは意図的に orphan instance を使っている。理由:
--   * ドメイン層（Types.hs）に aeson への依存を持ち込みたくない
--   * 永続化の方法はインフラ層の関心事であり、ドメイン層から分離すべき
--   * OPTIONS_GHC プラグマで警告を抑制している
--
-- == Aeson ライブラリ
--
-- aeson は Haskell で最もよく使われる JSON ライブラリ。
-- 主要な型クラス:
--   * ToJSON:   Haskell の値 → JSON (encode)
--   * FromJSON: JSON → Haskell の値 (decode)

{-# LANGUAGE OverloadedStrings #-}
{-# OPTIONS_GHC -fno-warn-orphans #-}
  -- ^ orphan instance の警告を抑制する GHC オプション。

module Infrastructure.Persistence
  ( loadTasks
  , saveTasks
  , findTask
  , updateTask
  , addTask
  , deleteTask
  , defaultDataFile
  ) where

import Data.Aeson
  -- ^ aeson ライブラリの主要な関数・型クラスを一括インポート。
  --   ToJSON, FromJSON, encode, eitherDecode, object, (.=), (.:) 等を含む。
import Data.Aeson.Key (fromText)
import qualified Data.Aeson.KeyMap as KM
import Data.Aeson.Types (Parser)
import qualified Data.ByteString.Lazy as BL
  -- ^ Lazy ByteString: JSON の読み書きに使用。
  --   ファイル全体を一度にメモリに載せるのではなく、必要に応じて遅延読み込みする。
import Data.List (find)
import qualified Data.Text as T
import System.Directory (doesFileExist)

import Domain.Task.Error (DomainError (..))
import Domain.Task.Types.Internal

-- ============================================================================
-- ファイル操作関数
-- ============================================================================

-- | デフォルトのデータファイルパス。
defaultDataFile :: FilePath
defaultDataFile = "data/tasks.json"

-- | JSON ファイルからタスク一覧を読み込む。
--
-- ファイルが存在しない場合やパースに失敗した場合は空リストを返す。
-- do 記法で IO アクションを順次実行している。
-- @<-@ は IO アクションの結果を変数に束縛する構文。
loadTasks :: FilePath -> IO [Task]
loadTasks path = do
  exists <- doesFileExist path     -- ファイル存在チェック（IO Bool）
  if not exists
    then return []                 -- return: 純粋な値を IO に持ち上げる
    else do
      content <- BL.readFile path  -- ファイル読み込み（IO ByteString）
      case eitherDecode content of -- JSON パース（Either String [Task]）
        Left _      -> return []   -- パース失敗時は空リスト
        Right tasks -> return tasks

-- | タスク一覧を JSON ファイルに保存する。
--
-- encode: [Task] → Lazy ByteString（JSON 文字列）
-- BL.writeFile: Lazy ByteString をファイルに書き込む
saveTasks :: FilePath -> [Task] -> IO ()
saveTasks path tasks = BL.writeFile path (encode tasks)

-- | TaskId（テキスト表現）でタスクを検索する。
--
-- Text を受け取り、内部で TaskId に変換する。
-- これにより呼び出し側が TaskId コンストラクタにアクセスする必要がなくなる。
-- find: リストから条件に合う最初の要素を探す（Maybe を返す）。
-- ここでは Maybe を Either DomainError に変換して返す。
findTask :: FilePath -> T.Text -> IO (Either DomainError Task)
findTask path tidText = do
  let tid = TaskId tidText
  tasks <- loadTasks path
  case find (\t -> taskId t == tid) tasks of
    Nothing   -> return $ Left $ TaskNotFound tidText
    Just task -> return $ Right task

-- | タスクを追加する。
--
-- @task : tasks@ はリストの先頭に要素を追加する cons 操作。
-- Haskell のリストは先頭への追加が O(1) で効率的。
addTask :: FilePath -> Task -> IO ()
addTask path task = do
  tasks <- loadTasks path
  saveTasks path (task : tasks)

-- | TaskId に一致するタスクを更新する。
--
-- map でリスト全体を走査し、ID が一致する要素だけを置き換える。
-- ラムダ式 @\t -> ...@ は無名関数。
updateTask :: FilePath -> Task -> IO ()
updateTask path updatedTask = do
  tasks <- loadTasks path
  let tasks' = map (\t -> if taskId t == taskId updatedTask then updatedTask else t) tasks
  saveTasks path tasks'

-- | タスクの削除（Close 処理）。
--
-- 実際にはリストから削除するのではなく、Closed 状態に更新する。
-- そのため updateTask と同じ実装。関数の別名を提供することで意図を明確にしている。
deleteTask :: FilePath -> Task -> IO ()
deleteTask = updateTask

-- ============================================================================
-- Aeson インスタンス（JSON シリアライゼーション）
-- ============================================================================
-- ToJSON: Haskell の値 → JSON Value（エンコード）
-- FromJSON: JSON Value → Haskell の値（デコード）
--
-- newtype の場合はそのまま内部の値を JSON 化/復元する。
-- レコード型の場合は object/withObject で JSON オブジェクトとして変換する。
-- ============================================================================

-- --- Value Objects ---

instance ToJSON TaskId where
  toJSON (TaskId t) = toJSON t  -- Text としてそのまま JSON 化

instance FromJSON TaskId where
  -- withText: JSON が文字列であることを検証してから処理する。
  -- 文字列でなければ自動的にパースエラーになる。
  parseJSON = withText "TaskId" $ return . TaskId

instance ToJSON Content where
  toJSON (Content t) = toJSON t

instance FromJSON Content where
  parseJSON = withText "Content" $ return . Content

instance ToJSON Priority where
  toJSON (Priority n) = toJSON n

instance FromJSON Priority where
  -- withScientific: JSON の数値型（Scientific）から変換する。
  -- round で整数に丸めている。
  parseJSON = withScientific "Priority" $ return . Priority . round

instance ToJSON Tag where
  toJSON (Tag t) = toJSON t

instance FromJSON Tag where
  parseJSON = withText "Tag" $ return . Tag

instance ToJSON Tags where
  toJSON (Tags ts) = toJSON ts  -- [Tag] → JSON Array

instance FromJSON Tags where
  -- withArray: JSON が配列であることを検証する。
  -- Vector（aeson の内部表現）を Haskell のリストに変換してから
  -- 各要素を parseJSON で Tag にデコードする。
  parseJSON = withArray "Tags" $ \arr -> Tags <$> mapM parseJSON (toList arr)
    where
      toList = foldr (:) []  -- Vector → List 変換

-- --- 状態別タスク型 ---
-- object [...] で JSON オブジェクトを構築する。
-- (.=) はキーと値のペアを作る演算子。
-- 例: "id" .= backlogId t  →  {"id": "abc12345"}

instance ToJSON BacklogTask where
  toJSON t = object
    [ "id"         .= backlogId t
    , "content"    .= backlogContent t
    , "priority"   .= backlogPriority t
    , "tags"       .= backlogTags t
    , "created_at" .= backlogCreatedAt t
    ]

instance FromJSON BacklogTask where
  -- withObject: JSON がオブジェクトであることを検証する。
  -- Applicative スタイル（<$> と <*>）でフィールドを順番に取り出す:
  --   BacklogTask <$> (最初のフィールド) <*> (2番目) <*> ... <*> (最後)
  --
  -- <$> は fmap の中置版: 関数を Functor（ここでは Parser）の中の値に適用する。
  -- <*> は Applicative の適用: Parser に包まれた関数を Parser に包まれた値に適用する。
  --
  -- (.:) はオブジェクトからキーを取り出す演算子。
  -- 例: v .: "id" → "id" キーの値を Parser TaskId として返す。
  parseJSON = withObject "BacklogTask" $ \v ->
    BacklogTask
      <$> v .: "id"
      <*> v .: "content"
      <*> v .: "priority"
      <*> v .: "tags"
      <*> v .: "created_at"

instance ToJSON InProgressTask where
  toJSON t = object
    [ "id"         .= inProgressId t
    , "content"    .= inProgressContent t
    , "priority"   .= inProgressPriority t
    , "tags"       .= inProgressTags t
    , "created_at" .= inProgressCreatedAt t
    , "started_at" .= inProgressStartedAt t
    ]

instance FromJSON InProgressTask where
  parseJSON = withObject "InProgressTask" $ \v ->
    InProgressTask
      <$> v .: "id"
      <*> v .: "content"
      <*> v .: "priority"
      <*> v .: "tags"
      <*> v .: "created_at"
      <*> v .: "started_at"

instance ToJSON DoneTask where
  toJSON t = object
    [ "id"           .= doneId t
    , "content"      .= doneContent t
    , "priority"     .= donePriority t
    , "tags"         .= doneTags t
    , "created_at"   .= doneCreatedAt t
    , "started_at"   .= doneStartedAt t
    , "completed_at" .= doneCompletedAt t
    ]

instance FromJSON DoneTask where
  parseJSON = withObject "DoneTask" $ \v ->
    DoneTask
      <$> v .: "id"
      <*> v .: "content"
      <*> v .: "priority"
      <*> v .: "tags"
      <*> v .: "created_at"
      <*> v .: "started_at"
      <*> v .: "completed_at"

instance ToJSON ClosedTask where
  toJSON t = object
    [ "id"         .= closedId t
    , "content"    .= closedContent t
    , "priority"   .= closedPriority t
    , "tags"       .= closedTags t
    , "created_at" .= closedCreatedAt t
    , "closed_at"  .= closedClosedAt t
    ]

instance FromJSON ClosedTask where
  parseJSON = withObject "ClosedTask" $ \v ->
    ClosedTask
      <$> v .: "id"
      <*> v .: "content"
      <*> v .: "priority"
      <*> v .: "tags"
      <*> v .: "created_at"
      <*> v .: "closed_at"

-- --- Task Sum Type ---
-- ToJSON: 各状態の JSON に "status" フィールドを追加する。
-- FromJSON: "status" フィールドで状態を判定し、対応する型にデコードする。

instance ToJSON Task where
  -- mergeStatus で各状態の JSON オブジェクトに "status" キーを追加する。
  toJSON (TaskBacklog t)    = mergeStatus "backlog"     (toJSON t)
  toJSON (TaskInProgress t) = mergeStatus "in_progress" (toJSON t)
  toJSON (TaskDone t)       = mergeStatus "done"        (toJSON t)
  toJSON (TaskClosed t)     = mergeStatus "closed"      (toJSON t)

-- | JSON オブジェクトに "status" フィールドを追加するヘルパー。
--
-- KM.insert: KeyMap（aeson の内部的な JSON オブジェクト表現）に
-- キーと値を挿入する。既存のキーがあれば上書きされる。
mergeStatus :: T.Text -> Value -> Value
mergeStatus status (Object o) = Object $ KM.insert (fromText "status") (toJSON status) o
mergeStatus _ v = v  -- Object 以外の場合はそのまま返す（通常は到達しない）

instance FromJSON Task where
  -- まず "status" フィールドを読み取り、その値に応じて
  -- 適切な状態別型のパーサーに委譲する。
  -- do 記法は Parser モナド内で使用している（IO ではない）。
  parseJSON = withObject "Task" $ \v -> do
    status <- v .: "status" :: Parser T.Text
    case status of
      "backlog"     -> TaskBacklog    <$> parseJSON (Object v)
      "in_progress" -> TaskInProgress <$> parseJSON (Object v)
      "done"        -> TaskDone       <$> parseJSON (Object v)
      "closed"      -> TaskClosed     <$> parseJSON (Object v)
      _             -> fail $ "Unknown status: " <> T.unpack status
