import Foundation
import Testing
@testable import TownCore

/// Each fixture in protocol/fixtures/ has an expected-state file in protocol/fixtures/expected/:
/// the building state after each event that changes it. Another app (the Windows one) replays the
/// same fixtures against the same files. To write them again after a deliberate change:
/// `UPDATE_EXPECTED=1 swift test --filter fixturesMatchTheirExpectedState`, then review the diff.
@Test func fixturesMatchTheirExpectedState() throws {
    let dir = repoRoot.appending(path: "protocol/fixtures")
    let expectedDir = dir.appending(path: "expected")
    let update = ProcessInfo.processInfo.environment["UPDATE_EXPECTED"] == "1"
    let names = try FileManager.default.contentsOfDirectory(atPath: dir.path).filter { $0.hasSuffix(".json") }.sorted()
    #expect(!names.isEmpty)
    for n in names {
        let events = try fixture(String(n.dropLast(5)))
        var got = Building.canonicalJSON(Building.expectedStates(for: events))
        got.append(0x0A) // a final newline
        let file = expectedDir.appending(path: n)
        if update {
            try FileManager.default.createDirectory(at: expectedDir, withIntermediateDirectories: true)
            try got.write(to: file)
            continue
        }
        let want = try? Data(contentsOf: file)
        #expect(want == got, "\(n) differs from protocol/fixtures/expected/\(n); rerun with UPDATE_EXPECTED=1 if the change is deliberate")
    }
}
