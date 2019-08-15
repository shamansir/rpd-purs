module Rpd.API.Action.Sequence where

import Prelude

import Effect (Effect)

import Data.List (List(..), snoc)
import Data.Either
import Data.Tuple (fst)
import Data.Tuple.Nested ((/\), type (/\))
import Data.Traversable (traverse_)

import FRP.Event (Event)
import FRP.Event as Event

import Rpd.Network
import Rpd.API (RpdError)
import Rpd.API.Action
import Rpd.API.Action.Apply (Step, apply, performEffect)
import Rpd.Path as Path
import Rpd.Toolkit (Toolkit, NodeDef)


newtype ActionList d c n = ActionList (List (Action d c n))
newtype EveryStep d c n = EveryStep (Network d c n -> Effect Unit)
newtype EveryStep' d c n = EveryStep' (Either RpdError (Network d c n) -> Effect Unit)
newtype ErrorHandler = ErrorHandler (RpdError -> Effect Unit)
newtype LastStep d c n = LastStep (Network d c n -> Effect Unit)
newtype EveryAction d c n = EveryAction (Action d c n -> Effect Unit)


infixl 1 andThen as </>


init :: forall d c n. ActionList d c n
init = ActionList $ Nil


addPatch :: forall d c n. Path.Alias -> Action d c n
addPatch = Request <<< ToAddPatch


addNode :: forall d c n. Path.ToPatch -> Path.Alias -> n -> Action d c n
addNode patch alias n = Request $ ToAddNode patch alias n


addNodeByDef :: forall d c n. Path.ToPatch -> Path.Alias -> n -> NodeDef d c -> Action d c n
addNodeByDef patch alias n def = Request $ ToAddNodeByDef patch alias n def


addInlet :: forall d c n. Path.ToNode -> Path.Alias -> c -> Action d c n
addInlet node alias c = Request $ ToAddInlet node alias c


addOutlet :: forall d c n. Path.ToNode -> Path.Alias -> c -> Action d c n
addOutlet node alias c = Request $ ToAddOutlet node alias c


removeInlet :: forall d c n. Path.ToInlet -> Action d c n
removeInlet inlet = Request $ ToRemoveInlet inlet


removeOutlet :: forall d c n. Path.ToOutlet -> Action d c n
removeOutlet outlet = Request $ ToRemoveOutlet outlet


connect :: forall d c n. Path.ToOutlet -> Path.ToInlet -> Action d c n
connect outlet inlet = Request $ ToConnect outlet inlet


disconnect :: forall d c n. Path.ToOutlet -> Path.ToInlet -> Action d c n
disconnect outlet inlet = Request $ ToDisconnect outlet inlet


sendToInlet :: forall d c n. Path.ToInlet -> d -> Action d c n
sendToInlet inlet d = Request $ ToSendToInlet inlet d


sendToOutlet :: forall d c n. Path.ToOutlet -> d -> Action d c n
sendToOutlet outlet d = Request $ ToSendToOutlet outlet d


streamToInlet :: forall d c n. Path.ToInlet -> (Event d) -> Action d c n
streamToInlet inlet event = Request $ ToStreamToInlet inlet event


streamToOutlet :: forall d c n. Path.ToOutlet -> (Event d) -> Action d c n
streamToOutlet outlet event = Request $ ToStreamToOutlet outlet event


subscribeToInlet :: forall d c n. Path.ToInlet -> InletSubscription d -> Action d c n
subscribeToInlet inlet handler = Request $ ToSubscribeToInlet inlet handler


subscribeToOutlet :: forall d c n. Path.ToOutlet -> OutletSubscription d -> Action d c n
subscribeToOutlet outlet handler = Request $ ToSubscribeToOutlet outlet handler


subscribeToNode
    :: forall d c n
     . Path.ToNode
    -> NodeInletsSubscription d
    -> NodeOutletsSubscription d
    -> Action d c n
subscribeToNode node inletsHandler outletsHandler =
    Request $ ToSubscribeToNode node inletsHandler outletsHandler


do_ :: forall d c n. (Perform d c n) -> Action d c n
do_ f = Inner $ Do f


pass :: forall d c n. EveryStep d c n
pass = EveryStep $ const $ pure unit


prepare_
    :: forall model action effect
     . model
    -> (action -> model -> Either RpdError (model /\ Array effect))
    -> ((action -> Effect Unit) -> effect -> model -> Effect Unit)
    -> Effect
        { models :: Event (Either RpdError model)
        , actions :: Event action
        , pushAction :: action -> Effect Unit
        , stop :: Effect Unit
        }
prepare_ initialModel apply performEff = do
    { event : actions, push : pushAction } <- Event.create
    let
        (updates :: Event (Either RpdError (model /\ Array effect))) =
            Event.fold
                (\action step ->
                    case step of
                        Left err -> Left err
                        Right ( model /\ _ ) -> apply action model
                )
                actions
                (pure $ initialModel /\ [])
        (models :: Event (Either RpdError model))
            = ((<$>) fst) <$> updates
    stop <- Event.subscribe updates \step ->
        case step of
            Left err -> pure unit
            Right (model /\ effects) ->
                traverse_ (\eff -> performEff pushAction eff model) effects
    pure { models, pushAction, stop, actions }


prepare
    :: forall d c n
     . Network d c n
    -> Toolkit d c n
    -> Effect
        { models :: Event (Either RpdError (Network d c n))
        , actions :: Event (Action d c n)
        , pushAction :: Action d c n -> Effect Unit
        , stop :: Effect Unit
        }
prepare nw toolkit = prepare_ nw (apply toolkit) (performEffect toolkit)


run
    :: forall d c n
     . Toolkit d c n
    -> Network d c n
    -> ErrorHandler
    -> EveryStep d c n
    -> ActionList d c n
    -> Effect Unit
run toolkit initialNW (ErrorHandler onError) (EveryStep everyStep) (ActionList actionList) = do
    { models, pushAction } <- prepare initialNW toolkit
    _ <- Event.subscribe models $ either onError everyStep
    _ <- traverse_ pushAction actionList
    pure unit


run'
    :: forall d c n
     . Toolkit d c n
    -> Network d c n
    -> EveryStep' d c n
    -> ActionList d c n
    -> Effect Unit
run' toolkit initialNW (EveryStep' everyStep) (ActionList actionList) = do
    { models, pushAction } <- prepare initialNW toolkit
    _ <- Event.subscribe models everyStep
    _ <- traverse_ pushAction actionList
    pure unit


run_
    :: forall d c n
     . Toolkit d c n
    -> Network d c n
    -> ErrorHandler
    -> LastStep d c n
    -> ActionList d c n
    -> Effect Unit
run_ toolkit initialNW (ErrorHandler onError) (LastStep lastStep) (ActionList actionList) = do
    { models, pushAction } <- prepare initialNW toolkit
    _ <- Event.subscribe models $ either onError $ const $ pure unit
    _ <- traverse_ pushAction actionList
    pushAction $ Inner $ Do lastStep
    pure unit


runTracing
    :: forall d c n
     . Toolkit d c n
    -> Network d c n
    -> ErrorHandler
    -> EveryAction d c n
    -> ActionList d c n
    -> Effect Unit
runTracing toolkit initialNW (ErrorHandler onError) (EveryAction everyAction) (ActionList actionList) = do
    { pushAction, actions, models } <- prepare initialNW toolkit
    _ <- Event.subscribe models $ either onError $ const $ pure unit
    _ <- Event.subscribe actions everyAction
    _ <- traverse_ pushAction actionList
    pure unit


andThen :: forall d c n. ActionList d c n -> Action d c n -> ActionList d c n
andThen (ActionList arr) msg = ActionList (arr `snoc` msg)