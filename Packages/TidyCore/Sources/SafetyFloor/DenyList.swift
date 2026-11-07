/// Names the helper never touches (spec 005 §5.1). `Rules/protected.json` carries the same
/// names and a test fails if the two differ.
public enum DenyList {
    /// Direct children of the `libraryLeftovers` zone roots that are always refused.
    public static let libraryLeftoverNames: Set<String> = [
        "Apple", "Developer", "CrashReporter", "iPod", "Script Editor", "Audio", "ColorSync",
        "Fonts", "Keyboard Layouts", "Input Methods",
    ]

    /// Leftover matching never offers an item whose name starts with this (spec 006 §5.2).
    public static let applePrefix = "com.apple."

    public static func isAppleItem(_ name: String) -> Bool {
        PathNormalizer.fold(name).hasPrefix(applePrefix)
    }
}
