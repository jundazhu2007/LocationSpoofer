import Foundation

struct CommandResult: Sendable { let status: Int32; let output: String }

/// Runs `xcrun devicectl ...` (bundled with Xcode, uses CoreDevice, supports USB and wireless).
enum DeviceCtl {
    static func run(_ args: [String], timeout: Duration = .seconds(30)) async -> CommandResult {
        await withCheckedContinuation { cont in
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
            p.arguments = ["devicectl"] + args
            let pipe = Pipe()
            p.standardOutput = pipe; p.standardError = pipe
            p.standardInput = FileHandle.nullDevice
            p.terminationHandler = { proc in
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                cont.resume(returning: .init(status: proc.terminationStatus, output: String(decoding: data, as: UTF8.self)))
            }
            do { try p.run() } catch { cont.resume(returning: .init(status: -1, output: error.localizedDescription)); return }
            let box = Box(p)
            Task { try? await Task.sleep(for: timeout); if box.p.isRunning { box.p.terminate() } }
        }
    }
    private final class Box: @unchecked Sendable { let p: Process; init(_ p: Process) { self.p = p } }

    /// Synchronous variant, only used to restore the location when the app quits.
    static func runSync(_ args: [String]) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
        p.arguments = ["devicectl"] + args
        p.standardOutput = FileHandle.nullDevice; p.standardError = FileHandle.nullDevice
        try? p.run(); p.waitUntilExit()
    }
}
