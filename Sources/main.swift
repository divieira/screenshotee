import AppKit
import ServiceManagement
import os

let log = Logger(subsystem: "dev.screenshotee", category: "main")
let imageExtensions: Set<String> = ["png", "jpg", "jpeg", "heic", "tiff", "gif"]

/// Reads the macOS screenshot destination (System Settings > Screenshot > Save to).
func screenshotDirectory() -> URL {
    let defaults = UserDefaults(suiteName: "com.apple.screencapture")
    let path = defaults?.string(forKey: "location") ?? "~/Desktop"
    return URL(fileURLWithPath: (path as NSString).expandingTildeInPath, isDirectory: true)
        .resolvingSymlinksInPath()
}

final class Watcher {
    let dir: URL
    private var seen = Set<String>()
    private var source: DispatchSourceFileSystemObject?
    private var timer: Timer?
    private let queue = DispatchQueue(label: "dev.screenshotee.scan")

    init(dir: URL) { self.dir = dir }

    private func listing() throws -> [URL] {
        try FileManager.default.contentsOfDirectory(
            at: dir, includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles])
            .filter { imageExtensions.contains($0.pathExtension.lowercased()) }
    }

    func start() {
        do {
            seen = Set(try listing().map(\.lastPathComponent))
        } catch {
            // Reading the folder is what triggers the macOS privacy prompt.
            log.error("Cannot read \(self.dir.path, privacy: .public): \(error.localizedDescription, privacy: .public)")
            fputs("error: cannot read \(dir.path): \(error.localizedDescription)\n", stderr)
        }
        log.info("Watching \(self.dir.path, privacy: .public) (\(self.seen.count) existing files)")

        // Fast path: kernel notification. Cloud-sync folders don't always deliver these,
        // so a light poll runs as well.
        let fd = open(dir.path, O_EVTONLY)
        if fd >= 0 {
            let src = DispatchSource.makeFileSystemObjectSource(
                fileDescriptor: fd, eventMask: [.write, .rename, .extend], queue: queue)
            src.setEventHandler { [weak self] in self?.scan() }
            src.setCancelHandler { close(fd) }
            src.resume()
            source = src
        }
        timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            self?.queue.async { self?.scan() }
        }
    }

    private func scan() {
        guard let files = try? listing() else { return }
        for url in files where !seen.contains(url.lastPathComponent) {
            seen.insert(url.lastPathComponent)
            copyWhenStable(url)
        }
    }

    /// Waits until the file size stops changing (screencapture / sync may still be writing).
    private func copyWhenStable(_ url: URL, attempt: Int = 0) {
        func size() -> Int { (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? -1 }
        let before = size()
        queue.asyncAfter(deadline: .now() + 0.3) { [self] in
            let after = size()
            if after > 0, after == before {
                DispatchQueue.main.async { copyToClipboard(url) }
            } else if attempt < 20 {
                copyWhenStable(url, attempt: attempt + 1)
            } else {
                log.error("Gave up on \(url.lastPathComponent, privacy: .public)")
            }
        }
    }
}

func copyToClipboard(_ url: URL) {
    guard let image = NSImage(contentsOf: url) else {
        log.error("Not a readable image: \(url.lastPathComponent, privacy: .public)")
        return
    }
    let pb = NSPasteboard.general
    pb.clearContents()
    pb.writeObjects([image])
    log.info("Copied \(url.lastPathComponent, privacy: .public)")
    print("copied \(url.lastPathComponent)")
}

// MARK: - CLI

switch CommandLine.arguments.dropFirst().first {
case "--install":
    do { try SMAppService.mainApp.register(); print("Registered as login item (status: \(SMAppService.mainApp.status.rawValue)). Approve in System Settings > General > Login Items if prompted.") }
    catch { print("error: \(error)"); exit(1) }
    exit(0)
case "--uninstall":
    do { try SMAppService.mainApp.unregister(); print("Removed login item.") }
    catch { print("error: \(error)"); exit(1) }
    exit(0)
case "--help", "-h":
    print("""
    screenshotee: copies new screenshots to the clipboard.
      (no args)     run the watcher
      --install     start at login
      --uninstall   stop starting at login
    """)
    exit(0)
default:
    break
}

setbuf(stdout, nil)
let app = NSApplication.shared
app.setActivationPolicy(.prohibited)
let watcher = Watcher(dir: screenshotDirectory())
watcher.start()
app.run()
