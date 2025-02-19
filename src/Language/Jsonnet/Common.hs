{-# LANGUAGE DefaultSignatures #-}
{-# LANGUAGE DeriveDataTypeable #-}
{-# LANGUAGE DeriveFunctor #-}
{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE DeriveTraversable #-}
{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE LambdaCase #-}
{-# LANGUAGE MultiParamTypeClasses #-}
{-# LANGUAGE TemplateHaskell #-}
{-# LANGUAGE TypeApplications #-}
{-# LANGUAGE UndecidableInstances #-}

-- |
-- Module                  : Language.Jsonnet.Common
-- Copyright               : (c) 2020-2021 Alexandre Moreno
-- SPDX-License-Identifier : BSD-3-Clause OR Apache-2.0
-- Maintainer              : Alexandre Moreno <alexmorenocano@gmail.com>
-- Stability               : experimental
-- Portability             : non-portable
module Language.Jsonnet.Common where

import Data.Binary (Binary)
import Data.Data (Data)
import Data.Functor.Classes
import Data.Functor.Classes.Generic
import Data.Scientific (Scientific)
import Data.String
import Data.Text (Text)
import Data.Typeable (Typeable)
import GHC.Generics (Generic, Generic1)
import Language.Jsonnet.Parser.SrcSpan
import Text.Show.Deriving
import Unbound.Generics.LocallyNameless
import Unbound.Generics.LocallyNameless.TH (makeClosedAlpha)

data Literal
  = Null
  | Bool Bool
  | String Text
  | Number Scientific
  deriving (Show, Eq, Ord, Generic, Typeable, Data)

makeClosedAlpha ''Literal

instance Binary Literal

instance Subst a Literal where
  subst _ _ = id
  substs _ = id

data Prim
  = UnyOp UnyOp
  | BinOp BinOp
  | Cond
  deriving (Show, Eq, Generic, Typeable, Data)

instance Alpha Prim

instance Binary Prim

data BinOp
  = Add
  | Sub
  | Mul
  | Div
  | Mod
  | Lt
  | Le
  | Gt
  | Ge
  | Eq
  | Ne
  | And
  | Or
  | Xor
  | ShiftL
  | ShiftR
  | LAnd
  | LOr
  | In
  | Lookup
  deriving (Show, Eq, Generic, Typeable, Data)

instance Alpha BinOp

instance Binary BinOp

data UnyOp
  = Compl
  | LNot
  | Plus
  | Minus
  | Err
  deriving (Show, Eq, Generic, Typeable, Data)

instance Alpha UnyOp

instance Binary UnyOp

data Strictness = Strict | Lazy
  deriving (Eq, Read, Show, Generic, Typeable, Data)

instance Alpha Strictness

instance Binary Strictness

data Arg a = Pos a | Named String a
  deriving
    ( Eq,
      Read,
      Show,
      Typeable,
      Data,
      Generic,
      Generic1,
      Functor,
      Foldable,
      Traversable
    )

deriveShow1 ''Arg

instance Alpha a => Alpha (Arg a)

instance Binary a => Binary (Arg a)

data Args a = Args
  { args :: [Arg a],
    strictness :: Strictness
  }
  deriving
    ( Eq,
      Read,
      Show,
      Typeable,
      Data,
      Generic,
      Functor,
      Foldable,
      Traversable
    )

deriveShow1 ''Args

instance Alpha a => Alpha (Args a)

instance Binary a => Binary (Args a)

data Assert a = Assert
  { cond :: a,
    msg :: Maybe a,
    expr :: a
  }
  deriving
    ( Eq,
      Read,
      Show,
      Typeable,
      Data,
      Generic,
      Functor,
      Foldable,
      Traversable
    )

instance Alpha a => Alpha (Assert a)

deriveShow1 ''Assert

data CompSpec a = CompSpec
  { var :: String,
    forspec :: a,
    ifspec :: Maybe a
  }
  deriving
    ( Eq,
      Read,
      Show,
      Typeable,
      Data,
      Generic,
      Functor,
      Foldable,
      Traversable
    )

deriveShow1 ''CompSpec

instance Alpha a => Alpha (CompSpec a)

data StackFrame a = StackFrame
  { name :: Name a,
    span :: SrcSpan
  }
  deriving (Eq, Show)

newtype Backtrace a = Backtrace [StackFrame a]
  deriving (Eq, Show)

data Visibility = Visible | Hidden | Forced
  deriving
    ( Eq,
      Read,
      Show,
      Generic,
      Typeable,
      Data
    )

instance Alpha Visibility

instance Binary Visibility

class HasVisibility a where
  visible :: a -> Bool
  forced :: a -> Bool
  hidden :: a -> Bool
