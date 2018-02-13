module Rpd
    ( Id, PatchId, NodeId, ChannelId, InletId, OutletId, LinkId
    , App, Network, Patch, Node, Inlet, Outlet, Link
    , run
    , network, patch, node, inlet, outlet
    , addPatch, removePatch, select, deselect, enter, exit
    , addNode, addInlet, addOutlet
    -- , connect, disconnect
    -- , log--, logData
    ) where

import Control.Monad.Writer
import Control.Monad.Writer.Class
import Prelude

import Control.Monad.Eff (Eff)
import Control.Plus (empty)
import Data.Array ((:))
import Data.Array as Array
import Data.Function (apply, applyFlipped)
import Data.List as List
import Data.Map (Map, insert, delete, values)
import Data.Map as Map
import Data.Maybe (Maybe(..), fromMaybe)
import Data.Monoid (mempty)
import Data.Tuple (Tuple(..))
import Data.Unit as Unit
import Signal as S
import Signal.Channel as SC

-- Elm-style operators

infixr 0 apply as <|
infixl 1 applyFlipped as |>

type Id = String


type PatchId = Id
type NodeId = Id
type ChannelId = Id
type InletId = ChannelId
type OutletId = ChannelId
type LinkId = Id


-- `n` — node type
-- `c` — channel type
-- `a` — data type
-- `x` — error type

data NetworkMsg n c a x
    = Start
    | UpdatePatch (Array PatchMsg) (Patch n c a x)
    | ForgetPatch PatchId
    | UpdateNode (Array (NodeMsg n)) (Node n c a x)
    | ForgetNode NodeId
    | UpdateInlet (Array (InletMsg c a x)) (Inlet c a x)
    | ForgetInlet InletId
    | UpdateOutlet (Array (OutletMsg c)) (Outlet c a x)
    | ForgetOutlet OutletId
    | Connect NodeId NodeId OutletId InletId
    | Disconnect NodeId NodeId OutletId InletId
    | Stop


data PatchMsg
    = InitPatch String
    | SelectPatch
    | DeselectPatch
    | EnterPatch
    | ExitPatch
    | AddNode NodeId
    | RemoveNode NodeId


data NodeMsg n
    = InitNode n String
    | AddInlet InletId
    | RemoveInlet InletId
    | AddOutlet InletId
    | RemoveOutlet OutletId


data InletMsg c a x
    = InitInlet c String
    | ConnectToOutlet OutletId (FlowSignal a x)
    | DisconnectFromOutlet OutletId
    | HideInlet
    | RevealInlet


data OutletMsg c
    = InitOutlet c String
    | ConnectToInlet InletId
    | DisconnectFromInlet InletId


data Value a x
    = Bang
    | Data a
    | Error x
    | SysError String


-- type Actions n c a x = List.List (Action n c a x)


-- init = ( [] )

-- addNode :: NodeActions -> PatchActions

-- addInlet :: InletActions -> NodeActions

-- modifyInlet :: InletActions -> InletActions

-- ^ WRITER MONAD

-- etc...

-- run :: Actions n c a x ->


-- The signal where all the data flows: Bangs, data chunks and errors
-- type FlowChannel a x = SC.Channel (Value a x)
type FlowSignal a x = S.Signal (Value a x)

-- type TaggedFlowChannel a x = SC.Channel (Tuple InletId (Value a x))
type TaggedFlowSignal a x = S.Signal (Tuple InletId (Value a x))

-- The signal where the messages go
--type MsgChannel m = SC.Channel m
-- type MsgEmitter eff m = SL.Emitter eff m

-- The special channel for nodes which tracks the data flow through node inputs and outlets
-- type ProcessChannel a x = SC.Channel (Tuple (Map InletId (Value a x)) (Map OutletId (Value a x)))
type ProcessSignal a x = S.Signal (Tuple (Map InletId (Value a x)) (Map OutletId (Value a x)))


data Network n c a x =
    NetworkT
        { messages :: S.Signal (NetworkMsg n c a x)
        , patches :: Map PatchId (Patch n c a x)
        , nodes :: Map NodeId (Node n c a x)
        , inlets :: Map InletId (Inlet c a x)
        , outlets :: Map OutletId (Outlet c a x)
        , links ::  Map LinkId (Link a x)
        , selected :: Maybe PatchId
        , entered :: Array PatchId
        }


data Patch n c a x =
    PatchT
        { id :: PatchId
        , title :: String
        , nodes :: Array NodeId
        , links :: Array LinkId
        }


data Node n c a x =
    NodeT
        { id :: NodeId
        , title :: String
        , type :: Maybe n
        , inlets :: Array InletId
        , outlets :: Array OutletId
        , process :: Maybe (Map InletId (Value a x) -> Map OutletId (Value a x))
        }
        (ProcessSignal a x)


data Inlet c a x =
    InletT
        { id :: InletId
        , label :: String
        , type :: Maybe c
        }
        (FlowSignal a x)


data Outlet c a x =
    OutletT
        { id :: OutletId
        , label :: String
        , type :: Maybe c
        }
        (FlowSignal a x)


data Link a x = LinkT
        { id :: LinkId
        , inlet :: InletId
        , outlet :: OutletId
        }
        (FlowSignal a x)


newtype Actions' e a =
    Actions' (Eff (channel :: SC.CHANNEL | e) (SC.Channel a))

newtype TaggedActions' e a i  =
    TaggedActions'
        (Eff (channel :: SC.CHANNEL | e) (Tuple i (SC.Channel a)))


type NetworkActions' e n c a x = Actions' e (NetworkMsg n c a x)
type PatchActions' e = TaggedActions' e PatchMsg PatchId
type NodeActions' e n = TaggedActions' e (NodeMsg n) NodeId
type InletActions' e c a x = TaggedActions' e (InletMsg c a x) InletId
type OutletActions' e c = TaggedActions' e (OutletMsg c) OutletId

-- type NetworkActions' n c a x = Writer (Array (NetworkMsg n c a x)) (Network n c a x)
-- type PatchActions' n c a x = Writer (Array PatchMsg) (Patch n c a x)
-- type NodeActions' n c a x = Writer (Array (NodeMsg n)) (Node n c a x)
-- type InletActions' c a x = Writer (Array (InletMsg c a x)) (Inlet c a x)
-- type OutletActions' c a x = Writer (Array (OutletMsg c)) (Outlet c a x)
-- type LinkActions' c a x = (Link a x)


data Actions e n c a x
    = NetworkActions (NetworkActions' e n c a x)
    | PatchActions (PatchActions' e)
    | NodeActions (NodeActions' e n)
    | InletActions (InletActions' e c a x)
    | OutletActions (OutletActions' e c)
    -- | LinkActions (LinkActions' c a x)


-- API:


network' :: forall n c a x. Network n c a x
network' =
    NetworkT
        { messages : S.constant Start
        , patches : Map.empty
        , nodes : Map.empty
        , inlets : Map.empty
        , outlets : Map.empty
        , links :  Map.empty
        , selected : Nothing
        , entered : []
        }


patch' :: forall n c a x. Patch n c a x
patch' =
    PatchT
        { id : "test"
        , title : "Noname"
        , nodes : []
        , links : []
        }


node' :: forall n c a x. Node n c a x
node' =
    NodeT
        { id : "test"
        , title : "Unknown"
        , type : Nothing
        , inlets : []
        , outlets : []
        , process : Nothing
        }


inlet' :: forall c a x. Inlet c a x
inlet' =
    InletT
        { id: "test"
        , label : "foo"
        , type : Nothing
        }
        S.constant Bang


outlet' :: forall c a x. Outlet c a x
outlet' =
    OutletT
        { id: "test"
        , label : "foo"
        , type : Nothing
        }
        S.constant Bang


tellAndPerform
    :: forall subj msg
     . msg
    -> (msg -> subj -> subj)
    -> Writer (Array msg) subj
    -> Writer (Array msg) subj
tellAndPerform msg updateF w = do
    let
        (Tuple subj prevMsgs) = runWriter w
        joinedMsgs = msg : prevMsgs
    tell joinedMsgs
    writer (Tuple (updateF msg subj) joinedMsgs)


tellAndPerform'
    :: forall ssubj smsg tsubj tmsg
     . (ssubj -> tmsg)
    -> (tmsg -> tsubj -> tsubj)
    -> (ssubj -> smsg -> tmsg)
    -> Writer (Array smsg) ssubj
    -> Writer (Array tmsg) tsubj
    -> Writer (Array tmsg) tsubj
tellAndPerform' msgF updateF mapF srcW trgW = do
    let
        (Tuple srcSubj srcMsgs) = runWriter srcW
        (Tuple trgSubj _) = runWriter trgW
        trgMsg = msgF srcSubj
        trgMsgs = srcMsgs |> map (mapF srcSubj)
        joinedMsgs = trgMsg : trgMsgs
    tell joinedMsgs
    writer (Tuple (updateF trgMsg trgSubj) joinedMsgs)


sendMsg :: forall e a i. a -> TaggedActions' e a i -> TaggedActions' e a i
sendMsg msg src = TaggedActions' $ do
    TaggedActions' (Tuple _ chan) <- src
    SC.send chan msg
    pure $ Tuple id chan


getId :: forall e a i. TaggedActions' e a i -> i
getId (TaggedActions' (Tuple id _)) =
    id


taggedActions :: forall e a i. i -> a -> TaggedActions' e a i
taggedActions id default = TaggedActions' $ do
    chan <- SC.channel default
    pure $ Tuple id chan


network :: forall e n c a x. NetworkActions' e n c a x
network = tellAndPerform Start update network'


patch :: forall e. String -> PatchActions' e
patch title =
    taggedActions title (InitPatch title)


node :: forall e n. e n -> String -> NodeActions' e n
node type_ title =
    tellAndPerform (InitNode type_ title) updateNode node'


inlet :: forall e c a x. c -> String -> InletActions' e c a x
inlet type_ label =
    tellAndPerform (InitInlet type_ label) updateInlet inlet'


outlet :: forall e c. c -> String -> OutletActions' e c
outlet type_ label =
    tellAndPerform (InitOutlet type_ label) updateOutlet outlet'


addPatch :: PatchActions' e -> NetworkActions' e n c a x -> NetworkActions' e n c a x
addPatch (WriterT patchActions patch) networkActions =
    tellAndPerform' (UpdatePatch patchActions patch) update network


removePatch
    :: forall e n c a x
     . PatchActions' e
    -> NetworkActions' e n c a x
    -> NetworkActions' e n c a x
removePatch patchActions networkActions = do
    SC.send networkActions (ForgetPatch (getId patchActions))


select :: forall e. PatchActions' e -> PatchActions' e
select patchActions =
    sendMsg patchActions SelectPatch


deselect :: PatchActions' -> PatchActions'
deselect patchActions =
    tellAndPerform DeselectPatch updatePatch patch


enter :: PatchActions' -> PatchActions'
enter patchActions =
    tellAndPerform EnterPatch updatePatch patch


exit :: PatchActions' -> PatchActions'
exit patchActions =
    tellAndPerform ExitPatch updatePatch patchActions


addNode :: NodeActions' -> PatchActions' -> PatchActions'
addNode nodeActions patchActions =
    patchActions -- FIXME: implement
    -- tellAndPerform' (UpdateNode nodeActions node) updatePatch patch


removeNode
    :: forall e n
     . NodeActions' e n
    -> PatchActions' e
    -> PatchActions' e
removeNode nodeActions patchActions =
    patchActions -- FIXME: implement
    -- tellAndPerform' (ForgetInlet inlet.id) updateNode node


addInlet :: forall e n c a x. InletActions' c a x -> NodeActions' e n  -> NodeActions' e n
addInlet inletActions nodeActions =
    nodeActions -- FIXME: implement
    -- tellAndPerform (UpdateInlet inletActions inlet) updateNode nodeActions


removeInlet :: forall e n c a x. InletActions' e c a x -> NodeActions' e n -> NodeActions' e n
removeInlet inletActions nodeActions =
    nodeActions -- FIXME: implement
    -- tellAndPerform (ForgetInlet inlet.id) updateNode nodeActions


addOutlet :: forall e n c a x. OutletActions' e c a x -> NodeActions' e n -> NodeActions' e n
addOutlet outletActions nodeActions =
    nodeActions -- FIXME: implement
    -- tellAndPerform' (UpdateOutlet outletActions outlet) updateNode nodeActions


removeOutlet :: forall e n c. OutletActions' e c -> NodeActions' e n -> NodeActions' e n
removeOutlet outletAction nodeActions =
    nodeActions -- FIXME: implemeent
    -- do
    -- tellAndPerform'
    --     (\(OutletT outlet' _) -> ForgetOutlet outlet'.id)
    --     update
    --     (\outlet outletMsg -> UpdateOutlet [ outletMsg ] outlet)
    --     outletAction
    --     ?todo


-- Logic:

type Renderer n c a x eff = (Network n c a x -> Eff eff Unit)


data App nodes channels datatype error effect =
    App
        { network :: Maybe (Network nodes channels datatype error)
        -- , data :: SC.Channel
        --     { patch :: PatchId
        --     , node :: NodeId
        --     , inlet :: InletId
        --     , value :: Value datatype error
        --     }
        -- , data :: ProcessChannel datatype error
        , renderers :: Array (Renderer nodes channels datatype error effect)
        }


run :: forall n c a x eff
     . Array (NetworkMsg n c a x)
    -> (S.Signal (NetworkMsg n c a x) ->
        S.Signal (Eff (channel :: SC.CHANNEL | eff) Unit))
    -> Eff (channel :: SC.CHANNEL | eff) Unit
run messages f = void do
    c <- SC.channel Start
    let s = SC.subscribe c
    SC.send c (Array.head messages |> fromMaybe Stop)
    S.runSignal (f s)
    Array.foldM
        (\msgStack msg -> do
            SC.send c msg
            --fromMaybe [] (tail msgStack)
        )
        Unit.unit
        (Array.tail messages |> fromMaybe [ Stop ])
    pure s


initProcessChannel :: forall a x. ProcessSignal a x
initProcessChannel =
    S.constant (Tuple Map.empty Map.empty)


update :: forall n c a x. NetworkMsg n c a x -> Network n c a x -> Network n c a x
update Start network = network
update (UpdatePatch _ patch@(PatchT { id })) (NetworkT network'@{ patches }) =
    NetworkT network'
        { patches =
            patches |> Map.insert id patch }
update (ForgetPatch patchId) (NetworkT network'@{ patches }) =
    NetworkT network'
        { patches =
            patches |> Map.delete patchId }
update (UpdateNode _ node@(NodeT { id } _)) (NetworkT network'@{ nodes }) =
    NetworkT network'
        { nodes =
            nodes |> Map.insert id node }
update (ForgetNode nodeId) (NetworkT network'@{ nodes }) =
    NetworkT network'
        { nodes =
            nodes |> Map.delete nodeId }
update (Connect srcId dstId outletId inletId) network = network -- TODO: implement
update _ network = network -- FIXME : implement


updatePatch :: forall n c a x. PatchMsg -> Patch n c a x -> Patch n c a x
updatePatch (InitPatch title) patch = patch
updatePatch _ patch = patch -- FIXME : implement


updateNode :: forall n c a x. NodeMsg n -> Node n c a x -> Node n c a x
updateNode (InitNode type_ title) node = node
updateNode _ node = node -- FIXME : implement


updateInlet :: forall c a x. InletMsg c a x -> Inlet c a x -> Inlet c a x
updateInlet (InitInlet type_ label) inlet = inlet
updateInlet _ inlet = inlet -- FIXME : implement


updateOutlet :: forall c a x. OutletMsg c -> Outlet c a x -> Outlet c a x
updateOutlet (InitOutlet type_ label) outlet = outlet
updateOutlet _ outlet = outlet -- FIXME : implement


tagFlowSignal :: forall n c a x. Inlet c a x -> TaggedFlowSignal a x
tagFlowSignal (InletT inlet' flowSignal) =
    flowSignal S.~> (\val -> Tuple inlet'.id val)


-- make data items require a Show instance,
-- maybe even everywhere. Also create some type class which defines interfaces
-- for Node type and Channel type?
-- like accept() allow() etc.


instance showNetwork :: Show (Network n c a x) where
    show (NetworkT network) = "(Network \n"
        <> show (Map.size network.patches) <> " Patches\n"
        <> show (Map.size network.nodes) <> " Nodes\n"
        <> show (Map.size network.inlets) <> " Inlets\n"
        <> show (Map.size network.outlets) <> " Outlets\n"
        <> "Selected Patch: " <> show network.selected
        <> "Entered Patches: " <> show network.entered
        <> ")"


instance showPatch :: Show (Patch n c a x) where
    show (PatchT patch) = "(Patch " <> patch.id <> "\n"
        <> show (Array.length patch.nodes) <> " Nodes\n"
        <> show (Array.length patch.links) <> " Links\n"
        <> ")"


instance showNode :: Show n => Show (Node n c a x) where
    show (NodeT node _) = "(Node " <> node.id <> "\n"
        <> show node.type <> " "
        <> show (Array.length node.inlets) <> " Inlets\n"
        <> show (Array.length node.outlets) <> " Outlets\n"
        <> ")"


instance showInlet :: Show c => Show (Inlet c a x) where
    show (InletT inlet _) =
        "(Inlet " <> inlet.id <> " "
                  <> show inlet.type <> " "
                  <> inlet.label <> ")"


instance showOutlet :: Show c => Show (Outlet c a x) where
    show (OutletT outlet _) =
        "(Outlet " <> show outlet.type <> " "
                   <> outlet.id <> " "
                   <> outlet.label <> ")"


instance showNetworkMsg :: ( Show n, Show c ) => Show (NetworkMsg n c a x) where
    show Start = "Start"
    show (UpdatePatch _ patch) = "Update patch: " <> show patch
    show (ForgetPatch patchId) = "Forget patch: " <> patchId
    show (UpdateNode _ node) = "Update node: " <> show node
    show (ForgetNode nodeId) = "Forget node: " <> nodeId
    show (UpdateInlet _ inlet) = "Update inlet: " <> show inlet
    show (ForgetInlet inletId) = "Forget inlet: " <> inletId
    show (UpdateOutlet _ outlet) = "Update outlet: " <> show outlet
    show (ForgetOutlet outletId) = "Forget outlet: " <> outletId
    show (Connect srcNodeId dstNodeId outletId inletId) = "Connect:\n"
        <> "Node " <> srcNodeId <> " -> Node " <> dstNodeId <> "\n"
        <> "Outlet " <> outletId <> " -> Inlet " <> inletId
    show (Disconnect srcNodeId dstNodeId outletId inletId) = "Disconnect:\n"
        <> "Node " <> srcNodeId <> " -> Node " <> dstNodeId <> "\n"
        <> "Outlet " <> outletId <> " -> Inlet " <> inletId
    show Stop = "Stop"


instance showPatchMsg :: Show (PatchMsg) where
    show (InitPatch title) = "Init patch: " <> title
    show SelectPatch = "Select patch"
    show DeselectPatch = "Deselect patch"
    show EnterPatch = "Enter patch"
    show ExitPatch = "Exit patch"
    show (AddNode nodeId) = "Add node: " <> nodeId
    show (RemoveNode nodeId) = "Remove node:"  <> nodeId



instance showNodeMsg :: Show n => Show (NodeMsg n) where
    show (InitNode type_ title) = "Init node: " <> show type_ <> " " <> title
    show (AddInlet inletId) = "Add inlet: " <> inletId
    show (RemoveInlet inletId) = "Remove inlet:"  <> inletId
    show (AddOutlet outletId) = "Add outlet: " <> outletId
    show (RemoveOutlet outletId) = "Remove outlet:"  <> outletId


instance showInletMsg :: Show c => Show (InletMsg c a x) where
    show (InitInlet type_ label) = "Init inlet: " <> show type_ <> " " <> label
    show (ConnectToOutlet outletId _) = "Connect to outlet: " <> outletId
    show (DisconnectFromOutlet outletId) = "Disconnect from outlet:"  <> outletId
    show HideInlet = "Hide inlet"
    show RevealInlet = "Reveal inlet"


instance showOutletMsg :: Show c => Show (OutletMsg c) where
    show (InitOutlet type_ label) = "Init outlet: " <> show type_ <> " " <> label
    show (ConnectToInlet inletId) = "Connect to inlet: " <> inletId
    show (DisconnectFromInlet inletId) = "Disconnect from inlet:"  <> inletId


instance showValue :: ( Show a, Show x ) => Show (Value a x) where
    show Bang = "Bang"
    show (Data val) = "Data: " <> show val
    show (Error err) = "Error: " <> show err
    show (SysError msg) = "System Error: " <> msg


-- log :: forall n c a x. Network n c a x -> S.Signal String
-- log = logNetwork


-- logNetwork :: forall n c a x. Network n c a x -> S.Signal String
-- logNetwork (Network _ networkSignal) =
--     networkSignal S.~> show


logDataFlow :: forall n c a x. Show a => Show x => Network n c a x -> S.Signal String
logDataFlow (NetworkT network') =
    let
        allNodes = List.foldr
            (\(PatchT patch') allNodes ->
                allNodes <> values patch'.nodes) empty (values network'.patches)
        allDataSignals =
            List.foldr (\(NodeT node' dataSignal) allSignals ->
                allSignals
                    <> (map (\(InletT inlet' dataSignal) -> dataSignal) (values node'.inlets))
                    <> (map (\(OutletT outlet' dataSignal) -> dataSignal) (values node'.outlets))
            ) empty allNodes
    in
        case S.mergeMany allDataSignals of
            Just signal -> map show signal
            Nothing -> S.constant "Empty"
