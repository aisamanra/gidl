
module Gidl.Backend.Haskell.Test where


import Data.Monoid
import Gidl.Interface
import Gidl.Schema
import Gidl.Backend.Haskell.Interface
import Ivory.Artifact
import Text.PrettyPrint.Mainland

serializeTestModule :: [String] -> [Interface] -> Artifact
serializeTestModule modulepath is =
  artifactText "SerializeTest.hs" $
  prettyLazyText 80 $
  stack
    [ text "{-# LANGUAGE ScopedTypeVariables #-}"
    , empty
    , text "module Main where"
    , empty
    , text "import Data.Serialize"
    , text "import System.Exit (exitFailure, exitSuccess)"
    , text "import qualified Test.QuickCheck as Q"
    , empty
    , stack [ text "import" <+> im (ifModuleName i) | i <- is ]
    , empty
    , text "main :: IO ()"
    , text "main" <+> equals <+> text "do" <+> align (stack
        ([ testSchema i (producerSchema i) </> testSchema i (consumerSchema i)
         | i <- is ] ++
         [ text "exitSuccess" ]))
    , empty
    , props
    ]
  where
  im mname = mconcat $ punctuate dot
                     $ map text (modulepath ++ ["Interface", mname])

testSchema :: Interface -> Schema -> Doc
testSchema i (Schema sn []) =
  text "-- no tests for empty schema" <+> text (ifModuleName i ++ sn)
testSchema i (Schema sn _) = stack
  [ text "runQC" <+> parens
      (text "serializeRoundtrip ::" <+> text sname <+> text "-> Bool")
  , text "runQC" <+> parens
      (text "serializeManyRoundtrip ::" <+> brackets (text sname) <+> text "-> Bool")
  ]
  where sname = ifModuleName i ++ sn

props :: Doc
props = stack
  [ text "serializeRoundtrip :: (Serialize a, Eq a) => a -> Bool"
  , text "serializeRoundtrip v = case runGet get (runPut (put v)) of"
  , indent 2 $ text "Left e -> False"
  , indent 2 $ text "Right v' -> v == v'"
  , empty
  , text "serializeManyRoundtrip :: (Serialize a, Eq a) => [a] -> Bool"
  , text "serializeManyRoundtrip vs ="
  , indent 2 $ text "case runGet (mapM (const get) vs) (runPut (mapM_ put vs)) of"
  , indent 4 $ text "Left e -> False"
  , indent 4 $ text "Right vs' -> vs == vs'"
  , empty

  , text "runQC :: Q.Testable p => p -> IO ()"
  , text "runQC prop = do"
  , indent 2 $ text "r <- Q.quickCheckWithResult Q.stdArgs prop"
  , indent 2 $ text "case r of"
  , indent 4 $ text "Q.Success {} -> return ()"
  , indent 4 $ text "_ -> exitFailure"
 ]
