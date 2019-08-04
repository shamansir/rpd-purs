module RpdTest.Structure
    ( spec ) where

import Prelude

import Data.Lens (view) as L
import Data.Maybe (Maybe(..))
import Data.Sequence as Seq

import Effect.Class (liftEffect)
import Effect.Class.Console (log)

import Test.Spec (Spec, describe, it, pending)
import Test.Spec.Assertions (shouldEqual, fail)

import Rpd.API as R
import Rpd.API.Action.Sequence ((</>), ErrorHandler(..), EveryStep(..))
import Rpd.API.Action.Sequence as Actions
import Rpd.API.Action.Sequence (init, addPatch, addNode) as R
import Rpd.Path
import Rpd.Optics as L
import Rpd.Network as N
import Rpd.Toolkit as T


data MyData
  = Bang

data Channel = Channel

data Node = Node


spec :: Spec Unit
spec =
  describe "structure" do

    it "constructing the empty network works" do
      _ <- liftEffect $
              Actions.run
                (T.empty "foo")
                (N.empty "foo")
                (ErrorHandler $ log <<< show) -- FIXME: fail here
                (EveryStep $ const $ pure unit)
                R.init
      pure unit

    describe "order of addition" do

      it "adding nodes to the patch preserves the order of addition" $ do
        _ <- liftEffect $
                Actions.run
                  (T.empty "foo")
                  (N.empty "foo")
                  (ErrorHandler $ log <<< show) -- FIXME: fail here
                  (EveryStep $ const $ pure unit) -- FIXME: check the actual order
                  $ R.init "network"
                    </> R.addPatch "patch"
                    </> R.addNode (toPatch "patch") "one" Node
                    </> R.addNode (toPatch "patch") "two" Node
                    </> R.addNode (toPatch "patch") "three" Node
        pure unit

        -- R.init "network"
        --   </> R.addPatch "patch"
        --   </> R.addNode (toPatch "patch") "one" Node
        --   </> R.addNode (toPatch "patch") "two" Node
        --   </> R.addNode (toPatch "patch") "three" Node
        --    #  withRpd \nw -> do
        --         case L.view (L._patchNodesByPath $ toPatch "patch") nw of
        --           Just nodes ->
        --             (nodes
        --               <#> \(R.Node _ (ToNode { node }) _ _ _) -> node)
        --               # Seq.toUnfoldable
        --               # shouldEqual [ "one", "two", "three" ]
        --           Nothing -> fail "patch wasn't found"

      it "adding inlets to the node preserves the order of addition" $ do
        R.init "network"
          </> R.addPatch "patch"
          </> R.addNode (toPatch "patch") "node" Node
          </> R.addInlet (toNode "patch" "node") "one" Channel
          </> R.addInlet (toNode "patch" "node") "two" Channel
          </> R.addInlet (toNode "patch" "node") "three" Channel
           #  withRpd \nw -> do
                case L.view (L._nodeInletsByPath $ toNode "patch" "node") nw of
                  Just inlets ->
                    (inlets
                      <#> \(R.Inlet _ (ToInlet { inlet }) _ _) -> inlet)
                      # Seq.toUnfoldable
                      # shouldEqual [ "one", "two", "three" ]
                  Nothing -> fail "node wasn't found"

      it "adding outlets to the node preserves the order of addition" $ do
        R.init "network"
          </> R.addPatch "patch"
          </> R.addNode (toPatch "patch") "node" Node
          </> R.addOutlet (toNode "patch" "node") "one" Channel
          </> R.addOutlet (toNode "patch" "node") "two" Channel
          </> R.addOutlet (toNode "patch" "node") "three" Channel
           #  withRpd \nw -> do
                case L.view (L._nodeOutletsByPath $ toNode "patch" "node") nw of
                  Just inlets ->
                    (inlets
                      <#> \(R.Outlet _ (ToOutlet { outlet }) _ _) -> outlet)
                      # Seq.toUnfoldable
                      # shouldEqual [ "one", "two", "three" ]
                  Nothing -> fail "node wasn't found"

      -- TODO: subPatches
