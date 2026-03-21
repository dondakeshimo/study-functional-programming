{-# LANGUAGE OverloadedStrings #-}

module Domain.Task.ValidationSpec (spec) where

import Test.Hspec
import qualified Data.Text as T

import Domain.Task.Types (Content (..), Priority (..), Tag (..), Tags (..))
import Domain.Task.Validation (mkContent, mkPriority, mkTag, mkTags)

spec :: Spec
spec = do
  describe "mkContent" $ do
    it "accepts a valid content string" $
      mkContent "Hello" `shouldBe` Right (Content "Hello")

    it "rejects an empty string" $
      mkContent "" `shouldSatisfy` isLeft

    it "accepts a 1024-character string" $
      mkContent (T.replicate 1024 "a") `shouldBe` Right (Content (T.replicate 1024 "a"))

    it "rejects a 1025-character string" $
      mkContent (T.replicate 1025 "a") `shouldSatisfy` isLeft

  describe "mkPriority" $ do
    it "accepts priority 0" $
      mkPriority 0 `shouldBe` Right (Priority 0)

    it "accepts priority 5" $
      mkPriority 5 `shouldBe` Right (Priority 5)

    it "rejects priority -1" $
      mkPriority (-1) `shouldSatisfy` isLeft

    it "rejects priority 6" $
      mkPriority 6 `shouldSatisfy` isLeft

  describe "mkTag" $ do
    it "accepts a valid tag" $
      mkTag "haskell" `shouldBe` Right (Tag "haskell")

    it "rejects an empty tag" $
      mkTag "" `shouldSatisfy` isLeft

    it "accepts a 64-character tag" $
      mkTag (T.replicate 64 "x") `shouldBe` Right (Tag (T.replicate 64 "x"))

    it "rejects a 65-character tag" $
      mkTag (T.replicate 65 "x") `shouldSatisfy` isLeft

  describe "mkTags" $ do
    it "accepts an empty list" $
      mkTags [] `shouldBe` Right (Tags [])

    it "accepts a list of valid tags" $
      mkTags ["a", "b"] `shouldBe` Right (Tags [Tag "a", Tag "b"])

    it "accepts 10 tags" $
      mkTags (replicate 10 "tag") `shouldBe` Right (Tags (replicate 10 (Tag "tag")))

    it "rejects 11 tags" $
      mkTags (replicate 11 "tag") `shouldSatisfy` isLeft

    it "rejects a list containing an empty tag" $
      mkTags ["valid", ""] `shouldSatisfy` isLeft

isLeft :: Either a b -> Bool
isLeft (Left _)  = True
isLeft (Right _) = False
