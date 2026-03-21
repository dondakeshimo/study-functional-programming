-- | アプリケーションのエントリーポイント。
--
-- Haskell プログラムの実行は必ず Main モジュールの main 関数から始まる。
-- main の型は @IO ()@ で、副作用を伴い値を返さないことを意味する。
--
-- このモジュールはアプリケーションの「組み立て」を行う:
--   1. データディレクトリの準備（インフラストラクチャの初期化）
--   2. Web サーバーの起動（scotty 関数にルーティング定義を渡す）
--
-- ドメインロジックやルーティング定義はここには書かない。
-- Main の責務は「各層を結合して起動する」ことだけ。
module Main where

import System.Directory (createDirectoryIfMissing)
import Web.App (app)
import Web.Scotty (scotty)

main :: IO ()
main = do
  -- JSON データファイルの保存先ディレクトリを作成する。
  -- createDirectoryIfMissing True は、親ディレクトリも含めて再帰的に作成する
  -- （mkdir -p に相当）。既に存在する場合は何もしない。
  createDirectoryIfMissing True "data"
  putStrLn "Starting server on http://localhost:3000"
  -- scotty: ポート番号とルーティング定義を受け取り、HTTP サーバーを起動する。
  -- app（Web.App モジュール）は ScottyM () 型のルーティング定義。
  -- この関数呼び出しはサーバーが停止するまでブロックする。
  scotty 3000 app
