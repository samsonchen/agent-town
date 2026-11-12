import Testing
@testable import TownCore

@Suite struct ViewFocusTests {
    let half = SIMD2<Float>(2, 2)

    @Test func nobodyMovingKeepsTheView() {
        #expect(ViewFocus.bestCenter([], current: [5, 5], half: half) == nil)
    }

    @Test func theCurrentViewStaysWhenItHoldsTheMost() {
        let c = ViewFocus.bestCenter([[5, 5], [20, 20]], current: [5, 5], half: half)
        #expect(c == [5, 5])
    }

    @Test func movesToTheGroupWithTheMostWalkers() {
        // One walker in view, three together further down.
        let c = ViewFocus.bestCenter([[5, 5], [10, 20], [11, 20], [10, 21]], current: [5, 5], half: half)
        let got = try! #require(c)
        #expect(abs(got.x - 31.0 / 3) < 0.01 && abs(got.y - 61.0 / 3) < 0.01)
    }

    @Test func movesToALoneWalkerWhenTheViewIsEmpty() {
        #expect(ViewFocus.bestCenter([[12, 3]], current: [0, 0], half: half) == [12, 3])
    }
}
