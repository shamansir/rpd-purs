module Noodle.Channel.Shape
    where


import Prelude ((>>>), (<<<), (>>=), (<$>), ($), (<*>), (=<<))


import Data.Maybe (Maybe(..))
-- import Noodle.Shape (Shape)

import Data.Functor (class Functor)
import Data.Functor.Invariant (class Invariant)


{- instance Invariant Shape where
    imap :: forall a b. (a -> b) -> (b -> a) -> Shape a -> Shape b
    imap toB toA (Shape { default, accept, isHot }) =
        Shape { default : toB default, accept : \b -> toB <$> accept (toA b), isHot } -}


data Shape a d =
    Shape
        { default :: a -- d?
        , accept :: a -> Maybe d -- TODO: remove, move to typeclass, can be used on `Node.connect` / `Node.send`
        --, adapt :: d -> d
        , isHot :: Boolean
        , hidden :: Boolean
        }


class IsShape a d where
    accept :: a -> Maybe d
    --default :: a


instance functorShape :: Functor (Shape a) where
    map :: forall a z d. (d -> z) -> Shape a d -> Shape a z
    map f (Shape { default, accept, isHot, hidden }) =
        Shape
            { default, isHot, hidden
            , accept : ((<$>) f) <$> accept
            }


transform :: forall a d. Shape a d -> a -> Maybe d
transform (Shape { accept }) = accept


-- TODO: Functor Shape ...


-- TODO: monoid :: Monoid m => Shape m


-- TODO: int :: Shape Int
-- TODO:int = {}


isHot :: forall a d. Shape a d -> Boolean
isHot (Shape def) = def.isHot


cold :: forall a d. Shape a d -> Shape a d
cold (Shape def) =
    Shape def { isHot = false }


hot :: forall a d. Shape a d -> Shape a d
hot (Shape def) =
    Shape def { isHot = true }


shape :: forall a d. a -> (a -> Maybe d) -> Shape a d
shape v accept =
    Shape
        { default : v
        , accept : accept
        , isHot : true
        , hidden : false
        }


acceptWith :: forall a d. (a -> Maybe d) -> Shape a d -> Shape a d
acceptWith f (Shape def) = Shape def { accept = f }


{- int :: Int -> Shape Int
int = shape -}


number :: forall d. Number -> (Number -> Maybe d) -> Shape Number d
number = shape


{- boolean :: Boolean -> Shape Boolean
boolean = shape -}

-- TODO

{-
foo :: forall a d. (a -> d) -> (d -> a) -> Shape a d -> Shape d d
foo f g (Shape { default, accept, isHot, hidden }) =
    Shape
        { default : f default
        , accept : g >>> accept -- <<< ?wh
        , isHot
        , hidden
        }

-}