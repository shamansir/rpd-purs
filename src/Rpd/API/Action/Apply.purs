module Rpd.API.Action.Apply where

import Prelude
import Effect (Effect)

import Data.Maybe
import Data.String (take) as String
import Data.Either
import Data.Tuple.Nested ((/\), type (/\))
import Data.Sequence (empty, singleton, toUnfoldable) as Seq
import Data.Lens (view, setJust, set)
import Data.List (singleton) as List
import Data.Array ((:))
import Data.Foldable (class Foldable, foldr)
import Data.Traversable (traverse, traverse_)
import Data.Covered (Covered)
import Data.Covered (carry, fromEither, whenC, unpack) as Covered

import Debug.Trace as DT

import FRP.Event as E
import FRP.Event.Class (count) as E
import FRP.Event.Time as E

import FSM.Covered (follow, followJoin) as Covered
import FSM.Covered (fine, fineDo)

import Rpd.Util (PushableFlow(..), Canceler)
import Rpd.API as Api
import Rpd.API (uuidByPath, makePushableFlow)
import Rpd.API.Errors (RpdError)
import Rpd.API.Errors as Err
import Rpd.API.Action
    ( Action(..)
    , InnerAction(..)
    , RequestAction(..)
    , BuildAction(..)
    , DataAction(..)
    )
import Rpd.Network
import Rpd.Process
import Rpd.Optics
import Rpd.Path as Path
import Rpd.Toolkit
import Rpd.UUID as UUID


type Step d c n = Covered RpdError (Network d c n) /\ Array (Effect (Action d c n))


infixl 1 next as <∞>


-- TODO: make an operator?
-- TODO: close to Actions sequensing?
next :: forall d c n. Step d c n -> (Network d c n -> Step d c n) -> Step d c n
next = Covered.followJoin
    -- (nw /\ effs) <- stepA
    -- (nw' /\ effs') <- stepB nw
    -- pure $ nw' /\ (effs <> effs')


foldSteps
    :: forall d c n x f
     . Foldable f
    => Network d c n
    -> f x
    -> (x -> Network d c n -> Step d c n)
    -> Step d c n
foldSteps initNW foldable foldF =
    foldr
        (\x step -> step <∞> foldF x)
        ((Covered.carry $ initNW) /\ [])
        foldable


apply
    :: forall d c n
     . Toolkit d c n
    -> Action d c n
    -> Network d c n
    -> Step d c n
apply _ NoOp nw = fine nw
apply toolkit (Inner innerAction) nw = applyInnerAction toolkit innerAction nw
apply toolkit (Request requestAction) nw = applyRequestAction toolkit requestAction nw
apply toolkit (Build buildAction) nw = applyBuildAction toolkit buildAction nw
apply toolkit (Data dataAction) nw = applyDataAction toolkit dataAction nw


applyDataAction
    :: forall d c n
     . Toolkit d c n
    -> DataAction d c
    -> Network d c n
    -> Step d c n
applyDataAction _ Bang nw =
    fine nw
applyDataAction _ (GotInletData _ _) nw =
    fine nw
applyDataAction _ (GotOutletData _ _) nw =
    fine nw
applyDataAction _ (SendToInlet inlet d) nw = -- FIXME: either implement or get rid of
    pure nw /\ [ Api.sendToInlet inlet d >>= const $ pure NoOp ]
applyDataAction _ (SendToOutlet outlet d) nw = -- FIXME: either implement or get rid of
    pure nw /\ [ Api.sendToOutlet outlet d >>= const $ pure NoOp ]


applyRequestAction
    :: forall d c n
     . Toolkit d c n
    -> RequestAction d c n
    -> Network d c n
    -> Step d c n
applyRequestAction _ (ToAddPatch alias) nw =
    pure nw /\
        [ do
            uuid <- UUID.new
            let path = Path.toPatch alias
            pure $ Build $ AddPatch $
                Patch
                    (UUID.ToPatch uuid)
                    path
                    { nodes : Seq.empty
                    , links : Seq.empty
                    }
        ]
applyRequestAction tk@(Toolkit _ getDef) (ToAddNode patchPath alias n) nw =
    applyRequestAction tk (ToAddNodeByDef patchPath n $ getDef n) nw
applyRequestAction tk@(Toolkit _ getDef) (ToAddNextNode patchPath n) nw = do
    applyRequestAction tk (ToAddNextNodeByDef patchPath n $ getDef n) nw
applyRequestAction _ (ToAddNodeByDef patchPath alias n def) nw =
    pure nw /\
        let
            path = Path.nodeInPatch patchPath alias
            addInlet path (InletAlias alias /\ c) =
                Request $ ToAddInlet path alias c
            addOutlet path (OutletAlias alias /\ c) =
                Request $ ToAddOutlet path alias c
        in
            [ do
                uuid <- UUID.new
                flows <- Api.makeInletOutletsFlows
                let
                    PushableFlow pushToInlets inletsFlow = flows.inlets
                    PushableFlow pushToOutlets outletsFlow = flows.outlets
                    node =
                        Node
                            (UUID.ToNode uuid)
                            path
                            n
                            Withhold
                            { inlets : Seq.empty
                            , outlets : Seq.empty
                            , inletsFlow : InletsFlow inletsFlow
                            , outletsFlow : OutletsFlow outletsFlow
                            , pushToInlets : PushToInlets pushToInlets
                            , pushToOutlets : PushToOutlets pushToOutlets
                            }
                pure $ Batch
                        $  (List.singleton $ Build $ AddNode node)
                        <> (addInlet path <$> def.inlets)
                        <> (addOutlet path <$> def.outlets)
            , pure $ Request $ ToProcessWith path def.process
            {-
            , do
                flows <- Api.makeInletOutletsFlows
                let
                    PushableFlow pushToInlets inletsFlow = flows.inlets
                    PushableFlow pushToOutlets outletsFlow = flows.outlets
                pure $ Batch $ (addInlet path <$> def.inlets) <> (addOutlet path <$> def.outlets)
            -}
            ]
applyRequestAction _ (ToAddNextNodeByDef patchPath n def) nw = do
    pure nw /\
        [ do
            uuid <- UUID.new
            let shortHash = String.take 6 $ UUID.toRawString uuid
            pure $ Request $ ToAddNodeByDef patchPath shortHash n def
        ]
applyRequestAction tk (ToRemoveNode nodePath) nw = do
    nodeUuid <- uuidByPath UUID.toNode nodePath nw
    node <- view (_node nodeUuid) nw # note (Err.ftfs $ UUID.uuid nodeUuid)
    applyBuildAction tk (RemoveNode node) nw
applyRequestAction _ (ToAddInlet nodePath alias c) nw =
    pure nw /\
        [ do
            uuid <- UUID.new
            flow <- makePushableFlow
            let
                path = Path.inletInNode nodePath alias
                PushableFlow pushToInlet inletFlow = flow
                newInlet =
                    Inlet
                        (UUID.ToInlet uuid)
                        path
                        c
                        { flow : InletFlow inletFlow
                        , push : PushToInlet pushToInlet
                        }
            pure $ Build $ AddInlet newInlet
        ]
applyRequestAction _ (ToAddOutlet nodePath alias c) nw =
    pure nw /\
        [ do
            uuid <- UUID.new
            flow <- makePushableFlow
            let
                path = Path.outletInNode nodePath alias
                PushableFlow pushToOutlet outletFlow = flow
                newOutlet =
                    Outlet
                        (UUID.ToOutlet uuid)
                        path
                        c
                        { flow : OutletFlow outletFlow
                        , push : PushToOutlet pushToOutlet
                        }
            pure $ Build $ AddOutlet newOutlet
        ]
applyRequestAction tk (ToRemoveInlet inletPath) nw = do
    inletUuid <- uuidByPath UUID.toInlet inletPath nw
    inlet <- view (_inlet inletUuid) nw # note (Err.ftfs $ UUID.uuid inletUuid)
    applyBuildAction tk (RemoveInlet inlet) nw
applyRequestAction tk (ToRemoveOutlet outletPath) nw = do
    outletUuid <- uuidByPath UUID.toOutlet outletPath nw
    outlet <- view (_outlet outletUuid) nw # note (Err.ftfs $ UUID.uuid outletUuid)
    applyBuildAction tk (RemoveOutlet outlet) nw
applyRequestAction _ (ToProcessWith nodePath processF) nw = do
    pure nw /\
        [ do
            nodeUuid <- uuidByPath UUID.toNode nodePath nw
            node <- view (_node nodeUuid) nw # note (Err.ftfs $ UUID.uuid nodeUuid)
            pure $ Build $ ProcessWith node processF
        ]
applyRequestAction _ (ToConnect outletPath inletPath) nw = do
    outletUuid <- uuidByPath UUID.toOutlet outletPath nw
    outlet <- view (_outlet outletUuid) nw # note (Err.ftfs $ UUID.uuid outletUuid)
    inletUuid <- uuidByPath UUID.toInlet inletPath nw
    inlet <- view (_inlet inletUuid) nw # note (Err.ftfs $ UUID.uuid inletUuid)
    pure nw /\ [ do
        uuid <- UUID.new
        let
            (Outlet ouuid _ _ { flow : outletFlow' }) = outlet
            (Inlet iuuid _ _ { push : pushToInlet' }) = inlet
            (OutletFlow outletFlow) = outletFlow'
            (PushToInlet pushToInlet) = pushToInlet'
            newLink = Link (UUID.ToLink uuid) { outlet : ouuid, inlet : iuuid }
        canceler :: Canceler <- E.subscribe outletFlow pushToInlet
        pure $ Batch
            [ Build $ AddLink newLink
            , Inner $ StoreLinkCanceler newLink canceler
            ]
    ]
applyRequestAction _ (ToDisconnect outletPath inletPath) nw = do
    pure  $ nw /\ [ ]
    -- pure $ nw /\ [ Disconnect link ]
    -- pure $ TODO: perform and remove cancelers
applyRequestAction _ (ToSendToInlet inletPath d) nw = do
    inletUuid <- uuidByPath UUID.toInlet inletPath nw
    inlet <- view (_inlet inletUuid) nw # note (Err.ftfs $ UUID.uuid inletUuid)
    -- TODO: adapt / check the data with the channel instance? or do it in the caller?
    -- FIXME: use SendToInlet data action?
    pure nw /\ [ pure $ Data $ SendToInlet inlet d ]
applyRequestAction _ (ToSendToOutlet outletPath d) nw = do
    outletUuid <- uuidByPath UUID.toOutlet outletPath nw
    outlet <- view (_outlet outletUuid) nw # note (Err.ftfs $ UUID.uuid outletUuid)
    -- TODO: adapt / check the data with the channel instance? or do it in the caller?
    pure nw /\ [ pure $ Data $ SendToOutlet outlet d ]
applyRequestAction _ (ToSendPeriodicallyToInlet inletPath period fn) nw = do
    inletUuid <- uuidByPath UUID.toInlet inletPath nw
    inlet <- view (_inlet inletUuid) nw # note (Err.ftfs $ UUID.uuid inletUuid)
    -- TODO: adapt / check the data with the channel instance? or do it in the caller?
    pure $ nw /\ [ SendPeriodicallyToInletE inlet period fn ]
applyRequestAction _ (ToStreamToInlet inletPath event) nw = do
    inletUuid <- uuidByPath UUID.toInlet inletPath nw
    inlet <- view (_inlet inletUuid) nw # note (Err.ftfs $ UUID.uuid inletUuid)
    -- TODO: adapt / check the data with the channel instance? or do it in the caller?
    pure $ nw /\ [ StreamToInletE inlet event ]
applyRequestAction _ (ToStreamToOutlet outletPath event) nw = do
    outletUuid <- uuidByPath UUID.toOutlet outletPath nw
    outlet <- view (_outlet outletUuid) nw # note (Err.ftfs $ UUID.uuid outletUuid)
    -- TODO: adapt / check the data with the channel instance? or do it in the caller?
    pure $ nw /\ [ StreamToOutletE outlet event ]
applyRequestAction _ (ToSubscribeToInlet inletPath handler) nw = do
    inletUuid <- uuidByPath UUID.toInlet inletPath nw
    inlet <- view (_inlet inletUuid) nw # note (Err.ftfs $ UUID.uuid inletUuid)
    -- TODO: adapt / check the data with the channel instance? or do it in the caller?
    pure $ nw /\ [ SubscribeToInletE inlet handler ]
applyRequestAction _ (ToSubscribeToOutlet outletPath handler) nw = do
    outletUuid <- uuidByPath UUID.toOutlet outletPath nw
    outlet <- view (_outlet outletUuid) nw # note (Err.ftfs $ UUID.uuid outletUuid)
    -- TODO: adapt / check the data with the channel instance? or do it in the caller?
    pure $ nw /\ [ SubscribeToOutletE outlet handler ]
applyRequestAction _ (ToSubscribeToNode nodePath inletsHandler outletsHandler) nw = do
    nodeUuid <- uuidByPath UUID.toNode nodePath nw
    node <- view (_node nodeUuid) nw # note (Err.ftfs $ UUID.uuid nodeUuid)
    -- TODO: adapt / check the data with the channel instance? or do it in the caller?
    pure $ nw /\ [ SubscribeToNodeE node inletsHandler outletsHandler ]


applyBuildAction
    :: forall d c n
     . Toolkit d c n
    -> BuildAction d c n
    -> Network d c n
    -> Step d c n
applyBuildAction _ (AddPatch p) nw =
    fine $ Api.addPatch p nw
applyBuildAction _ (AddNode node) nw =
    (Covered.fromEither nw $ Api.addNode node nw) /\
        [ {--
            All subscriptions
        --}
        ]
applyBuildAction tk (RemoveNode node) nw = do
    (Covered.fromEither nw $ Api.removeNode node nw) /\ []
    {- FIXME: bring back, RemoveNode whould do that in order:
              remove inlets, remove outlets, so cancel their subscriptions
              then remove the node itself
    let (Node uuid _ _ _ _) = node
    inlets <- view (_nodeInlets uuid) nw # note (Err.ftfs $ UUID.uuid uuid)
    outlets <- view (_nodeOutlets uuid) nw # note (Err.ftfs $ UUID.uuid uuid)
    nw' /\ effs
        <- removeInlets inlets nw <∞> removeOutlets outlets
    nw'' <- Api.removeNode node nw'
    pure $ nw'' /\
        (effs <>
            [ CancelNodeSubscriptions node
            ])
    where
        removeInlets :: forall f. Foldable f => f (Inlet d c) -> Network d c n -> Step d c n
        removeInlets inlets inNW =
            foldSteps inNW inlets $ applyBuildAction tk <<< RemoveInlet
        removeOutlets :: forall f. Foldable f => f (Outlet d c) -> Network d c n -> Step d c n
        removeOutlets outlets inNW =
            foldSteps inNW outlets $ applyBuildAction tk <<< RemoveOutlet
    -}
applyBuildAction _ (RemoveInlet inlet) nw = do
    (Covered.fromEither nw $ Api.removeInlet inlet nw) /\
        [ {- CancelInletSubscriptions inlet
        , CancelNodeSubscriptions node
        , SubscribeNodeProcess node
        , InformNodeOnInletUpdates inlet node
        , SubscribeNodeUpdates node
        , SendActionOnInletUpdatesE inlet
        -} ]
applyBuildAction _ (RemoveOutlet outlet) nw = do
    (Covered.fromEither nw $ Api.removeOutlet outlet nw) /\
        [ {- CancelOutletSubscriptions outlet -} ]
applyBuildAction _ (ProcessWith node@(Node uuid _ _ _ _) processF) nw =
    let newNode = Api.processWith processF node
        nw' = nw # setJust (_node uuid) newNode
    in
        (Covered.carry $ nw') /\ [ {- SubscribeNodeProcess newNode -} ]
applyBuildAction _ (AddInlet inlet@(Inlet uuid path _ _)) nw = (do
    nodePath <- (Path.getNodePath $ Path.lift path) # note (Err.nnp $ Path.lift path)
    nodeUuid <- uuidByPath UUID.toNode nodePath nw
    node <- view (_node nodeUuid) nw # note (Err.ftfs $ UUID.uuid nodeUuid)
    nw' <- Api.addInlet inlet nw
    pure $ nw' /\
        [ {- CancelNodeSubscriptions node
        , SubscribeNodeProcess node
        , InformNodeOnInletUpdates inlet node
        , SubscribeNodeUpdates node
        , SendActionOnInletUpdatesE inlet
        -} ] ) # Covered.fromEither (nw /\ []) # Covered.unpack
applyBuildAction _ (AddOutlet outlet@(Outlet uuid path _ _)) nw = (do
    nodePath <- (Path.getNodePath $ Path.lift path) # note (Err.nnp $ Path.lift path)
    nodeUuid <- uuidByPath UUID.toNode nodePath nw
    node <- view (_node nodeUuid) nw # note (Err.ftfs $ UUID.uuid nodeUuid)
    nw' <- Api.addOutlet outlet nw
    pure $ nw' /\
        [ {- CancelNodeSubscriptions node
        , SubscribeNodeProcess node
        , InformNodeOnOutletUpdates outlet node
        , SubscribeNodeUpdates node
        , SendActionOnOutletUpdatesE outlet
        -} ]) # Covered.fromEither (nw /\ []) # Covered.unpack
applyBuildAction _ (Connect outlet inlet) nw = do
    pure nw /\ [ {- AddLinkE outlet inlet -} ]
applyBuildAction _ (AddLink link) nw =
    (Covered.fromEither nw $ Api.addLink link nw) /\ []


applyInnerAction
    :: forall d c n
     . Toolkit d c n
    -> InnerAction d c n
    -> Network d c n
    -> Step d c n
applyInnerAction _ (Do effectful) nw =
    fineDo nw $ effectful nw *> pure NoOp
applyInnerAction _ (StoreNodeCanceler (Node uuid _ _ _ _) canceler) nw =
    let
        curNodeCancelers = Api.getNodeCancelers uuid nw
        newNodeCancelers = canceler : curNodeCancelers
    in
        fine $ Api.storeNodeCancelers uuid newNodeCancelers nw
applyInnerAction _ (ClearNodeCancelers (Node uuid _ _ _ _)) nw =
    fine $ Api.clearNodeCancelers uuid nw
applyInnerAction _ (StoreInletCanceler (Inlet uuid _ _ _) canceler) nw =
    let
        curInletCancelers = Api.getInletCancelers uuid nw
        newInletCancelers = canceler : curInletCancelers
    in
        fine $ Api.storeInletCancelers uuid newInletCancelers nw
applyInnerAction _ (ClearInletCancelers (Inlet uuid _ _ _)) nw =
    fine $ Api.clearInletCancelers uuid nw
applyInnerAction _ (StoreOutletCanceler (Outlet uuid _ _ _) canceler) nw =
    let
        curOutletCancelers = Api.getOutletCancelers uuid nw
        newOutletCancelers = canceler : curOutletCancelers
    in
        fine $ Api.storeOutletCancelers uuid newOutletCancelers nw
applyInnerAction _ (ClearOutletCancelers (Outlet uuid _ _ _)) nw =
    fine $ Api.clearOutletCancelers uuid nw
applyInnerAction _ (StoreLinkCanceler (Link uuid _) canceler) nw =
    let
        curLinkCancelers = Api.getLinkCancelers uuid nw
        newLinkCancelers = canceler : curLinkCancelers
    in
        fine $ Api.storeLinkCancelers uuid newLinkCancelers nw
applyInnerAction _ (ClearLinkCancelers (Link uuid _)) nw =
    fine $ Api.clearLinkCancelers uuid nw


{-
performEffect -- TODO: move to a separate module
    :: forall d c n
     . Toolkit d c n -- TODO: check if it really needs toolkit
    -> (Action d c n -> Effect Unit)
    -> RpdEffect d c n
    -> Network d c n
    -> Effect Unit
performEffect _ pushAction (DoE effectful) nw = effectful nw
performEffect _ pushAction (AddPatchE alias) _ = MOVED
performEffect _ pushAction (AddNodeE patchPath nodeAlias n (NodeDef def)) _ = MOVED
performEffect toolkit pushAction (AddNextNodeE patchPath n (NodeDef def)) nw = MOVED
performEffect _ pushAction (ProcessWithE node processF) _ = do
    pushAction $ Build $ ProcessWith node processF
performEffect _ pushAction (AddLinkE outlet inlet) _ =  MOVED
performEffect _ pushAction (SubscribeNodeProcess node) nw = do
    canceler <- Api.setupNodeProcessFlow node nw
    pushAction $ Inner $ StoreNodeCanceler node canceler
performEffect _ pushAction (CancelNodeSubscriptions node@(Node uuid _ _ _ _)) nw = do
    _ <- Api.cancelNodeSubscriptions uuid nw
    pushAction $ Inner $ ClearNodeCancelers node
performEffect _ pushAction (CancelInletSubscriptions inlet@(Inlet uuid _ _ _ )) nw = do
    _ <- Api.cancelInletSubscriptions uuid nw
    pushAction $ Inner $ ClearInletCancelers inlet
performEffect _ pushAction (CancelOutletSubscriptions outlet@(Outlet uuid _ _ _ )) nw = do
    _ <- Api.cancelOutletSubscriptions uuid nw
    pushAction $ Inner $ ClearOutletCancelers outlet
performEffect _ pushAction (CancelLinkSubscriptions link@(Link uuid _)) nw = do
    _ <- Api.cancelLinkSubscriptions uuid nw
    pushAction $ Inner $ ClearLinkCancelers link
performEffect _ pushAction (AddInletE nodePath inletAlias c) _ = MOVED
performEffect _ pushAction (InformNodeOnInletUpdates inlet node) _ = do
    canceler <- Api.informNodeOnInletUpdates inlet node
    pushAction $ Inner $ StoreInletCanceler inlet canceler
performEffect _ pushAction (AddOutletE nodePath outletAlias c) _ = MOVED
performEffect _ pushAction (InformNodeOnOutletUpdates outlet node) _ = do
    canceler :: Canceler <- Api.informNodeOnOutletUpdates outlet node
    pushAction $ Inner $ StoreOutletCanceler outlet canceler
performEffect _ pushAction (SubscribeNodeUpdates node) _ = do
    canceler :: Canceler <-
        Api.subscribeNode node
            (const $ const $ const $ pure unit) -- FIXME: implement
            (const $ const $ const $ pure unit) -- FIXME: implement
    pushAction $ Inner $ StoreNodeCanceler node canceler
performEffect _ pushAction (SendToInletE inlet d) _ = do
    Api.sendToInlet inlet d
performEffect _ pushAction (SendToOutletE outlet d) _ =
    Api.sendToOutlet outlet d
performEffect _ pushAction (StreamToInletE inlet flow) _ = do
    canceler :: Canceler <- Api.streamToInlet inlet flow
    pushAction $ Inner $ StoreInletCanceler inlet canceler
performEffect _ pushAction (StreamToOutletE outlet flow) _ = do
    canceler :: Canceler <- Api.streamToOutlet outlet flow
    pushAction $ Inner $ StoreOutletCanceler outlet canceler
performEffect _ pushAction (SubscribeToInletE inlet handler) _ = do
    canceler :: Canceler <- Api.subscribeToInlet inlet handler
    pushAction $ Inner $ StoreInletCanceler inlet canceler
performEffect _ pushAction (SubscribeToOutletE outlet handler) _ = do
    canceler :: Canceler <- Api.subscribeToOutlet outlet handler
    pushAction $ Inner $ StoreOutletCanceler outlet canceler
performEffect _ pushAction
    (SubscribeToNodeE node inletsHandler outletsHandler) _ = do
    canceler :: Canceler <- Api.subscribeNode node inletsHandler outletsHandler
    pushAction $ Inner $ StoreNodeCanceler node canceler
performEffect _ pushAction (SendActionOnInletUpdatesE inlet@(Inlet _ path _ { flow })) _ = do
    let (InletFlow flow') = flow
    canceler :: Canceler <- E.subscribe flow' (pushAction <<< Data <<< GotInletData inlet)
    pushAction $ Inner $ StoreInletCanceler inlet canceler
performEffect _ pushAction (SendActionOnOutletUpdatesE outlet@(Outlet _ path _ { flow })) _ = do
    let (OutletFlow flow') = flow
    canceler :: Canceler <- E.subscribe flow' (pushAction <<< Data <<< GotOutletData outlet)
    pushAction $ Inner $ StoreOutletCanceler outlet canceler
performEffect _ pushAction (SendPeriodicallyToInletE inlet period fn) _ = do
    canceler :: Canceler <- Api.sendPeriodicallyToInlet inlet period fn
    pushAction $ Inner $ StoreInletCanceler inlet canceler
performEffect _ pushAction (SendPeriodicallyToOutletE outlet period fn) _ = do
    canceler :: Canceler <- Api.sendPeriodicallyToOutlet outlet period fn
    pushAction $ Inner $ StoreOutletCanceler outlet canceler
-}


-- apply'
--     :: forall d c n
--      . Action d c n
--     -> (Action d c n -> Effect Unit)
--     -> Toolkit d c n
--     -> R.Network d c n
--     -> R.Rpd (R.Network d c n)
-- apply' Bang pushAction _ nw =
--     Rpd.subscribeAllInlets onInletData nw
--         </> Rpd.subscribeAllOutlets onOutletData
--     where
--         onInletData inletPath d =
--             pushAction $ GotInletData inletPath d
--         onOutletData outletPath d =
--             pushAction $ GotOutletData outletPath d
-- apply' (AddPatch alias) pushAction _ nw =
--     R.addPatch alias nw
--         -- FIXME: subscribe the nodes in the patch
-- apply' (AddNode patchPath alias n) pushAction _ nw =
--     Rpd.addNode patchPath alias n nw
--         -- FIXME: `onInletData`/`onOutletData` do not receive the proper state
--         --        of the network this way (do they need it?), but they should
--         --        (pass the current network state in the Process function?)
--         </> Rpd.subscribeNode nodePath
--                 (onNodeInletData nodePath)
--                 (onNodeOutletData nodePath)
--     where
--         nodePath = P.nodeInPatch patchPath alias
--         (patchAlias /\ nodeAlias) = P.explodeNodePath nodePath
--         -- addModel = pure <<< ((/\) model)
--         onNodeInletData nodePath (inletAlias /\ _ /\ d) =
--             pushAction $ GotInletData (P.toInlet patchAlias nodeAlias inletAlias) d
--         onNodeOutletData nodePath (outletAlias /\ _ /\ d) =
--             pushAction $ GotOutletData (P.toOutlet patchAlias nodeAlias outletAlias) d
-- apply' (AddInlet nodePath alias c) pushAction _ nw =
--     let
--         inletPath = P.inletInNode nodePath alias
--         onInletData d =
--             pushAction $ GotInletData inletPath d
--     in
--         Rpd.addInlet nodePath alias c nw
--             </> Rpd.subscribeInlet inletPath (R.InletHandler onInletData)
-- apply' (AddOutlet nodePath alias c) pushAction _ nw =
--     let
--         outletPath = P.outletInNode nodePath alias
--         onOutletData d =
--             pushAction $ GotOutletData outletPath d
--     in
--         Rpd.addOutlet nodePath alias c nw
--             </> Rpd.subscribeOutlet outletPath (R.OutletHandler onOutletData)
-- apply' (Connect { inlet : inletPath, outlet : outletPath }) _ _ nw =
--     Rpd.connect outletPath inletPath nw
-- apply' (Disconnect { inlet : inletPath, outlet : outletPath }) _ _ nw =
--     Rpd.disconnectTop outletPath inletPath nw
-- apply' _ _ _ nw = pure nw

