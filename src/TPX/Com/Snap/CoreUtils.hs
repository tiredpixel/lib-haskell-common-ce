{-# LANGUAGE MultiParamTypeClasses #-}


module TPX.Com.Snap.CoreUtils (
    ErrorC(..),
    RouteHref(..),
    RouteId(..),
    ValidateJSON(..),
    badReq,
    calcLink,
    created,
    formatTime,
    getBoundedJSON',
    getJSON',
    getJSONB,
    init,
    intErr,
    mergeObject,
    noContent,
    notFound,
    parseReq,
    run,
    runValidate,
    setResLink,
    snapCfg,
    unauthorized,
    wait,
    writeJSON',
    ) where


import           Control.Concurrent      (ThreadId, killThread)
import           Data.Aeson
import           Data.Time.Clock
import           Prelude                 hiding (init)
import           Safe
import           Snap.Core
import           Snap.Extras.CoreUtils   (jsonResponse)
import           Snap.Extras.JSON
import           Snap.Http.Server.Config
import           System.IO
import           System.Posix.Signals
import           TPX.Com.Cursor
import qualified Data.ByteString.Char8   as C8
import qualified Data.HashMap.Strict     as HM
import qualified Data.Time.Format        as Time


newtype ErrorC = ErrorC { errorCDebug :: Text
    } deriving (Show)
instance ToJSON ErrorC where
    toJSON o = object [
        "msg" .= errorCDebug o]

class RouteHref a b where
    toRouteHref :: b -> a
    fromRouteHref :: a -> Maybe b

class RouteId a where
    toRouteId :: ByteString -> Maybe a
    fromRouteId :: a -> ByteString

class ValidateJSON r where
    validateJSON :: MonadSnap m => Either Text r -> m (Either ErrorC r)
    validateJSON (Right r)  = validateJSONOk r
    validateJSON (Left err) = validateJSONErr err
    
    validateJSONOk :: MonadSnap m => r -> m (Either ErrorC r)
    validateJSONOk r = return $ Right r
    
    validateJSONErr :: MonadSnap m => Text -> m (Either ErrorC r)
    validateJSONErr err = return $ Left ErrorC {
        errorCDebug = err}

badReq :: MonadSnap m => ErrorC -> m ()
badReq err = do
    modifyResponse $ setResponseCode 400
    writeJSON err
    getResponse >>= finishWith

calcLink :: [(ByteString, Maybe ByteString)] -> ByteString
calcLink links = C8.intercalate ", " links'
    where
        linkify r h = "<" <> h <> ">; rel=\"" <> r <> "\""
        links' = [linkify k v | (k, Just v) <- links]

created :: (MonadSnap m, ToJSON a) => ByteString -> a -> m ()
created loc msg = do
    modifyResponse $ setResponseCode 201
    modifyResponse $ setHeader "Location" loc
    writeJSON msg

formatTime :: UTCTime -> ByteString
formatTime = encodeUtf8 . toText . Time.formatTime Time.defaultTimeLocale f
    where
        f = Time.iso8601DateFormat (Just "%T%QZ")

getBoundedJSON' :: (MonadSnap m, FromJSON a) => Int64 -> m (Either Text a)
getBoundedJSON' s = do
    v <- getBoundedJSON s
    return $ case v of
        Left l  -> Left $ toText l
        Right r -> Right r

getJSON' :: (MonadSnap m, FromJSON a) => m (Either Text a)
getJSON' = do
    v <- getJSON
    return $ case v of
        Left l  -> Left $ toText l
        Right r -> Right r

getJSONB :: (MonadSnap m, FromJSON a) => LByteString -> m (Either Text a)
getJSONB body = do
    bodyVal <- decode `fmap` return body
    return $ case bodyVal of
        Just v -> case fromJSON v of
            Success a -> Right a
            Error e   -> Left $ toText e
        Nothing -> Left "Can't find JSON data in POST body"

init :: IO (MVar ())
init = newEmptyMVar

intErr :: MonadSnap m => SomeException -> m ()
intErr ex = do
    logError $ encodeUtf8 (show ex :: Text)
    modifyResponse $ setResponseCode 500

mergeObject :: Value -> Value -> Value
mergeObject (Object a) (Object b) = Object $ HM.unionWith mergeObject a b
mergeObject _ b = b

noContent :: MonadSnap m => m ()
noContent = modifyResponse $ setResponseCode 204

notFound :: MonadSnap m => m ()
notFound = do
    modifyResponse $ setResponseCode 404
    getResponse >>= finishWith

parseReq :: MonadSnap m => m Cursor
parseReq = do
    lim_  <- getParam curLim
    posN_ <- getParam curNext
    posP_ <- getParam curPrev
    let
        lim = fromMaybe limDef $ lim_ >>= readMaybe . decodeUtf8
        pos = case (posN_, posP_) of
            (Just posN, _)       -> Just $ Right posN
            (Nothing, Just posP) -> Just $ Left  posP
            _ -> Nothing
    return Cursor {
        cursorPos = pos,
        cursorLim = max limMin $ min limMax lim}
    where
        limMin = 1
        limMax = 256
        limDef = 32

run :: Monad m => m a1 -> MaybeT m a2 -> m (Maybe a2)
run f e = do
    r_ <- runMaybeT e
    case r_ of
        Just r  -> return $ Just r
        Nothing -> f >> return Nothing

runValidate :: MonadSnap m => Either ErrorC a -> m (Maybe a)
runValidate e = case e of
    Right r  -> return $ Just r
    Left err -> f err >> return Nothing
    where
        f = badReq

snapCfg :: MonadSnap m => Config m a
snapCfg =
    setAccessLog (ConfigFileLog "-") $
    setErrorLog (ConfigFileLog "-")
    defaultConfig

setResLink :: MonadSnap m => ByteString -> (a -> ByteString) -> [a] -> m ()
setResLink url href es =
    modifyResponse $ setHeader "Link" $ calcLink links
    where
        joinUrl r u = url <> "?" <> r <> "=" <> u
        links = [
            ("first", Just url),
            ("next",  joinUrl curNext . href <$> lastMay es),
            ("prev",  joinUrl curPrev . href <$> headMay es)]

unauthorized :: MonadSnap m => m ()
unauthorized = do
    modifyResponse $ setResponseCode 401
    modifyResponse $ setHeader "WWW-Authenticate" "Basic"
    getResponse >>= finishWith

wait :: MVar () -> ThreadId -> IO ()
wait done tId = do
    _ <- installHandler sigTERM sigTERMH Nothing
    takeMVar done
    hPutStrLn stderr "Čau"
    where
        sigTERMH = CatchOnce $ do
            hPutStrLn stderr "Handling SIGTERM"
            killThread tId
            putMVar done ()

writeJSON' :: MonadSnap m => LByteString -> m ()
writeJSON' a = do
    jsonResponse
    writeLBS a


curLim :: ByteString
curLim = "_lim"

curNext :: ByteString
curNext = "_next"

curPrev :: ByteString
curPrev = "_prev"
