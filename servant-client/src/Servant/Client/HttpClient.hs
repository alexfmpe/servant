{-# LANGUAGE CPP                        #-}
{-# LANGUAGE DeriveDataTypeable         #-}
{-# LANGUAGE DeriveGeneric              #-}
{-# LANGUAGE FlexibleInstances          #-}
{-# LANGUAGE GeneralizedNewtypeDeriving #-}
{-# LANGUAGE MultiParamTypeClasses      #-}
{-# LANGUAGE OverloadedStrings          #-}
{-# LANGUAGE ScopedTypeVariables        #-}
{-# LANGUAGE TypeFamilies               #-}

{-| http-client based client  requests executor -}
module Servant.Client.HttpClient where


import           Prelude                     ()
import           Prelude.Compat

import           Control.Exception
import           Control.Monad
import           Control.Monad.Base          (MonadBase (..))
import           Control.Monad.Catch         (MonadCatch, MonadThrow)
import           Control.Monad.Error.Class   (MonadError (..))
import           Control.Monad.Reader
import           Control.Monad.Trans.Control (MonadBaseControl (..))
import           Control.Monad.Trans.Except
import           Data.ByteString.Builder     (toLazyByteString)
import qualified Data.ByteString.Lazy        as BSL
import           Data.Foldable               (toList)
import           Data.Functor.Alt            (Alt (..))
import           Data.Monoid                 ((<>))
import           Data.String                 (fromString)
import qualified Data.Text                   as T
import           GHC.Exts                    (fromList)
import           GHC.Generics
import           Network.HTTP.Media          (renderHeader)
import           Network.HTTP.Types          (hContentType, renderQuery,
                                              statusCode)
import           Servant.Client.Core

import qualified Network.HTTP.Client         as Client

data ClientEnv
  = ClientEnv
  { manager :: Client.Manager
  , baseUrl :: BaseUrl
  }


-- | @ClientM@ is the monad in which client functions run. Contains the
-- 'Manager' and 'BaseUrl' used for requests in the reader environment.
newtype ClientM a = ClientM { runClientM' :: ReaderT ClientEnv (ExceptT ServantError IO) a }
                    deriving ( Functor, Applicative, Monad, MonadIO, Generic
                             , MonadReader ClientEnv
                             , MonadError ServantError
                             , MonadThrow, MonadCatch
                             )

instance MonadBase IO ClientM where
  liftBase = ClientM . liftBase

instance MonadBaseControl IO ClientM where
  type StM ClientM a = Either ServantError a

  liftBaseWith f = ClientM (liftBaseWith (\g -> f (g . runClientM')))

  restoreM st = ClientM (restoreM st)

-- | Try clients in order, last error is preserved.
instance Alt ClientM where
  a <!> b = a `catchError` \_ -> b

instance RunClient ClientM where
  runRequest = performRequest

runClientM :: ClientM a -> ClientEnv -> IO (Either ServantError a)
runClientM cm env = runExceptT $ (flip runReaderT env) $ runClientM' cm



performRequest :: Request -> ClientM Response
performRequest req = do
  m <- asks manager
  burl <- asks baseUrl
  let request = requestToClientRequest burl req

  eResponse <- liftIO $ catchConnectionError $ Client.httpLbs request m
  case eResponse of
    Left err -> throwError $ err
    Right response -> do
      let status = Client.responseStatus response
          status_code = statusCode status
          ourResponse = clientResponseToReponse response
      unless (status_code >= 200 && status_code < 300) $
        throwError $ FailureResponse ourResponse
      return ourResponse

clientResponseToReponse :: Client.Response BSL.ByteString -> Response
clientResponseToReponse r = Response
  { responseStatusCode = Client.responseStatus r
  , responseBody = Client.responseBody r
  , responseHeaders = fromList $ Client.responseHeaders r
  , responseHttpVersion = Client.responseVersion r
  }

requestToClientRequest :: BaseUrl -> Request -> Client.Request
requestToClientRequest burl r = Client.defaultRequest
  { Client.method = requestMethod r
  , Client.host = fromString $ baseUrlHost burl
  , Client.port = baseUrlPort burl
  , Client.path = BSL.toStrict
                $ fromString (baseUrlPath burl)
               <> toLazyByteString (requestPath r)
  , Client.queryString = renderQuery True . toList $ requestQueryString r
  , Client.requestHeaders =
      let orig = toList $ requestHeaders r
      in maybe orig (: orig) contentTypeHdr
  , Client.requestBody = body
  }
  where
    (body, contentTypeHdr) = case requestBody r of
      Nothing -> (Client.RequestBodyLBS "", Nothing)
      Just (RequestBodyLBS body', typ)
        -> (Client.RequestBodyLBS body', Just (hContentType, renderHeader typ))

catchConnectionError :: IO a -> IO (Either ServantError a)
catchConnectionError action =
  catch (Right <$> action) $ \e ->
    pure . Left . ConnectionError . T.pack $ show (e :: Client.HttpException)
