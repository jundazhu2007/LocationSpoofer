import Foundation

/// Project info shared by the About window and the README.
enum AppInfo {
    static let name = "Location Spoofer"
    static let author = "Jundazhu"
    static let email = "jundazhu@nannancat.tw"
    static let githubUser = "jundazhu2007"
    static let repoName = "LocationSpoofer"
    static let profileURL = URL(string: "https://github.com/\(githubUser)")!
    static let xHandle = "junda_070826"
    static let xURL = URL(string: "https://x.com/\(xHandle)")!
    static let repoURL = URL(string: "https://github.com/\(githubUser)/\(repoName)")!
    static let year = "2026"

    static var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"
    }
}
