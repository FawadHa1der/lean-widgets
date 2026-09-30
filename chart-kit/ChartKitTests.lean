import ChartKitTests.Helpers
import ChartKitTests.ScaleTests
import ChartKitTests.ModelTests
import ChartKitTests.FloatTests
import ChartKitTests.RenderTests
import ChartKitTests.ContractTests
import ChartKitTests.CommandTests

/-! # ChartKit test suite

Compile-time tests (`#guard` / `#guard_msgs`): building this library IS
running the suite — `lake test` builds it.
-/

#guard ChartKit.version = "0.1.0"
