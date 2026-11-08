import Testing
@testable import LocationSpoofer

struct GeoTests {
    let tpe = Coordinate(latitude: 25.0777, longitude: 121.2328)
    let nrt = Coordinate(latitude: 35.7720, longitude: 140.3929)

    @Test func greatCircleDistance() {
        let km = tpe.distance(to: nrt) / 1000
        #expect(abs(km - 2182) < 5)
    }

    @Test func moveAndMeasureRoundTrip() {
        let o = Coordinate(latitude: 0, longitude: 0)
        let e = o.moved(distance: 1000, bearing: .pi / 2)
        #expect(abs(o.distance(to: e) - 1000) < 0.01)
    }

    @Test func interpolationMidpointIsEquidistant() {
        let mid = tpe.interpolated(to: nrt, fraction: 0.5)
        #expect(abs(tpe.distance(to: mid) - mid.distance(to: nrt)) < 1)
    }

    @Test func pathTrackSamplesEndpoints() throws {
        let t = PathTrack(points: [tpe, tpe.interpolated(to: nrt, fraction: 0.5), nrt, nrt])
        let end = try #require(t.sample(at: 1e12))
        #expect(end.coordinate.distance(to: nrt) < 1)
        let start = try #require(t.sample(at: 0))
        #expect(start.coordinate.distance(to: tpe) < 1)
    }

    @Test func parsesCoordinateText() {
        #expect(Coordinate.parse("25.033, 121.564") == Coordinate(latitude: 25.033, longitude: 121.564))
        #expect(Coordinate.parse("(25.033,-121.5)") == Coordinate(latitude: 25.033, longitude: -121.5))
        #expect(Coordinate.parse("https://www.google.com/maps/place/x/data=!3d25.0339!4d121.5645") == Coordinate(latitude: 25.0339, longitude: 121.5645))
        #expect(Coordinate.parse("not a coordinate") == nil)
        #expect(Coordinate.parse("95, 10") == nil)
    }
}
