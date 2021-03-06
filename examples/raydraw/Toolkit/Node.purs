module RayDraw.Toolkit.Node where

import Prelude

import Data.Maybe (Maybe(..))
import Data.Tuple.Nested ((/\))
import Noodle.Process (ProcessF(..)) as R
import Noodle.Render.Atom (class Atom) as R
import Noodle.Toolkit ((~<), (>~))
import Noodle.Toolkit (NodeDef, defineNode, withInlets, withOutlets) as T
import RayDraw.Toolkit.Channel (Channel(..))
import RayDraw.Toolkit.Render (renderRay)
import RayDraw.Toolkit.Value (Value(..), getColor1, getColor2, getColor3, rayPoints)

type NodeDef = T.NodeDef Value Channel


data Node
    = BangNode
    | NodeListNode
    | ProductPaletteNode
    | ColorNode
    | RayNode
    | RayPointsNode
    | DrawLogoNode
    | PreviewNode    



nodesForTheList :: Array Node
nodesForTheList =
    [ BangNode,
      ProductPaletteNode,
      ColorNode,
      RayNode,
      RayPointsNode,
      DrawLogoNode,
      PreviewNode
    ]


instance showNode :: Show Node where
    show BangNode = "bang"
    show NodeListNode = "node list"
    show ProductPaletteNode = "product palette"
    show ColorNode = "color"
    show RayNode = "ray"
    show RayPointsNode = "ray points"
    show DrawLogoNode = "draw logo"
    show PreviewNode = "preview"



{- BANG NODE -}

bangNode :: NodeDef
bangNode =
    T.defineNode
        (T.withInlets
            ~< "bang" /\ Channel)
        (T.withOutlets
            >~ "bang" /\ Channel)
        $ R.Process pure


{- PRODUCT PALETTE NODE -}

productPaletteNode :: NodeDef
productPaletteNode =
    T.defineNode
        (T.withInlets
            ~< "bang" /\ Channel)
        (T.withOutlets
            >~ "palette" /\ Channel)
        $ R.Withhold

{- COLOR NODE -}

colorNode :: NodeDef
colorNode =
    T.defineNode
        (T.withInlets
            ~< "bang" /\ Channel)
        (T.withOutlets
            >~ "color" /\ Channel)
        $ R.Withhold

{- RAY NODE -}

rayNode :: NodeDef
rayNode =
    T.defineNode
        (T.withInlets
            ~< "bang" /\ Channel)
        (T.withOutlets
            >~ "bang" /\ Channel)
        $ R.Withhold

{- RAY POINTS NODE -}

rayPointsNode :: NodeDef
rayPointsNode =
    T.defineNode
        (T.withInlets
            ~< "points" /\ Channel)
        (T.withOutlets
            >~ "points" /\ Channel)
        $ R.Process $ \receive -> 
            let
                send "points" = receive "points"
                send _ = Nothing
            in pure send                


{- DRAW LOGO NODE -}

drawLogoNode :: NodeDef
drawLogoNode =
    T.defineNode
        (T.withInlets
            ~< "color" /\ Channel
            ~< "bang" /\ Channel)
        (T.withOutlets
            >~ "logo" /\ Channel)
        $ R.Process
            $ \receive ->
                let
                    send "color" = receive "logo"
                    send _ = Nothing
                in pure send

{- PREVIEW NODE -}

previewNode :: NodeDef
previewNode =
    T.defineNode
        (T.withInlets
            ~< "bang" /\ Channel
            ~< "points" /\ Channel
            ~< "palette" /\ Channel)
        (T.withOutlets
            >~ "image" /\ Channel)
        $ R.Process
            $ \receive ->
               case (receive "bang") /\ (receive "points") /\ (receive "palette") of               
                    (Just Bang) /\ (Just (Points rayPoints)) /\ (Just (Palette palette))-> do
                        renderRay rayPoints (getColor1 palette) (getColor2 palette) (getColor3 palette)                                                               
                        pure $ const Nothing
                    _ -> pure $ const Nothing

           
instance nodeAtom :: R.Atom Node where
    labelOf = show
    uniqueIdOf = show
    debugInfoOf = show
