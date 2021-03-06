
module Gidl.Backend.Haskell.Interface where


import Data.Monoid
import Data.List (intercalate, nub)
import Data.Char (toUpper)

import Gidl.Types
import Gidl.Interface
import Gidl.Schema
import Gidl.Backend.Haskell.Types
import Ivory.Artifact
import Text.PrettyPrint.Mainland

interfaceModule :: Bool -> [String] -> Interface -> Artifact
interfaceModule useAeson modulepath i =
  artifactPath (intercalate "/" modulepath) $
  artifactText ((ifModuleName i) ++ ".hs") $
  prettyLazyText 80 $
  stack $
    [ text "{-# LANGUAGE DeriveDataTypeable #-}"
    , text "{-# LANGUAGE DeriveGeneric #-}"
    , empty
    , text "module"
      <+> im (ifModuleName i)
      <+> text "where"
    , empty
    , stack $ typeimports ++ extraimports
    , empty
    , schemaDoc useAeson (ifModuleName i) (producerSchema i)
    , empty
    , schemaDoc useAeson (ifModuleName i) (consumerSchema i)
    , empty
    ]
  where
  im mname = mconcat $ punctuate dot
                     $ map text (modulepath ++ [mname])
  tm mname = mconcat $ punctuate dot
                     $ map text (typepath modulepath ++ ["Types", mname])
    where typepath = reverse . drop 1 . reverse

  typeimports = map (importDecl tm)
              $ nub
              $ map importType
              $ interfaceTypes i
  extraimports = [ text "import Data.Serialize"
                 , text "import Data.Typeable"
                 , text "import Data.Data"
                 , text "import GHC.Generics (Generic)"
                 , text "import qualified Test.QuickCheck as Q"
                 ] ++
                 [ text "import Data.Aeson (ToJSON,FromJSON)" | useAeson ]

schemaDoc :: Bool -> String -> Schema -> Doc
schemaDoc _ interfaceName (Schema schemaName [])     =
    text "-- Cannot define" <+> text schemaName  <+> text "schema for"
        <+> text interfaceName <+> text "interface: schema is empty"
schemaDoc useAeson interfaceName (Schema schemaName schema) = stack $
    [ text "-- Define" <+> text schemaName  <+> text "schema for"
        <+> text interfaceName <+> text "interface"
    , text "data" <+> text typeName
    , indent 2 $ encloseStack equals deriv (text "|")
        [ text (constructorName n) <+> text (typeHaskellType t)
        | (_, (Message n t)) <- schema
        ]
    , empty
    , text ("put" ++ typeName) <+> colon <> colon <+> text "Putter" <+> text typeName
    , stack
        [ text ("put" ++ typeName)
            <+> parens (text (constructorName n) <+> text "m")
            <+> equals
            <+> primTypePutter (sizedPrim Bits32) <+> ppr h <+> text ">>"
            <+> text "put" <+> text "m"
        | (h, Message n _) <- schema ]
    , empty
    , text ("get" ++ typeName) <+> colon <> colon <+> text "Get" <+> text typeName
    , text ("get" ++ typeName) <+> equals <+> text "do"
    , indent 2 $ stack
        [ text "a <-" <+> primTypeGetter (sizedPrim Bits32)
        , text "case a of"
        , indent 2 $ stack $
            [ ppr h <+> text "-> do" </> (indent 2 (stack
                [ text "m <- get"
                , text "return" <+> parens (text (constructorName n) <+> text "m")
                ]))
            | (h,Message n _) <- schema
            ] ++
            [ text "_ -> fail"
              <+> dquotes (text "encountered unknown tag in get" <> text typeName)
            ]
        ]
    , empty
    , serializeInstance typeName
    , empty
    , text ("arbitrary" ++ typeName) <+> colon <> colon <+> text "Q.Gen" <+> text typeName
    , text ("arbitrary" ++ typeName) <+> equals
    , indent 2 $ text "Q.oneof" <+> encloseStack lbracket rbracket comma
        [ text "do" </> (indent 4 (stack
           [ text "a <- Q.arbitrary"
           , text "return" <+> parens (text (constructorName n) <+> text "a")
           ]))
        | (_, Message n _) <- schema
        ]
    , empty
    , arbitraryInstance typeName
    , empty
    ] ++
    [ toJSONInstance   typeName | useAeson ] ++
    [ fromJSONInstance typeName | useAeson ]
  where
  constructorName n = userTypeModuleName n ++ schemaName
  deriv = text "deriving (Eq, Show, Data, Typeable, Generic)"
  typeName = interfaceName ++ schemaName

ifModuleName :: Interface -> String
ifModuleName (Interface iname _ _) = aux iname
  where
  aux :: String -> String
  aux = first_cap . u_to_camel
  first_cap (s:ss) = (toUpper s) : ss
  first_cap []     = []
  u_to_camel ('_':'i':[]) = []
  u_to_camel ('_':[]) = []
  u_to_camel ('_':a:as) = (toUpper a) : u_to_camel as
  u_to_camel (a:as) = a : u_to_camel as
  u_to_camel [] = []


