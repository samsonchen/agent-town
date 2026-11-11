import Testing
import simd
@testable import TownCore

private let view = FloorView(pitch: 62 * .pi / 180, target: [4.4, 0, 6.1], scale: 8, size: [900, 700])

private func near(_ a: SIMD3<Float>, _ b: SIMD3<Float>) -> Bool { simd_distance(a, b) < 0.001 }

@Test func floorPointsRoundTripThroughTheWindow() {
    for w: SIMD3<Float> in [[0, 0.02, 0], [4.4, 0.02, 6.1], [8.8, 0.02, 1.3], [1.3, 0.02, 11.7]] {
        #expect(near(view.ground(view.screen(w), height: 0.02), w))
    }
}

@Test func theTargetIsDrawnInTheMiddleAndZRunsDownTheWindow() {
    let mid = view.screen([4.4, 0, 6.1])
    #expect(abs(mid.x - 450) < 0.01 && abs(mid.y - 350) < 0.01)
    #expect(view.screen([4.4, 0, 7]).y > mid.y) // nearer the viewer: lower in the window
    #expect(view.screen([5, 0, 6.1]).x > mid.x)
    // The floor is foreshortened by the tilt: a meter of z is sin(pitch) as tall as a meter of x.
    let ppm: Float = 700 / 8
    #expect(abs((view.screen([4.4, 0, 7.1]).y - mid.y) - ppm * sin(view.pitch)) < 0.01)
    #expect(abs((view.screen([5.4, 0, 6.1]).x - mid.x) - ppm) < 0.01)
}

@Test func aClickOnSomethingRaisedLandsOnTheFloorBehindIt() {
    // A desk top 0.75 m up hides the floor behind it, farther from the viewer.
    let top: SIMD3<Float> = [2, 0.75, 5]
    let floor = view.ground(view.screen(top), height: 0)
    #expect(abs(floor.x - 2) < 0.001)
    #expect(floor.z < 5)
    #expect(abs((5 - floor.z) - 0.75 / tan(view.pitch)) < 0.001)
}

@Test func freeSpotsStayOnTheFloorAndOutOfFurniture() {
    let size: SIMD2<Float> = [8.8, 7]
    let desk: FloorPlan.Rect = ([1, 1], [2, 1.6])
    // Free ground is kept as it is.
    #expect(FloorPlan.freeSpot(near: [4, 4], size: size, obstacles: [desk], radius: 0.15) == [4, 4])
    // Off the floor: pulled back inside, the radius from the edge.
    #expect(FloorPlan.freeSpot(near: [-3, 20], size: size, obstacles: [desk], radius: 0.15) == [0.15, 6.85])
    // Inside the desk: the nearest spot beside it, clear of it.
    let p = FloorPlan.freeSpot(near: [1.5, 1.1], size: size, obstacles: [desk], radius: 0.15)!
    #expect(!FloorPlan.inside(p, desk, pad: 0.15))
    #expect(simd_distance(p, [1.5, 1.1]) < 0.4) // out the back edge, not around the far side
    #expect(p.y < 1)
}
