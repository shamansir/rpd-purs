module Noodle.Node
    ( Node, Link
    , send, produce, connect, disconnect
    , make, move
    , inlet, outlet
    , inlets, outlets
    , inletSignal, outletSignal, outletSignalFlipped
    , inletsSignal, outletsSignal
    , (<|), (|>), (<~>), (<+), (+>), (++>)
    , consumer
    , dimensions
    )
    where

import Prelude

import Data.Array (mapMaybe) as Array
import Data.Maybe (Maybe(..))
import Data.Tuple (uncurry, curry, fst, snd, Tuple(..))
import Data.Tuple.Nested ((/\), type (/\))
import Data.Map as Map
import Data.Map.Extra (type (/->))
import Data.Traversable (traverse_, sequence)
import Data.Newtype (unwrap)
import Data.Functor (class Functor)
import Data.Functor.Invariant (class Invariant, imap)

import Effect (Effect)
import Effect.Ref (Ref)
import Effect.Ref as Ref

import Noodle.Node.Define (Def(..))
import Noodle.Node.Define as Def
import Noodle.Node.Shape (Shape)
import Noodle.Node.Shape as Shape
import Noodle.Channel.Shape as Channel

import Signal (Signal, (~>))
import Signal (foldp, runSignal, filter) as Signal
import Signal.Channel (Channel)
import Signal.Channel as Ch
import Signal.Channel.Extra as Ch



{- Node stores incoming and outgoing channels (`Signal.Channel`, not `Noodle.Channel`) of data of type `d` + any additional data -}
data Node d
    = Node
        d
        (Shape d)
        (Channel (String /\ d) /\ Channel (String /\ d))
        -- we can turn these into Signals if we either pass the function needed to send values and forget it,
        -- or create it ourselves and return it to be re-used by outer world.
        -- Signals will give us Functors etc.
        -- see: https://github.com/sharkdp/purescript-flare/blob/master/src/Flare.purs#L156


newtype Link = Link (Ref Boolean)


consumer :: String
consumer = "consume_"


make
    :: forall d
     . d
    -> Def d
    -> Effect (Node d)
make default (Def shape fn) = do
    inlets_chan <- Ch.channel (consumer /\ default)
    outlets_chan <- Ch.channel (consumer /\ default)
    let
        inlets = Ch.subscribe inlets_chan
        node = Node default shape (inlets_chan /\ outlets_chan)
        store ( inlet /\ d ) ( _ /\ map ) = inlet /\ (map # Map.insert inlet d)
        maps = inlets # Signal.foldp store (consumer /\ Map.empty)
        toReceive (last /\ fromInlets) = Def.Receive { last, fromInlets }
        fn_signal :: Signal (Effect (Def.Pass d))
        fn_signal = maps ~> toReceive ~> fn -- Do not call fn if not the `isHot` inlet triggered the calculation
        passFx :: Signal (Effect Unit)
        passFx = ((=<<) $ distribute outlets_chan) <$> fn_signal
    _ <- Signal.runSignal passFx
    pure node


-- TODO: makeFixedPoint --forall i o. (Emitter i -> { input :: Emitter i, output :: Emitter o }) -> Emitter o



infixl 5 Def.receive as <+
infixl 5 send as +>
infixl 5 produce as ++>
infixl 4 connect as <~>
infixl 4 inletSignal as |>
infixl 4 outletSignalFlipped as <|


-- fromFn' :: (d -> d) -> Node''' d

distribute :: forall d. Channel (String /\ d) -> Def.Pass d -> Effect Unit
distribute passTo (Def.Pass { toOutlets }) =
    traverse_ (Ch.send passTo) $ (Map.toUnfoldable toOutlets :: Array (String /\ d))


send :: forall d. Node d -> (String /\ d) -> Effect Unit
send node (inlet /\ d) =
    Ch.send (getInletsChannel node) $ inlet /\ d


produce :: forall d. Node d -> (String /\ d) -> Effect Unit
produce node (outlet /\ d) =
    Ch.send (getOutletsChannel node) $ outlet /\ d


-- TODO: sendToOutlet ??


connect :: forall d. (Node d /\ String) -> (Node d /\ String) -> Effect Link
connect (srcNode /\ srcOutlet) (dstNode /\ dstInlet) =
    let inlets_chan = getInletsChannel dstNode
    in do
        ref <- Ref.new true
        _ <- Signal.runSignal
                $ outletSignal srcNode srcOutlet
                ~> Tuple dstInlet
                -- ~> Ch.send inlets_chan
                ~> Ch.sendIfRef inlets_chan ref
        pure $ Link ref


disconnect :: Link -> Effect Unit
disconnect (Link ref) =
    ref # Ref.write false


attach :: forall d. Signal d -> String -> Node d -> Effect (Node d)
attach signal inlet node = pure node -- FIXME: TODO


getInletsChannel :: forall d. Node d -> Channel (String /\ d)
getInletsChannel (Node _ _ (inlets_chan /\ _)) = inlets_chan


getOutletsChannel :: forall d. Node d -> Channel (String /\ d)
getOutletsChannel (Node _ _ (_ /\ outlets_chan)) = outlets_chan


inletsSignal :: forall d. Node d -> Signal (String /\ d)
inletsSignal =
    Ch.subscribe <<< getInletsChannel


outletsSignal :: forall d. Node d -> Signal (String /\ d)
outletsSignal =
    Ch.subscribe <<< getOutletsChannel


inletSignal :: forall d. Node d -> String -> Signal d
inletSignal node name =
    Ch.subscribe (getInletsChannel node) ~> snd -- FIXME


outletSignal :: forall d. Node d -> String -> Signal d
outletSignal node _ =
    Ch.subscribe (getOutletsChannel node) ~> snd -- FIXME


outletSignalFlipped :: forall d. String -> Node d -> Signal d
outletSignalFlipped = flip outletSignal


getShape :: forall d. Node d -> Shape.Inlets d /\ Shape.Outlets d
getShape = unwrap <<< getShape'


getShape' :: forall d. Node d -> Shape d
getShape' (Node _ shape _) = shape


inlet :: forall d. String -> Node d -> Maybe (Channel.Shape d d)
inlet name = getShape' >>> Shape.inlet name


outlet :: forall d. String -> Node d -> Maybe (Channel.Shape d d)
outlet name = getShape' >>> Shape.outlet name


inlets :: forall d. Node d -> Array (String /\ (Channel.Shape d d))
inlets = getShape' >>> Shape.inlets


outlets :: forall d. Node d -> Array (String /\ (Channel.Shape d d))
outlets = getShape' >>> Shape.outlets


dimensions :: forall d. Node d -> Int /\ Int
dimensions (Node _ shape _) = Shape.dimensions shape


default :: forall d. Node d -> d
default (Node d _ _) = d


move :: forall a b. (a -> b) -> (b -> a) -> Node a -> Effect (Node b)
move f g (Node default shape (inChannel /\ outChannel)) =
    let
        movedShape = imap f g shape
        nextDefault = f default
    in do
        newInChannel <- Ch.channel (consumer /\ nextDefault)
        newOutChannel <- Ch.channel (consumer /\ nextDefault)
        _ <- Signal.runSignal $ (Ch.subscribe inChannel ~> ((<$>) f) ~> Ch.send newInChannel)
        _ <- Signal.runSignal $ (Ch.subscribe outChannel ~> ((<$>) f) ~> Ch.send newOutChannel)
        pure $ Node nextDefault movedShape (newInChannel /\ newOutChannel)