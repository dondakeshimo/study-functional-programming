-- | スマートコンストラクタによるバリデーション。
--
-- == スマートコンストラクタパターンとは
--
-- Types モジュールで定義した newtype（Content, Priority 等）のコンストラクタは
-- 公開されているため、直接 @Content ""@ のように不正な値を作れてしまう。
--
-- スマートコンストラクタは「バリデーション付きの生成関数」で、
-- 不正な値の生成を防ぐ。戻り値は @Either DomainError Value@ 型で、
-- 成功時は Right に値を、失敗時は Left にエラーを返す。
--
-- "Domain Modeling Made Functional" では、未検証の入力（Unvalidated）と
-- 検証済みの値（Validated）を型で区別することを推奨している。
-- このモジュールが「未検証 → 検証済み」の境界を担う。
--
-- == ガード構文
--
-- Haskell のガード（ | 条件 = 式 ）は、パターンマッチの拡張で、
-- 条件式に基づいて異なる結果を返す。上から順に評価され、
-- 最初に True になった条件の式が返される。
-- otherwise は True の別名で、「それ以外の場合」を表す。

{-# LANGUAGE OverloadedStrings #-}

module Domain.Task.Validation
  ( mkContent
  , mkPriority
  , mkTag
  , mkTags
  , defaultPriority
  ) where

import qualified Data.Text as T
  -- ^ qualified import: Data.Text の関数を T.xxx の形式で使う。
  --   これにより Prelude の関数（null, length 等）との名前衝突を避けられる。

import Domain.Task.Error (DomainError (..))
import Domain.Task.Types (Content (..), Priority (..), Tag (..), Tags (..))

-- | Content のスマートコンストラクタ。
--
-- 制約: 1〜1024文字、空文字不可。
--
-- @
-- mkContent ""     == Left (ValidationError "Content must not be empty")
-- mkContent "todo" == Right (Content "todo")
-- @
mkContent :: T.Text -> Either DomainError Content
mkContent t
  | T.null t          = Left $ ValidationError "Content must not be empty"
  | T.length t > 1024 = Left $ ValidationError "Content must be at most 1024 characters"
  | otherwise         = Right $ Content t

-- | Priority のスマートコンストラクタ。
--
-- 制約: 0〜5の整数。0 が最も緊急。
mkPriority :: Int -> Either DomainError Priority
mkPriority n
  | n < 0 || n > 5 = Left $ ValidationError "Priority must be between 0 and 5"
  | otherwise       = Right $ Priority n

-- | デフォルトの優先度（3）。
--   API で priority が省略された場合に使用される。
defaultPriority :: Priority
defaultPriority = Priority 3

-- | Tag のスマートコンストラクタ。
--
-- 制約: 1〜64文字、空文字不可。
mkTag :: T.Text -> Either DomainError Tag
mkTag t
  | T.null t        = Left $ ValidationError "Tag must not be empty"
  | T.length t > 64 = Left $ ValidationError "Tag must be at most 64 characters"
  | otherwise       = Right $ Tag t

-- | Tags のスマートコンストラクタ。
--
-- 制約: 最大10個、各要素は mkTag で検証される。空リストは許可。
--
-- @Tags <$> traverse mkTag ts@ の読み方:
--
--   1. @traverse mkTag ts@ : リスト ts の各要素に mkTag を適用し、
--      全て Right なら Right [Tag, ...] を、一つでも Left なら Left err を返す。
--      traverse は「リストの各要素に Either を返す関数を適用し、
--      全体を Either にまとめる」関数。
--
--   2. @Tags <$>@ : Right の中身（[Tag]）に Tags コンストラクタを適用する。
--      <$> は fmap の中置演算子版で、Either の Right 側の値を変換する。
mkTags :: [T.Text] -> Either DomainError Tags
mkTags ts
  | length ts > 10 = Left $ ValidationError "Tags must have at most 10 elements"
  | otherwise      = Tags <$> traverse mkTag ts
