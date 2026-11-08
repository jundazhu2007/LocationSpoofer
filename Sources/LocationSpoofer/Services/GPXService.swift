import Foundation

enum GPXService {
    static func parse(_ data: Data) -> [Coordinate] {
        let delegate = Delegate()
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        parser.parse()
        return delegate.points
    }

    static func export(name: String, points: [Coordinate]) -> String {
        let pts = points.map { "      <rtept lat=\"\($0.latitude)\" lon=\"\($0.longitude)\"/>" }.joined(separator: "\n")
        return """
        <?xml version="1.0" encoding="UTF-8"?>
        <gpx version="1.1" creator="LocationSpoofer" xmlns="http://www.topografix.com/GPX/1/1">
          <rte>
            <name>\(name)</name>
        \(pts)
          </rte>
        </gpx>
        """
    }

    private final class Delegate: NSObject, XMLParserDelegate {
        var points: [Coordinate] = []
        func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?, qualifiedName: String?, attributes a: [String: String]) {
            guard ["trkpt", "rtept", "wpt"].contains(name), let la = a["lat"].flatMap(Double.init), let lo = a["lon"].flatMap(Double.init) else { return }
            points.append(Coordinate(latitude: la, longitude: lo))
        }
    }
}
