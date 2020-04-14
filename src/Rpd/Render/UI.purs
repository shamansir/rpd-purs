module Rpd.Render.UI
    ( UI, CoveredUI
    , make, run
    , imapModel, imapAction, imapError
    ) where

import Prelude

import Effect (Effect)

import Data.Either (Either(..))
import Data.Tuple.Nested ((/\), type (/\))
import Data.Maybe (Maybe(..))

import FRP.Event (Event)
import FRP.Event as Event

import Data.Covered (Covered, recover, inject, hasError, cover', mapError)

import FSM (FSM)
import FSM (run, run', make, imapModel, imapAction) as FSM
import Data.Foldable (class Foldable)


import Rpd.Network (Network) as R
-- import Rpd.API as R
import Rpd.API.Action (Action) as Core
import Rpd.API.Action.Apply (apply) as Core
import Rpd.API.Action.Sequence (make) as ActionSeq
import Rpd.API.Errors (RpdError) as R
import Rpd.Toolkit as T
import Rpd.Util (Canceler)



data UI action model view = UI (FSM action model) (model -> view)


type CoveredUI error action model view = UI action (Covered error model) view


make
    :: forall action model view
     . (action -> model -> model /\ Effect action)
    -> (model -> view)
    -> UI action model view
make updateF viewF =
    UI (FSM.make updateF) viewF


run
    :: forall action model view f
     . DoNothing action
    => Foldable f
    => UI action model view
    -> view
    -> model
    -> f action
    -> Effect
        { next :: Event view
        , push :: action -> Effect Unit
        , stop :: Canceler
        }
run (UI fsm viewF) view model actions = do
    { event : views, push : pushView } <- Event.create
    { pushAction, stop } <- FSM.run' fsm model (pushView <<< viewF) actions
    pure
        { next : views
        , push : pushAction
        , stop
        }


imapModel
    :: forall action modelA modelB view
     . (modelA -> modelB)
    -> (modelB -> modelA)
    -> UI action modelA view
    -> UI action modelB view
imapModel mapAToB mapBToA (UI fsm viewF) =
    UI
        (fsm # FSM.imapModel mapAToB mapBToA)
        (viewF <<< mapBToA)


imapAction
    :: forall actionA actionB model view
     . (actionA -> actionB)
    -> (actionB -> actionA)
    -> UI actionA model view
    -> UI actionB model view
imapAction mapAToB mapBToA (UI fsm viewF) =
    UI
        (fsm # FSM.imapAction mapAToB mapBToA)
        viewF


imapError
    :: forall errorA errorB action model view
     . (errorA -> errorB)
    -> (errorB -> errorA)
    -> CoveredUI errorA action model view
    -> CoveredUI errorB action model view
imapError mapAToB mapBToA =
    imapModel (mapError mapAToB) (mapError mapBToA)


once
    :: forall action model view
     . UI action model view
    -> model
    -> view
once (UI _ viewF) model = viewF model
