{-# LANGUAGE OverloadedStrings, FlexibleContexts, TypeFamilies, QuasiQuotes, TemplateHaskell, DeriveGeneric #-}
module WeatherService.Service (WeatherField(..)
                              , dayHandler
                              , dayPutHandler) where
{-| Semester 2 assignment for CI285, University of Brighton
    Jim Burton <j.burton@brighton.ac.uk>
-}
import           System.Log.Logger ( updateGlobalLogger
                                   , rootLoggerName
                                   , setLevel
                                   , debugM
                                   , Priority(..)
                                   )
import           Control.Monad.IO.Class (liftIO)
import           Control.Monad          (msum)
import           Data.List         (intercalate)
import           Data.Text         (Text, pack, unpack)
import           Happstack.Server  
import           Database.SQLite.Simple
import           Database.SQLite.Simple.FromRow
import           Data.Aeson
import           GHC.Generics                  (Generic)
import qualified Data.ByteString.Lazy.Char8 as BC

data WeatherField = WeatherField {date :: Text, temperature :: Float}
                    deriving (Generic, Show)

instance FromRow WeatherField where -- ^ Marshal data from DB to our ADT
  fromRow = WeatherField <$> field <*> field 

instance ToRow WeatherField where -- ^ Marshal data from our ADT to the DB
  toRow (WeatherField theDate temp) = toRow (theDate, temp)

instance ToJSON   WeatherField -- ^ Marshal data from our ADT to JSON
instance FromJSON WeatherField -- ^ Marshal data from JSON to our ADT

{-| Handle reuests for a single date. -}
dayHandler :: Text -> Connection -> ServerPart Response
dayHandler d conn = do
  r <- liftIO (queryNamed conn "SELECT the_date, temperature \
                               \ FROM  weather \
                               \ WHERE the_date = :dt" [":dt" := d] :: IO [WeatherField])
  liftIO $ debugM "The Date" (listToOutput r) -- ^ NB example of how to output debug messages
  case r of
    [] -> notFoundHandler
    _  -> ok $ toResponse (listToOutput r)

{-| Handle PUT reuests for date/temperature pairs. -}
dayPutHandler :: Text -> Text -> Connection -> ServerPart Response
dayPutHandler d t conn = do
  r <- liftIO (queryNamed conn "SELECT the_date, temperature \
                               \ FROM  weather \
                               \ WHERE the_date = :dt" [":dt" := d] :: IO [WeatherField])
  liftIO $ debugM "Date PUT request" (listToOutput r)
  case r of
    [] -> insertHandler d t conn
    _  -> updateHandler d t conn

{-| Insert a new date/temperature pair. -}
insertHandler :: Text -> Text -> Connection -> ServerPart Response
insertHandler d t conn = do
  let t' = (read $ unpack t)::Float
  liftIO (execute conn "INSERT INTO weather (the_date, temperature) VALUES (?,?)" (WeatherField d t'))
  ok $ emptyJSONResponse

{-| Update a date/temperature pair. -}
updateHandler :: Text -> Text -> Connection -> ServerPart Response
updateHandler d t conn = do
  liftIO (execute conn "UPDATE weather SET temperature = ? WHERE the_date = ?" (Only t))
  ok $ emptyJSONResponse

{-| Return 404 Not Found and an empty JSON object -}
notFoundHandler :: ServerPart Response
notFoundHandler = notFound $ emptyJSONResponse

{-| An empty JSON object -}
--emptyJSONObject :: ServerPart Response
emptyJSONResponse = toResponse (pack "[]")

{-| Turn a list of WeatherFields into a JSON object. -}
listToOutput :: ToJSON a => [a] -> String
listToOutput xs = "[" ++ intercalate "," (map (BC.unpack . encode) xs) ++ "]"

{-| Return all records in the database that fall between d1 & d2. -}
rangeHandler :: Text -> Text -> Connection -> ServerPart Response  
rangeHandler d1 d2 conn = do 
  r <- liftIO (queryNamed conn "SELECT the_date, temperature \
                               \ FROM  weather \
                               \ WHERE the_date >= :d1 AND the_date <= :d2" [":d1" := d1, "d2" := d2] :: IO [WeatherField])
  liftIO $ debugM "The Date" (listToOutput r)
  case r of
    [] -> notFoundHandler
    _  -> ok $ toResponse (listToOutput r)


{-| Return the details of the day with the max. temperature between d1 & d2. -}
maxHandler :: Text -> Text -> Connection -> ServerPart Response 
maxHandler d1 d2 conn = do 
  r <- liftIO (queryNamed conn "SELECT the_date, max(temperature) \
                               \ FROM  weather \
                               \ WHERE the_date >= :d1 AND the_date <= :d2" [":d1" := d1, "d2" := d2] :: IO [WeatherField]) 
  liftIO $ debugM "The Date" (listToOutput r)
  case r of
    [] -> notFoundHandler
    _  -> ok $ toResponse (listToOutput r)

{-| Return all records in the database where temperature = t. -}
aboveHandler :: Text -> Connection -> ServerPart Response 
aboveHandler t conn = do 
  r <- liftIO (queryNamed conn "SELECT * \
                               \ FROM  weather \
                               \ WHERE temperature = :t" [":t" := t] :: IO [WeatherField]) 
  liftIO $ debugM "The Temperature" (listToOutput r)
  case r of
    [] -> notFoundHandler
    _  -> ok $ toResponse (listToOutput r)
