import Foundation

/// Scheduled flights: boards (teleports to the departure airport), departs and lands on time; delays can be edited any time and apply immediately.
@MainActor @Observable
final class FlightScheduler {
    enum Phase: Equatable { case waiting, boarding, airborne, none }
    struct Status {
        var phase: Phase
        var scheduled: Date?       // Scheduled departure
        var departure: Date?       // Actual departure (including delay)
        var arrival: Date?         // Expected landing (including delay)
    }
    struct Running { let flightID: UUID; let key: String; let scheduled: Date }

    var flights: [ScheduledFlight] = [] { didSet { onChange?() } }
    private(set) var running: Running?

    let controller: MovementController
    let airports: AirportDB
    var now: @MainActor () -> Date = { Date() }
    var onChange: (@MainActor () -> Void)?
    var onLog: (@MainActor (String) -> Void)?
    var onClear: (@MainActor () -> Void)?

    private var handled: Set<String> = []
    private var boardingKey: String?
    private var restoreAt: Date?
    private var task: Task<Void, Never>?

    init(controller: MovementController, airports: AirportDB) {
        self.controller = controller; self.airports = airports
    }

    func start() {
        guard task == nil else { return }
        task = Task { [weak self] in
            while !Task.isCancelled {
                self?.tick()
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    private func key(_ f: ScheduledFlight, _ s: Date) -> String { "\(f.id)|\(Int(s.timeIntervalSince1970))" }
    private func depart(_ f: ScheduledFlight, _ s: Date) -> Date { s.addingTimeInterval(Double(f.delayMinutes) * 60) }
    private func arrive(_ f: ScheduledFlight, _ s: Date) -> Date { s.addingTimeInterval(Double(f.durationMinutes + f.delayMinutes) * 60) }

    func tick() {
        let t = now()

        if let r = restoreAt, t >= r { restoreAt = nil; onLog?(L("落地後時間到,還原真實定位")); onClear?() }

        // In flight: keep applying the latest delay and detect landing
        if let run = running {
            guard let f = flights.first(where: { $0.id == run.flightID }), f.enabled else {
                controller.stop(); handled.insert(run.key); running = nil
                onLog?(L("航班已停用或刪除,中止飛行")); return
            }
            controller.flightDeadline = arrive(f, run.scheduled)
            if controller.state == .idle {
                handled.insert(run.key); running = nil
                if controller.arrived {
                    onLog?(L("✈︎ %@ 已落地", f.title))
                    if f.restoreAfterLandingMinutes > 0 { restoreAt = t.addingTimeInterval(Double(f.restoreAfterLandingMinutes) * 60) }
                } else { onLog?(L("%@ 已中止:%@", f.title, controller.message)) }
            }
            return
        }
        if controller.isActive { return }   // The user is operating manually

        for f in flights where f.enabled {
            for s in f.occurrences(from: t) {
                let k = key(f, s)
                if handled.contains(k) { continue }
                if t >= arrive(f, s) { handled.insert(k); continue }          // The whole flight was missed
                if t >= depart(f, s) { startFlight(f, s, k, elapsed: t.timeIntervalSince(depart(f, s))); return }
                if t >= depart(f, s).addingTimeInterval(-Double(f.boardingLeadMinutes) * 60), boardingKey != k { board(f, k) }
            }
        }
    }

    private func board(_ f: ScheduledFlight, _ k: String) {
        boardingKey = k
        guard let o = airports.airport(f.origin) else { return }
        controller.teleport(to: o.coordinate)
        onLog?(L("登機:%@,已傳送到 %@", f.title, o.iata))
    }

    private func startFlight(_ f: ScheduledFlight, _ s: Date, _ k: String, elapsed: Double) {
        guard let o = airports.airport(f.origin), let d = airports.airport(f.destination), o.iata != d.iata else {
            handled.insert(k); onLog?(L("%@:機場代碼無效,略過", f.title)); return
        }
        controller.mode = .flight
        controller.flightOrigin = o; controller.flightDest = d
        controller.timeScale = 1
        controller.flightDeadline = arrive(f, s)
        running = Running(flightID: f.id, key: k, scheduled: s)
        onLog?(L("✈︎ %@ 起飛", f.title) + (elapsed > 5 ? L("(已飛行 %@,追上目前進度)", Format.duration(elapsed)) : ""))
        Task { await controller.start(fallbackOrigin: nil, flightElapsed: elapsed) }
    }

    // MARK: Display
    func status(of f: ScheduledFlight) -> Status {
        let t = now()
        if let r = running, r.flightID == f.id {
            return .init(phase: .airborne, scheduled: r.scheduled, departure: depart(f, r.scheduled), arrival: arrive(f, r.scheduled))
        }
        for s in f.occurrences(from: t) where !handled.contains(key(f, s)) && arrive(f, s) > t {
            let dep = depart(f, s)
            let boarding = t >= dep.addingTimeInterval(-Double(f.boardingLeadMinutes) * 60)
            return .init(phase: boarding ? .boarding : .waiting, scheduled: s, departure: dep, arrival: arrive(f, s))
        }
        return .init(phase: .none, scheduled: nil, departure: nil, arrival: nil)
    }

    /// The next time the Mac should wake (2 minutes before boarding).
    func nextWakeDate() -> Date? {
        let t = now()
        return flights.filter(\.enabled).flatMap { f in
            f.occurrences(from: t).filter { !handled.contains(key(f, $0)) }
                .map { depart(f, $0).addingTimeInterval(-Double(f.boardingLeadMinutes + 2) * 60) }
        }.filter { $0 > t }.min()
    }
}
