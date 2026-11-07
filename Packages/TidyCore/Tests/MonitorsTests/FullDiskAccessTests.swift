import Darwin
import Foundation
import Testing
@testable import Monitors
import SafetyFloor

struct FullDiskAccessTests {
    let home = Home(root: URL(fileURLWithPath: "/fixture/home"), temporaryDirectory: URL(fileURLWithPath: "/tmp"),
                    userCacheDirectory: URL(fileURLWithPath: "/tmp"), userID: 501)

    func state(_ results: [String: FullDiskAccess.OpenResult]) -> FullDiskAccess.State {
        FullDiskAccess.state(home: home) { results[$0] ?? .failed(ENOENT) }
    }

    @Test func mapping() {
        let trash = "/fixture/home/.Trash", safari = "/fixture/home/Library/Safari", mail = "/fixture/home/Library/Mail"
        #expect(FullDiskAccess.probePaths(home) == [trash, safari, mail])
        #expect(state([trash: .opened]) == .granted)
        #expect(state([trash: .failed(EPERM), safari: .opened]) == .granted)
        #expect(state([trash: .failed(EPERM), safari: .failed(EPERM), mail: .failed(ENOENT)]) == .missing)
        #expect(state([:]) == .unknown)
        #expect(state([trash: .failed(EACCES)]) == .unknown)
    }
}
