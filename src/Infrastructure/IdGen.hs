-- | タスクIDの生成。インフラストラクチャ層に属する。
--
-- ドメイン層の TaskId 型は「ハッシュ文字列である」という仕様を定義するが、
-- 具体的な生成アルゴリズムはドメインの関心事ではないため、
-- インフラストラクチャ層で実装している。
--
-- これは DDD の「関心の分離」の実践:
--   * ドメイン層: 「TaskId は一意な識別子である」という概念
--   * インフラ層: 「SHA256 ハッシュで生成する」という実装の詳細

{-# LANGUAGE OverloadedStrings #-}

module Infrastructure.IdGen
  ( generateTaskId
  ) where

import qualified Crypto.Hash.SHA256 as SHA256
import qualified Data.ByteString.Base16 as Base16
import Data.Text (Text)
import qualified Data.Text as T
import Data.Text.Encoding (decodeUtf8, encodeUtf8)
import Data.Time (UTCTime)
import Data.Time.Format (formatTime, defaultTimeLocale)

import Domain.Task.Types.Internal (TaskId (..))

-- | Content と現在時刻から SHA256 ハッシュの先頭8文字を TaskId として生成する。
--
-- 処理の流れ:
--   1. content と時刻文字列を結合して入力を作る
--   2. SHA256 でハッシュ化（ByteString → ByteString）
--   3. Base16（16進数）エンコードで人間が読める文字列に変換
--   4. 先頭8文字を取得（git の短縮ハッシュと同様の考え方）
--
-- let ... in 式は、ローカル変数を定義してから最終的な式を評価する構文。
-- where と似ているが、let は式の前に変数を定義する点が異なる。
--
-- この関数は純粋関数である（IO を使わない）。
-- 時刻は引数として外部から渡されるため、同じ入力に対して常に同じ結果を返す。
generateTaskId :: Text -> UTCTime -> TaskId
generateTaskId content now =
  let input    = encodeUtf8 $ content <> T.pack (formatTime defaultTimeLocale "%s%q" now)
                 -- ^ encodeUtf8: Text → ByteString（SHA256 の入力に必要）
                 --   %s: エポック秒、%q: ピコ秒（高精度な時刻で衝突を防ぐ）
      hash     = SHA256.hash input
                 -- ^ SHA256 ハッシュを計算（32バイトの ByteString）
      hashText = decodeUtf8 $ Base16.encode hash
                 -- ^ Base16.encode: バイナリ → 16進数文字列（ByteString）
                 --   decodeUtf8: ByteString → Text
  in  TaskId (T.take 8 hashText)
      -- ^ 先頭8文字（16進数で8桁 = 4バイト = 約40億通り）を取得
