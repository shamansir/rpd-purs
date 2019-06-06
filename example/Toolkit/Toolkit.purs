module Example.Toolkit where

import Prelude (($))

import Data.Map (singleton) as Map
import Data.Tuple.Nested ((/\))

import Rpd.Toolkit as T
import Rpd.Util (type (/->))

import Example.Toolkit.Value
import Example.Toolkit.Channel
import Example.Toolkit.Nodes
import Example.Toolkit.Render.Html as RenderHtml


    -- let
    --     toolkits = T.Toolkits
    --         $ Map.singleton (T.ToolkitName "example")
    --         $ T.mkToolkitE toolkit
    -- in
    --     VDom.embed' "#app" htmlRenderer toolkits network

toolkit :: T.Toolkit Value Channel
toolkit =
    T.Toolkit
        { name : T.ToolkitName "example"
        , nodes
        , render :
            Map.singleton (T.RendererAlias "html")
            $ T.mkRendererEE RenderHtml.renderer
        }
    where
        nodes :: T.NodeDefAlias /-> T.NodeDef Value Channel
        nodes =
            T.nodes
                [ "random" /\ randomNode
                ]
