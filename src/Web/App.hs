{-# LANGUAGE OverloadedStrings #-}

module Web.App (app) where

import Data.Text.Lazy (Text)
import Web.Scotty (ScottyM, get, text)

greeting :: Text
greeting = "Hello, World!"

app :: ScottyM ()
app = do
  get "/" $ text greeting
