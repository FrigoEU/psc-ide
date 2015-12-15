{-# LANGUAGE TemplateHaskell #-}
{-# LANGUAGE TupleSections #-}
{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE PackageImports #-}

module PureScript.Ide where

import           Control.Concurrent.STM
import           Control.Monad.Except
import           Control.Monad.State.Lazy (StateT (..))
import           Control.Monad.State.Class
import           Control.Monad.Trans.Either
import           "monad-logger" Control.Monad.Logger
import qualified Data.Map.Lazy            as M
import           Data.Maybe               (mapMaybe, catMaybes)
import           Data.Monoid
import qualified Data.Text  as T
import           PureScript.Ide.Completion
import           PureScript.Ide.Externs
import           PureScript.Ide.Pursuit
import           PureScript.Ide.Error
import           PureScript.Ide.Types
import           PureScript.Ide.SourceFile
import           PureScript.Ide.Reexports
import           System.FilePath
import           System.Directory

type PscIde = LoggingT (StateT (TVar PscState) IO)

getPscIdeState :: (MonadIO m, MonadState (TVar PscState) m) =>
                  m (M.Map ModuleIdent [ExternDecl])
getPscIdeState = do
  stateVar <- get
  liftIO $ pscStateModules <$> readTVarIO stateVar

getAllDecls :: PscIde [ExternDecl]
getAllDecls = concat <$> getPscIdeState

getAllModules :: PscIde [Module]
getAllModules = M.toList <$> getPscIdeState

getAllModulesWithReexports :: (Monad m, MonadIO m, MonadState (TVar PscState) m, MonadLogger m) =>
                              m [Module]
getAllModulesWithReexports = do
  mis <- M.keys <$> getPscIdeState
  ms  <- traverse getModuleWithReexports mis
  return (catMaybes ms)

getModule :: (MonadIO m, MonadState (TVar PscState) m, MonadLogger m) =>
             ModuleIdent -> m (Maybe Module)
getModule m = do
    $(logDebug) ("Getting the module: " <> T.pack (show m))
    modules <- getPscIdeState
    return ((m,) <$> M.lookup m modules)

getModuleWithReexports :: (MonadIO m, MonadState (TVar PscState) m, MonadLogger m) =>
                          ModuleIdent -> m (Maybe Module)
getModuleWithReexports mi = do
  m <- getModule mi
  modules <- getPscIdeState
  pure $ resolveReexports modules <$> m

resolveReexports :: M.Map ModuleIdent [ExternDecl] -> Module ->  Module
resolveReexports modules m = do
  let replaced = replaceReexports m modules
  if null . getReexports $ replaced
    then replaced
    else resolveReexports modules replaced

insertModule :: Module -> PscIde ()
insertModule (name, decls) = do
  stateVar <- get
  liftIO . atomically $ modifyTVar stateVar $ \x ->
    x { pscStateModules = M.insert name decls (pscStateModules x)}

findCompletions :: [Filter] -> Matcher -> PscIde Success
findCompletions filters matcher =
  findCompletions' filters matcher <$> getAllModulesWithReexports

findCompletions' :: [Filter] -> Matcher -> [Module] -> Success
findCompletions' f m ms = CompletionResult $ getCompletions f m ms

findType :: DeclIdent -> [Filter] -> PscIde Success
findType search filters =
  findType' search filters <$> getAllModulesWithReexports

findType' :: DeclIdent -> [Filter] -> [Module] -> Success
findType' search fs ms = CompletionResult $ getExactMatches search fs ms

findPursuitCompletions :: PursuitQuery -> PscIde Success
findPursuitCompletions (PursuitQuery q) =
  PursuitResult <$> liftIO (searchPursuitForDeclarations q)

findPursuitPackages :: PursuitQuery -> PscIde Success
findPursuitPackages (PursuitQuery q) =
  PursuitResult <$> liftIO (findPackagesForModuleIdent q)

loadExtern :: FilePath -> PscIde (Either Error ())
loadExtern fp = runEitherT $ do
  m <- EitherT . liftIO $ readExternFile fp
  lift (insertModule m)

printModules :: (MonadIO m, MonadState (TVar PscState) m) => m Success
printModules = printModules' <$> getPscIdeState

printModules' :: M.Map ModuleIdent [ExternDecl] -> Success
printModules' = ModuleList . M.keys

listAvailableModules :: MonadIO m => m Success
listAvailableModules = liftIO $ do
  cwd <- getCurrentDirectory
  dirs <- getDirectoryContents (cwd </> "output")
  return (listAvailableModules' dirs)

listAvailableModules' :: [FilePath] -> Success
listAvailableModules' dirs =
  let cleanedModules = filter (`notElem` [".", ".."]) dirs
  in ModuleList (map T.pack cleanedModules)

importsForFile :: FilePath -> PscIde (Either Error Success)
importsForFile fp = do
  imports <- liftIO (getImportsForFile fp)
  return (ImportList <$> imports)

-- | The first argument is a set of modules to load. The second argument
--   denotes modules for which to load dependencies
loadModulesAndDeps :: [ModuleIdent] -> [ModuleIdent] -> PscIde (Either Error Success)
loadModulesAndDeps mods deps = do
  r1 <- mapM loadModule (mods ++ deps)
  r2 <- mapM loadModuleDependencies deps
  return $ do
    moduleResults <- fmap T.concat (sequence r1)
    dependencyResults <- fmap T.concat (sequence r2)
    return (TextResult (moduleResults <> ", " <> dependencyResults))

loadModuleDependencies :: ModuleIdent -> PscIde (Either Error T.Text)
loadModuleDependencies moduleName = do
  m <- getModule moduleName
  case getDependenciesForModule <$> m of
    Just deps -> do
      mapM_ loadModule deps
      -- We need to load the modules, that get reexported from the dependencies
      depModules <- catMaybes <$> mapM getModule deps
      -- What to do with errors here? This basically means a reexported dependency
      -- doesn't exist in the output/ folder
      _ <- traverse loadReexports depModules
      return (Right ("Dependencies for " <> moduleName <> " loaded."))
    Nothing -> return (Left (ModuleNotFound moduleName))

loadReexports :: Module -> PscIde (Either Error [ModuleIdent])
loadReexports m = case getReexports m of
  [] -> return (Right [])
  exportDeps -> runEitherT $ do
    -- I'm fine with this crashing on a failed pattern match.
    -- If this ever fails I'll need to look at GADTs
    let reexports = map (\(Export mn) -> mn) exportDeps
    -- liftIO $ print reexports
    _ <- traverse (EitherT . loadModule) reexports
    exportDepsModules <- lift $ catMaybes <$> traverse getModule reexports
    exportDepDeps <- traverse (EitherT . loadReexports) exportDepsModules
    return $ concat exportDepDeps

getDependenciesForModule :: Module -> [ModuleIdent]
getDependenciesForModule (_, decls) = mapMaybe getDependencyName decls
  where getDependencyName (Dependency dependencyName _) = Just dependencyName
        getDependencyName _ = Nothing

loadModule :: ModuleIdent -> PscIde (Either Error T.Text)
loadModule mn = runEitherT $ do
  path <- EitherT . liftIO $ filePathFromModule "json" mn
  EitherT (loadExtern path)
  return ("Loaded extern file at: " <> T.pack path)

filePathFromModule :: String -> ModuleIdent -> IO (Either Error FilePath)
filePathFromModule extension moduleName = do
  cwd <- getCurrentDirectory
  let path = cwd </> "output" </> T.unpack moduleName </> "externs." ++ extension
  ex <- doesFileExist path
  return $
    if ex
    then Right path
    else Left (ModuleFileNotFound moduleName)

-- | Taken from Data.Either.Utils
maybeToEither :: MonadError e m =>
                 e                      -- ^ (Left e) will be returned if the Maybe value is Nothing
              -> Maybe a                -- ^ (Right a) will be returned if this is (Just a)
              -> m a
maybeToEither errorval Nothing = throwError errorval
maybeToEither _ (Just normalval) = return normalval
