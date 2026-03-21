-- | Web 層: Scotty による HTTP ルーティングとハンドラの定義。
--
-- == アーキテクチャ上の位置づけ
--
-- Web 層はアプリケーションの最外殻であり、以下を担当する:
--   * HTTP リクエストの受信とパース
--   * ドメイン層のワークフロー関数の呼び出し
--   * HTTP レスポンスの構築と送信
--
-- ドメインロジック自体はここには書かない。
-- Web 層は「ドメイン層に仕事を依頼して、結果を HTTP に変換する」だけ。
--
-- == Scotty フレームワーク
--
-- Scotty は Ruby の Sinatra に影響を受けた軽量 Web フレームワーク。
-- 主要な型:
--   * ScottyM: ルーティング定義用のモナド（アプリケーション全体の設計図）
--   * ActionM: 個別のリクエストハンドラ用のモナド（リクエスト処理）
--
-- == liftIO
--
-- ActionM モナド内で IO アクションを実行するには liftIO が必要。
-- ActionM は IO のラッパーであり、直接 IO アクションは書けない。
-- liftIO :: IO a -> ActionM a で IO を ActionM に「持ち上げる」。

{-# LANGUAGE OverloadedStrings #-}

module Web.App (app) where

import Control.Monad.IO.Class (liftIO)
  -- ^ liftIO: IO アクションを他のモナド（ActionM）内で実行するための関数。
import Data.List (sortBy)
import Data.Ord (comparing)
import qualified Data.Text as T
import qualified Data.Text.Lazy as TL
  -- ^ Scotty は内部的に Lazy Text を使用するため、
  --   Data.Text（Strict）と Data.Text.Lazy の両方が必要。
import Data.Time.Clock (getCurrentTime)
import Network.HTTP.Types.Status (status201, status400, status404, status409)
import Web.Scotty (ScottyM, get, post, put, delete, json, jsonData, pathParam, queryParamMaybe, status, text, ActionM)

import Domain.Task.Error (DomainError (..))
import Domain.Task.Types
import Domain.Task.Validation (mkContent, mkPriority, mkTags, defaultPriority)
import Domain.Task.Workflow (transitionTask, closeTask, createTask)
import Infrastructure.IdGen (generateTaskId)
import Infrastructure.Persistence (loadTasks, addTask, updateTask, findTask, defaultDataFile)
import Web.Dto (CreateTaskRequest (..), UpdateTaskRequest (..), taskToResponse, parseTransitionCommand)

-- | アプリケーションのルーティング定義。
--
-- ScottyM モナド内で各エンドポイントを登録する。
-- この関数自体は「設計図」を構築するだけで、HTTP サーバーは起動しない。
-- 実際のサーバー起動は Main.hs の @scotty 3000 app@ で行われる。
app :: ScottyM ()
app = do
  post   "/tasks"     createTaskHandler   -- タスク新規作成
  get    "/tasks"     listTasksHandler    -- タスク一覧（フィルター・ソート対応）
  get    "/tasks/:id" getTaskHandler      -- タスク個別取得
  put    "/tasks/:id" updateTaskHandler   -- 状態遷移
  delete "/tasks/:id" deleteTaskHandler   -- Close 処理

-- | POST /tasks — タスク新規作成ハンドラ。
--
-- 処理の流れ:
--   1. JSON リクエストボディをパース（jsonData）
--   2. スマートコンストラクタでバリデーション
--   3. バリデーション成功時: ID 生成 → タスク作成 → 永続化 → 201 レスポンス
--   4. バリデーション失敗時: 400 エラーレスポンス
--
-- @:: ActionM CreateTaskRequest@ は型注釈。
-- jsonData は多相関数なので、どの型にパースするか明示する必要がある。
createTaskHandler :: ActionM ()
createTaskHandler = do
  req <- jsonData :: ActionM CreateTaskRequest
  -- let で複数のバリデーション結果を束縛。
  -- maybe はMaybe値の処理: maybe デフォルト値 関数 Maybe値
  -- @maybe (Right defaultPriority) mkPriority@ は
  -- Nothing なら Right defaultPriority、Just n なら mkPriority n を返す。
  let contentResult  = mkContent (ctrContent req)
      priorityResult = maybe (Right defaultPriority) mkPriority (ctrPriority req)
      tagsResult     = mkTags (maybe [] id (ctrTags req))
  -- 3つのバリデーション結果をタプルでパターンマッチ。
  -- 全て Right の場合のみ処理を続行する。
  case (contentResult, priorityResult, tagsResult) of
    (Left err, _, _) -> domainErrorResponse err
    (_, Left err, _) -> domainErrorResponse err
    (_, _, Left err) -> domainErrorResponse err
    (Right content, Right priority, Right tags) -> do
      now <- liftIO getCurrentTime           -- 現在時刻を取得（IO）
      let tid  = generateTaskId (unContent content) now  -- ID 生成（純粋）
          task = createTask tid now content priority tags -- タスク作成（純粋）
      liftIO $ addTask defaultDataFile (TaskBacklog task)  -- 永続化（IO）
      status status201                       -- HTTP 201 Created
      json (taskToResponse (TaskBacklog task))

-- | GET /tasks — タスク一覧取得ハンドラ。
--
-- クエリパラメータ:
--   * ?tag=xxx    — 指定タグを持つタスクでフィルター
--   * ?sort=priority — 優先度で昇順ソート（0が最も緊急なので先頭に来る）
--
-- queryParamMaybe: クエリパラメータを Maybe として取得する。
-- パラメータがなければ Nothing を返す。
listTasksHandler :: ActionM ()
listTasksHandler = do
  tagFilter <- queryParamMaybe "tag"  :: ActionM (Maybe TL.Text)
  sortParam <- queryParamMaybe "sort" :: ActionM (Maybe TL.Text)
  tasks <- liftIO $ loadTasks defaultDataFile
  let filtered = case tagFilter of
        Nothing -> tasks
        Just tg -> filter (hasTag (TL.toStrict tg)) tasks
                   -- filter: 条件を満たす要素だけを残す
                   -- TL.toStrict: Lazy Text → Strict Text に変換
      sorted = case sortParam of
        Just "priority" -> sortBy (comparing taskPriority) filtered
                           -- sortBy: 比較関数でソート
                           -- comparing f: f の結果で比較する関数を作る
        _               -> filtered
  json (map taskToResponse sorted)
       -- map: リストの各要素に関数を適用

-- | GET /tasks/:id — タスク個別取得ハンドラ。
--
-- pathParam: URL パスパラメータを取得する。
-- /tasks/:id の :id 部分が取得される。
getTaskHandler :: ActionM ()
getTaskHandler = do
  tid <- pathParam "id" :: ActionM TL.Text
  result <- liftIO $ findTask defaultDataFile (TaskId (TL.toStrict tid))
  case result of
    Left err   -> domainErrorResponse err
    Right task -> json (taskToResponse task)

-- | PUT /tasks/:id — 状態遷移ハンドラ。
--
-- 処理の流れ:
--   1. パスから TaskId を取得
--   2. リクエストボディから遷移コマンドをパース
--   3. ストレージからタスクを検索
--   4. ドメインの transitionTask で遷移を試みる
--   5. 成功時: 更新を永続化してレスポンス
--   6. 失敗時: エラーレスポンス（400, 404, 409）
updateTaskHandler :: ActionM ()
updateTaskHandler = do
  tid <- pathParam "id" :: ActionM TL.Text
  req <- jsonData :: ActionM UpdateTaskRequest
  case parseTransitionCommand (utrTransition req) of
    Nothing -> do
      status status400
      text "Invalid transition command. Use: start, complete, revert"
    Just cmd -> do
      result <- liftIO $ findTask defaultDataFile (TaskId (TL.toStrict tid))
      case result of
        Left err -> domainErrorResponse err
        Right task -> do
          now <- liftIO getCurrentTime
          case transitionTask cmd now task of
            Left err          -> domainErrorResponse err
            Right updatedTask -> do
              liftIO $ updateTask defaultDataFile updatedTask
              json (taskToResponse updatedTask)

-- | DELETE /tasks/:id — Close 処理ハンドラ。
--
-- Backlog または InProgress のタスクを Closed 状態に遷移させる。
-- Done や Closed のタスクに対して実行するとエラー（409 Conflict）を返す。
deleteTaskHandler :: ActionM ()
deleteTaskHandler = do
  tid <- pathParam "id" :: ActionM TL.Text
  result <- liftIO $ findTask defaultDataFile (TaskId (TL.toStrict tid))
  case result of
    Left err -> domainErrorResponse err
    Right task -> do
      now <- liftIO getCurrentTime
      case closeTask now task of
        Left err          -> domainErrorResponse err
        Right closedTask' -> do
          liftIO $ updateTask defaultDataFile closedTask'
          json (taskToResponse closedTask')

-- ============================================================================
-- ヘルパー関数
-- ============================================================================

-- | ドメインエラーを適切な HTTP レスポンスに変換する。
--
-- エラーの種類に応じて異なるステータスコードを返す:
--   * ValidationError   → 400 Bad Request
--   * InvalidTransition → 409 Conflict（状態遷移の競合）
--   * TaskNotFound      → 404 Not Found
domainErrorResponse :: DomainError -> ActionM ()
domainErrorResponse (ValidationError msg) = do
  status status400
  text (TL.fromStrict msg)
domainErrorResponse (InvalidTransition msg) = do
  status status409
  text (TL.fromStrict msg)
domainErrorResponse (TaskNotFound msg) = do
  status status404
  text (TL.fromStrict $ "Task not found: " <> msg)

-- | タスクが指定タグを持つかチェックするヘルパー。
--
-- 全状態でパターンマッチして tags フィールドにアクセスする。
-- any: リストの要素のうち、一つでも条件を満たすものがあれば True を返す。
hasTag :: T.Text -> Task -> Bool
hasTag tg (TaskBacklog t)    = any (\(Tag x) -> x == tg) (unTags (backlogTags t))
hasTag tg (TaskInProgress t) = any (\(Tag x) -> x == tg) (unTags (inProgressTags t))
hasTag tg (TaskDone t)       = any (\(Tag x) -> x == tg) (unTags (doneTags t))
hasTag tg (TaskClosed t)     = any (\(Tag x) -> x == tg) (unTags (closedTags t))

-- | タスクの Priority（Int 値）を取得するヘルパー。
--
-- sortBy (comparing taskPriority) でソートに使用される。
taskPriority :: Task -> Int
taskPriority (TaskBacklog t)    = unPriority (backlogPriority t)
taskPriority (TaskInProgress t) = unPriority (inProgressPriority t)
taskPriority (TaskDone t)       = unPriority (donePriority t)
taskPriority (TaskClosed t)     = unPriority (closedPriority t)
