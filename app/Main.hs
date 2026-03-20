module Main where

import Web.App (app)
import Web.Scotty (scotty)

main :: IO ()
main = do
  putStrLn "Starting server on http://localhost:3000"
  scotty 3000 app
