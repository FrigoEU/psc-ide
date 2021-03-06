{-# LANGUAGE ScopedTypeVariables #-}
module PureScript.Ide.Command where

import           Control.Monad
import           Data.Aeson
import           Data.Maybe
import           PureScript.Ide.Filter
import           PureScript.Ide.Matcher
import           PureScript.Ide.Types

data Command
    = Load { loadModules      :: [ModuleIdent]
           , loadDependencies :: [ModuleIdent]}
    | Type { typeSearch  :: DeclIdent
           , typeFilters :: [Filter]}
    | Complete { completeFilters :: [Filter]
               , completeMatcher :: Matcher}
    | Pursuit { pursuitQuery      :: PursuitQuery
              , pursuitSearchType :: PursuitSearchType}
    | List {listType :: ListType}
    | Cwd
    | Quit

data ListType = LoadedModules | Imports FilePath | AvailableModules

instance FromJSON ListType where
  parseJSON = withObject "ListType" $ \o -> do
    (listType' :: String) <- o .: "type"
    case listType' of
      "import" -> do
        fp <- o .: "file"
        return (Imports fp)
      "loadedModules" -> return LoadedModules
      "availableModules" -> return AvailableModules
      _ -> mzero

instance FromJSON Command where
  parseJSON = withObject "command" $ \o -> do
    (command :: String) <- o .: "command"
    case command of
      "list" -> do
        listType' <- o .:? "params"
        return $ List (fromMaybe LoadedModules listType')
      "cwd"  -> return Cwd
      "quit" -> return Quit
      "load" -> do
        params <- o .: "params"
        mods <- params .:? "modules"
        deps <- params .:? "dependencies"
        return $ Load (fromMaybe [] mods) (fromMaybe [] deps)
      "type" -> do
        params <- o .: "params"
        search <- params .: "search"
        filters <- params .: "filters"
        return $ Type search filters
      "complete" -> do
        params <- o .: "params"
        filters <- params .:? "filters"
        matcher <- params .:? "matcher"
        return $ Complete (fromMaybe [] filters) (fromMaybe mempty matcher)
      "pursuit" -> do
        params <- o .: "params"
        query <- params .: "query"
        queryType <- params .: "type"
        return $ Pursuit query queryType
      _ -> mzero

instance FromJSON Filter where
  parseJSON = withObject "filter" $ \o -> do
    (filter' :: String) <- o .: "filter"
    case filter' of
      "exact" -> do
        params <- o .: "params"
        search <- params .: "search"
        return $ equalityFilter search
      "prefix" -> do
        params <- o.: "params"
        search <- params .: "search"
        return $ prefixFilter search
      "modules" -> do
        params <- o .: "params"
        modules <- params .: "modules"
        return $ moduleFilter modules
      "dependencies" -> do
        params <- o .: "params"
        deps <- params .: "modules"
        return $ dependencyFilter deps
      _ -> mzero

instance FromJSON Matcher where
  parseJSON = withObject "matcher" $ \o -> do
    (matcher :: Maybe String) <- o .:? "matcher"
    case matcher of
      Just "flex" -> do
        params <- o .: "params"
        search <- params .: "search"
        return $ flexMatcher search
      Just "helm" -> error "Helm matcher not implemented yet."
      Just "distance" -> error "Distance matcher not implemented yet."
      Just _ -> mzero
      Nothing -> return mempty
