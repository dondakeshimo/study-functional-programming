# 0004: コンストラクタ隠蔽と Functor

## 概要

Value Object やタスク型のコンストラクタを隠蔽して不変条件を型で強制するリファクタリングを実施した。
その過程で `$`, `<$>`, `fmap`, `traverse`, `=>`, `where` といった Haskell の構文要素を学んだ。

## リファクタリング: Internal モジュールパターン

### 問題

`Domain.Task.Types` が全コンストラクタを `(..)` で公開していたため、
スマートコンストラクタやワークフロー関数をバイパスして不正な値を直接構築できた。

```haskell
Content ""                     -- バリデーションをバイパスして空の Content を作れてしまう
DoneTask { ... }               -- completeTask を経由せず DoneTask を直接構築できてしまう
```

### 解決策: Internal モジュールパターン

コンストラクタの公開範囲を制限するため、2層構造にした。

```
Domain.Task.Types.Internal  ← 全コンストラクタを公開（信頼されたコードのみ使用）
Domain.Task.Types           ← アクセサのみ公開、コンストラクタは隠蔽（一般利用向け）
```

#### Types.hs（公開モジュール）

```haskell
module Domain.Task.Types
  ( TaskId (unTaskId)         -- コンストラクタは隠し、アクセサのみ公開
  , Content (unContent)
  , ...
  , BacklogTask (backlogId, backlogContent, ...)  -- アクセサのみ
  , DoneTask (doneId, ...)                         -- アクセサのみ
  , Task (..)                 -- Sum Type のコンストラクタはパターンマッチに必要なので公開
  , taskId
  , taskStatus
  ) where

import Domain.Task.Types.Internal
```

#### Internal.hs

```haskell
module Domain.Task.Types.Internal
  ( TaskId (..)       -- 全コンストラクタ公開
  , Content (..)
  , ...
  , BacklogTask (..)
  , DoneTask (..)
  , Task (..)
  , taskId
  , taskStatus
  ) where
```

### 各モジュールのインポート先

| モジュール | インポート元 | 理由 |
|-----------|------------|------|
| Web.App, Web.Dto | `Types` | アクセサとパターンマッチのみ使用 |
| Validation | `Types.Internal` | スマートコンストラクタでコンストラクタが必要 |
| Workflow | `Types.Internal` | 状態遷移でコンストラクタが必要 |
| Persistence | `Types.Internal` | JSON デシリアライズでコンストラクタが必要 |
| テスト | `Types.Internal` | 期待値との比較でコンストラクタが必要 |

### 付随する変更

- `Web.App.hs`: `Tag` のパターンマッチを `unTag` アクセサに変更
  ```haskell
  -- 変更前: コンストラクタでパターンマッチ
  any (\(Tag x) -> x == tg) (unTags (backlogTags t))
  -- 変更後: アクセサ関数を使用
  any (\tag -> unTag tag == tg) (unTags (backlogTags t))
  ```
- `Persistence.hs`: `findTask` の引数を `TaskId` から `Text` に変更し、
  内部で `TaskId` を構築するように変更。呼び出し側が `TaskId` コンストラクタ不要に

### 補足: Haskell エコシステムでの Internal パターン

Internal モジュールは Haskell で広く使われている慣習（例: `Data.Text.Internal`）。
「使ってもよいが、不変条件の維持は自己責任」という契約を表す。

## 学んだ Haskell の構文

### $ — 関数適用演算子

括弧を省略するための演算子。右側の式全体を左側の関数に渡す。

```haskell
-- $ を使う
Left $ ValidationError "Content must not be empty"

-- 括弧を使う（同じ意味）
Left (ValidationError "Content must not be empty")
```

`$` は優先度が最も低い演算子なので、右側全体をまとめてくれる。
ネストが深い場合に括弧を減らせて読みやすくなる:

```haskell
-- 括弧が多くなる
return (Left (TaskNotFound (unTaskId tid)))

-- $ で読みやすく
return $ Left $ TaskNotFound (unTaskId tid)
```

### fmap — 文脈の中の値に関数を適用する

```haskell
fmap :: Functor f => (a -> b) -> f a -> f b
```

「箱（文脈）の中身に関数を適用し、箱はそのまま保つ」:

```haskell
fmap (+1) (Just 3)          -- Just 4
fmap (+1) Nothing           -- Nothing
fmap (*2) [1, 2, 3]         -- [2, 4, 6]
fmap (*2) (Right 5)         -- Right 10
fmap (*2) (Left "error")    -- Left "error"
```

各型（Maybe, Either, リスト等）が Functor 型クラスのインスタンスを実装しており、
`fmap` の動作が型ごとにパターンマッチで定義されている:

```haskell
instance Functor Maybe where
  fmap f (Just x) = Just (f x)
  fmap _ Nothing  = Nothing
```

### <$> — fmap の中置演算子版

`fmap` と全く同じ。中置で書ける版:

```haskell
fmap Tags (traverse mkTag ts)   -- 前置
Tags <$> traverse mkTag ts      -- 中置（同じ意味）
```

`$` との違い:

| 演算子 | 意味 |
|--------|------|
| `$` | 普通の関数適用（`f $ x` = `f x`） |
| `<$>` | 文脈（Either, Maybe 等）の中の値に関数を適用 |

### traverse — リストの各要素にアクション付き関数を適用し、結果をまとめる

```haskell
traverse :: (Traversable t, Applicative f) => (a -> f b) -> t a -> f (t b)
```

リストに絞ると:

```haskell
traverse :: Applicative f => (a -> f b) -> [a] -> f [b]
```

全て成功なら `Right [結果リスト]`、1つでも失敗なら即 `Left`:

```haskell
traverse mkTag ["haskell", "fp"]
-- → Right [Tag "haskell", Tag "fp"]

traverse mkTag ["haskell", ""]
-- → Left (ValidationError "Tag must not be empty")
```

`map` との違い:

| 関数 | 結果の型 | 意味 |
|------|---------|------|
| `map mkTag` | `[Either DomainError Tag]` | 各要素の成否がバラバラ |
| `traverse mkTag` | `Either DomainError [Tag]` | 全体として成功 or 失敗 |

### => — 型クラス制約

型変数に条件を付ける構文。`=>` の左が条件、右が本体の型:

```haskell
(==) :: Eq a => a -> a -> Bool
--      ~~~~
--      a が Eq（等値比較可能）である場合のみ使える

traverse :: (Traversable t, Applicative f) => (a -> f b) -> t a -> f (t b)
--          ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
--          t が Traversable かつ f が Applicative である場合のみ使える
```

他言語との対応:

| Haskell | Java 相当 |
|---------|-----------|
| `Eq a =>` | `<T extends Equatable>` |
| `(Eq a, Show a) =>` | `<T extends Equatable & Printable>` |

### where — ブロックの開始を示すキーワード

「これに続く部分がこの定義の本体である」ことを示す:

```haskell
-- モジュール定義
module Web.App (app) where

-- 型クラスインスタンス定義
instance Functor Maybe where
  fmap f (Just x) = Just (f x)

-- 関数内のローカル定義
parseJSON = withArray "Tags" $ \arr -> Tags <$> mapM parseJSON (toList arr)
  where
    toList = foldr (:) []
```

## Functor → Applicative → Monad の階層

Haskell の主要な型クラスは階層構造になっている:

| 型クラス | 主要な操作 | できること |
|---------|-----------|-----------|
| Functor | `fmap` / `<$>` | 文脈の中の値に関数を適用 |
| Applicative | `<*>` / `pure` | 複数の文脈の中の値を組み合わせる |
| Monad | `>>=` / `do` | 前の結果に応じて次の処理を決める |

上位ほどできることが増える。Monad は Applicative であり、Applicative は Functor である。
