module TPX.Com.API.Req (
    ValidateJSON(..),
    getBoundedJSON'
    ) where


import              Data.Aeson
import              Snap.Core
import              Snap.Extras.JSON
import qualified    TPX.Com.API.Resource.CommonError        as  RC


class ValidateJSON r where
    validateJSON :: Either Text r -> Snap (Either RC.ErrorN r)
    validateJSON (Right r)  = validateJSONOk r
    validateJSON (Left err) = validateJSONErr err
    
    validateJSONOk :: r -> Snap (Either RC.ErrorN r)
    validateJSONOk r = return $ Right r
    
    validateJSONErr :: Text -> Snap (Either RC.ErrorN r)
    validateJSONErr err = return $ Left RC.ErrorN {
        RC.errorNDebug = err}

getBoundedJSON' :: (MonadSnap m, FromJSON a) => Int64 -> m (Either Text a)
getBoundedJSON' s = do
    v <- getBoundedJSON s
    return $ case v of
        Left l  -> Left $ toText l
        Right r -> Right r
