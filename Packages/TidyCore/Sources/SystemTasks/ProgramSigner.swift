import Foundation
import Security

/// Vendor name from a program's code signature: the organisation of a Developer ID leaf
/// certificate ("Developer ID Application: Example Inc (ABCDE12345)" → "Example Inc").
public struct SystemProgramSigner: ProgramSigner {
    public init() {}

    public func vendor(of program: String) -> String? {
        var code: SecStaticCode?
        guard SecStaticCodeCreateWithPath(URL(fileURLWithPath: program) as CFURL, [], &code) == errSecSuccess, let code else { return nil }
        var info: CFDictionary?
        guard SecCodeCopySigningInformation(code, SecCSFlags(rawValue: kSecCSSigningInformation), &info) == errSecSuccess,
              let dict = info as? [String: Any],
              let certs = dict[kSecCodeInfoCertificates as String] as? [SecCertificate], let leaf = certs.first,
              let summary = SecCertificateCopySubjectSummary(leaf) as String? else { return nil }
        return Self.vendorName(fromSubject: summary)
    }

    public static func vendorName(fromSubject s: String) -> String {
        var name = s
        for prefix in ["Developer ID Application: ", "Apple Development: ", "Apple Distribution: ", "Mac Developer: "] where name.hasPrefix(prefix) {
            name.removeFirst(prefix.count)
        }
        if let open = name.range(of: " (", options: .backwards), name.hasSuffix(")") { name = String(name[..<open.lowerBound]) }
        return name
    }
}
