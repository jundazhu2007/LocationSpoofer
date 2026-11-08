import AppKit

@MainActor
enum AboutPanel {
    static func show() {
        let body = NSMutableAttributedString()
        let paragraph = NSMutableParagraphStyle(); paragraph.alignment = .center; paragraph.paragraphSpacing = 3
        let base: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 11), .foregroundColor: NSColor.labelColor, .paragraphStyle: paragraph]
        let secondary: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 10), .foregroundColor: NSColor.secondaryLabelColor, .paragraphStyle: paragraph]
        let bold: [NSAttributedString.Key: Any] = [.font: NSFont.boldSystemFont(ofSize: 12), .foregroundColor: NSColor.labelColor, .paragraphStyle: paragraph]

        /// One line of text; a part that carries a URL becomes a link.
        func line(_ parts: [(String, URL?)], _ attrs: [NSAttributedString.Key: Any]) {
            for (text, url) in parts {
                var a = attrs
                if let url { a[.link] = url; a[.foregroundColor] = NSColor.linkColor }
                body.append(NSAttributedString(string: text, attributes: a))
            }
            body.append(NSAttributedString(string: "\n", attributes: attrs))
        }

        line([(L("版本 %@", AppInfo.version), nil)], secondary)
        line([(L("由 %@ 開發", AppInfo.author), nil)], bold)
        line([("github.com/\(AppInfo.githubUser)/\(AppInfo.repoName)", AppInfo.repoURL)], base)
        line([("github.com/\(AppInfo.githubUser)", AppInfo.profileURL), ("  ·  ", nil), ("X @\(AppInfo.xHandle)", AppInfo.xURL)], base)
        line([(AppInfo.email, URL(string: "mailto:\(AppInfo.email)"))], base)
        line([(L("開源授權:MIT License"), nil)], secondary)
        line([(L("機場與航線資料來自 OpenFlights(ODbL)"), nil)], secondary)
        line([(L("僅供開發測試、隱私研究與學習用途。請遵守當地法律與各服務的使用條款。"), nil)], secondary)

        NSApp.orderFrontStandardAboutPanel(options: [
            .applicationName: AppInfo.name,
            .applicationVersion: "",
            .version: "",
            .credits: body,
            NSApplication.AboutPanelOptionKey(rawValue: "Copyright"): "© \(AppInfo.year) \(AppInfo.author) · MIT License",
        ])
        NSApp.activate(ignoringOtherApps: true)
    }
}
