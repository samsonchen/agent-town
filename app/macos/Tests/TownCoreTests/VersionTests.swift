import Testing
@testable import TownCore
@Test func version() { #expect(TownCore.protocolVersion == 1) }
