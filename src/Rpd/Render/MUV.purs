module Rpd.Render.MUV
    ( Renderer(..)
    , UpdateF
    , ViewF
    , PushMsg
    , once
    , run
    , run'
    , make
    , make'
    ) where

import Prelude

import Data.Maybe (Maybe(..))
import Data.Either (Either(..))
import Data.Tuple.Nested (type (/\), (/\))
import Data.Foldable (foldr)

import Effect (Effect)

import FRP.Event (Event)
import FRP.Event as Event

import Rpd (run) as R
import Rpd.API ((</>))
import Rpd.API (Rpd, RpdError) as R
import Rpd.API as Rpd
import Rpd.Path (nodePath, InletPath(..), OutletPath(..)) as R
import Rpd.Command as C
import Rpd.CommandApply as C
import Rpd.Network (Network) as R
import Rpd.Util (Canceler) as R
import Rpd.Render as R


data PushMsg msg = PushMsg (msg -> Effect Unit)
{- UpdateF:
   - gets message: either core one from Rpd.Render, or the custom one used by user in the MUV loop;
   - gets the latest MUV model paired with the latest network state;
   - and returns new MUV model with an array of messages to execute in the next loop, when needed;

   TODO: let user do effects in `UpdateF`
-}
type UpdateF d model msg
    =  msg
    -> (model /\ R.Network d)
    -> (model /\ Array msg)
{- ViewF:
   - gets the function allowing to push messages to the flow (for use in view handlers);
   - gets the latest MUV model paired with the latest network state;
   - and returns new view built using these states;
-}
type ViewF d model view msg =
    PushMsg msg -> Either R.RpdError (model /\ R.Network d) -> view


data Renderer d model view msg
    = Renderer
        { from :: view -- initial view
        , init :: model -- initial state
        , update :: UpdateF d model msg
        , view :: ViewF d model view msg
        }


-- core :: forall d m. Core.Message d -> Message d m
-- core = Core


-- custom :: forall d m. m -> Message d m
-- custom = Custom


extractRpd
    :: forall d model view msg
     . ViewF d model view msg
    -> PushMsg msg
    -> R.Rpd (model /\ R.Network d)
    -> Effect view
extractRpd view pushMsg rpd =
    R.run onError onSuccess rpd
    where
        onError err = view pushMsg $ Left err
        onSuccess res = view pushMsg $ Right res


{- render once -}
once
    :: forall d model view msg
     . Renderer d model view msg
    -> R.Rpd (R.Network d)
    -> Effect view
once (Renderer { view, init, update }) rpd =
    extractRpd view neverPush withModel
    where
        withModel = (/\) init <$> rpd
        neverPush = PushMsg $ const $ pure unit


{- Prepare the rendering cycle with internal message producer.
   Returns the first view and the event flow with
   all the next views.

   Actually the process starts just when user subscribes
   to the `next` views flow. `Event.subscribe` returns the
   canceler, so it is possible to stop the thing.
-}
make
    :: forall d model view msg
     . R.Rpd (R.Network d)
    -> Renderer d model view msg
    -> Effect
        { first :: view
        , next :: Event (Effect view)
        }
make nw renderer =
    Event.create >>=
        \event -> pure $ make' event nw renderer


{- Prepare the rendering cycle with custom message producer
   (so, the `Event` with the messages source and
   the function which pushes them to this flow).
   Returns the first view and the event flow with
   all the next views.

   Actually the process starts just when user subscribes
   to the `next` views flow. `Event.subscribe` returns the
   canceler, so it is possible to stop the thing.

   TODO: do not ask user for `event`, just pushing function.
-}
make'
    :: forall d model view msg
     . { event :: Event msg
       , push :: (msg -> Effect Unit)
       }
    -> R.Rpd (R.Network d)
    -> Renderer d model view msg
    -> { first :: view
       , next :: Event (Effect view)
       }
make'
    { event : messages, push : pushMessage }
    rpd
    (Renderer { from, init, view, update : userUpdate })
    = let
        updateFlow = Event.fold updatePipeline messages $ (/\) init <$> rpd
        viewFlow = viewer (PushMsg pushMessage) <$> updateFlow
    in
        { first : from
        , next : viewFlow
        }
    where
        -- C.apply
        update :: msg -> (model /\ R.Network d) -> PushMsg msg -> R.PushCmd d -> R.Rpd (model /\ R.Network d)
        update _ ( model /\ nw ) _ _ = pure (model /\ nw)
        updatePipeline
            :: msg
            -> R.Rpd (model /\ R.Network d)
            -> R.Rpd (model /\ R.Network d)
        updatePipeline msg rpd = rpd >>=
            \(model /\ nw) -> do
                -- perform update using core/simple Renderer and do some our things e.g. subscriptions
                model' /\ nw' <- update msg (model /\ nw) (PushMsg pushMessage) R.neverPush
                -- perform user update function, collect user messages
                -- TODO: allow `userUpdate` to be effectful
                let model'' /\ msgs = userUpdate msg $ model' /\ nw'
                -- apply user messages returned from previous line to the models
                model''' /\ nw'' <-
                    foldr updatePipeline (pure $ model'' /\ nw') msgs
                -- return all the latest states
                pure $ model''' /\ nw''
        viewer
            :: PushMsg msg
            -> R.Rpd (model /\ R.Network d)
            -> Effect view
        viewer pushMessage =
            extractRpd view pushMessage


{- Run the rendering cycle without any special handling
   (so the rendering results are omitted).

   Returns the canceler. -}
run
    :: forall d view model msg
     . R.Rpd (R.Network d)
    -> Renderer d view model msg
    -> Effect R.Canceler
run nw renderer =
    make nw renderer >>=
        \{ first, next } -> Event.subscribe next (pure <<< identity)


{- Run the rendering cycle with custom message producer
   (so, the `Event` with the messages source and
   the function which pushes them to this flow).
   Returns the first view and the event flow with
   all the next views.

   TODO: do not ask user for `event`, just pushing function.
-}
run'
    :: forall d view model msg
     . { event :: Event msg
       , push :: (msg -> Effect Unit)
       }
    -> R.Rpd (R.Network d)
    -> Renderer d view model msg
    -> Effect R.Canceler
run' event nw renderer =
    case make' event nw renderer of
        { first, next } -> Event.subscribe next (pure <<< identity)

