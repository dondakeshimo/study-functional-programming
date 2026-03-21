{-# LANGUAGE OverloadedStrings #-}

module Domain.Task.WorkflowSpec (spec) where

import Test.Hspec
import Data.Time.Clock (UTCTime (..))
import Data.Time.Calendar (fromGregorian)

import Domain.Task.Types.Internal
import Domain.Task.Workflow

-- テスト用の固定時刻
time1, time2, time3 :: UTCTime
time1 = UTCTime (fromGregorian 2026 1 1) 0
time2 = UTCTime (fromGregorian 2026 1 2) 0
time3 = UTCTime (fromGregorian 2026 1 3) 0

-- テスト用のBacklogTask
sampleBacklog :: BacklogTask
sampleBacklog = createTask (TaskId "abc12345") time1 (Content "Test task") (Priority 3) (Tags [])

spec :: Spec
spec = do
  describe "createTask" $ do
    it "creates a BacklogTask with correct fields" $ do
      backlogId sampleBacklog `shouldBe` TaskId "abc12345"
      backlogContent sampleBacklog `shouldBe` Content "Test task"
      backlogPriority sampleBacklog `shouldBe` Priority 3
      backlogCreatedAt sampleBacklog `shouldBe` time1

  describe "startTask" $ do
    it "transitions Backlog to InProgress" $ do
      let ip = startTask time2 sampleBacklog
      inProgressId ip `shouldBe` TaskId "abc12345"
      inProgressStartedAt ip `shouldBe` time2

  describe "completeTask" $ do
    it "transitions InProgress to Done" $ do
      let ip = startTask time2 sampleBacklog
          done = completeTask time3 ip
      doneId done `shouldBe` TaskId "abc12345"
      doneStartedAt done `shouldBe` time2
      doneCompletedAt done `shouldBe` time3

  describe "revertTask" $ do
    it "transitions InProgress back to Backlog" $ do
      let ip = startTask time2 sampleBacklog
          reverted = revertTask ip
      backlogId reverted `shouldBe` TaskId "abc12345"
      backlogCreatedAt reverted `shouldBe` time1

  describe "closeBacklog" $ do
    it "transitions Backlog to Closed" $ do
      let closed = closeBacklog time2 sampleBacklog
      closedId closed `shouldBe` TaskId "abc12345"
      closedClosedAt closed `shouldBe` time2

  describe "closeInProgress" $ do
    it "transitions InProgress to Closed" $ do
      let ip = startTask time2 sampleBacklog
          closed = closeInProgress time3 ip
      closedId closed `shouldBe` TaskId "abc12345"
      closedClosedAt closed `shouldBe` time3

  describe "transitionTask" $ do
    it "starts a Backlog task" $ do
      let result = transitionTask Start time2 (TaskBacklog sampleBacklog)
      result `shouldSatisfy` isRight
      case result of
        Right (TaskInProgress _) -> return ()
        _                        -> expectationFailure "Expected TaskInProgress"

    it "completes an InProgress task" $ do
      let ip = startTask time2 sampleBacklog
          result = transitionTask Complete time3 (TaskInProgress ip)
      result `shouldSatisfy` isRight

    it "reverts an InProgress task" $ do
      let ip = startTask time2 sampleBacklog
          result = transitionTask Revert time3 (TaskInProgress ip)
      result `shouldSatisfy` isRight
      case result of
        Right (TaskBacklog _) -> return ()
        _                     -> expectationFailure "Expected TaskBacklog"

    it "rejects starting an InProgress task" $ do
      let ip = startTask time2 sampleBacklog
          result = transitionTask Start time3 (TaskInProgress ip)
      result `shouldSatisfy` isLeft

    it "rejects completing a Backlog task" $ do
      let result = transitionTask Complete time2 (TaskBacklog sampleBacklog)
      result `shouldSatisfy` isLeft

    it "rejects any transition on a Done task" $ do
      let ip = startTask time2 sampleBacklog
          done = completeTask time3 ip
      transitionTask Start time3 (TaskDone done) `shouldSatisfy` isLeft
      transitionTask Complete time3 (TaskDone done) `shouldSatisfy` isLeft
      transitionTask Revert time3 (TaskDone done) `shouldSatisfy` isLeft

  describe "closeTask" $ do
    it "closes a Backlog task" $ do
      let result = closeTask time2 (TaskBacklog sampleBacklog)
      result `shouldSatisfy` isRight

    it "closes an InProgress task" $ do
      let ip = startTask time2 sampleBacklog
          result = closeTask time3 (TaskInProgress ip)
      result `shouldSatisfy` isRight

    it "rejects closing a Done task" $ do
      let ip = startTask time2 sampleBacklog
          done = completeTask time3 ip
          result = closeTask time3 (TaskDone done)
      result `shouldSatisfy` isLeft

    it "rejects closing a Closed task" $ do
      let closed = closeBacklog time2 sampleBacklog
          result = closeTask time3 (TaskClosed closed)
      result `shouldSatisfy` isLeft

isLeft :: Either a b -> Bool
isLeft (Left _)  = True
isLeft (Right _) = False

isRight :: Either a b -> Bool
isRight (Right _) = True
isRight (Left _)  = False
