module Main (main) where

import Control.Monad.IO.Class (MonadIO (liftIO))
import Control.Monad.Free (Free (..))

import Data.Functor((<&>))
import Data.Time ( UTCTime, getCurrentTime, formatTime, defaultTimeLocale )
import Data.List qualified as L
import Lib1 qualified
import Lib2 qualified
import Lib3 qualified
import InMemoryTables qualified
import DataFrame (DataFrame(..), Column (..), ColumnType (..), Value (..), Row, DataFrame (..))
import Lib2 (parseStatement, ParsedStatement(..), Condition(..), ValueExpr(..))
import System.Console.Repline
  ( CompleterStyle (Word),
    ExitDecision (Exit),
    HaskelineT,
    WordCompleter,
    evalRepl,
  )
import System.Console.Terminal.Size (Window, size, width)





type TableName = String
type FileContent = String
type ErrorMessage = String

type Repl a = HaskelineT IO a

final :: Repl ExitDecision
final = do
  liftIO $ putStrLn "Goodbye!"
  return Exit

ini :: Repl ()
ini = liftIO $ putStrLn "Welcome to select-manipulate database! Press [TAB] for auto completion."

completer :: (Monad m) => WordCompleter m
completer n = do
  let names = [
              "select", "*", "from", "show", "table",
              "tables", "insert", "into", "values",
              "set", "update", "delete"
              ]
  return $ Prelude.filter (L.isPrefixOf n) names

-- Evaluation : handle each line user inputs
cmd :: String -> Repl ()
cmd c = do
  s <- terminalWidth <$> liftIO size
  result <- liftIO $ cmd' s
  case result of
    Left err -> liftIO $ putStrLn $ "Error: " ++ err
    Right table -> liftIO $ putStrLn table
  where
    terminalWidth :: (Integral n) => Maybe (Window n) -> n
    terminalWidth = maybe 80 width
    cmd' :: Integer -> IO (Either String String)
    cmd' s = do
      df <- runExecuteIO $ Lib3.executeSql c 
      return $ Lib1.renderDataFrameAsTable s <$> df

main :: IO ()
main =
  evalRepl (const $ pure ">>> ") cmd [] Nothing Nothing (Word completer) ini final

runExecuteIOTest :: Lib3.Execution r -> IO r
runExecuteIOTest (Pure r) = return r
runExecuteIOTest (Free step) = do
    next <- runStep step
    runExecuteIOTest next
    where
        runStep :: Lib3.ExecutionAlgebra a -> IO a
        runStep (Lib3.ExecuteSelect dfs stmt next) = do
          let processedData = Lib3.executeSelectOperation dfs stmt
          return $ next processedData

        runStep (Lib3.ExecuteUpdate df stmt next) = do
          let processedData = Lib3.executeUpdateOperation df stmt
          return $ next processedData

        runStep (Lib3.ExecuteInsert df stmt next) = do
          let processedData = Lib3.executeInsertOperation df stmt
          return $ next processedData

        runStep (Lib3.GetTime next) = do
          -- Return frozen time for testing
          let testTime = read "2000-01-01 12:00:00 UTC" :: UTCTime
          return $ next testTime

        runStep (Lib3.DisplayTime time next) = do
          let timestr = formatTime defaultTimeLocale "%F %T" time
          let df = DataFrame [Column "current_time" StringType] [[StringValue timestr]]
          return $ next df

        runStep (Lib3.LoadFile tableName next) = return (next tableName)
            -- Return the name for testing

        runStep (Lib3.ParseStringOfFile tableName next) = do
          -- Return data from InMemoryTables
          let maybeDataFrame = lookup tableName InMemoryTables.database
          case maybeDataFrame of
            Just df -> return (next (Right df))
            Nothing -> return (next (Left "Table not found in InMemoryTables"))

        runStep (Lib3.SerializeDataFrameToYAML _ df next) = do
          -- Skip for testing
          return (next df)

        runStep (Lib3.CheckDataFrame df next) = do
          let validationResult = Lib1.validateDataFrame df
          return (next validationResult)




runExecuteIO :: Lib3.Execution r -> IO r
runExecuteIO (Pure r) = return r
runExecuteIO (Free step) = do
    next <- runStep step
    runExecuteIO next
    where
        runStep :: Lib3.ExecutionAlgebra a -> IO a
        runStep (Lib3.ExecuteSelect dfs stmt next) = do
          let processedData = Lib3.executeSelectOperation dfs stmt
          return $ next processedData

        runStep (Lib3.ExecuteUpdate df stmt next) = do
          let processedData = Lib3.executeUpdateOperation df stmt
          return $ next processedData

        runStep (Lib3.ExecuteInsert df stmt next) = do
          let processedData = Lib3.executeInsertOperation df stmt
          return $ next processedData

        runStep (Lib3.GetTime next) = getCurrentTime >>= return . next

        runStep (Lib3.DisplayTime time next) = do
          let timestr = formatTime defaultTimeLocale "%F %T" time
          let df = DataFrame [Column "current_time" StringType] [[StringValue timestr]]
          return $ next df

        runStep (Lib3.LoadFile tableName next) = do
          let relativePath = Lib3.getPath tableName
          fileContent <- readFile relativePath
          return (next fileContent)

        runStep (Lib3.ParseStringOfFile fileContent next) = do
          let parseContent = Lib3.parseContentToDataFrame fileContent
          return (next parseContent)

        runStep (Lib3.SerializeDataFrameToYAML tableName df next) = do
          returnedDf <- Lib3.writeDataFrameToYAML tableName df
          return (next returnedDf)

        runStep (Lib3.CheckDataFrame df next) = do
          let validationResult = Lib1.validateDataFrame df
          return (next validationResult)


        
