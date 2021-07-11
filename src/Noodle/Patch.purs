module Noodle.Patch where


import Noodle.Node

import Prelude ((#))

import Data.Maybe (Maybe)
import Data.Map as Map
import Data.Map.Extra (type (/->))
import Data.Tuple.Nested ((/\), type (/\))


type InletPath = String /\ String
type OutletPath = String /\ String


data Patch d =
    Patch
        (String /-> Node d)
        ((OutletPath /\ InletPath) /-> Link)


empty :: forall d. Patch d
empty = Patch Map.empty Map.empty


addNode :: forall d. String -> Node d -> Patch d -> Patch d
addNode name node (Patch nodes links) =
    Patch
        (nodes # Map.insert name node)
        links


nodes :: forall d. Patch d -> Array (String /\ Node d)
nodes (Patch nodes _) = nodes # Map.toUnfoldable


findNode :: forall d. String -> Patch d -> Maybe (Node d)
findNode name (Patch nodes _) = nodes # Map.lookup name


nodesCount :: forall d. Patch d -> Int
nodesCount (Patch nodes _) = Map.size nodes


linksCount :: forall d. Patch d -> Int
linksCount (Patch _ links) = Map.size links