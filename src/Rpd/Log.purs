module Rpd.Log
    ( reportError
    , reportAndReturn
    , runRpdLogging
    , runRpdLogging'
    , extract
    ) where


import Prelude

import Effect (Effect)
import Effect.Class.Console (log)

import Rpd (run') as R
import Rpd.API (Rpd, RpdError) as R


-- FIXME: add examples

reportError :: R.RpdError -> Effect Unit
reportError = log <<< (<>) "RPD Error: " <<< show


reportAndReturn :: forall a. a -> R.RpdError -> Effect a
reportAndReturn v err =
  reportError err >>= \_ -> pure v


runRpdLogging :: forall a. (a -> Effect Unit) -> R.Rpd a -> Effect Unit
runRpdLogging onSuccess rpd =
  R.run' reportError onSuccess rpd


runRpdLogging' :: forall a. R.Rpd a -> Effect Unit
runRpdLogging' rpd =
  R.run' reportError (const $ pure unit) rpd


extract :: forall a. a -> R.Rpd a -> Effect a
extract def rpd =
  R.run' (reportAndReturn def) pure rpd
