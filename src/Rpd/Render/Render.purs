module Rpd.Render
    ( UI(..)
    , UIState
    , Push
    , Message(..), Selection(..), ClickSubject(..)
    , isPatchSelected, isNodeSelected, isInletSelected, isOutletSelected
    , init, update, subscribeData
    ) where

import Prelude

import Control.Monad.Eff.Class (liftEff)
import Control.Monad.Eff.Console (CONSOLE, log)
import Data.Array ((:))
import Data.Array as Array
import Data.Map (Map(..))
import Data.Map as Map
import Data.Set (Set(..))
import Data.Set as Set
import Data.Foldable (foldr)
import Data.Maybe (Maybe(..), maybe, fromMaybe, isJust, isNothing)
import Data.Tuple.Nested ((/\), type (/\))
import Rpd as R
-- import Signal.Channel as SC


-- newtype UIState d =
--     UIState
type UIState d =
    { selection :: Selection
    , dragging :: Maybe R.NodePath
    , connecting :: Maybe R.OutletPath
    , lastInletData :: Map R.InletPath d
    , lastOutletData :: Map R.OutletPath d
    , areLinksChanged :: Boolean
    -- TODO: lastConnection: Maybe Link
    -- , prevCanceller :: Maybe (R.Canceller e)
    , lastMessages :: Array (Message d) -- FIXME: remove, make some friendly debugger or History plugin to track it
    , friendlyLog :: String -- FIXME: remove, as well as the above
    }


-- data Message d
--     = Init
--     | Select Selection -- TrySelecting Selection
--     | Deselect Selection
--     | ConnectFrom R.OutletPath
--     | ConnectTo R.InletPath
--     | DisconnectAt R.InletPath
--     | DataAtInlet R.InletPath d
--     | DataAtOutlet R.OutletPath d


-- TODO: Rename to UIEvent and produce more meaningful Messages out of it?
--       or maybe there should be some Rpd Command, like Message above,
--       which affects the state, also used for import and export,
--       and most of the UI Events could be converted to such and vice versa?
--       So Commands are the things which change Network and Messages are the things
--       which change UI State!
data Message d
    = Init
    | Click ClickSubject
    | DataAtInlet R.InletPath d
    | DataAtOutlet R.OutletPath d


data Selection -- TODO: allow multiple selections
    = SNone
    | SNetwork
    | SPatch R.PatchId
    | SNodes (Set R.NodePath)
    | SInlets (Set R.InletPath)
    | SOutlets (Set R.OutletPath)
    | SLinks (Set R.LinkId)


data ClickSubject
    = CSNetwork -- a.k.a. None / Background ?
    | CSPatch R.PatchId
    | CSNode R.NodePath
    | CSInlet R.InletPath
    | CSInletConnector R.InletPath
    | CSOutlet R.OutletPath
    | CSOutletConnector R.OutletPath
    | CSLink R.LinkId


data UI d = UI (UIState d) (R.Network d)


type Push d e = Message d -> R.RpdEff e Unit


init :: forall d. UIState d
init =
    { selection : SNone
    , dragging : Nothing
    , connecting : Nothing
    , lastInletData : Map.empty
    , lastOutletData : Map.empty
    , areLinksChanged : false
    , lastMessages : []
    , friendlyLog : ""
    }


update :: forall d. Message d -> UI d -> UI d
update msg (UI state network) =
    update' msg (UI state' network)
    where
        state' = state
            { areLinksChanged = false
            , friendlyLog = ""
            }


update' :: forall d. Message d -> UI d -> UI d
update' (DataAtInlet inletPath d) (UI state network) =
    UI state' network
    where
        state' =
            state
                { lastInletData =
                    Map.insert inletPath d state.lastInletData
                }
update' (DataAtOutlet outletPath d) (UI state network) =
    UI state' network
    where
        state' =
            state
                { lastOutletData =
                    Map.insert outletPath d state.lastOutletData
                }
update' (Click (CSOutletConnector outletPath)) (UI state network) =
    UI state' network
    where
        state' = state
            { connecting = Just outletPath
            , friendlyLog = "connect from " <> show outletPath
            }
update' (Click (CSInletConnector inletPath)) (UI state network)
    | isJust state.connecting =
    UI state' network'
    where
        state' =
            state
                { connecting = Nothing
                , areLinksChanged = true
                , friendlyLog = "connect " <> maybe "?" show state.connecting
                        <> " to " <> show inletPath
                }
        network'=
            case state.connecting of
                Just outletPath ->
                    fromMaybe network $ R.connect' outletPath inletPath network
                Nothing -> network
update' (Click (CSInletConnector inletPath)) (UI state network)
    | isNothing state.connecting =
    UI state' network'
    where
        network' = fromMaybe network $ R.disconnectLast inletPath network
        state' = state
            { areLinksChanged = true
            , friendlyLog = "disconnect last at " <> show inletPath
            }
update' (Click subject) (UI state network)
    | affectsSelection subject =
    UI state' network
    where
        newSelection = join state.selection subject
        state' =
            state
                { selection = newSelection
                , friendlyLog = "select " <> show newSelection
                }
update' _ ui = ui


subscribeData
    :: forall d e
     . (d -> R.InletPath -> R.RpdEff e Unit)
    -> (d -> R.OutletPath -> R.RpdEff e Unit)
    -> R.Network d
    -> R.Subscriber e
subscribeData inletHandler outletHandler network = do
    log "aaa"
    R.subscribeDataFlow inletHandler outletHandler network


-- TODO:
-- addLog :: forall d x. (Message d -> UI d -> x) -> Writer (Array (Message d)) x
-- addLog f =
--     \msg ui -> do
--         tell msg
--         pure $ f msg ui


-- areLinksChanged :: forall d. Message d -> Boolean
-- areLinksChanged (ConnectTo _) = true
-- areLinksChanged _ = false


affectsSelection :: ClickSubject -> Boolean
affectsSelection (CSInletConnector _) = false
affectsSelection (CSOutletConnector _) = false
affectsSelection _ = true


join :: Selection -> ClickSubject -> Selection
join _ CSNetwork = SNetwork
join SNone (CSPatch newPatch) = SPatch newPatch
join prevSelection (CSPatch newPatch) | isPatchSelected prevSelection newPatch = SNone
                                      | otherwise = SPatch newPatch
join SNone (CSNode newNode) = SNodes $ Set.singleton newNode
join prevSelection (CSNode newNode) | isNodeSelected prevSelection newNode = prevSelection -- remove node from selection
                                    | otherwise = prevSelection -- it depends on what was selected
join SNone (CSInlet newInlet) = SInlets $ Set.singleton newInlet
join SNone (CSOutlet newOutlet) = SOutlets $ Set.singleton newOutlet
join SNone (CSLink newLink) = SLinks $ Set.singleton newLink
join prevSelection _ = prevSelection


-- select :: forall d. Selection -> Selection -> Maybe Selection
-- select newSelection SNone = Just newSelection
-- select (SPatch newPatch) prevSelection   | isPatchSelected prevSelection newPatch = Just SNone
--                                          | otherwise = Just (SPatch newPatch)
-- select (SNode newNode) prevSelection     | isNodeSelected prevSelection newNode =
--                                                 Just (SPatch $ R.getPatchOfNode newNode)
--                                          | otherwise = Just (SNode newNode)
-- select (SInlet newInlet) prevSelection   | isInletSelected prevSelection newInlet =
--                                                 Just (SNode $ R.getNodeOfInlet newInlet)
--                                          | otherwise = Just (SInlet newInlet)
-- select (SOutlet newOutlet) prevSelection | isOutletSelected prevSelection newOutlet =
--                                                 Just (SNode $ R.getNodeOfOutlet newOutlet)
--                                          | otherwise = Just (SOutlet newOutlet)
-- select SNone _ = Just SNone
-- select _ _ = Nothing


someSatisfy :: forall a. (a -> Boolean) -> Set a -> Boolean
someSatisfy predicate set =
    foldr (\elm res -> res || predicate elm) false set


isPatchSelected :: Selection -> R.PatchId -> Boolean
isPatchSelected (SPatch selectedPatchId) patchId = selectedPatchId == patchId
isPatchSelected (SNodes nodePaths) patchId =
    someSatisfy (flip R.isNodeInPatch $ patchId) nodePaths
isPatchSelected (SInlets inletPaths) patchId =
    someSatisfy (flip R.isInletInPatch $ patchId) inletPaths
isPatchSelected (SOutlets outletPaths) patchId =
    someSatisfy (flip R.isOutletInPatch $ patchId) outletPaths
isPatchSelected _ _ = false


isNodeSelected :: Selection -> R.NodePath -> Boolean
isNodeSelected (SNodes nodePaths) nodePath = someSatisfy ((==) nodePath) nodePaths
isNodeSelected (SInlets inletPaths) nodePath =
    someSatisfy (flip R.isInletInNode $ nodePath) inletPaths
isNodeSelected (SOutlets outletPaths) nodePath =
    someSatisfy (flip R.isOutletInNode $ nodePath) outletPaths
isNodeSelected _ _ = false


isInletSelected :: forall d. Selection -> R.InletPath -> Boolean
isInletSelected (SInlets inletPaths) inletPath = someSatisfy ((==) inletPath) inletPaths
isInletSelected _ _ = false


isOutletSelected :: forall d. Selection -> R.OutletPath -> Boolean
isOutletSelected (SOutlets outletPaths) outletPath = someSatisfy ((==) outletPath) outletPaths
isOutletSelected _ _ = false


instance showSelection :: Show Selection where
    show SNone = "Nothing"
    show SNetwork = "Network"
    show (SPatch patchId) = show patchId
    show (SNodes nodePaths) = show nodePaths
    show (SInlets inletPaths) = show inletPaths
    show (SOutlets outletPaths) = show outletPaths
    show (SLinks linkIds) = show linkIds


instance showClickSubject :: Show ClickSubject where
    show CSNetwork = "Network"
    show (CSPatch patchId) = "Patch: " <> show patchId
    show (CSNode nodePath) = "Node: " <> show nodePath
    show (CSInlet inletPath) = "Inlet: " <> show inletPath
    show (CSOutlet outletPath) = "Outlet: " <> show outletPath
    show (CSLink linkId) = "Link: " <> show linkId
    show (CSInletConnector inletPath) = "InletCon: " <> show inletPath
    show (CSOutletConnector outletPath) = "OutletCon: " <> show outletPath


instance showUI :: (Show d) => Show (UI d) where
    show (UI s _)
        = "Selection: " <> show s.selection <>
        ", Dragging: " <> show s.dragging <>
        ", Connecting: " <> show s.connecting <>
        ", Inlets: " <> show s.lastInletData <>
        ", Outlets: " <> show s.lastOutletData <>
        ", Last events: " <> show (Array.reverse s.lastMessages) <>
        ", Friendly log: " <> s.friendlyLog


instance showMessage :: (Show d) => Show (Message d) where
    show Init = "Init"
    show (Click subject) = "Click " <> show subject
    show (DataAtInlet inletPath d) = "InletData " <> show inletPath <> " " <> show d
    show (DataAtOutlet outletPath d) = "OutletData " <> show outletPath <> " " <> show d
    --show _ = "?"
