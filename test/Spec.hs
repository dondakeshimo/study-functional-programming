import Test.Hspec

import qualified Domain.Task.ValidationSpec
import qualified Domain.Task.WorkflowSpec

main :: IO ()
main = hspec $ do
  Domain.Task.ValidationSpec.spec
  Domain.Task.WorkflowSpec.spec
