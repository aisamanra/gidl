
module Gidl.Parse where

import Data.Functor.Identity
import Control.Monad
import Text.Parsec.Prim
import Text.Parsec.Char
import Text.Parsec.Token
import Text.Parsec.Combinator
import Text.Parsec.Language
import Text.Parsec.Error

import Gidl.Types
import Gidl.Interface

type Parser u a = ParsecT String u Identity a
type ParseEnv = (TypeEnv, InterfaceEnv)

emptyParseEnv :: ParseEnv
emptyParseEnv = (emptyTypeEnv, emptyInterfaceEnv)

getTypeEnv :: Parser ParseEnv TypeEnv
getTypeEnv = fmap fst getState

getInterfaceEnv :: Parser ParseEnv InterfaceEnv
getInterfaceEnv = fmap snd getState

setTypeEnv :: TypeEnv -> Parser ParseEnv ()
setTypeEnv te = do
  (_, ie) <- getState
  setState (te, ie)

setInterfaceEnv :: InterfaceEnv -> Parser ParseEnv ()
setInterfaceEnv ie = do
  (te, _) <- getState
  setState (te, ie)

---

lexer :: GenTokenParser String u Identity
lexer = makeTokenParser haskellDef

tWhiteSpace :: Parser u ()
tWhiteSpace = whiteSpace lexer

tInteger :: Parser u Integer
tInteger = (integer lexer) <?> "integer"

tNatural :: Parser u Integer
tNatural = do
  i <- tInteger
  case i < 0 of
    True -> fail "expected positive integer"
    False -> return i

tFloat :: Parser u Double
tFloat = (float lexer) <?> "floating point number"

tString :: Parser u String
tString = (stringLiteral lexer) <?> "string"

tSymbol :: Parser u String
tSymbol = (many1 $ noneOf "()\" \t\n\r") <?> "symbol"

tIdentifier :: String -> Parser u ()
tIdentifier i = do
  s <- tSymbol
  case s == i of
    True -> return ()
    False -> fail ("expected identifier " ++ i)

tList :: Parser u a -> Parser u a
tList c = do
  tWhiteSpace
  void $ char '('
  tWhiteSpace
  r <- c
  tWhiteSpace
  void $ char ')'
  return r
  <?> "list"


tPair :: Parser u a
      -> Parser u b
      -> Parser u (a, b)
tPair a b = tList $ do
  ra <- a
  tWhiteSpace
  rb <- b
  return (ra, rb)

tKnownTypeName :: Parser ParseEnv TypeName
tKnownTypeName = do
  s <- tSymbol
  te <- getTypeEnv
  case lookupTypeName s te of
    Just _ -> return s
    Nothing -> fail ("expected a known type name, got " ++ s)

tStructRow :: Parser ParseEnv (Identifier, TypeName)
tStructRow = tPair tSymbol tKnownTypeName
  <?> "struct row"

tStructBody :: Parser ParseEnv [(Identifier, TypeName)]
tStructBody = tList (many1 (tWhiteSpace >> tStructRow))
  <?> "struct body"

tStructDecl :: Parser ParseEnv (TypeName, Type)
tStructDecl = tList $ do
  tIdentifier "def-struct"
  tWhiteSpace
  n <- tSymbol
  b <- tStructBody
  return (n, StructType (Struct b))

defineType :: (TypeName, Type) -> Parser ParseEnv ()
defineType (tn, t) = do
  te <- getTypeEnv
  case lookupTypeName tn te of
    Just _ -> fail ("type named '" ++ tn ++ "' already exists")
    Nothing -> setTypeEnv (insertType tn t te)

defineInterface :: (InterfaceName, Interface) -> Parser ParseEnv ()
defineInterface (ina, i) = do
  ie <- getInterfaceEnv
  case lookupInterface ina ie of
    Just _ -> fail ("interface named '" ++ ina ++ "' already exists")
    Nothing -> setInterfaceEnv (insertInterface ina i ie)

tNewtypeDecl :: Parser ParseEnv (TypeName, Type)
tNewtypeDecl = tList $ do
  tIdentifier "def-newtype"
  tWhiteSpace
  n <- tSymbol
  tWhiteSpace
  c <- tKnownTypeName
  return (n, NewtypeType (Newtype c))

tEnumDecl :: Parser ParseEnv (TypeName, Type)
tEnumDecl = tList $ do
  tIdentifier "def-enum"
  tWhiteSpace
  n <- tSymbol
  -- XXX specify bit width, optionally
  vs <- tList $ many1 $ tPair tSymbol tNatural
  -- XXX check that symbols are unique, numbers are unique, numbers are
  -- ascending
  -- XXX make it possible to implicitly assign numbers
  return (n, EnumType (EnumT Bits32 vs))

tPermission :: Parser a Perm
tPermission = do
  s <- tSymbol
  case s of
    "read"      -> return Read
    "r"         -> return Read
    "write"     -> return Write
    "w"         -> return Write
    "readwrite" -> return ReadWrite
    "rw"        -> return ReadWrite
    _           -> fail "expected permission"

tInterfaceMethod :: Parser ParseEnv (MethodName, Method)
tInterfaceMethod = tList $ do
  n <- tSymbol
  m <- choice [ try tAttr, try tStream ]
  return (n, m)
  where
  tAttr = tList $ do
    tIdentifier "attr"
    tWhiteSpace
    p <- tPermission
    tWhiteSpace
    tn <- tKnownTypeName
    return (AttrMethod p tn)
  tStream = tList $ do
    tIdentifier "stream"
    tWhiteSpace
    r <- tInteger
    tWhiteSpace
    tn <- tKnownTypeName
    return (StreamMethod r tn)

tKnownInterfaceName :: Parser ParseEnv InterfaceName
tKnownInterfaceName  = do
  n <- tSymbol
  ie <- getInterfaceEnv
  case lookupInterface n ie of
    Just _ -> return n
    Nothing -> fail ("expected a known interface name, got " ++ n)

tInterfaceDecl :: Parser ParseEnv (InterfaceName, Interface)
tInterfaceDecl = tList $ do
  tIdentifier "def-interface"
  tWhiteSpace
  n <- tSymbol
  tWhiteSpace
  ms <- tList (many1 tInterfaceMethod)
  -- XXX require the names to be unique
  tWhiteSpace
  ps <- optionMaybe (tList (many1 tKnownInterfaceName))
  -- XXX require the ms not shadow names in inherited interfaces
  case ps of
    Just p -> return (n, Interface  p ms)
    Nothing -> return (n, Interface [] ms)

tDecls :: Parser ParseEnv ParseEnv
tDecls = do
  _ <- many (choice [ try tStructDecl    >>= defineType
                    , try tNewtypeDecl   >>= defineType
                    , try tEnumDecl      >>= defineType
                    , try tInterfaceDecl >>= defineInterface
                    ])
  tWhiteSpace >> eof
  getState

parseDecls :: String -> Either ParseError ParseEnv
parseDecls s = runP tDecls emptyParseEnv "" s

