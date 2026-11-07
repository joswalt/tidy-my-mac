import Foundation

let helperLabel = "com.tidymymac.spike.helper"
let appBundleID = "com.tidymymac.spike"

@objc protocol SpikeHelperProtocol {
    /// Returns "uid=<n> euid=<n> wrote=<path>" after a root-only write test.
    func whoAmI(reply: @escaping (String) -> Void)
    /// Spec 005 §12 probes: Full Disk Access (Q2) and Wi-Fi SSIDs as root (Q4).
    func probes(reply: @escaping (String) -> Void)
}
