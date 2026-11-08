import Testing
import Foundation
@testable import LocationSpoofer

@MainActor
struct ControllerTests {
    let a = Coordinate(latitude: 25, longitude: 121)

    @Test func smartInsertPicksNearestSegment() {
        let c = MovementController()
        let b = a.moved(distance: 4000, bearing: .pi / 2)
        let d = b.moved(distance: 4000, bearing: 0)
        c.waypoints = [a, b, d]; c.smartInsert = true
        let nearAB = a.moved(distance: 2000, bearing: .pi / 2).moved(distance: 100, bearing: .pi)
        c.addWaypoint(nearAB)
        #expect(c.waypoints.firstIndex(of: nearAB) == 1)
        let beyond = d.moved(distance: 3000, bearing: 0)
        c.addWaypoint(beyond)
        #expect(c.waypoints.last == beyond)
        let before = a.moved(distance: 3000, bearing: .pi)
        c.addWaypoint(before)
        #expect(c.waypoints.first == before)
    }

    @Test func plainAppendWhenSmartInsertOff() {
        let c = MovementController()
        c.waypoints = [a, a.moved(distance: 100, bearing: 0)]
        let z = Coordinate(latitude: 26, longitude: 122)
        c.addWaypoint(z)
        #expect(c.waypoints.last == z)
        c.removeWaypoint(0)
        #expect(c.waypoints.count == 2)
    }

    @Test func routeReachesTheEndAndStops() async throws {
        let c = MovementController()
        var count = 0
        c.onPosition = { _ in count += 1 }
        let b = a.moved(distance: 500, bearing: 0)
        c.mode = .route; c.transport = .custom; c.speedKmh = 720
        c.followRoads = false; c.smoothMotion = false
        c.waypoints = [a, b]
        await c.start(fallbackOrigin: nil)
        for _ in 0..<100 where c.state != .idle { try await Task.sleep(for: .milliseconds(100)) }
        #expect(c.state == .idle)
        #expect(c.message == "已抵達終點")
        #expect(try #require(c.current).distance(to: b) < 1)
        #expect(count > 2)
    }

    @Test func loopRunsRequestedLapsThenStops() async throws {
        let c = MovementController()
        let b = a.moved(distance: 800, bearing: 0), d = b.moved(distance: 800, bearing: .pi / 2)
        c.mode = .route; c.transport = .custom; c.speedKmh = 3600
        c.followRoads = false; c.smoothMotion = false
        c.loop = .loop; c.repeatCount = 2; c.waypoints = [a, b, d]
        let t0 = Date()
        await c.start(fallbackOrigin: nil)
        for _ in 0..<150 where c.state != .idle { try await Task.sleep(for: .milliseconds(100)) }
        #expect(c.state == .idle)
        let lap = a.distance(to: b) + b.distance(to: d) + d.distance(to: a)
        #expect(abs(Date().timeIntervalSince(t0) - lap * 2 / 1000) < 1.5)
    }
}
