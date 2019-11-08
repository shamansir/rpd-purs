module Example.Toolkit.OnCanvas where

import Prelude

import Math (pi) as Math
import Data.Array (catMaybes) as Array

import Graphics.Canvas

import Effect (Effect)

import Example.Toolkit.Value
import Example.Toolkit.Value (Value(..)) as V

import Data.Traversable (traverse_, for_)
import Data.Spread (run) as Spread

class OnCanvas x where
    apply :: x -> Context2D -> Effect Unit


instance drawOnCanvas :: OnCanvas DrawOp where
    apply (Ellipse a b) ctx = do
        withContext ctx $ do
            -- -- scale ctx { scaleX : 1.0, scaleY : b / a }
            -- _ <- DT.spy "drawing" $ pure unit
            -- setFillStyle ctx "#000000"
            -- fillText ctx ("AAAAAAA") 40.0 20.0
            beginPath ctx
            arc ctx
                { x : 0.0, y : 0.0
                , radius : a
                , start : 0.0
                , end : 2.0 * Math.pi
                }
            closePath ctx
        fill ctx
        stroke ctx
    apply (Rect w h) ctx = do
        rect ctx { x : 0.0, y : 0.0, width : w, height : h }
        fill ctx
        stroke ctx


instance styleOnCanvas :: OnCanvas StyleOp where
    apply (Fill fill) ctx =
        setFillStyle ctx $ show fill
    apply (Stroke color w) ctx = do
        setStrokeStyle ctx $ show color
        setLineWidth ctx w


instance transformOnCanvas :: OnCanvas TransformOp where
    apply (Move x y) ctx =
        translate ctx { translateX : x, translateY : y }
    apply (Scale x y) ctx = do
        scale ctx { scaleX : x, scaleY : y }


instance instructionOnCanvas :: OnCanvas Instruction where
    apply NoOp _ = pure unit
    apply (Draw draw) ctx = apply draw ctx
    apply (Style style) ctx = apply style ctx
    apply (Transform transform) ctx = apply transform ctx


instance valueOnCanvas :: OnCanvas Value where
    apply Bang ctx =
        fillText ctx "●" 0.0 0.0
    apply (Numerical n) ctx =
        fillText ctx (show n) 0.0 0.0
    apply (V.Color color) ctx = do
        fillText ctx (show color) 0.0 0.0
        setFillStyle ctx (show color)
        fillPath ctx $ do
            moveTo ctx 10.0 10.0
            lineTo ctx 20.0 20.0
            lineTo ctx 10.0 20.0
            closePath ctx
    apply (Apply instruction) ctx =
        apply instruction ctx
    apply (Pair instA instB) ctx = do
        apply instA ctx
        apply instB ctx
    apply (Spread spread) ctx =
        for_ (Array.catMaybes $ Spread.run spread) $ flip apply ctx