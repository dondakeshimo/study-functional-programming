# Plan: GET リクエストに "Hello, World!" を返す Web Server

## Context

関数型プログラミング学習リポジトリに、最初の Web サーバーを追加する。GET `/` で "Hello, World!" を返すシンプルな実装。

## フレームワーク選定: Scotty

- **Scotty**: Sinatra風の軽量DSL。学習用途に最適。内部的に warp を使うため本格的なHTTPエンジン上で動作する
- servant や素の warp は学習初期には複雑すぎるためスキップ

## 変更対象ファイル

### 1. `study-fp.cabal` — 依存追加・モジュール登録

- `library` の `build-depends` に `scotty >= 0.22` と `text` を追加
- `exposed-modules` に `Web.App` を追加

### 2. `src/Web/App.hs` — 新規作成（アプリケーション定義）

```haskell
module Web.App (app) where

import Web.Scotty (ScottyM, get, text)
import Data.Text.Lazy (Text)

greeting :: Text
greeting = "Hello, World!"

app :: ScottyM ()
app = do
  get "/" $ text greeting
```

### 3. `app/Main.hs` — サーバー起動に変更

```haskell
module Main where

import Web.Scotty (scotty)
import Web.App (app)

main :: IO ()
main = do
  putStrLn "Starting server on http://localhost:3000"
  scotty 3000 app
```

### 4. `src/MyLib.hs` — 変更なし

## 検証方法

```bash
cabal build
cabal run study-fp
# 別ターミナルで:
curl http://localhost:3000/   # => "Hello, World!"
```
