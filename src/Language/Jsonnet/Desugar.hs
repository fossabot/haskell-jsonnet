{-# LANGUAGE ConstraintKinds #-}
{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE LambdaCase #-}
{-# LANGUAGE NamedFieldPuns #-}
{-# LANGUAGE OverloadedLists #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE RecordWildCards #-}
{-# LANGUAGE TypeSynonymInstances #-}

module Language.Jsonnet.Desugar (desugar) where

import Data.Fix as F
import Data.List.NonEmpty (NonEmpty (..), fromList, toList)
import qualified Data.List.NonEmpty as NE
import Data.Maybe (fromMaybe)
import Data.Text (Text)
import Language.Jsonnet.Annotate
import Language.Jsonnet.Common
import Language.Jsonnet.Core
import Language.Jsonnet.Parser.SrcSpan
import Language.Jsonnet.Syntax
import Unbound.Generics.LocallyNameless

desugar :: HasSrcSpan a => Ann ExprF a -> Core
desugar =
  foldFix alg
    . zipWithOutermost
    . annMap srcSpan

-- annotate nodes with a boolean denoting outermost objects
zipWithOutermost :: Ann ExprF a -> Ann ExprF (a, Bool)
zipWithOutermost = annZip . inherit go False
  where
    go (Fix (AnnF (EObj {}) _)) False = (True, True)
    go (Fix (AnnF (EObj {}) _)) True = (False, True)
    go _ x = (False, x)

alg :: AnnF ExprF (SrcSpan, Bool) Core -> Core
alg (AnnF f (a, b)) = go b $ CLoc a <$> f
  where
    go outermost = \case
      ELit l -> CLit l
      EIdent i -> CVar (s2n i)
      EFun ps e -> mkFun ps e
      EApply e es -> CApp e es
      ELocal bnds e -> mkLet bnds e
      EBinOp op e1 e2 -> CBinOp op e1 e2
      EUnyOp op e -> CUnyOp op e
      EIfElse c t e -> CIfElse c t e
      EIf c t -> CIfElse c t (CLit Null)
      EArr e -> CArr e
      EObj {..} ->
        mkLet (("self", CObj fields) :| bnds) self
        where
          bnds =
            if outermost
              then (("$", self) : locals)
              else locals
          self = CVar (s2n "self")
      ELookup e1 e2 -> CLookup e1 e2
      EIndex e1 e2 -> CLookup e1 e2
      EErr e -> CErr e
      EAssert e -> mkAssert e
      ESlice {..} ->
        stdFunc
          "slice"
          ( Positional
              [ maybeNull start,
                maybeNull end,
                maybeNull step,
                expr
              ]
          )
        where
          maybeNull = fromMaybe (CLit Null)
      EArrComp {expr, comp} -> mkArrComp expr comp
      EObjComp {field, comp, locals} -> mkObjComp field comp

mkAssert :: Assert Core -> Core
mkAssert (Assert c m e) =
  CIfElse
    c
    e
    ( CErr $
        fromMaybe
          (CLit $ String "Assertion failed")
          m
    )

mkArrComp :: Core -> NonEmpty (CompSpec Core) -> Core
mkArrComp expr comp = foldr f (CArr [expr]) comp
  where
    f CompSpec {..} e =
      CComp (ArrC (bind (s2n var) (e, ifspec))) forspec

mkObjComp :: Field Core -> NonEmpty (CompSpec Core) -> Core
mkObjComp Field {..} comp =
  CComp (ObjC (bind (s2n "arr") (field', Nothing))) arrComp
  where
    field' = Field (mkLet bnds key) (mkLet bnds value) hidden
    bnds = NE.zip (fmap var comp) xs
    xs = CLookup (CVar $ s2n "arr") . CLit . Number . fromIntegral <$> [0 ..]
    arrComp = mkArrComp (CArr $ NE.toList $ CVar . s2n . var <$> comp) comp

stdFunc :: Text -> Args Core -> Core
stdFunc f =
  CApp
    ( CLookup
        (CVar "std")
        (CLit $ String f)
    )

mkFun ps e =
  CFun $
    bind
      ( rec $
          fmap
            ( \(n, a) ->
                (s2n n, Embed a)
            )
            ps
      )
      e

mkLet bnds e =
  CLet $
    bind
      ( rec $
          toList
            ( fmap
                ( \(n, a) ->
                    (s2n n, Embed a)
                )
                bnds
            )
      )
      e
