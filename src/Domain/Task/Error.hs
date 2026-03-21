-- | ドメイン層で発生するエラーを表す型。
--
-- DDDにおいて、ドメインエラーはドメインの言葉で表現される。
-- Haskell では代数的データ型（ADT）を使い、起こりうるエラーを
-- 網羅的に列挙することで、呼び出し側にパターンマッチでの処理を強制できる。
--
-- 例外（Exception）ではなく Either の Left 値として返すことで、
-- エラーハンドリングを型レベルで強制する（呼び出し側が無視できない）。
module Domain.Task.Error
  ( DomainError (..)
  ) where

import Data.Text (Text)

-- | ドメインエラーの代数的データ型。
--
-- 各コンストラクタは Text のエラーメッセージを保持する。
-- deriving (Show, Eq) により、デバッグ出力やテストでの比較が可能になる。
data DomainError
  = ValidationError Text     -- ^ 入力値のバリデーション違反（例: Content が空文字）
  | InvalidTransition Text   -- ^ 許可されていない状態遷移（例: Done → Start）
  | TaskNotFound Text        -- ^ 指定されたIDのタスクが存在しない
  deriving (Show, Eq)
