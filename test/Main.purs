module Test.Main where

import Prelude

import Data.Function (apply, applyFlipped)
import Data.Time.Duration as Duration

import Control.Monad.Aff (Aff, delay, forkAff)
import Control.Monad.Eff (Eff)
import Control.Monad.Eff.Class (liftEff)
import Control.Monad.Eff.Ref (REF)

import Test.Spec (pending, describe, it)
import Test.Spec.Assertions (shouldEqual)
import Test.Spec.Reporter.Console (consoleReporter)
import Test.Spec.Runner (RunnerEffects, run)

import Signal as S
import Signal.Channel as SC
import Signal.Time (debounce)

import Test.Signal (expect')

import Rpd as R

infixr 0 apply as <|
infixl 1 applyFlipped as |>

data MyNodeType = SumNode | CustomNode
data MyChannelType = NumberChannel | StringChannel

main :: forall eff. Eff (RunnerEffects ( ref :: REF, channel :: SC.CHANNEL | eff )) Unit
main = run [consoleReporter] do
  describe "Rpd" do
    describe "Running the application" do
      it "runs with provided network structure" do
        let
          app = R.run [] do
            let
              myPatch = R.patch "MyPatch"
              sumNode = R.node SumNode
              inletA = R.getInlet "a" sumNode
              inletB = R.getInlet "b" sumNode
              myCustomNode =
                R.node CustomNode "Custom"
                  |> R.addInlet (R.inlet NumberChannel "a" |> R.allow
                      [ StringChannel fromString ])
                  |> R.addInlet (R.inlet NumberChannel "b" |> default 10)
                  |> R.addOutlet (R.outlet NumberChannel "out")
                  |> R.process (\inlets -> { out: inlets.a * inlets.b })
            inletA |> R.send 10 |> R.send 20
            inletB |> R.send 10 |> R.send 10 |> R.send 5
            myCustomNode |> R.getInlet "a" |> R.send "12" |> R.send 11
            myCustomNode |> R.getOutlet "out" |> R.connect (sumNode |> getInlet "a")
            myPatch |> R.addNode R.sumNode
            myCustomNode |> R.getInlet "b" |> R.send 13
            myNetwork <- network |> R.addPatch myPatch
            S.runSignal (map show myNetwork.messages S.~> log)
            pure myNetwork
        true `shouldEqual` true

  -- describe "purescript-spec" do
  --   describe "Attributes" do
  --     it "awesome" do
  --       let isAwesome = true
  --       isAwesome `shouldEqual` true
  --     pending "feature complete"
  --   describe "Features" do
  --     it "runs in NodeJS" $ pure unit
  --     it "runs in the browser" $ pure unit
  --     it "supports streaming reporters" $ pure unit
  --     it "supports async specs" do
  --       delay (Duration.Milliseconds 100.0)
  --       res <- pure "Alligator"
  --       res `shouldEqual` "Alligator"
  --     it "is PureScript 0.10.x compatible" $ pure unit
  --     it "tests signals"
  --       $ expect' (S.constant "lol") ["lol"]
  --     it "tests async signals" $ do
  --       chan <- liftEff $ SC.channel 0
  --       let sig = debounce 10.0 $ SC.subscribe chan
  --           send' = liftEff <<< SC.send chan
  --       _ <- forkAff $ expect' sig [0,2,4]
  --       wait 20.0
  --       send' 1
  --       wait 5.0
  --       send' 2
  --       wait 20.0
  --       send' 3
  --       wait 5.0
  --       send' 4
  --       wait 20.0



wait :: forall e. Number -> Aff e Unit
wait t = do
  delay (Duration.Milliseconds t)
  pure unit
