import Foundation

struct LibraryStore: Sendable {
    private var url: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("LocationSpoofer")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("library.json")
    }
    func load() -> LibraryData {
        (try? JSONDecoder().decode(LibraryData.self, from: Data(contentsOf: url))) ?? LibraryData()
    }
    func save(_ lib: LibraryData) {
        if let d = try? JSONEncoder().encode(lib) { try? d.write(to: url, options: .atomic) }
    }
}
