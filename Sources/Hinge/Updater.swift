import AppKit

/// Checks GitHub releases and swaps the running bundle for a newer one.
///
/// The release has to carry a zip of `Hinge.app` as an asset, and be tagged
/// with the version (`v1.1` or `1.1`); that tag is what gets compared against
/// the bundle's own `CFBundleShortVersionString`.
@MainActor
final class Updater: ObservableObject {
    enum State: Equatable {
        case idle
        case checking
        case upToDate
        case available(String)
        case installing
        case failed(String)
    }

    @Published private(set) var state: State = .idle
    private var pending: Release?

    static let repository = "Pikare02/Hinge"

    static var currentVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"
    }

    struct Release: Decodable, Equatable {
        let tagName: String
        let htmlURL: URL
        let assets: [Asset]

        struct Asset: Decodable, Equatable {
            let name: String
            let browserDownloadURL: URL

            enum CodingKeys: String, CodingKey {
                case name
                case browserDownloadURL = "browser_download_url"
            }
        }

        enum CodingKeys: String, CodingKey {
            case tagName = "tag_name"
            case htmlURL = "html_url"
            case assets
        }

        /// The app itself, as opposed to source archives GitHub attaches.
        var appZip: URL? {
            assets.first { $0.name.hasSuffix(".zip") }?.browserDownloadURL
        }
    }

    // MARK: - Checking

    /// Looks for a newer release. With `install` set, a find is installed
    /// straight away, which is what the automatic setting does.
    func check(install: Bool) async {
        guard state != .checking, state != .installing else { return }
        state = .checking
        do {
            let release = try await latestRelease()
            guard Updater.isNewer(release.tagName, than: Updater.currentVersion) else {
                pending = nil
                state = .upToDate
                return
            }
            pending = release
            state = .available(Updater.version(from: release.tagName))
            if install { await self.install() }
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    private func latestRelease() async throws -> Release {
        let url = URL(string: "https://api.github.com/repos/\(Updater.repository)/releases/latest")!
        var request = URLRequest(url: url)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            throw Failure("GitHub answered \(code). There may be no releases yet.")
        }
        return try JSONDecoder().decode(Release.self, from: data)
    }

    // MARK: - Installing

    /// Downloads the new bundle, puts it where the running one sits, and hands
    /// over to it. Anything that goes wrong leaves the installed app untouched.
    func install() async {
        guard let release = pending else { return }
        state = .installing
        do {
            guard let zip = release.appZip else {
                throw Failure("That release has no app to download.")
            }
            let bundle = Bundle.main.bundleURL
            guard bundle.pathExtension == "app" else {
                throw Failure("Hinge is not running from an app bundle, so it cannot replace itself.")
            }
            guard FileManager.default.isWritableFile(atPath: bundle.deletingLastPathComponent().path) else {
                throw Failure("No permission to write to \(bundle.deletingLastPathComponent().path).")
            }
            let replacement = try await download(zip)
            try FileManager.default.replaceItem(at: bundle, withItemAt: replacement,
                                                backupItemName: nil, options: [],
                                                resultingItemURL: nil)
            relaunch(at: bundle)
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    /// Unpacks the zip and returns the app bundle inside it, having checked it
    /// is one rather than whatever else the archive happened to hold.
    private func download(_ url: URL) async throws -> URL {
        let (file, response) = try await URLSession.shared.download(from: url)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw Failure("The download failed.")
        }
        let unpacked = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("hinge-update-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: unpacked, withIntermediateDirectories: true)
        // ditto is what preserves the bundle's signature and symlinks.
        let ditto = Process()
        ditto.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        ditto.arguments = ["-x", "-k", file.path, unpacked.path]
        try ditto.run()
        ditto.waitUntilExit()
        guard ditto.terminationStatus == 0 else { throw Failure("The download could not be unpacked.") }

        let contents = try FileManager.default.contentsOfDirectory(at: unpacked, includingPropertiesForKeys: nil)
        guard let app = contents.first(where: { $0.lastPathComponent == "Hinge.app" }),
              FileManager.default.isExecutableFile(atPath: app.appendingPathComponent("Contents/MacOS/Hinge").path)
        else {
            throw Failure("The download did not contain Hinge.app.")
        }
        return app
    }

    /// Starts the new copy and gets out of its way. Two copies must never run
    /// at once, so this one goes down as soon as the other is up.
    private func relaunch(at bundle: URL) {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(at: bundle, configuration: configuration) { _, _ in
            DispatchQueue.main.async { NSApp.terminate(nil) }
        }
    }

    // MARK: - Versions

    /// Tags are compared component by component as numbers, so 1.10 sits above
    /// 1.9 where a string comparison would have it the other way around.
    static func isNewer(_ tag: String, than current: String) -> Bool {
        let a = components(version(from: tag))
        let b = components(current)
        for i in 0..<max(a.count, b.count) {
            let left = i < a.count ? a[i] : 0
            let right = i < b.count ? b[i] : 0
            if left != right { return left > right }
        }
        return false
    }

    static func version(from tag: String) -> String {
        tag.hasPrefix("v") ? String(tag.dropFirst()) : tag
    }

    private static func components(_ version: String) -> [Int] {
        version.split(separator: ".").map { Int($0.prefix(while: \.isNumber)) ?? 0 }
    }

    private struct Failure: LocalizedError {
        let errorDescription: String?
        init(_ message: String) { errorDescription = message }
    }

    static func selfCheck() {
        assert(isNewer("1.1", than: "1.0"), "a higher version must count as newer")
        assert(isNewer("v1.1", than: "1.0"), "a v prefix must not change the comparison")
        assert(isNewer("1.10", than: "1.9"), "versions must compare as numbers, not as text")
        assert(isNewer("2.0", than: "1.12.3"), "a higher major must win")
        assert(!isNewer("1.0", than: "1.0"), "the same version must not count as newer")
        assert(!isNewer("1.0", than: "1.0.1"), "an older version must not count as newer")
        assert(!isNewer("0.9", than: "1.0"), "a lower version must not count as newer")
        assert(version(from: "v2.3") == "2.3", "the tag must read as a plain version")
        print("Updater.selfCheck passed")
    }
}
