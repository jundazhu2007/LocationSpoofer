import Testing
@testable import LocationSpoofer

struct AirportTests {
    static let db = AirportDB(
        airportsTSV: """
        TPE\tTaiwan Taoyuan International Airport\tTaipei\tTaiwan\t25.0777\t121.2328
        HKG\tHong Kong International Airport\tHong Kong\tHong Kong\t22.3089\t113.9145
        NRT\tNarita International Airport\tTokyo\tJapan\t35.7720\t140.3929
        HND\tHaneda Airport\tTokyo\tJapan\t35.5494\t139.7798
        ZZZ\tNo Service Airport\tNowhere\tNowhere\t0.0\t0.0
        """,
        routesTXT: "TPE:HKG,NRT\nHKG:TPE\n")

    @Test func searchByCodeCityAndChinese() {
        #expect(Self.db.search("TPE").first?.iata == "TPE")
        #expect(Self.db.search("桃園").first?.iata == "TPE")
        #expect(Self.db.search("東京").map(\.iata).contains("NRT"))
        #expect(Self.db.search("tokyo").count == 2)
    }

    @Test func directOnlyFiltersDestinations() throws {
        let tpe = try #require(Self.db.airport("TPE"))
        let r = Self.db.search("tokyo", from: tpe, directOnly: true).map(\.iata)
        #expect(r == ["NRT"])
        #expect(Self.db.hasDirect("HKG", "TPE"))
        #expect(!Self.db.hasDirect("TPE", "HND"))
    }

    @Test func flightProfileShape() {
        let total = 2_000_000.0
        #expect(FlightProfile.speedKmh(at: 0, total: total, cruise: 850) < 100)
        #expect(FlightProfile.speedKmh(at: total / 2, total: total, cruise: 850) == 850)
        #expect(FlightProfile.speedKmh(at: total, total: total, cruise: 850) < 100)
    }

    @Test func solveCruiseHitsTargetDuration() {
        let total = 2_000_000.0
        let target = FlightProfile.duration(total: total, cruise: 780)
        let r = FlightProfile.solveCruise(total: total, seconds: target)
        #expect(r.feasible)
        #expect(abs(r.cruise - 780) < 2)
        #expect(!FlightProfile.solveCruise(total: total, seconds: 60).feasible)
    }
}
