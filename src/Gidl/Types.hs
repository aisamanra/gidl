module Gidl.Types
  ( module Gidl.Types.AST
  , module Gidl.Types.Base
  , lookupTypeName
  , insertType
  , typeLeaves
  , sizeOf
  , basePrimType
  ) where

import Data.List (nub)
import Gidl.Types.AST
import Gidl.Types.Base

lookupTypeName :: TypeName -> TypeEnv -> Maybe Type
lookupTypeName tn te =
  case aux te of
    Just a -> Just a
    Nothing -> case aux baseTypeEnv of
      Just a -> Just a
      Nothing -> Nothing
  where
  aux (TypeEnv e) = lookup tn e

insertType :: TypeName -> Type -> TypeEnv -> TypeEnv
insertType tn t e@(TypeEnv te) = case lookupTypeName tn e of
  Nothing -> TypeEnv ((tn,t):te)
  Just _ -> error ("insertType invariant broken: type " ++ tn ++ " already exists")

typeLeaves :: Type -> [PrimType]
typeLeaves (StructType _ s) = nub (map snd s)
typeLeaves (PrimType (Newtype _ tn)) = [tn]
typeLeaves _ = []


sizeOf :: Type -> Integer
sizeOf (StructType _ s) = sum [ sizeOf (PrimType tr) | (_, tr) <- s ]
sizeOf (PrimType (Newtype _ tr)) = sizeOf (PrimType tr)
sizeOf (PrimType (EnumType _ bs _)) = bitsSize bs
sizeOf (PrimType (AtomType (AtomInt bs))) = bitsSize bs
sizeOf (PrimType (AtomType (AtomWord bs))) = bitsSize bs
sizeOf (PrimType (AtomType AtomFloat)) = 4
sizeOf (PrimType (AtomType AtomDouble)) = 8
sizeOf (PrimType VoidType) = 0

bitsSize :: Bits -> Integer
bitsSize Bits8  = 1
bitsSize Bits16 = 2
bitsSize Bits32 = 4
bitsSize Bits64 = 8

-- Reduce a newtype to the innermost concrete type
basePrimType :: PrimType -> PrimType
basePrimType (Newtype _ t) = basePrimType t
basePrimType a = a
