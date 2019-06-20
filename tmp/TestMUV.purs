module TestMUV where

import Prelude

import Effect (Effect)
import Effect.Class (liftEffect)
import Effect.Console (log)

import Data.String (take)
import Data.Either (Either(..), either)
import Data.Tuple.Nested ((/\), type (/\))
import Data.Traversable (traverse_)

import Control.Monad.Except.Trans (ExceptT, runExceptT)

import FRP.Event (Event)
import FRP.Event as Event

import Debug.Trace as DT

import UUID (UUID)
import UUID as UUID

newtype Error = Error String

type Program a = Either Error a


data Msg
    = MsgOne
    | MsgTwo
    | Start
    | MakeUUID (UUID -> Msg)
    | Store UUID



derive newtype instance showError :: Show Error

instance showMsg :: Show Msg where
    show MsgOne = "MSG-ONE"
    show MsgTwo = "MSG-TWO"
    show Start = "START"
    show (Store uuid) = "STORE-UUID: " <> (take 5 $ show uuid)
    show (MakeUUID _) = "MAKE-UUID"


type EffectsToPerform = Array (Effect Msg)


runMUV
    :: forall model view
     . { event :: Event Msg, push :: Msg -> Effect Unit }
    -> Program model
    -> (Msg -> model -> Program model /\ EffectsToPerform)
    -> (Program model -> view)
    -> Effect (Event view)
runMUV { event : messages, push : pushMessage } init userUpdate userView = do
    let
        updates =
            Event.fold
                (\msg ( prog /\ _ ) ->
                    case prog of
                        Left err -> prog /\ []
                        Right model -> userUpdate msg model)
                messages
                (init /\ [])
    { event : views, push : pushView } <- Event.create
    _ <- Event.subscribe updates \progAndEffects ->
        performEffects pushMessage progAndEffects >>= pushView <<< userView
    pure views
    where
        performEffects
            :: (Msg -> Effect Unit)
            -> Program model /\ EffectsToPerform
            -> Effect (Program model)
        performEffects pushMsg (prog /\ effects) = do
            traverse_ ((=<<) pushMsg) effects
            pure prog


main :: Effect Unit
main = do
    { event : messages, push : pushMessage } <- Event.create
    views <- runMUV { event : messages, push : pushMessage } (pure "|") update view
    _ <- Event.subscribe views log
    pushMessage MsgOne
    pushMessage MsgTwo
    pushMessage MsgTwo
    pushMessage Start
    pure unit
    where
        update :: Msg -> String -> Program String /\ EffectsToPerform
        update msg model =
            case update' msg model of
                ( Left err /\ effects ) ->
                    pure ("(" <> show msg <> ")-" <> show err) /\ effects
                ( Right model' /\ effects ) ->
                    pure ("(" <> show msg <> ")-" <> model') /\ effects
        update' :: Msg -> String -> Program String /\ EffectsToPerform
        update' (MakeUUID f) model = pure model /\ [ f <$> UUID.new ]
        update' MsgTwo model = pure model /\ [ pure MsgOne ]
        update' Start model = pure model /\
            [ pure $ MakeUUID Store
            , pure $ MakeUUID Store
            , pure $ MakeUUID Store
            ]
        update' (Store uuid) model =
            pure ("<" <> show uuid <> ">-" <> model)
            /\ []
        update' _ model = pure model /\ []
        -- update msg m = m
        --     case model of
        --     model >>= \prev -> do
        --         uuid <- liftEffect UUID.new
        --         -- let _ = DT.spy "uuid" uuid
        --         pure $ "(" <> show msg <> ":" <> UUID.toString uuid <> ")-" <> prev
        view errOrModel =
            either (const "ERR") identity errOrModel
