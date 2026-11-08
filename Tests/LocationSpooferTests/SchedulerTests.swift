import Testing
import Foundation
@testable import LocationSpoofer

@MainActor
struct SchedulerTests {
    /// 假時鐘:1 真實秒 = 10 假分鐘。
    final class FakeClock: @unchecked Sendable {
        let realStart = Date(), fakeStart = Date(), speed = 600.0
        func now() -> Date { fakeStart.addingTimeInterval(Date().timeIntervalSince(realStart) * speed) }
    }

    @Test func boardsFliesAppliesLiveDelayAndLands() async throws {
        let clock = FakeClock()
        let c = MovementController(); c.now = { clock.now() }
        let sch = FlightScheduler(controller: c, airports: AirportTests.db); sch.now = { clock.now() }
        var logs: [String] = []
        sch.onLog = { logs.append($0) }

        let cal = Calendar.current
        let dep = clock.fakeStart.addingTimeInterval(20 * 60)
        var f = ScheduledFlight(flightNumber: "T1", origin: "TPE", destination: "HKG")
        f.hour = cal.component(.hour, from: dep); f.minute = cal.component(.minute, from: dep)
        f.weekdays = Set(1...7)      // 每天重複,避免測試在午夜前後跨日而不穩定
        f.durationMinutes = 90; f.boardingLeadMinutes = 10
        sch.flights = [f]
        sch.start()

        var delayed = false, airborne = false, landedAt: Date?
        let deadline = Date().addingTimeInterval(60)
        while Date() < deadline {
            try await Task.sleep(for: .milliseconds(100))
            let phase = sch.status(of: sch.flights[0]).phase
            if !delayed, phase == .boarding || phase == .waiting { delayed = true; sch.flights[0].delayMinutes = 15 }
            if phase == .airborne { airborne = true }
            if airborne, sch.running == nil { landedAt = clock.now(); break }
        }
        let scheduled = try #require(f.occurrences(from: clock.fakeStart).min { abs($0.timeIntervalSince(dep)) < abs($1.timeIntervalSince(dep)) })
        let expected = scheduled.addingTimeInterval((90 + 15) * 60)

        #expect(logs.contains { $0.contains("登機") })
        #expect(logs.contains { $0.contains("起飛") })
        #expect(logs.contains { $0.contains("已落地") })
        let landing = try #require(landedAt)
        // 排程器每真實 1 秒檢查一次 = 10 假分鐘的偵測誤差,所以只能晚不能早:
        // 若誤點(15 分)沒套用,落地會早 15 分鐘而失敗。
        let diffMinutes = landing.timeIntervalSince(expected) / 60
        #expect(diffMinutes > -4 && diffMinutes < 12)
        let hkg = try #require(AirportTests.db.airport("HKG"))
        #expect(try #require(c.current).distance(to: hkg.coordinate) < 1)
    }

    @Test func occurrencesRespectWeekdays() {
        var f = ScheduledFlight(origin: "TPE", destination: "HKG")
        f.hour = 9; f.minute = 30; f.weekdays = [2, 4]    // 週一、三
        let list = f.occurrences(from: Date(), days: 14)
        #expect(!list.isEmpty)
        for d in list { #expect([2, 4].contains(Calendar.current.component(.weekday, from: d))) }
    }

    @Test func oldLibraryFilesStillLoad() throws {
        let old = #"{"places":[{"id":"6E1D3E9A-0000-4000-8000-000000000001","name":"A","coordinate":{"latitude":1,"longitude":2}}],"routes":[],"history":[]}"#
        let lib = try JSONDecoder().decode(LibraryData.self, from: Data(old.utf8))
        #expect(lib.places.count == 1 && lib.flights.isEmpty)
    }
}
