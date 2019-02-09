module Rpd.Network
    ( Network(..)
    , Patch(..)
    , Node(..)
    , Inlet(..)
    , Outlet(..)
    , Link(..)
    , InletFlow(..), OutletFlow(..)
    , InletsFlow(..), OutletsFlow(..)
    , PushToInlet(..), PushToOutlet(..)
    , PushToProcess(..)
    -- FIXME: do not expose constructors, provide all the optics as getters
    , empty
    ) where

import Prelude (class Eq, (==), (&&), class Show, show, (<>))

import Data.List as List
import Data.List (List)
import Data.Map as Map
import Data.Set (Set)
import Data.Tuple.Nested (type (/\))

import Rpd.Def
import Rpd.Path
import Rpd.Util (type (/->), Canceler, Flow, PushableFlow, PushF)


-- data InletPFlow d = InletPFlow (PushableFlow d)
-- data OutletPFlow d = OutletPFlow (PushableFlow d)
-- data ProcessPFlow d = ProcessPFlow (PushableFlow (Int /\ d))

data InletFlow d = InletFlow (Flow d)
data InletsFlow d = InletsFlow (Flow (Int /\ d))
data PushToInlet d = PushToInlet (PushF d)
data PushToProcess d = PushToProcess (PushF (Int /\ d))
data OutletFlow d = OutletFlow (Flow d)
data OutletsFlow d = OutletsFlow (Flow (Int /\ d))
data PushToOutlet d = PushToOutlet (PushF d)


data Network d =
    Network
        { name :: String
        , patchDefs :: List (PatchDef d)
        }
        { patches :: PatchId /-> Patch d
        , nodes :: NodePath /-> Node d
        , inlets :: InletPath /-> Inlet d
        , outlets :: OutletPath /-> Outlet d
        , links :: LinkId /-> Link
        , cancelers ::
            { links :: LinkId /-> Array Canceler
            , nodes :: NodePath /-> Array Canceler
            , inlets :: InletPath /-> Array Canceler
            }
        }
data Patch d =
    Patch
        PatchId
        (PatchDef d)
        { nodes :: Set NodePath
        }
data Node d =
    Node
        NodePath -- (NodeDef d)
        (NodeDef d)
        { inlets :: Set InletPath
        , outlets :: Set OutletPath
        , inletsFlow :: InletsFlow d
        , outletsFlow :: OutletsFlow d
        , process :: PushToProcess d
        }
data Inlet d =
    Inlet
        InletPath
        (InletDef d)
        { flow :: InletFlow d
        , push :: PushToInlet d
        -- sources :: Set (DataSource d)
        }
data Outlet d =
    Outlet
        OutletPath
        (OutletDef d)
        { flow :: OutletFlow d
        }
data Link = Link OutletPath InletPath


empty :: forall d. String -> Network d
empty name =
    Network
        { name
        , patchDefs : List.Nil
        }
        { patches : Map.empty
        , nodes : Map.empty
        , inlets : Map.empty
        , outlets : Map.empty
        , links : Map.empty
        , cancelers :
            { links : Map.empty
            , inlets : Map.empty
            , nodes : Map.empty
            }
        }


instance eqPatch :: Eq (Patch d) where
    eq (Patch idA _ _) (Patch idB _ _) = (idA == idB)

instance eqNode :: Eq (Node d) where
    eq (Node pathA _ _) (Node pathB _ _) = (pathA == pathB)

instance eqInlet :: Eq (Inlet d) where
    eq (Inlet pathA _ _) (Inlet pathB _ _) = (pathA == pathB)

instance eqOutlet :: Eq (Outlet d) where
    eq (Outlet pathA _ _) (Outlet pathB _ _) = (pathA == pathB)

instance eqLink :: Eq Link where
    eq (Link outletA inletA) (Link outletB inletB) = (outletA == outletB) && (inletA == inletB)


instance showLink :: Show Link where
    show (Link outletPath inletPath) = "Link " <> show outletPath <> " -> " <> show inletPath
