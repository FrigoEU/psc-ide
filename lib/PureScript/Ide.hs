{-# OPTIONS_GHC -fno-warn-unused-do-bind #-}

module PureScript.Ide
  (
    emptyPscState,
    findTypeForName,
    findCompletionsByPrefix,
    loadExtern,
    getDependenciesForModule,
    printModules,
    unsafeStateFromDecls,
    PscIde,
    PscState(..),
  ) where

import           Control.Monad
import           Control.Monad.State.Lazy (StateT (..), get, modify)
import           Control.Monad.Trans
import           Data.Foldable
import qualified Data.Map.Lazy            as M
import           Data.Maybe               (mapMaybe)
import           Data.Monoid
import           Data.Text                (Text ())
import qualified Data.Text                as T
import           PureScript.Ide.Command
import           PureScript.Ide.Externs
import           PureScript.Ide.Pursuit

type Module = (ModuleIdent, [ExternDecl])

type PscIde = StateT PscState IO

data PscState = PscState
    { pscStateModules :: M.Map Text [ExternDecl]
    } deriving (Show,Eq)

emptyPscState :: PscState
emptyPscState = PscState M.empty

getAllDecls :: PscIde [ExternDecl]
getAllDecls = return . concat =<< fmap pscStateModules get

-- | Given a set of ExternDeclarations finds the type for a given function
--   name and returns Nothing if the functionName can not be matched
findTypeForName :: DeclIdent -> PscIde (Maybe Type)
findTypeForName name = do
  getFirst . foldMap (First . go) <$> getAllDecls
  where
    go :: ExternDecl -> Maybe Type
    go decl =
        case decl of
            FunctionDecl n t ->
                if name == n
                    then Just t
                    else Nothing
            _ -> Nothing

findCompletionsByPrefix :: DeclIdent -> Level -> PscIde [DeclIdent]
findCompletionsByPrefix prefix level
  | level == File || level == Project = fileMatches
  | level == Pursuit                  = liftM2 mappend fileMatches pursuitMatches
  where
    fileMatches    = findCompletionsByPrefix' prefix <$> getAllDecls
    pursuitMatches = liftIO $ liftM (fmap fst) (searchPursuit prefix)

findCompletionsByPrefix' :: DeclIdent -> [ExternDecl] -> [DeclIdent]
findCompletionsByPrefix' prefix decls =
  mapMaybe go decls
  where
    matches name =
       if prefix `T.isPrefixOf` name
            then Just name
            else Nothing
    go :: ExternDecl -> Maybe DeclIdent
    go (FunctionDecl name _) = matches name
    go (DataDecl name _) = matches name
    go _ = Nothing

loadExtern :: FilePath -> PscIde ()
loadExtern fp = do
    parseResult <- liftIO $ readExternFile fp
    case parseResult of
        Right decls ->
            let (name, decls') = unsafeModuleFromDecls decls
            in modify
                   (\x ->
                         x
                         { pscStateModules = M.insert
                               name
                               decls'
                               (pscStateModules x)
                         })
        Left _ -> liftIO $ putStrLn "The module could not be parsed"

getDependenciesForModule :: ModuleIdent -> PscIde (Maybe [ModuleIdent])
getDependenciesForModule m = do
  mDecls <- M.lookup m . pscStateModules <$> get
  return $ mapMaybe getDependencyName <$> mDecls
  where getDependencyName (Dependency dependencyName _) = Just dependencyName
        getDependencyName _ = Nothing

unsafeModuleFromDecls :: [ExternDecl] -> Module
unsafeModuleFromDecls (ModuleDecl name _ : decls) = (name, decls)
unsafeModuleFromDecls _ =
    error "An externs File didn't start with a module declaration"

unsafeStateFromDecls :: [[ExternDecl]] -> PscState
unsafeStateFromDecls = PscState . M.fromList . fmap unsafeModuleFromDecls

printModules :: PscIde [ModuleIdent]
printModules = return . M.keys . pscStateModules =<< get

