{-# LANGUAGE FlexibleContexts #-}

-- |
-- Module      :  Streamly.External.FileSystem.Handle
-- Copyright   :  © 2020 Julian Ospald
-- License     :  BSD3
--
-- Maintainer  :  Julian Ospald <hasufell@posteo.de>
-- Stability   :  experimental
-- Portability :  portable
--
-- This module provides high-level file streaming API, working
-- with file handles.
module Streamly.External.FileSystem.Handle
  (
  -- * File reading
    readFileLBS
  , readFileLBS'
  , readFileStream
  , readFileStream'
  -- * File writing
  , copyFileHandle
  , copyFileHandle'
  , copyFileStream
  , copyFileStream'
  , copyLBS
  , copyLBS'
  )
where

import           Control.Exception.Safe
import           Control.Monad.IO.Class         ( liftIO )
import           Data.Word                      ( Word8 )
import           Prelude                 hiding ( readFile )
import           Streamly
import           Streamly.Memory.Array
import           System.IO                      ( Handle
                                                , hClose
                                                )
import           System.IO.Unsafe
import qualified Data.ByteString.Lazy          as L
import qualified Data.ByteString.Lazy.Internal as BSLI
import qualified Streamly.External.ByteString  as Strict
import qualified Streamly.External.ByteString.Lazy
                                               as Lazy
import qualified Streamly.FileSystem.Handle    as FH
import qualified Streamly.Internal.Data.Unfold as SIU
import qualified Streamly.Internal.Prelude     as S


-- https://github.com/psibi/streamly-bytestring/issues/7
fromChunks :: SerialT IO (Array Word8) -> IO BSLI.ByteString
fromChunks =
  S.foldrM (\x b -> unsafeInterleaveIO b >>= pure . BSLI.chunk x)
           (pure BSLI.Empty)
    . S.map Strict.fromArray


-- |Read a file lazily as a lazy ByteString.
--
-- The handle is closed automatically, when the stream exits normally,
-- aborts or gets garbage collected.
--
-- This uses `unsafeInterleaveIO` under the hood.
readFileLBS :: Handle  -- ^ readable file handle
            -> IO L.ByteString
readFileLBS handle' = fromChunks (readFileStream handle')


-- |Like 'readFileLBS', except doesn't close the handle..
readFileLBS' :: Handle  -- ^ readable file handle
             -> IO L.ByteString
readFileLBS' handle' = fromChunks (readFileStream' handle')


-- | Read a handle as a streamly filestream.
--
-- The handle is closed automatically, when the stream exits normally,
-- aborts or gets garbage collected.
-- The stream must not be used after the handle is closed.
readFileStream :: (MonadCatch m, MonadAsync m)
               => Handle
               -> SerialT m (Array Word8)
readFileStream = S.unfold (SIU.finallyIO (liftIO . hClose) FH.readChunks)

-- | Like 'readFileStream', except doesn't close the handle.
readFileStream' :: (MonadCatch m, MonadAsync m)
                => Handle
                -> SerialT m (Array Word8)
readFileStream' = S.unfold FH.readChunks


-- | Like 'copyFileStream', except for two file handles.
--
-- Both handles are closed automatically.
copyFileHandle :: (MonadCatch m, MonadAsync m, MonadMask m)
               => Handle  -- ^ copy from this handle, must be readable
               -> Handle  -- ^ copy to this handle, must be writable
               -> m ()
copyFileHandle fromHandle toHandle =
  copyFileStream (readFileStream fromHandle) toHandle

-- | Like 'copyFileHandle', except doesn't close the handles.
copyFileHandle' :: (MonadCatch m, MonadAsync m, MonadMask m)
                => Handle  -- ^ copy from this handle, must be readable
                -> Handle  -- ^ copy to this handle, must be writable
                -> m ()
copyFileHandle' fromHandle toHandle =
  copyFileStream' (readFileStream' fromHandle) toHandle


-- | Copy a stream to a file handle.
--
-- The handle is closed automatically after the stream is copied.
copyFileStream :: (MonadCatch m, MonadAsync m, MonadMask m)
               => SerialT m (Array Word8) -- ^ stream to copy
               -> Handle                  -- ^ file handle to copy to, must be writable
               -> m ()
copyFileStream stream handle' =
  (flip finally) (liftIO $ hClose handle') $ copyFileStream' stream handle'


-- | Like 'copyFileStream', except doesn't close the handle.
copyFileStream' :: (MonadCatch m, MonadAsync m, MonadMask m)
                => SerialT m (Array Word8) -- ^ stream to copy
                -> Handle                  -- ^ file handle to copy to, must be writable
                -> m ()
copyFileStream' stream handle' = S.fold (FH.writeChunks handle') stream


-- | Like 'copyFileStream', except with a lazy bytestring.
--
-- The handle is closed automatically after the bytestring is copied.
copyLBS :: (MonadCatch m, MonadAsync m, MonadMask m)
        => L.ByteString -- ^ lazy bytestring to copy
        -> Handle       -- ^ file handle to copy to, must be writable
        -> m ()
copyLBS lbs = copyFileStream (Lazy.toChunks lbs)


-- | Like 'copyLBS', except doesn't close the handle.
copyLBS' :: (MonadCatch m, MonadAsync m, MonadMask m)
         => L.ByteString -- ^ lazy bytestring to copy
         -> Handle       -- ^ file handle to copy to, must be writable
         -> m ()
copyLBS' lbs = copyFileStream' (Lazy.toChunks lbs)
