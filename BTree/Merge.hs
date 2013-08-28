{-# LANGUAGE TemplateHaskell, BangPatterns, GeneralizedNewtypeDeriving #-}

module BTree.Merge ( mergeTrees
                   , mergeLeaves
                   , sizedProducerForTree
                   ) where

import Prelude hiding (sum, compare)
import Control.Applicative
import Data.Foldable
import Data.Function (on)
import Control.Monad.State hiding (forM_)
import Data.Binary       
import Control.Lens
import Pipes
import Pipes.Interleave

import BTree.Types
import BTree.Builder
import BTree.Walk

-- | Merge trees' leaves taking ordered leaves from a set of producers.
-- 
-- Each producer must be annotated with the number of leaves it is
-- expected to produce. The size of the resulting tree will be at most
-- the sum of these sizes.
mergeLeaves :: (MonadIO m, Functor m, Binary k, Binary e)
            => (k -> k -> Ordering)          -- ^ ordering on keys
            -> (e -> e -> m e)               -- ^ merge operation on elements
            -> Order                         -- ^ order of merged tree
            -> FilePath                      -- ^ name of output file
            -> [(Size, Producer (BLeaf k e) m ())]   -- ^ producers of leaves to merge
            -> m ()
mergeLeaves compare append destOrder destFile producers = do
    let size = sum $ map fst producers
    fromOrderedToFile destOrder size destFile $
      merge (compare `on` key) doAppend (map snd producers)
  where doAppend (BLeaf k e) (BLeaf _ e') = BLeaf k <$> append e e'
        key (BLeaf k _) = k

-- | Merge several 'LookupTrees'
--
-- This is a convenience function for merging several trees already on
-- disk. For a more flexible interface, see 'mergeLeaves'.
mergeTrees :: (MonadIO m, Functor m, Binary k, Binary e)
           => (k -> k -> Ordering)   -- ^ ordering on keys
           -> (e -> e -> m e)        -- ^ merge operation on elements
           -> Order                  -- ^ order of merged tree
           -> FilePath               -- ^ name of output file
           -> [LookupTree k e]       -- ^ trees to merge
           -> m ()
mergeTrees compare append destOrder destFile trees = do
    mergeLeaves compare append destOrder destFile
    $ map sizedProducerForTree trees

-- | Get a sized producer suitable for 'mergeLeaves' from a 'LookupTree'
sizedProducerForTree :: (Monad m, Binary k, Binary e)
                     => LookupTree k e   -- ^ a tree
                     -> (Size, Producer (BLeaf k e) m ())
                                         -- ^ a sized Producer suitable for passing 
                                         -- to 'mergeLeaves'
sizedProducerForTree lt = (lt ^. ltHeader . btSize, void $ walkLeaves lt)
