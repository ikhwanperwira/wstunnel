{-# LANGUAGE DeriveDataTypeable #-}
{-# OPTIONS_GHC -fno-cse #-}

module Main where

import           Lib

import           ClassyPrelude          (readMay)
import qualified Data.ByteString.Char8  as BC
import           System.Console.CmdArgs
import           System.Environment     (getArgs, withArgs)


data WsTunnel = WsTunnel
  { localToRemote  :: String
  , remoteToLocal  :: String
  , wsTunnelServer :: String
  , udpMode        :: Bool
  , serverMode     :: Bool
  , restrictTo     :: String
  , _last          :: Bool
  } deriving (Show, Data, Typeable)


cmdLine :: WsTunnel
cmdLine = WsTunnel
  { localToRemote = def &= explicit &= name "L" &= name "localToRemote" &= typ "[BIND:]PORT:HOST:PORT"
                    &= help "Listen on local and forward traffic from remote" &= groupname "Client options"
  , remoteToLocal = def &= explicit &= name "R" &= name "RemoteToLocal" &= typ "[BIND:]PORT:HOST:PORT"
                    &= help "Listen on remote and forward traffic from local"
  , udpMode = def &= explicit &= name "u" &= name "udp" &= help "forward UDP traffic instead of TCP"
  , wsTunnelServer = def &= argPos 0 &= typ "ws[s]://wstunnelServer[:port]"

  , serverMode = def &= explicit &= name "server"
                 &= help "Start a server that will forward traffic for you" &= groupname "Server options"
  , restrictTo = def &= explicit &= name "r" &= name "restrictTo"
                 &= help "Accept traffic to be forwarded only to this service" &= typ "HOST:PORT"

  , _last = def &= explicit &= name "ツ" &= groupname "Common options"
  } &= summary ("Use the websockets protocol to tunnel {TCP,UDP} traffic\n"
                ++ "wsTunnelClient <---> wsTunnelServer <---> RemoteHost\n"
                ++ "Use secure connection (wss://) to bypass proxies"
               )
    &= helpArg [explicit, name "help", name "h"]


data WsServerInfo = WsServerInfo
  { useTls :: !Bool
  , host   :: !String
  , port   :: !Int
  } deriving (Show)

toPort :: String -> Int
toPort str = case readMay str of
                  Just por -> por
                  Nothing -> error $ "Invalid port number `" ++ str ++ "`"

parseServerInfo :: WsServerInfo -> String -> WsServerInfo
parseServerInfo server [] = server
parseServerInfo server ('w':'s':':':'/':'/':xs) = parseServerInfo (server {useTls = False, port = 80}) xs
parseServerInfo server ('w':'s':'s':':':'/':'/':xs) = parseServerInfo (server {useTls = True, port = 443}) xs
parseServerInfo server (':':prt) = server {port = toPort prt}
parseServerInfo server hostPath = parseServerInfo (server {host = takeWhile (/= ':') hostPath}) (dropWhile (/= ':') hostPath)


data TunnelInfo = TunnelInfo
  { localHost  :: !String
  , localPort  :: !Int
  , remoteHost :: !String
  , remotePort :: !Int
  } deriving (Show)

parseTunnelInfo :: String -> TunnelInfo
parseTunnelInfo str = mk $ BC.unpack <$> BC.split ':' (BC.pack str)
  where
    mk [lPort, host, rPort] = TunnelInfo { localHost = "127.0.0.1", localPort = toPort lPort, remoteHost = host, remotePort = toPort rPort}
    mk [bind,lPort, host,rPort] = TunnelInfo { localHost = bind, localPort = toPort lPort, remoteHost = host, remotePort = toPort rPort}
    mk _ = error $  "Invalid tunneling information `" ++ str ++ "`, please use format [BIND:]PORT:HOST:PORT"




main :: IO ()
main = do
  args <- getArgs
  cfg <- if null args then withArgs ["--help"] (cmdArgs cmdLine) else cmdArgs cmdLine

  let serverInfo = parseServerInfo (WsServerInfo False "" 0) (wsTunnelServer cfg)

  if serverMode cfg
    then putStrLn ("Starting server with opts " ++ show serverInfo )
         >> runServer (host serverInfo, port serverInfo)
    else if not $ null (localToRemote cfg)
               then let (TunnelInfo lHost lPort rHost rPort) = parseTunnelInfo (localToRemote cfg) in runClient (if udpMode cfg then UDP else TCP) (lHost, lPort) (host serverInfo, port serverInfo) (rHost, rPort)
               else return ()


  putStrLn "Goodbye !"
  return ()
