extension HelperProtocol {
    /// The signing team both sides require of each other (005 §9). Compiled in, never read from a
    /// file at runtime. scripts/safety-lint.sh checks it equals DEVELOPMENT_TEAM in Config/Identity.xcconfig.
    public static let teamID = "26TUUFN7M2"
}
