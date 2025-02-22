{-# LANGUAGE BangPatterns #-}
{-# LANGUAGE LambdaCase #-}
{-# LANGUAGE NamedFieldPuns #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE RecordWildCards #-}
{-# OPTIONS_GHC -Wno-orphans #-}

-- |
-- Module                  : Language.Jsonnet.Pretty
-- Copyright               : (c) 2020-2021 Alexandre Moreno
-- SPDX-License-Identifier : BSD-3-Clause OR Apache-2.0
-- Maintainer              : Alexandre Moreno <alexmorenocano@gmail.com>
-- Stability               : experimental
-- Portability             : non-portable
module Language.Jsonnet.Pretty where

import qualified Data.Aeson as JSON
import qualified Data.Aeson.Text as JSON (encodeToLazyText)
import qualified Data.HashMap.Lazy as H
import Data.List (sortOn)
import Data.Scientific (Scientific (..))
import Data.Text (Text)
import qualified Data.Text as T
import qualified Data.Text.Lazy as LT
import Data.Text.Lazy.Builder
import Data.Text.Lazy.Builder.Scientific (scientificBuilder)
import qualified Data.Vector as V
import GHC.IO.Exception (IOException (..))
import Language.Jsonnet.Common
import Language.Jsonnet.Error
import Language.Jsonnet.Parser.SrcSpan
import Text.Megaparsec.Error (errorBundlePretty)
import Text.Megaparsec.Pos
import Text.PrettyPrint.ANSI.Leijen hiding (encloseSep, (<$>))
import Unbound.Generics.LocallyNameless (Name, name2String)

instance Pretty (Name a) where
  pretty v = pretty (name2String v)

instance Pretty Text where
  pretty v = pretty (T.unpack v)

ppNumber s
  | e < 0 || e > 1024 =
    text $
      LT.unpack $
        toLazyText $
          scientificBuilder s
  | otherwise = integer (coefficient s * 10 ^ e)
  where
    e = base10Exponent s

ppJson :: Int -> JSON.Value -> Doc
ppJson i =
  \case
    JSON.Null -> text "null"
    JSON.Number n -> ppNumber n
    JSON.Bool True -> text "true"
    JSON.Bool False -> text "false"
    JSON.String s -> ppString s
    JSON.Array a -> ppArray a
    JSON.Object o -> ppObject o
  where
    encloseSep l r s ds = case ds of
      [] -> l <> r
      _ -> l <$$> indent i (vcat $ punctuate s ds) <$$> r
    ppObject o = encloseSep lbrace rbrace comma xs
      where
        prop (k, v) = ppString k <> colon <+> ppJson i v
        xs = map prop (sortOn fst $ H.toList o)
    ppArray a = encloseSep lbracket rbracket comma xs
      where
        xs = map (ppJson i) (V.toList a)
    ppString = text . LT.unpack . JSON.encodeToLazyText

instance Pretty JSON.Value where
  pretty = ppJson 4

instance Pretty SrcSpan where
  pretty SrcSpan {spanBegin, spanEnd} =
    text (sourceName spanBegin)
      <> colon
      <> lc spanBegin spanEnd
    where
      lc (SourcePos _ lb cb) (SourcePos _ le ce)
        | lb == le =
          int (unPos lb) <> colon
            <> int (unPos cb)
            <> dash
            <> int (unPos ce)
        | otherwise =
          int (unPos lb) <> colon <> int (unPos cb) <> dash
            <> int (unPos le)
            <> colon
            <> int (unPos ce)
      dash = char '-'

instance Pretty ParserError where
  pretty (ParseError e) = pretty (errorBundlePretty e)
  pretty (ImportError (IOError _ _ _ desc _ f) sp) =
    text "Parse error:"
      <+> pretty f
      <+> parens (text desc)
      <$$> indent 4 (pretty sp)

instance Pretty CheckError where
  pretty =
    \case
      DuplicateParam e ->
        text "duplicate parameter"
          <+> squotes (text e)
      DuplicateBinding e ->
        text "duplicate local var"
          <+> squotes (text e)
      PosAfterNamedParam ->
        text "positional after named argument"

instance Pretty EvalError where
  pretty =
    \case
      TypeMismatch {..} ->
        text "type mismatch:"
          <+> text "expected"
          <+> text (T.unpack expected)
          <+> text "but got"
          <+> text (T.unpack actual)
      InvalidKey k ->
        text "invalid key:"
          <+> k
      InvalidIndex k ->
        text "invalid index:"
          <+> k
      NoSuchKey k ->
        text "no such key:"
          <+> k
      IndexOutOfBounds i ->
        text "index out of bounds:"
          <+> ppNumber i
      DivByZero ->
        text "divide by zero exception"
      VarNotFound v ->
        text "variable"
          <+> squotes (text $ show v)
          <+> text "is not defined"
      AssertionFailed e ->
        text "assertion failed:" <+> e
      StdError e -> e
      RuntimeError e -> e
      ParamNotBound s ->
        text "parameter not bound:"
          <+> text (show s)
      BadParam s ->
        text "function has no parameter"
          <+> squotes s
      ManifestError e ->
        text "manifest error:"
          <+> e
      TooManyArgs n ->
        text "too many args, function has"
          <+> int n
          <+> "parameter(s)"

instance Pretty (StackFrame a) where
  pretty StackFrame {..} =
    pretty span <+> pretty (f $ name2String name)
    where
      f "top-level" = mempty
      f x = text "function" <+> (angles $ pretty x)

instance Pretty (Backtrace a) where
  pretty (Backtrace xs) = vcat $ pretty <$> xs

instance Pretty Error where
  pretty =
    \case
      EvalError e bt ->
        text "Runtime error:"
          <+> pretty e
          <$$> indent 2 (pretty bt)
      ParserError e -> pretty e
      CheckError e sp ->
        text "Static error:"
          <+> pretty e
          <$$> indent 2 (pretty sp)
