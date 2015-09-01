{-# LANGUAGE OverloadedStrings #-}

module Purescript.Ide
  (
    readExternFile,
    findTypeForName,
    findCompletion,
    loadModule,
    printModules,
    unsafeModuleFromDecls,
    ExternParse,
    ExternDecl,
    PscIde,
    PscState(..)
  ) where

import           Control.Monad.State.Lazy (StateT (..), evalStateT, get, modify)
import           Control.Monad.Trans
import           Data.Char                (digitToInt)
import           Data.Foldable
import           Data.Maybe               (mapMaybe)
import           Data.Monoid
import           Data.Text                (Text ())
import qualified Data.Text                as T
import qualified Data.Text.IO             as T
import           Text.Parsec
import           Text.Parsec.Text

type ExternParse = Either ParseError [ExternDecl]

data Module = Module
    { moduleName  :: Text
    , moduleDecls :: [ExternDecl]
    } deriving (Show,Eq)


data PscState = PscState
    { pscStateModules :: [Module]
    } deriving (Show,Eq)


type PscIde = StateT PscState IO

data Fixity = Infix | Infixl | Infixr deriving(Show, Eq)

data ExternDecl
    = FunctionDecl { functionName :: Text
                   , functionType :: Text}
    | FixityDeclaration Fixity
                        Int
                        Text
    | Dependency { dependencyModule :: Text
                 , dependencyNames  :: Text}
    | ModuleDecl Text
                 [Text]
    | DataDecl Text
               Text
    deriving (Show,Eq)

getAllDecls :: PscIde [ExternDecl]
getAllDecls = return . concat . fmap moduleDecls =<< fmap pscStateModules get

-- | Given a set of ExternDeclarations finds the type for a given function
--   name and returns Nothing if the functionName can not be matched
findTypeForName :: Text -> PscIde (Maybe Text)
findTypeForName search = do
  decls <- getAllDecls
  return $ getFirst $ fold (map (First . go) decls)
  where
    go :: ExternDecl -> Maybe Text
    go decl =
        case decl of
            FunctionDecl n t ->
                if search == n
                    then Just t
                    else Nothing
            _ -> Nothing

-- | Given a set of ExternDeclarations finds all the possible completions.
--   Doesn't do any fancy flex matching. Just prefix search
findCompletion :: Text -> PscIde [Text]
findCompletion stub = fmap (mapMaybe go) getAllDecls
  where
    matches name =
        if stub `T.isPrefixOf` name
            then Just name
            else Nothing
    go :: ExternDecl -> Maybe Text
    go (FunctionDecl name _) = matches name
    go (DataDecl name _) = matches name
    go _ = Nothing

loadModule :: FilePath -> PscIde ()
loadModule fp = do
    parseResult <- liftIO $ readExternFile fp
    case parseResult of
        Right decls ->
            modify
                (\x ->
                      x
                      { pscStateModules = unsafeModuleFromDecls decls :
                        pscStateModules x
                      })
        Left _ -> liftIO $ putStrLn "The module could not be parsed"

unsafeModuleFromDecls :: [ExternDecl] -> Module
unsafeModuleFromDecls (ModuleDecl name _ : decls) = Module name decls

printModules :: PscIde ()
printModules = liftIO . print . fmap moduleName . pscStateModules =<< get

-- | Parses an extern file into the ExternDecl format.
readExternFile :: FilePath -> IO ExternParse
readExternFile fp = readExtern <$> (T.lines <$> T.readFile fp)

readExtern:: [Text] -> ExternParse
readExtern strs = mapM (parse parseExternDecl "") clean
  where
    clean = removeComments strs

removeComments :: [Text] -> [Text]
removeComments = filter (not . T.isPrefixOf "--")

parseExternDecl :: Parser ExternDecl
parseExternDecl =
    try parseDependency <|> try parseFixityDecl <|> try parseFunctionDecl <|>
    try parseDataDecl <|> try parseModuleDecl <|>
    return (ModuleDecl "" [])

parseDependency :: Parser ExternDecl
parseDependency = do
    string "import "
    module' <- many1 (noneOf " ")
    spaces
    names <- many1 anyChar
    eof
    return $ Dependency (T.pack module') (T.pack names)

parseFixityDecl :: Parser ExternDecl
parseFixityDecl = do
    fixity <- parseFixity
    spaces
    priority <- digitToInt <$> digit
    spaces
    symbol <- many1 anyChar
    eof
    return (FixityDeclaration fixity priority (T.pack symbol))

parseFixity :: Parser Fixity
parseFixity =
    (try (string "infixr") >> return Infixr) <|>
    (try (string "infixl") >> return Infixl) <|>
    (string "infix" >> return Infix)

parseFunctionDecl :: Parser ExternDecl
parseFunctionDecl = do
    string "foreign import"
    spaces
    name <- many1 (noneOf " ")
    spaces
    string "::"
    spaces
    type' <- many1 anyChar
    eof
    return (FunctionDecl (T.pack name) (T.pack type'))

parseDataDecl :: Parser ExternDecl
parseDataDecl = do
  string "foreign import data"
  spaces
  name <- many1 (noneOf " ")
  spaces
  string "::"
  spaces
  kind <- many1 anyChar
  eof
  return $ DataDecl (T.pack name) (T.pack kind)

parseModuleDecl :: Parser ExternDecl
parseModuleDecl = do
  string "module"
  spaces
  name <- many1 (noneOf " ")
  return (ModuleDecl (T.pack name) [])

-- Utilities for testing in ghci
findTypeForName' :: Text -> IO (Maybe Text)
findTypeForName' search = do
    exts <- externsFile
    case exts of
        Left x -> print x >> return Nothing
        Right decls -> evalStateT (findTypeForName search) (PscState [])

externsFile :: IO (Either ParseError [ExternDecl])
externsFile = readExternFile "/home/creek/sandbox/psc-ide/externs.purs"
