module Rpd.Render.Minimal
    ( Renderer(..)
    , PushF(..)
    , make
    , once
    ) where


import Prelude

import Data.Either (either)

import Effect (Effect)

import FRP.Event (Event)
import FRP.Event as Event

import Rpd.API (RpdError) as R
import Rpd.API.Action (Action) as C
import Rpd.API.Action.Sequence (prepare) as ActionSeq
import Rpd.Network (Network) as R
import Rpd.Toolkit (Toolkit) as T


-- data RendererAction d rcmd
--     = Core (C.Action d)
--     | Renderer rcmd


-- data PushAction d rcmd =
--     PushAction (RendererAction d rcmd -> Effect Unit)


-- type RenderF d rcmd view
--     =  PushAction (RendererAction d rcmd -> Effect Unit)
--     -> Either R.RpdError (R.Network d)
--     -> view

data PushF d c n =
    PushF (C.Action d c n -> Effect Unit)


data Renderer d c n view
    = Renderer
        { first :: view
        , viewError :: R.RpdError -> view
        , viewValue :: R.Network d c n -> view
        }


neverPush :: forall d c n. PushF d c n
neverPush = PushF $ const $ pure unit


make
    :: forall d c n view
     . Renderer d c n view
    -> T.Toolkit d c n
    -> R.Network d c n
    -> Effect
        { first :: view
        , next :: Event view
        , push :: PushF d c n
        , stop :: Effect Unit
        }
make (Renderer { first, viewError, viewValue }) toolkit initialNW = do
    { event : views, push : pushView } <- Event.create
    { models, pushAction } <- ActionSeq.prepare initialNW toolkit
    stop <- Event.subscribe models (pushView <<< either viewError viewValue)
    pure
        { first
        , next : views
        , push : PushF pushAction
        , stop
        }


once
    :: forall d c n view
     . Renderer d c n view
    -> T.Toolkit d c n
    -> R.Network d c n
    -> view
once (Renderer { viewValue }) _ nw =
    viewValue nw


