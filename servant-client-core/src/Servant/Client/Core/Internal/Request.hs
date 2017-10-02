{-# LANGUAGE CPP                        #-}
{-# LANGUAGE DeriveDataTypeable         #-}
{-# LANGUAGE DeriveGeneric              #-}
{-# LANGUAGE GeneralizedNewtypeDeriving #-}
{-# LANGUAGE MultiParamTypeClasses      #-}
{-# LANGUAGE OverloadedStrings          #-}
{-# LANGUAGE ScopedTypeVariables        #-}
{-# LANGUAGE TypeFamilies               #-}

module Servant.Common.Request where

import           Prelude                 ()
import           Prelude.Compat

import qualified Data.ByteString.Builder as Builder
import qualified Data.ByteString.Lazy    as LBS
import           Data.Semigroup          ((<>))
import qualified Data.Sequence           as Seq
import           Data.String.Conversions (cs)
import           Data.Text               (Text)
import           Data.Typeable           (Typeable)
import           GHC.Generics            (Generic)
import           Network.HTTP.Media      (MediaType)
import           Network.HTTP.Types      (Header, HeaderName, HttpVersion,
                                          Method, QueryItem, Status, http11)
import           Web.HttpApiData         (ToHttpApiData, toEncodedUrlPiece,
                                          toHeader)

data ServantError
  = FailureResponse Response
  | DecodeFailure Text Response
  | UnsupportedContentType MediaType Response
  | InvalidContentTypeHeader Response
  | ConnectionError Text
  deriving (Eq, Show, Generic, Typeable)

data Request = Request
  { requestPath        :: Builder.Builder
  , requestQueryString :: Seq.Seq QueryItem
  , requestBody        :: Maybe (RequestBody, MediaType)
  , requestAccept      :: Seq.Seq MediaType
  , requestHeaders     :: Seq.Seq Header
  , requestHttpVersion :: HttpVersion
  } deriving (Generic, Typeable)

newtype RequestBody = RequestBodyLBS LBS.ByteString
  deriving (Eq, Ord, Read, Show, Typeable)

data Response = Response
  { responseStatusCode  :: Status
  , responseBody        :: LBS.ByteString
  , responseHeaders     :: Seq.Seq Header
  , responseHttpVersion :: HttpVersion
  } deriving (Eq, Show, Generic, Typeable)

defaultRequest :: Request
defaultRequest = Request
  { requestPath = ""
  , requestQueryString = Seq.empty
  , requestBody = Nothing
  , requestAccept = Seq.empty
  , requestHeaders = Seq.empty
  , requestHttpVersion = http11
  }

appendToPath :: Text -> Request -> Request
appendToPath p req
  = req { requestPath = requestPath req <> "/" <> toEncodedUrlPiece p }

{-appendToQueryString :: Text       -- ^ param name-}
                    {--> Maybe Text -- ^ param value-}
                    {--> Request-}
                    {--> Request-}
{-appendToQueryString pname pvalue req-}
  {-= req { requestQueryString = requestQueryString req Seq.|> (pname, pvalue)}-}

addHeader :: ToHttpApiData a => HeaderName -> a -> Request -> Request
addHeader name val req
  = req { requestHeaders = requestHeaders req Seq.|> (name, toHeader val)}

-- | Set body and media type of the request being constructed.
--
-- The body is set to the given bytestring using the 'RequestBodyLBS'
-- constructor.
--
-- @since 0.12
--
setRequestBodyLBS :: LBS.ByteString -> MediaType -> Request -> Request
setRequestBodyLBS b t req
  = req { requestBody = Just (RequestBodyLBS b, t) }

-- | Set body and media type of the request being constructed.
--
-- @since 0.12
--
setRequestBody :: RequestBody -> MediaType -> Request -> Request
setRequestBody b t req = req { requestBody = Just (b, t) }

{-reqToRequest :: (Functor m, MonadThrow m) => Req -> BaseUrl -> m Request-}
{-reqToRequest req (BaseUrl reqScheme reqHost reqPort path) =-}
    {-setheaders . setAccept . setrqb . setQS <$> parseRequest url-}

  {-where url = show $ nullURI { uriScheme = case reqScheme of-}
                                  {-Http  -> "http:"-}
                                  {-Https -> "https:"-}
                             {-, uriAuthority = Just $-}
                                 {-URIAuth { uriUserInfo = ""-}
                                         {-, uriRegName = reqHost-}
                                         {-, uriPort = ":" ++ show reqPort-}
                                         {-}-}
                             {-, uriPath = fullPath-}
                             {-}-}
        {-fullPath = path ++ cs (Builder.toLazyByteString (reqPath req))-}

        {-setrqb r = case reqBody req of-}
                     {-Nothing -> r-}
                     {-Just (b,t) -> r { requestBody = b-}
                                     {-, requestHeaders = requestHeaders r-}
                                                     {-++ [(hContentType, cs . show $ t)] }-}
        {-setQS = setQueryString $ queryTextToQuery (qs req)-}
        {-setheaders r = r { requestHeaders = requestHeaders r-}
                                         {-<> fmap toProperHeader (headers req) }-}
        {-setAccept r = r { requestHeaders = filter ((/= "Accept") . fst) (requestHeaders r)-}
                                        {-<> [("Accept", renderHeader $ reqAccept req)-}
                                              {-| not . null . reqAccept $ req] }-}
        {-toProperHeader (name, val) =-}
          {-(fromString name, encodeUtf8 val)-}

#if !MIN_VERSION_http_client(0,4,30)
-- 'parseRequest' is introduced in http-client-0.4.30
-- it differs from 'parseUrl', by not throwing exceptions on non-2xx http statuses
--
-- See for implementations:
-- http://hackage.haskell.org/package/http-client-0.4.30/docs/src/Network-HTTP-Client-Request.html#parseRequest
-- http://hackage.haskell.org/package/http-client-0.5.0/docs/src/Network-HTTP-Client-Request.html#parseRequest
parseRequest :: MonadThrow m => String -> m Request
parseRequest url = liftM disableStatusCheck (parseUrl url)
  where
    disableStatusCheck req = req { checkStatus = \ _status _headers _cookies -> Nothing }
#endif


-- * performing requests

displayHttpRequest :: Method -> String
displayHttpRequest httpmethod = "HTTP " ++ cs httpmethod ++ " request"
