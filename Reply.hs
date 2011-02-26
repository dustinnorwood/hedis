{-# LANGUAGE OverloadedStrings #-}
module Reply (Reply(..), parseReply) where

import Prelude hiding (error, take)
import Control.Applicative
import Control.Concurrent
import Data.Attoparsec.Char8
import qualified Data.Attoparsec.Lazy as P
import qualified Data.ByteString.Char8 as S
import qualified Data.ByteString.Lazy.Char8 as L


data Reply = SingleLine S.ByteString
           | Error S.ByteString
           | Integer Integer
           | Bulk (Maybe S.ByteString)
           | MultiBulk (Maybe [Reply])
           | ConnectionLost
         deriving (Show)


parseReply :: L.ByteString -> [Reply]
parseReply input = 
    case P.parse asReply input of
        P.Fail _ _ _  -> undefined -- TODO report error to caller
        P.Done rest r -> r : parseReply rest
    

asReply :: Parser Reply
asReply = choice [singleLine, error, integer, bulk, multiBulk, shutdown]


------------------------------------------------------------------------------
-- Reply parsers
--
singleLine :: Parser Reply
singleLine = fmap SingleLine $ '+' `prefixing` line

error :: Parser Reply
error = fmap Error $ '-' `prefixing` line

integer :: Parser Reply
integer = fmap Integer $ ':' `prefixing` signed decimal

bulk :: Parser Reply
bulk = fmap Bulk $ do    
    len <- '$' `prefixing` signed decimal
    if len < 0
        then return Nothing
        else fmap Just $ beforeCRLF (P.take len)

multiBulk :: Parser Reply
multiBulk = fmap MultiBulk $ do
        len <- '*' `prefixing` signed decimal
        if len < 0
            then return Nothing
            else fmap Just $ count len (bulk <|> multiBulk)

shutdown :: Parser Reply
shutdown = P.endOfInput >> return ConnectionLost


------------------------------------------------------------------------------
-- Helpers & Combinators
--
prefixing :: Char -> Parser a -> Parser a
c `prefixing` a = char c >> beforeCRLF a

beforeCRLF :: Parser a -> Parser a
beforeCRLF a = do
    x <- a
    string "\r\n"
    return x

line :: Parser S.ByteString
line = takeTill (=='\r')