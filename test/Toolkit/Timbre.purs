module Noodle.Test.Toolkit.Timbre
    ( toolkit
    , Data
    , Channel
    , Node
    )
    where

import Prelude

import Data.List ((:))
import Data.List as List
import Data.Map as Map
import Data.Maybe (Maybe(..))
import Data.Tuple.Nested ((/\))
import Noodle.Process as R
import Noodle.Toolkit as T


data WaveKind
    = Sin
    | Saw
    | Tri
    | Pulse
    | Fami


data SoundState
    = Playing
    | Stopped


data Data
    = Value Number
    | Wave WaveKind
    | Sound SoundState


data Channel
    = CValue
    | CWave
    | CSound


data Node
    = Number
    | Osc
    | Plot
    | Play


instance timbreChannel :: T.Channels Data Channel where
    default CValue = Value 0.0
    default CWave = Wave Sin
    default CSound = Sound Stopped
    accept _ _ = true
    adapt _ = identity


toolkit :: T.Toolkit Data Channel Node
toolkit =
    T.Toolkit (T.ToolkitName "Timbre") nodes
    where
        nodes Number = numNode
        nodes Osc = oscNode
        nodes Plot = plotNode
        nodes Play = playNode


numNode :: T.NodeDef Data Channel
numNode =
    T.NodeDef
        { inlets : T.inlets []
        , outlets
            : T.outlets
                [ ( "num" /\ CValue )
                ]
        , process : R.Withhold -- TODO
        }


waveNode :: T.NodeDef Data Channel
waveNode =
    T.NodeDef
        { inlets
            : T.inlets []
        , outlets
            : T.outlets
                [ ( "wave" /\ CWave )
                ]
        , process : R.Withhold -- TODO
        }


oscNode :: T.NodeDef Data Channel
oscNode =
    T.NodeDef
        { inlets
            : T.inlets
                [ "freq" /\ CValue
                , "wave" /\ CWave
                ]
        , outlets
            : T.outlets
                [ "sound" /\ CSound
                ]
        , process : R.Withhold -- TODO
        }


plotNode :: T.NodeDef Data Channel
plotNode =
    T.NodeDef
        { inlets
            : T.inlets
                [ "sound" /\ CSound ]
        , outlets
            : T.outlets []
        , process : R.Withhold -- TODO
        }


playNode :: T.NodeDef Data Channel
playNode =
    T.NodeDef
        { inlets
            : T.inlets
                [ "sound" /\ CSound ]
        , outlets
            : T.outlets []
        , process : R.Withhold -- TODO
        }
