{-# LANGUAGE LambdaCase #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE TypeApplications #-}

module Language.Jsonnet.Std
  ( std,
    toString,
    equals,
    objectHasAll,
    flattenArrays,
  )
where

import Control.Applicative
import Control.Monad.Except
import qualified Data.ByteString as B
import Data.ByteString (ByteString)
import Data.Foldable
import Data.HashMap.Lazy (HashMap)
import qualified Data.HashMap.Lazy as H
import Data.List
import Data.Maybe (fromMaybe)
import Data.Text (Text)
import qualified Data.Text as T
import qualified Data.Text.Encoding as T
import Data.Vector (Vector)
import qualified Data.Vector as V
import Data.Word
import qualified Data.YAML.Aeson as YAML
import Language.Jsonnet.Error
import Language.Jsonnet.Eval.Monad
import Language.Jsonnet.Manifest (manifest)
import Language.Jsonnet.Pretty (ppJson)
import Language.Jsonnet.Value
import Numeric
import Text.PrettyPrint.ANSI.Leijen ((<+>), pretty, text)
import Text.Printf

-- The Jsonnet standard library, `std`, with each builtin function implemented
-- in Haskell code (incomplete)

std :: Value
std = VObj $ (Thunk . pure) <$> H.fromList xs
  where
    xs :: [(Key, Value)]
    xs =
      map
        (\(k, v) -> (Hidden k, v))
        [ ("assertEqual", inj assertEqual),
          ("type", inj valueType),
          ("isString", inj (isType "string")),
          ("isBoolean", inj (isType "boolean")),
          ("isNumber", inj (isType "number")),
          ("isObject", inj (isType "object")),
          ("isArray", inj (isType "array")),
          ("isFunction", inj (isType "function")),
          ("equals", inj equals),
          ("objectFields", inj objectFields),
          ("length", inj length'),
          ("abs", inj (abs @Double)),
          ("sign", inj (signum @Double)), -- incl. 0.0, (-0.0), and NaN
          ("max", inj (max @Double)),
          ("min", inj (min @Double)),
          ("pow", inj ((^^) @Double @Int)),
          ("exp", inj (exp @Double)),
          ("log", inj (log @Double)),
          ("exponent", inj (exponent @Double)),
          ("mantissa", inj (significand @Double)),
          ("floor", inj (floor @Double @Integer)),
          ("ceil", inj (ceiling @Double @Integer)),
          ("sqrt", inj (sqrt @Double)),
          ("sin", inj (sin @Double)),
          ("cos", inj (cos @Double)),
          ("tan", inj (tan @Double)),
          ("asin", inj (asin @Double)),
          ("acos", inj (acos @Double)),
          ("atan", inj (atan @Double)),
          ("mod", inj (mod @Integer)),
          ("toString", inj toString),
          ("codepoint", inj (fromEnum . T.head)),
          ("char", inj (T.singleton . toEnum)),
          ("substr", inj substr),
          ("startsWith", inj (flip T.isPrefixOf)),
          ("endsWith", inj (flip T.isSuffixOf)),
          ("stripChars", inj stripChars),
          ("lstripChars", inj lstripChars),
          ("rstripChars", inj rstripChars),
          ("split", inj T.splitOn),
          ("strReplace", inj strReplace),
          ("asciiLower", inj T.toLower),
          ("asciiUpper", inj T.toUpper),
          ("stringChars", inj (T.chunksOf 1)),
          ("parseInt", inj (read . T.unpack :: Text -> Int)),
          ("parseOctal", inj parseOctal),
          ("parseHex", inj parseHex),
          ("encodeUTF8", inj (B.unpack . T.encodeUtf8 :: Text -> [Word8])),
          ("decodeUTF8", inj (T.decodeUtf8 . B.pack :: [Word8] -> Text)),
          ("makeArray", inj makeArray),
          ("member", inj member),
          ("count", inj count),
          ("find", inj find'),
          ("map", inj (mapM @Vector @Eval @Value @Value)),
          ("mapWithIndex", inj mapWithIndex),
          ("filterMap", inj (filterMapM @Value @Value)),
          ("flatMap", inj (concatForM @Value @Value)), -- first function, then array
          ("filter", inj (filterM @Eval @Value)),
          ("foldl", inj (foldlM' @Vector @Value @Value)),
          ("foldr", inj (foldrM @Vector @Eval @Value @Value)),
          ("range", inj (enumFromTo @Int)),
          ("lines", inj T.unlines), -- yes, really
          ("repeat", inj repeat'),
          ("join", inj T.intercalate),
          ("reverse", inj (reverse @Value)),
          ("manifestYamlDoc", inj manifestYamlDoc),
          ("manifestJsonEx", inj manifestJsonEx),
          ("objectHasEx", inj objectHasEx),
          ("objectHas", inj objectHas),
          ("objectHasAll", inj objectHasAll),
          ("slice", inj slice),
          ("flattenArrays", inj flattenArrays)
        ]

toString :: Value -> Eval Text
toString (VStr s) = pure s
toString v = T.pack . show . pretty <$> manifest v

equals :: Value -> Value -> Eval Bool
equals a b = (==) <$> manifest a <*> manifest b

objectFields :: HashMap Key Value -> [Text]
objectFields o = [k | Visible k <- H.keys o]

assertEqual :: Value -> Value -> Eval Bool
assertEqual a b = do
  a' <- manifest a
  b' <- manifest b
  if a' /= b'
    then
      throwError
        ( AssertionFailed $
            pretty a'
              <+> text "!="
              <+> pretty b'
        )
    else (pure True)

isType :: Text -> Value -> Bool
isType ty = (==) ty . valueType

length' :: Value -> Eval Int
length' = \case
  VStr s -> pure $ T.length s
  VArr a -> pure $ length a
  VObj o -> pure $ length (H.keys o)
  v ->
    throwError
      ( StdError
          $ text
          $ T.unpack
          $ "length operates on strings, objects, and arrays, got "
            <> valueType v
      )

substr :: Text -> Int -> Int -> Text
substr str from len = T.take len $ T.drop from str

strReplace :: Text -> Text -> Text -> Text
strReplace str from to = T.replace from to str

containsChar :: Text -> Char -> Bool
containsChar s c = T.any (c ==) s

lstripChars :: Text -> Text -> Text
lstripChars s cs = T.dropWhile (containsChar cs) s

rstripChars :: Text -> Text -> Text
rstripChars s cs = T.dropWhileEnd (containsChar cs) s

stripChars :: Text -> Text -> Text
stripChars s cs = T.dropAround (containsChar cs) s

parseOctal :: Text -> Eval Integer
parseOctal num = case readOct (T.unpack num) of
  [(n, "")] -> pure n
  _ ->
    throwError
      ( StdError
          $ text
          $ T.unpack
          $ num
            <> " is not a base 8 integer"
      )

parseHex :: Text -> Eval Integer
parseHex num = case readHex (T.unpack num) of
  [(n, "")] -> pure n
  _ ->
    throwError
      ( StdError
          $ text
          $ T.unpack
          $ num
            <> " is not a base 16 integer"
      )

count :: [Value] -> Value -> Eval Int
count xs y = do
  xs' <- mapM manifest xs
  y' <- manifest y
  return $ length $ intersect xs' [y']

member :: [Value] -> Value -> Eval Bool
member xs y = (/= 0) <$> count xs y

find' :: Value -> [Value] -> Eval [Int]
find' y xs = liftA2 elemIndices (manifest y) (traverse manifest xs)

mapWithIndex :: (Value -> Int -> Eval Value) -> [Value] -> Eval [Value]
mapWithIndex f xs = zipWithM f xs [0 ..]

filterMapM :: (a -> Eval Bool) -> (a -> Eval b) -> [a] -> Eval [b]
filterMapM f g as = traverse g =<< filterM f as

makeArray :: Int -> (Int -> Eval Value) -> Eval [Value]
makeArray n f = traverse f [0 .. n - 1]

repeat' :: [Value] -> Int -> [Value]
repeat' xs times = join $ replicate times xs

concatForM :: (a -> Eval [b]) -> [a] -> Eval [b]
concatForM f xs = fmap concat (mapM f xs)

foldlM' :: Foldable t => (b -> a -> Eval b) -> t a -> b -> Eval b
foldlM' = flip . foldlM

manifestYamlDoc :: Value -> Eval ByteString
manifestYamlDoc = fmap YAML.encode1Strict . manifest

manifestJsonEx :: Value -> Text -> Eval String
manifestJsonEx x indent = show . ppJson sp <$> manifest x
  where
    sp = T.length indent

slice ::
  Maybe Int ->
  Maybe Int ->
  Maybe Int ->
  Value ->
  Eval Value
slice i n s v@(VArr _) = inj' (sliceV @Value i n s) v
slice i n s v@(VStr _) = inj' (sliceS i n s) v
slice _ _ _ v = throwTypeMismatch "array/string" v

sliceS ::
  Maybe Int ->
  Maybe Int ->
  Maybe Int ->
  Text ->
  Text
sliceS i n s t = go (fromMaybe 0 i) (fromMaybe len n) s t
  where
    go i n Nothing = T.drop i . T.take n
    go i n (Just s) =
      T.pack . snd . unzip
        . filter (\(x, _) -> x `mod` s == 0)
        . zip [0 ..]
        . T.unpack
        . T.drop i
        . T.take n
    len = T.length t

sliceV ::
  Maybe Int ->
  Maybe Int ->
  Maybe Int ->
  Vector a ->
  Vector a
sliceV i n s v = go (fromMaybe 0 i) (fromMaybe len n) s v
  where
    go i n Nothing = V.slice i n
    go i n (Just s) =
      V.ifilter (\x _ -> x `mod` s == 0)
        . V.drop i
        . V.take n
    len = V.length v

objectHasEx :: HashMap Key Thunk -> Text -> Bool -> Bool
objectHasEx o f True = H.member (Visible f) o || H.member (Hidden f) o
objectHasEx o f False = H.member (Visible f) o

objectHas :: HashMap Key Thunk -> Text -> Bool
objectHas o f = objectHasEx o f False

objectHasAll :: HashMap Key Thunk -> Text -> Bool
objectHasAll o f = objectHasEx o f True

flattenArrays :: Vector (Vector Thunk) -> Vector Thunk
flattenArrays = join
