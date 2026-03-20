# 0002: Hello World Web サーバー

## 概要

Scotty フレームワークを使って、GET リクエストに "Hello, World!" を返す Web サーバーを作成した。

## Scotty

Haskell の軽量 Web フレームワーク。Ruby の Sinatra に相当する。
内部的には warp（本格的な HTTP エンジン）を使用している。

### 他のフレームワークとの比較

| フレームワーク | 特徴 |
|---------------|------|
| Scotty | Sinatra 風の軽量 DSL。学習向き |
| warp | 低レベル HTTP エンジン。ルーティングなどを自前で書く必要がある |
| servant | 型レベル API 定義。強力だが DataKinds 等の高度な GHC 拡張が必要 |

## 実装

### プロジェクト構成

```
src/Web/App.hs   ← アプリケーション定義（ルート定義）
app/Main.hs      ← エントリーポイント（サーバー起動）
study-fp.cabal   ← ビルド設定
```

### src/Web/App.hs — ルート定義

```haskell
{-# LANGUAGE OverloadedStrings #-}

module Web.App (app) where

import Data.Text.Lazy (Text)
import Web.Scotty (ScottyM, get, text)

greeting :: Text
greeting = "Hello, World!"

app :: ScottyM ()
app = do
  get "/" $ text greeting
```

- `{-# LANGUAGE OverloadedStrings #-}` — 文字列リテラルを `String` 以外の型（`Text`, `RoutePattern` など）として扱える GHC 拡張
- `greeting` — 純粋な値。副作用を持たない
- `app` — `ScottyM` モナドでルーティングを定義。サーバーは起動しない。「設計図」を組み立てるだけ

### app/Main.hs — サーバー起動

```haskell
module Main where

import Web.App (app)
import Web.Scotty (scotty)

main :: IO ()
main = do
  putStrLn "Starting server on http://localhost:3000"
  scotty 3000 app
```

- `scotty 3000 app` — `ScottyM` の「設計図」を受け取り、実際に HTTP サーバーを起動する
- 「定義」と「実行」の分離が関数型の特徴的なパターン

### study-fp.cabal の変更点

- library の `build-depends` に `scotty >= 0.22` と `text` を追加
- library の `exposed-modules` に `Web.App` を追加
- executable の `build-depends` に `scotty >= 0.22` を追加
- executable に `ghc-options: -threaded` を追加

## `-threaded` オプション

GHC は2種類のランタイムシステム（RTS）を持つ:

- **シングルスレッド RTS**（デフォルト）— ロック不要で軽量だが、IO イベントマネージャが使えない
- **マルチスレッド RTS**（`-threaded`）— 軽量スレッド、非同期 IO、タイマーが動作する

warp は非同期 IO と軽量スレッドに依存しているため、`-threaded` が必須。
なしだと以下のエラーになる:

```
GHC.Event.Thread.getSystemTimerManager: the TimerManager requires linking against the threaded runtime
```

GHC がランタイムを選択制にしている理由は、Haskell が汎用言語であり、コンパイラのような計算主体のプログラムではマルチスレッド RTS のオーバーヘッドが不要なため。

## 動作確認

```bash
cabal build
cabal run study-fp
# 別ターミナルで:
curl http://localhost:3000/   # → Hello, World!
```

## 学んだ Haskell の基礎

### do 構文とバインド

`do` は `>>=`（バインド）の糖衣構文。

```haskell
-- do 構文
do
  a <- safeDiv 12 3
  safeDiv a 2

-- 脱糖後
safeDiv 12 3 >>= \a -> safeDiv a 2
```

- `>>=` — 「文脈から中身を取り出して関数に渡し、結果を同じ文脈に戻す」演算子
- `\x -> ...` — ラムダ式（無名関数）。`\` は `λ` の代わり
- `->` — 型シグネチャでは「引数→戻り値」、ラムダや case では「パターン→結果」

### モナド

型クラス（インタフェース相当）で定義される:

```haskell
class Monad m where
  return :: a -> m a
  (>>=)  :: m a -> (a -> m b) -> m b
```

`>>=` の意味がモナドごとに異なる:

| モナド | `>>=` の意味 |
|--------|-------------|
| Maybe | Nothing なら以降をスキップ |
| IO | 副作用を順番に実行 |
| リスト | 各要素に関数を適用して連結 |
| ScottyM | ルート定義を蓄積 |

### Maybe — 最も簡単なモナドの例

```haskell
data Maybe a = Nothing | Just a

instance Monad Maybe where
  return x = Just x
  Nothing >>= f = Nothing   -- 失敗なら即終了
  Just x  >>= f = f x       -- 成功なら中身を f に渡す
```

- `instance ... where` — 型クラス（インタフェース）の実装
- `Just` — データコンストラクタ。`Just 5 :: Maybe Int`
- `m a` のスペース区切りは型の適用。Java の `M<A>` に相当
- モナドのカインド（型の型）は `* -> *`（型を1つ取って型を返す）

### モナドの使われ方

特別な呼び出しは不要。`>>=` や `do` を使うと、値の型から適切な `Monad` インスタンスがコンパイル時に自動選択される。

```haskell
safeDiv 12 3 >>= \a -> safeDiv a 2  -- Maybe Int → Maybe の >>= が使われる
getLine >>= \name -> putStrLn name   -- IO String → IO の >>= が使われる
```

関数全体の返り値が `Maybe` である必要はない。途中の計算で使い、最後に `case` や `fromMaybe` で抜ければよい。

### Web アプリにおけるモナドの実践的な使い方

実際のアプリでは、既存のモナドを組み合わせてアプリケーションモナド（AppM）を定義するのが一般的:

```haskell
type AppM = ReaderT AppEnv (ExceptT AppError IO)
```

これはモナドトランスフォーマーと呼ばれる手法で、以下の機能を合成する:

- `ReaderT` — DB接続や設定値の暗黙的な引き回し
- `ExceptT` — エラーハンドリング
- `IO` — 副作用

`>>=` をゼロから実装することは稀で、既存のモナドの積み重ねで必要な機能を得る。
