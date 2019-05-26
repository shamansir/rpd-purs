module Rpd.Renderer.Html.DebugBox
    ( Model, init, update, view )
    where

import Prelude

import Data.Maybe (Maybe(..), fromMaybe)
import Data.List (List, (:))
import Data.List as List
import Data.Set (Set)
import Data.Set as Set
import Data.Lens (view, Lens') as L

import Spork.Html (Html)
import Spork.Html as H

import Rpd.Command as C
import Rpd.Network as R
import Rpd.Optics as L
import Rpd.UUID as R


type Model d =
    { lastCommands :: List (C.Command d)
    }


init :: forall d. Model d
init =
    { lastCommands : List.Nil
    }


update :: forall d. C.Command d -> R.Network d -> Model d -> Model d
update cmd nw model =
    model
        { lastCommands =
            cmd :
                (if List.length model.lastCommands < 5 then
                    model.lastCommands
                else
                    List.tail model.lastCommands # fromMaybe List.Nil
                )
        }


-- viewItems
--     :: forall uuid x a
--      . (Maybe x -> Html Unit)
--     -> (uuid -> L.Lens' a (Maybe x))
--     -> Set uuid
--     -> a
--     -> Array (Html Unit)
-- viewItems viewItem lens items nw =
--     viewItem
--         <$> (\uuid -> L.view (lens uuid) nw)
--         <$> (Set.toUnfoldable items :: Array uuid)


viewNetwork :: forall d. R.Network d -> Html Unit
viewNetwork nw@(R.Network { patches }) =
    H.div [ H.classes [ "network-debug" ] ]
        [ H.ul [] viewPatches
        -- [ H.ul [] (viewItems viewPatch ?wh patches nw)
        ]
    where
        viewPatches =
            viewPatch
                <$> (\patchUuid -> L.view (L._patch patchUuid) nw)
                <$>  (Set.toUnfoldable patches :: Array R.ToPatch)
        viewNodes nodes =
            viewNode
                <$> (\nodeUuid -> L.view (L._node nodeUuid) nw)
                <$> (Set.toUnfoldable nodes :: Array R.ToNode)
        viewInlets nodes =
            viewInlet
                <$> (\inletUuid -> L.view (L._inlet inletUuid) nw)
                <$> (Set.toUnfoldable nodes :: Array R.ToInlet)
        viewOutlets nodes =
            viewOutlet
                <$> (\outletUuid -> L.view (L._outlet outletUuid) nw)
                <$> (Set.toUnfoldable nodes :: Array R.ToOutlet)
        viewLinks nodes =
            viewLink
                <$> (\linkUuid -> L.view (L._link linkUuid) nw)
                <$> (Set.toUnfoldable nodes :: Array R.ToLink)
        viewPatch :: Maybe (R.Patch d) -> Html Unit
        viewPatch (Just (R.Patch uuid path nodes)) =
            H.li [ H.classes [ "patch-debug" ] ]
                [ H.ul []
                    $ viewNode
                        <$> (\nodeUuid -> L.view (L._node nodeUuid) nw)
                        <$> Set.toUnfoldable nodes
                ]
        viewPatch _ =
            H.li [ H.classes [ "patch-debug" ] ]
                [ H.text "Unknown patch" ]
        viewNode :: Maybe (R.Node d) -> Html Unit
        viewNode (Just node) = H.div [] []
        viewNode _ = H.div [] []
        viewInlet :: Maybe (R.Inlet d) -> Html Unit
        viewInlet (Just inlet) = H.div [] []
        viewInlet _ = H.div [] []
        viewOutlet :: Maybe (R.Outlet d) -> Html Unit
        viewOutlet (Just outlet) = H.div [] []
        viewOutlet _ = H.div [] []
        viewLink :: Maybe R.Link -> Html Unit
        viewLink (Just link) = H.div [] []
        viewLink _ = H.div [] []


viewModel :: forall d. Show d => Model d -> Html Unit
viewModel model =
    H.ul [ H.classes [ "commands-debug" ] ]
        $ List.toUnfoldable (viewCommand <$> model.lastCommands)
    where
        viewCommand :: C.Command d -> Html Unit
        viewCommand cmd =
            H.li [] [ H.text $ show cmd ]


view :: forall d. Show d => R.Network d -> Model d -> Html Unit
view nw model =
    H.div [ H.id_ "debug" ]
        [ H.div [ H.classes [ "network-debug" ] ]
            [ viewNetwork nw
            , viewModel model
            ]
        ]
