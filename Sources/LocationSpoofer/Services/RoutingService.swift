import MapKit

struct RouteBuildResult {
    var track: PathTrack
    var roadLegs = 0
    var fallbackLegs = 0
    var stops: [Double] = []   // Distance of each intermediate waypoint along the route (meters)
}

@MainActor
enum RoutingService {
    static func buildTrack(waypoints: [Coordinate], transport: Transport, followRoads: Bool, closed: Bool) async -> RouteBuildResult {
        var pts = waypoints
        if closed, let f = waypoints.first, waypoints.count > 1 { pts.append(f) }
        guard pts.count > 1 else { return .init(track: PathTrack(points: pts)) }

        var result: [Coordinate] = [pts[0]]
        var acc = 0.0
        var stops: [Double] = []
        var road = 0, fallback = 0
        func add(_ p: Coordinate) { acc += result[result.count - 1].distance(to: p); result.append(p) }
        for i in 1..<pts.count {
            let a = pts[i - 1], b = pts[i]
            if followRoads, transport.routing != .straight, let leg = await roadLeg(a, b, transport) {
                for p in leg.dropFirst() { add(p) }; road += 1
            } else {
                add(b); if followRoads && transport.routing != .straight { fallback += 1 }
            }
            if i < pts.count - 1 { stops.append(acc) }
        }
        return .init(track: PathTrack(points: result), roadLegs: road, fallbackLegs: fallback, stops: stops)
    }

    private static func roadLeg(_ a: Coordinate, _ b: Coordinate, _ t: Transport) async -> [Coordinate]? {
        let req = MKDirections.Request()
        req.source = MKMapItem(location: CLLocation(latitude: a.latitude, longitude: a.longitude), address: nil)
        req.destination = MKMapItem(location: CLLocation(latitude: b.latitude, longitude: b.longitude), address: nil)
        req.transportType = t.routing == .driving ? .automobile : .walking
        guard let route = try? await MKDirections(request: req).calculate().routes.first else { return nil }
        let poly = route.polyline
        var coords = [CLLocationCoordinate2D](repeating: .init(), count: poly.pointCount)
        poly.getCoordinates(&coords, range: NSRange(location: 0, length: poly.pointCount))
        let out = coords.map(Coordinate.init)
        return out.count > 1 ? [a] + out.dropFirst().dropLast() + [b] : nil
    }
}
