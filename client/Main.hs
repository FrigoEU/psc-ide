{-# LANGUAGE OverloadedStrings #-}
module Main where

import           Control.Exception
import           Data.Maybe          (fromMaybe)
import qualified Data.Text           as T
import qualified Data.Text.IO        as T
import           Data.Version        (showVersion)
import           Network
import           Options.Applicative
import           System.Exit
import           System.IO

import qualified Paths_psc_ide       as Paths

data Options = Options
    { optionsPort :: Maybe Int
    }

main :: IO ()
main = do
    Options port <- execParser opts
    let port' = PortNumber . fromIntegral $ fromMaybe 4242 port
    client port'
  where
    parser =
        Options <$>
          optional (option auto (long "port" <> short 'p'))
    opts = info (version <*> parser) mempty
    version = abortOption (InfoMsg (showVersion Paths.version)) $ long "version" <> help "Show the version number" <> hidden

client :: PortID -> IO ()
client port = do
    h <-
        connectTo "localhost" port `catch`
        (\(SomeException e) ->
              putStrLn
                  ("Couldn't connect to psc-ide-server on port: " ++
                   show port ++ " Error: " ++ show e) >>
              exitFailure)
    cmd <- T.getLine
    T.hPutStrLn h cmd
    res <- T.hGetLine h
    putStrLn (T.unpack res)
    hFlush stdout
    hClose h

