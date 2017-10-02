{-# LANGUAGE MultiParamTypeClasses #-}
{-| Types for possible backends to run client-side `Request` queries -}
module Servant.Client.Class where

import Data.Proxy
import Network.HTTP.Types
import Servant.Common.Req (Request, Response)

class (Monad m) => RunClient m ct where
  runRequest :: Proxy ct
             -> Method
             -> Request
             -> m Response
