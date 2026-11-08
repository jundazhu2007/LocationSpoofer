import Foundation

struct Device: Identifiable, Hashable, Sendable {
    let id: String          // UDID
    let name: String
    let osVersion: String
    let isWireless: Bool
    let isConnected: Bool
}

enum MovementMode: String, CaseIterable, Identifiable, Sendable {
    case teleport, route, flight, joystick, orbit, wander
    var id: String { rawValue }
    var title: String {
        switch self {
        case .teleport: L("定點")
        case .route: L("路線")
        case .flight: L("飛行")
        case .joystick: L("搖桿")
        case .orbit: L("環繞")
        case .wander: L("漫遊")
        }
    }
    var symbol: String {
        switch self {
        case .teleport: "mappin.and.ellipse"
        case .route: "point.topleft.down.to.point.bottomright.curvepath"
        case .flight: "airplane"
        case .joystick: "gamecontroller"
        case .orbit: "circle.dashed"
        case .wander: "figure.walk.motion"
        }
    }
}

enum Transport: String, CaseIterable, Identifiable, Codable, Sendable {
    case walk, run, bike, car, highway, train, hsr, plane, supersonic, custom
    var id: String { rawValue }
    var title: String {
        switch self {
        case .walk: L("步行")
        case .run: L("跑步")
        case .bike: L("單車")
        case .car: L("汽車")
        case .highway: L("高速公路")
        case .train: L("火車")
        case .hsr: L("高鐵")
        case .plane: L("客機")
        case .supersonic: L("超音速")
        case .custom: L("自訂")
        }
    }
    var symbol: String {
        switch self {
        case .walk: "figure.walk"
        case .run: "figure.run"
        case .bike: "bicycle"
        case .car: "car.fill"
        case .highway: "road.lanes"
        case .train: "tram.fill"
        case .hsr: "train.side.front.car"
        case .plane: "airplane"
        case .supersonic: "airplane.departure"
        case .custom: "slider.horizontal.3"
        }
    }
    /// Default speed in km/h
    var defaultKmh: Double {
        switch self {
        case .walk: 5
        case .run: 10
        case .bike: 20
        case .car: 50
        case .highway: 100
        case .train: 150
        case .hsr: 300
        case .plane: 900
        case .supersonic: 2000
        case .custom: 30
        }
    }
    enum Routing { case walking, driving, straight }
    var routing: Routing {
        switch self {
        case .walk, .run, .bike: .walking
        case .car, .highway: .driving
        default: .straight
        }
    }
}

enum LoopMode: String, CaseIterable, Identifiable, Sendable {
    case once, loop, pingPong
    var id: String { rawValue }
    var title: String {
        switch self { case .once: L("單程"); case .loop: L("循環"); case .pingPong: L("往返") }
    }
}

struct SavedPlace: Identifiable, Codable, Hashable, Sendable {
    var id = UUID()
    var name: String
    var coordinate: Coordinate
}

struct SavedRoute: Identifiable, Codable, Hashable, Sendable {
    var id = UUID()
    var name: String
    var waypoints: [Coordinate]
}

/// Scheduled flight: weekly or one-time. All times use the Mac's local time zone.
struct ScheduledFlight: Identifiable, Codable, Hashable, Sendable {
    var id = UUID()
    var flightNumber = ""
    var origin = ""                 // IATA
    var destination = ""            // IATA
    var hour = 8
    var minute = 0
    var weekdays: Set<Int> = []     // Calendar weekday: 1 = Sunday … 7 = Saturday; empty = one-time
    var oneOffDate: Date?           // Date of a one-time flight
    var durationMinutes = 120       // Scheduled duration (takeoff to landing)
    var delayMinutes = 0            // Delay in minutes: editable any time, applies immediately
    var boardingLeadMinutes = 20    // Minutes before takeoff to teleport to the departure airport
    var restoreAfterLandingMinutes = 0   // Minutes after landing to restore the real location (0 = stay at destination)
    var enabled = true

    var title: String { flightNumber.isEmpty ? "\(origin) → \(destination)" : "\(flightNumber)  \(origin) → \(destination)" }

    /// All scheduled departure times from one day before `start` to `days` days after it.
    func occurrences(from start: Date, days: Int = 8) -> [Date] {
        let cal = Calendar.current
        var out: [Date] = []
        for offset in -1...days {
            guard let day = cal.date(byAdding: .day, value: offset, to: cal.startOfDay(for: start)) else { continue }
            let match = weekdays.isEmpty
                ? (oneOffDate.map { cal.isDate($0, inSameDayAs: day) } ?? false)
                : weekdays.contains(cal.component(.weekday, from: day))
            if match, let s = cal.date(bySettingHour: hour, minute: minute, second: 0, of: day) { out.append(s) }
        }
        return out
    }
}

struct LibraryData: Codable, Sendable {
    var places: [SavedPlace] = []
    var routes: [SavedRoute] = []
    var history: [SavedPlace] = []
    var flights: [ScheduledFlight] = []

    init() {}
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        places = try c.decodeIfPresent([SavedPlace].self, forKey: .places) ?? []
        routes = try c.decodeIfPresent([SavedRoute].self, forKey: .routes) ?? []
        history = try c.decodeIfPresent([SavedPlace].self, forKey: .history) ?? []
        flights = try c.decodeIfPresent([ScheduledFlight].self, forKey: .flights) ?? []
    }
}

enum Format {
    static func distance(_ m: Double) -> String {
        m >= 1000 ? String(format: "%.2f km", m / 1000) : String(format: "%.0f m", m)
    }
    static func duration(_ s: Double) -> String {
        guard s.isFinite, s >= 0 else { return "—" }
        let t = Int(s.rounded())
        let h = t / 3600, m = (t % 3600) / 60, sec = t % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, sec) : String(format: "%d:%02d", m, sec)
    }
}
