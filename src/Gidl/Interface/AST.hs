
module Gidl.Interface.AST where

import Gidl.Types.AST

data InterfaceEnv
  = InterfaceEnv [(InterfaceName, Interface)]
  deriving (Eq, Show)

emptyInterfaceEnv :: InterfaceEnv
emptyInterfaceEnv = InterfaceEnv []

type InterfaceName = String
type MethodName = String

data Interface
  = Interface [InterfaceName] [(MethodName, Method)]
  deriving (Eq, Show)

data Method
  = AttrMethod Perm TypeName
  | StreamMethod Integer TypeName
  deriving (Eq, Show)

data Perm
  = Read
  | Write
  | ReadWrite
  deriving (Eq, Show)


