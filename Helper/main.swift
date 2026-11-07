// TidyMyMacHelper: the root helper (spec 005). This target holds the XPC listener and wiring only;
// all logic lives in HelperCore. Milestone 0 ships an empty stub that exits; the listener,
// caller checks and operations arrive in milestone 3 (docs/spec/README.md §7).
import Foundation
import HelperCore
import HelperProtocol

FileHandle.standardError.write(Data("TidyMyMacHelper: not active until milestone 3.\n".utf8))
exit(0)
