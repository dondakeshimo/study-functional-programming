# 0003: Haskell 構文とタスク作成の処理フロー

## 概要

タスク管理アプリの「タスク作成（POST /tasks）」の処理フローを `main` 関数から追い、
その過程で Haskell の基本的な構文要素を学んだ。

## タスク作成の処理フロー

### 全体のデータフロー

```
HTTP POST /tasks (JSON)
  |
CreateTaskRequest (DTO)          <- jsonData でパース
  |
mkContent / mkPriority / mkTags  <- バリデーション (純粋)
  |
Content, Priority, Tags          <- 検証済み Value Object
  |
generateTaskId                   <- ID生成 (純粋)
createTask                       <- BacklogTask 構築 (純粋)
  |
TaskBacklog BacklogTask          <- Sum Type で包む
  |
addTask (IO)                     <- JSON ファイルに永続化
  |
taskToResponse                   <- TaskResponse (DTO) に変換
  |
HTTP 201 Created (JSON)
```

### 1. main — アプリケーション起動 (app/Main.hs)

```haskell
main :: IO ()
main = do
  createDirectoryIfMissing True "data"
  putStrLn "Starting server on http://localhost:3000"
  scotty 3000 app
```

- `data/` ディレクトリを作成（JSON 保存先）
- Scotty Web サーバーをポート 3000 で起動し、ルーティング定義 `app` を渡す

### 2. app — ルーティング登録 (src/Web/App.hs)

```haskell
app :: ScottyM ()
app = do
  post "/tasks" createTaskHandler
  -- ...
```

`POST /tasks` が `createTaskHandler` にマッピングされる。

### 3. createTaskHandler — ハンドラ (src/Web/App.hs)

リクエスト到着時に以下が順次実行される。

#### 3-1. JSON パース

```haskell
req <- jsonData :: ActionM CreateTaskRequest
```

リクエストボディを `CreateTaskRequest` にデシリアライズ。

#### 3-2. バリデーション

```haskell
let contentResult  = mkContent (ctrContent req)
    priorityResult = maybe (Right defaultPriority) mkPriority (ctrPriority req)
    tagsResult     = mkTags (maybe [] id (ctrTags req))
```

スマートコンストラクタで入力値を検証し、`Either DomainError Value` を返す。

#### 3-3. パターンマッチによるエラーチェック

```haskell
case (contentResult, priorityResult, tagsResult) of
  (Left err, _, _) -> domainErrorResponse err
  (_, Left err, _) -> domainErrorResponse err
  (_, _, Left err) -> domainErrorResponse err
  (Right content, Right priority, Right tags) -> do ...
```

3 つの `Either` を一括チェック。1 つでも `Left`（エラー）なら 400 Bad Request。

#### 3-4. ID 生成・タスク作成（純粋）→ 永続化（IO）→ レスポンス

```haskell
now <- liftIO getCurrentTime
let tid  = generateTaskId (unContent content) now  -- 純粋
    task = createTask tid now content priority tags -- 純粋
liftIO $ addTask defaultDataFile (TaskBacklog task) -- IO
status status201
json (taskToResponse (TaskBacklog task))
```

- `generateTaskId`: content + 時刻から SHA256 ハッシュの先頭 8 文字を生成
- `createTask`: `BacklogTask` レコードを構築（新規タスクは必ず Backlog 状態）
- `TaskBacklog task`: `BacklogTask` を `Task` Sum Type で包む（`addTask` と `taskToResponse` が `Task` 型を要求するため）
- `addTask`: JSON ファイルにタスクを追加して保存

## 学んだ Haskell の構文

### newtype — ゼロコストの型ラッパー（Value Object）

既存の型に新しい名前を付けて、別の型として扱う仕組み。

```haskell
newtype TaskId = TaskId { unTaskId :: Text }
--      ~~~~     ~~~~~~   ~~~~~~~~    ~~~~
--      型名     コンストラクタ  アクセサ関数  中身の型
```

- `=` の左の `TaskId`: **型名**（型注釈で使う）
- `=` の右の `TaskId`: **コンストラクタ**（値を作る関数）
- 型名とコンストラクタは同じ名前にするのが慣習（名前空間が別なので衝突しない）
- `{ unTaskId :: Text }`: レコード構文。アクセサ関数 `unTaskId :: TaskId -> Text` が自動生成される
- `un` プレフィックスは「unwrap（包みを解く）」の慣習的な命名

```haskell
-- コンストラクタで値を包む
let tid = TaskId "abc123"

-- アクセサ関数で取り出す
unTaskId tid  -- → "abc123"

-- パターンマッチでも取り出せる
case tid of TaskId t -> t  -- → "abc123"
```

`newtype` は実行時コストがゼロ。コンパイル後にラッパーは消え、中身の `Text` がそのまま使われる。
型が異なるので取り違えるとコンパイルエラーになる:

```haskell
findTask :: TaskId -> IO Task
findTask (Content "買い物")  -- コンパイルエラー! Content は TaskId ではない
findTask (TaskId "abc123")   -- OK
```

### data — 代数的データ型

`newtype` と似ているが、以下の違いがある:

- 複数のフィールドを持てる
- 複数のコンストラクタを定義できる

#### コンストラクタが 1 つの場合

型名とコンストラクタ名を同じにするのが慣習:

```haskell
data BacklogTask = BacklogTask
  { backlogId        :: !TaskId
  , backlogContent   :: !Content
  , backlogPriority  :: !Priority
  , backlogTags      :: !Tags
  , backlogCreatedAt :: !UTCTime
  }
```

```
data BacklogTask = BacklogTask { ... }
--   ~~~~~~~~~~    ~~~~~~~~~~
--   型名          コンストラクタ（newtype と同じ仕組み）
```

#### コンストラクタが複数の場合（Sum Type）

必然的に型名とコンストラクタ名が異なる:

```haskell
data Task
  = TaskBacklog    !BacklogTask
  | TaskInProgress !InProgressTask
  | TaskDone       !DoneTask
  | TaskClosed     !ClosedTask
```

```
data Task           = TaskBacklog | TaskInProgress | TaskDone | TaskClosed
--   ~~~~             ~~~~~~~~~~~   ~~~~~~~~~~~~~~   ~~~~~~~~   ~~~~~~~~~~
--   型名(1つ)        コンストラクタ(4つ)
```

#### newtype と data の使い分け

| | `newtype` | `data` |
|--|-----------|--------|
| フィールド数 | 1 つだけ | 複数可 |
| コンストラクタ数 | 1 つだけ | 複数可 |
| 実行時コスト | ゼロ（コンパイル時に消える） | あり（ラッパーが残る） |
| 用途 | Value Object（型の区別） | レコード、Sum Type |

中身が 1 つだけなら `newtype`、それ以外は `data` を使う。

### deriving — 型クラスインスタンスの自動導出

コンパイラが型クラスの実装を自動生成する仕組み。

```haskell
newtype TaskId = TaskId { unTaskId :: Text }
  deriving (Show, Eq, Ord)
```

これにより `Show`（文字列表現）、`Eq`（等値比較）、`Ord`（順序比較）が自動実装される。
手書きすると以下に相当する:

```haskell
instance Eq TaskId where
  (TaskId a) == (TaskId b) = a == b
```

標準で導出できる型クラス: `Show`, `Eq`, `Ord`, `Read`, `Enum`, `Bounded`。

GHC 拡張による追加:

- `GeneralizedNewtypeDeriving` — newtype の内部型が持つインスタンスをそのまま引き継ぐ
- `DeriveGeneric` — `Generic` を導出し、aeson 等のライブラリが型の構造を自動解析可能にする

### (..) — 全コンストラクタのインポート/エクスポート

```haskell
import Domain.Task.Error (DomainError (..))
```

`DomainError` 型と、その全コンストラクタ（`ValidationError`, `InvalidTransition`, `TaskNotFound`）をインポートする。

| 書き方 | インポートされるもの |
|--------|---------------------|
| `TaskId` | 型のみ |
| `TaskId(TaskId)` | 型 + 指定したコンストラクタ |
| `TaskId(..)` | 型 + 全コンストラクタ + 全フィールド |

`(..)` がないとコンストラクタが使えず、パターンマッチや値の構築ができない。

### . — 関数合成演算子

2 つの関数を繋げて 1 つの関数にする。

```haskell
fieldLabelModifier = camelTo2 '_' . drop 3
```

右の関数を先に適用し、その結果を左の関数に渡す:

```
"ctrContent" -> drop 3 -> "Content" -> camelTo2 '_' -> "content"
```

ラムダ式で書くと `\s -> camelTo2 '_' (drop 3 s)` と同じ。
型は `(.) :: (b -> c) -> (a -> b) -> (a -> c)`。

### drop — リストの先頭から要素を除去

```haskell
drop :: Int -> [a] -> [a]

drop 3 "ctrContent"  -- "Content"
drop 3 [1,2,3,4,5]   -- [4,5]
drop 10 "hi"          -- ""（要素数を超えてもエラーにならない）
```

Haskell の `String` は `[Char]`（文字のリスト）なので、リスト用の `drop` がそのまま文字列にも使える。
対になる関数は `take`（先頭 n 個を取る）。

### パターンマッチ — 引数の値による分岐

関数定義の引数に直接パターンを書ける:

```haskell
parseTransitionCommand :: Text -> Maybe TransitionCommand
parseTransitionCommand "start"    = Just Start
parseTransitionCommand "complete" = Just Complete
parseTransitionCommand "revert"   = Just Revert
parseTransitionCommand _          = Nothing
```

上から順にマッチを試み、最初に一致したものの右辺が返される。
`_`（アンダースコア）はワイルドカードで何にでもマッチする。
`case` 式の糖衣構文:

```haskell
parseTransitionCommand cmd = case cmd of
  "start"    -> Just Start
  "complete" -> Just Complete
  "revert"   -> Just Revert
  _          -> Nothing
```

### <- — モナドの束縛（bind）

`do` 記法の中で、モナドからの値を取り出して変数に束縛する:

```haskell
req <- jsonData           -- アクションを実行して結果を取り出す
let x = ctrContent req    -- 純粋な計算の結果に名前をつける
```

| 構文 | 用途 |
|------|------|
| `x <- action` | アクション（IO, ActionM 等）を実行して結果を取り出す |
| `let x = expr` | 純粋な式の結果に名前をつける |

`<-` は `>>=`（bind 演算子）の糖衣構文:

```haskell
jsonData >>= \req -> ...
```

### レコードフィールドアクセス

レコード構文で定義したフィールド名はアクセサ関数として自動生成される:

```haskell
data CreateTaskRequest = CreateTaskRequest
  { ctrContent :: Text, ... }

-- ctrContent :: CreateTaskRequest -> Text が自動生成される
ctrContent req  -- レコードから値を取り出す（他言語の req.content に相当）
```

### maybe 関数 — Maybe 値の処理

```haskell
maybe :: b -> (a -> b) -> Maybe a -> b
maybe デフォルト値 関数 Maybe値
```

- `Nothing` → デフォルト値を返す
- `Just x` → 関数を `x` に適用して返す

```haskell
maybe (Right defaultPriority) mkPriority (ctrPriority req)
-- ctrPriority req が Nothing → Right (Priority 3)
-- ctrPriority req が Just 1  → mkPriority 1 → Right (Priority 1)
-- ctrPriority req が Just 99 → mkPriority 99 → Left (ValidationError ...)
```

`case` 式で書くと:

```haskell
case ctrPriority req of
  Nothing -> Right defaultPriority
  Just n  -> mkPriority n
```

### | — ガード構文

条件分岐。`|` の後の条件を上から順に評価し、最初に `True` になったものの右辺が返される:

```haskell
mkContent t
  | T.null t          = Left $ ValidationError "Content must not be empty"
  | T.length t > 1024 = Left $ ValidationError "Content must be at most 1024 characters"
  | otherwise         = Right $ Content t
```

`otherwise` は `True` の別名で、デフォルトケースとして使う。
`if-else` のネストより読みやすく、条件が 3 つ以上になる場合に特に有用。

### forall — 全称量化

「この型変数はどんな型でもよい」ことを明示する構文。

```haskell
id :: a -> a              -- forall が暗黙的に付いている
id :: forall a. a -> a    -- 明示的に書いた場合（同じ意味）
```

通常は省略されており、以下の場面で明示的に書く:

| 場面 | 用途 |
|------|------|
| `ScopedTypeVariables` | 関数本体で型変数を参照可能にする |
| `RankNTypes` | 引数に「多相的な関数」を要求する |
| 存在型 | 具体的な型を隠して抽象化する |

初学段階では「`forall a.` = 任意の型 `a` に対して」と読めれば十分。

## 副作用と純粋関数の分離

Haskell は副作用を禁止するのではなく、**型で区別する**。

```haskell
-- 純粋関数 — 型に IO や ActionM が含まれない
createTask :: TaskId -> UTCTime -> Content -> Priority -> Tags -> BacklogTask
mkContent :: Text -> Either DomainError Content

-- 副作用あり — 型がモナドで包まれている
status :: Status -> ActionM ()
json   :: ToJSON a => a -> ActionM ()
addTask :: FilePath -> Task -> IO ()
```

型シグネチャを見るだけで「この関数は副作用があるか」が判断できる。

### ActionM の正体

Scotty の `ActionM` は内部に「構築中の HTTP レスポンス」という状態を持つ。
`status` や `json` を呼ぶと、この内部状態が更新され、`do` ブロックの終了時に HTTP レスポンスが組み立てられる。

### このプロジェクトの層構成

| 層 | 副作用 | 型 |
|----|--------|-----|
| `Domain.Task.Workflow` | なし | 純粋な型のみ |
| `Domain.Task.Validation` | なし | 純粋な型のみ |
| `Infrastructure.Persistence` | あり | `IO` |
| `Web.App` | あり | `ActionM`（IO を含む） |

ドメインロジックは完全に純粋に保ち、副作用は外殻（Web 層・インフラ層）に押し出す。
これが "Domain Modeling Made Functional" の設計思想。
