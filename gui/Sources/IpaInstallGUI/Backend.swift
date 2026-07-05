// Backend.swift — subprocess layer mirroring the Python wrappers
// (ipatool.py / device.py / library.py). The GUI holds no App Store or device
// protocol logic of its own; it shells out to the very same bin/ binaries.
//
// GUI differences vs. the terminal version (no TTY available):
//   • auth login feeds the password (and 2FA code) to ipatool through a PTY
//     attached as the child's stdin — ipatool only prompts for a hidden
//     password on a TTY, and this keeps secrets off argv (argv is readable by
//     any same-user process via `ps`). We never store or log them ourselves.
//   • download runs with `--format json` and we read the saved path from the
//     JSON `output` key (no progress bar is drawn without a TTY).

import Foundation

// ── Data shapes ─────────────────────────────────────────────────────────────────
struct StoreApp: Identifiable, Hashable {
    let id: String          // numeric App Store id (string)
    let bundleID: String
    let name: String
    let version: String
    let price: String
}

struct VersionRow: Identifiable, Hashable {
    let id: String          // external version id
    let displayVersion: String
    let releaseDate: String
}

struct IpaFile: Identifiable, Hashable {
    let id: String          // absolute path
    let url: URL
    let name: String
    let version: String
    let minIOS: String
    let bundleID: String
    var fileName: String { url.lastPathComponent }
}

// A name↔id row from the offline catalog or a saved list. id is the numeric app id.
struct CatalogEntry: Identifiable, Hashable {
    let id: String
    let name: String
}

struct AccountInfo: Equatable {
    let name: String
    let email: String
}

enum LoginOutcome: Equatable {
    case success(AccountInfo)
    case twoFactorRequired
}

enum BackendError: LocalizedError {
    case message(String)
    var errorDescription: String? {
        switch self { case .message(let m): return m }
    }
}

// ── Path / binary resolution (mirrors config.py) ────────────────────────────────
struct AppPaths {
    let root: URL
    let standalone: Bool   // true when running as a bundle-only .app outside the repo

    static func discover() -> AppPaths {
        let fm = FileManager.default
        func hasBin(_ url: URL) -> Bool {
            fm.isExecutableFile(atPath: url.appendingPathComponent("bin/ipatool").path)
        }
        // 1. explicit override
        if let env = ProcessInfo.processInfo.environment["IPA_INSTALL_ROOT"] {
            let u = URL(fileURLWithPath: env)
            if hasBin(u) { return AppPaths(root: u, standalone: false) }
        }
        // 2. walk up from CWD, then from the executable location (dev / in-repo mode)
        var starts = [URL(fileURLWithPath: fm.currentDirectoryPath)]
        if let exe = Bundle.main.executableURL { starts.append(exe.deletingLastPathComponent()) }
        starts.append(URL(fileURLWithPath: CommandLine.arguments.first ?? ".").deletingLastPathComponent())
        for start in starts {
            var dir = start.standardizedFileURL
            for _ in 0..<8 {
                if hasBin(dir) { return AppPaths(root: dir, standalone: false) }
                let parent = dir.deletingLastPathComponent()
                if parent.path == dir.path { break }
                dir = parent
            }
        }
        // 3. standalone .app: the engine is bundled in Contents/Resources; user
        //    data lives under ~/Library/Application Support/IpaInstall.
        if let res = Bundle.main.resourceURL,
           fm.isExecutableFile(atPath: res.appendingPathComponent("ipatool").path) {
            let support = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
                ?? fm.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support")
            return AppPaths(root: support.appendingPathComponent("IpaInstall"), standalone: true)
        }
        // 4. fallback to the known project location
        let home = fm.homeDirectoryForCurrentUser
        return AppPaths(root: home.appendingPathComponent("code/ipa-install-macos"), standalone: false)
    }

    private func resolve(_ name: String) -> URL {
        let local = root.appendingPathComponent("bin").appendingPathComponent(name)
        if FileManager.default.isExecutableFile(atPath: local.path) { return local }
        // bundled copy inside the .app (standalone releases ship ipatool)
        if let res = Bundle.main.resourceURL {
            let cand = res.appendingPathComponent(name)
            if FileManager.default.isExecutableFile(atPath: cand.path) { return cand }
        }
        // search PATH, then common Homebrew prefixes
        let path = ProcessInfo.processInfo.environment["PATH"] ?? ""
        var dirs = path.split(separator: ":").map(String.init)
        dirs.append(contentsOf: ["/opt/homebrew/bin", "/usr/local/bin", "/usr/bin"])
        for d in dirs {
            let cand = URL(fileURLWithPath: d).appendingPathComponent(name)
            if FileManager.default.isExecutableFile(atPath: cand.path) { return cand }
        }
        return local // best effort; will surface a clear launch error
    }

    var ipatool: URL { resolve("ipatool") }
    var ideviceinstaller: URL { resolve("ideviceinstaller") }
    var ideviceID: URL { resolve("idevice_id") }
    var idevicePair: URL { resolve("idevicepair") }
    var unzip: URL { URL(fileURLWithPath: "/usr/bin/unzip") }

    // Standalone: downloads go where the user can find them (~/Downloads/IPA);
    // in-repo: keep sharing Apps/ with the Python TUI.
    var appsDir: URL {
        if standalone {
            let fm = FileManager.default
            let downloads = fm.urls(for: .downloadsDirectory, in: .userDomainMask).first
                ?? fm.homeDirectoryForCurrentUser.appendingPathComponent("Downloads")
            return downloads.appendingPathComponent("IPA")
        }
        return root.appendingPathComponent("Apps")
    }
    var listsDir: URL { root.appendingPathComponent("Lists") }
    var assetsList: URL {
        let inRepo = root.appendingPathComponent("assets/Apps_ID_List.txt")
        if FileManager.default.fileExists(atPath: inRepo.path) { return inRepo }
        // standalone releases bundle the offline catalog in Resources
        return (Bundle.main.resourceURL ?? root).appendingPathComponent("Apps_ID_List.txt")
    }
    var downloadedList: URL { listsDir.appendingPathComponent("Downloaded_IDs.json") }
    var purchasedList: URL { listsDir.appendingPathComponent("Purchased_IDs.json") }
    var ownedScanFile: URL { listsDir.appendingPathComponent("Owned_scan.json") }
    var langConfigFile: URL { root.appendingPathComponent("Lang_Config.txt") }
    var ipatoolHome: URL { FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".ipatool") }
    var accountFile: URL { ipatoolHome.appendingPathComponent("account") }

    func ensureDirs() {
        for d in [appsDir, listsDir, ipatoolHome] {
            try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        }
    }
}

// ── The backend ─────────────────────────────────────────────────────────────────
struct Backend {
    let paths: AppPaths

    // Raw process runner — returns exit code plus stdout/stderr as Data.
    private func runRaw(_ exe: URL, _ args: [String]) throws -> (Int32, Data, Data) {
        let proc = Process()
        proc.executableURL = exe
        proc.arguments = args
        let out = Pipe(); let err = Pipe()
        proc.standardOutput = out
        proc.standardError = err
        proc.standardInput = FileHandle.nullDevice
        do { try proc.run() } catch {
            throw BackendError.message("cannot launch \(exe.lastPathComponent): \(error.localizedDescription)")
        }
        // Drain stdout and stderr CONCURRENTLY. Reading one to EOF before the other
        // can deadlock if the child fills the unread pipe's ~64KB buffer while we
        // block on the first (e.g. ideviceinstaller / --debug emitting verbose stderr).
        var errData = Data()
        let group = DispatchGroup()
        group.enter()
        DispatchQueue.global(qos: .userInitiated).async {
            errData = err.fileHandleForReading.readDataToEndOfFile()
            group.leave()
        }
        let outData = out.fileHandleForReading.readDataToEndOfFile()
        group.wait()
        proc.waitUntilExit()
        return (proc.terminationStatus, outData, errData)
    }

    private func run(_ exe: URL, _ args: [String]) throws -> (code: Int32, out: String, err: String) {
        let (c, od, ed) = try runRaw(exe, args)
        return (c, String(decoding: od, as: UTF8.self), String(decoding: ed, as: UTF8.self))
    }

    // ipatool --format json <args> → parsed JSON object
    private func runJSON(_ args: [String]) throws -> [String: Any] {
        let r = try run(paths.ipatool, ["--format", "json"] + args)
        if r.code != 0 {
            let m = r.err.trimmingCharacters(in: .whitespacesAndNewlines)
            let m2 = m.isEmpty ? r.out.trimmingCharacters(in: .whitespacesAndNewlines) : m
            throw BackendError.message(m2.isEmpty ? "ipatool failed" : m2)
        }
        if let obj = Self.jsonObject(from: r.out) { return obj }
        throw BackendError.message("ipatool returned no parseable JSON")
    }

    static func jsonObject(from s: String) -> [String: Any]? {
        if let d = s.data(using: .utf8),
           let o = try? JSONSerialization.jsonObject(with: d) as? [String: Any] { return o }
        for line in s.split(separator: "\n").reversed() {
            let t = line.trimmingCharacters(in: .whitespaces)
            if t.hasPrefix("{"), let d = t.data(using: .utf8),
               let o = try? JSONSerialization.jsonObject(with: d) as? [String: Any] { return o }
        }
        return nil
    }

    private static func str(_ any: Any?) -> String {
        switch any {
        case let s as String: return s
        case let n as NSNumber: return n.stringValue
        case .some(let v): return "\(v)"
        case .none: return ""
        }
    }

    // ── Auth ──
    var isLoggedIn: Bool { FileManager.default.fileExists(atPath: paths.accountFile.path) }

    func authInfo() throws -> AccountInfo {
        let d = try runJSON(["auth", "info"])
        return AccountInfo(name: Self.str(d["name"]), email: Self.str(d["email"]))
    }

    func authLogin(email: String, password: String, authCode: String?) throws -> LoginOutcome {
        // The password never goes on argv (any same-user process can read argv via
        // `ps`). ipatool only prompts for a hidden password when stdin is a TTY, so
        // the child gets a PTY slave as stdin and we type the secrets into the PTY
        // master: first the password, then the 2FA code if we have one. Closing the
        // master right after delivers EOF once the buffer drains, so a login that
        // unexpectedly needs a code we don't have exits instead of hanging on the
        // prompt (its stderr then contains "Enter 2FA code:", mapped below).
        let args = ["--format", "json", "auth", "login", "-e", email]
        var master: Int32 = -1
        var slave: Int32 = -1
        guard openpty(&master, &slave, nil, nil, nil) == 0 else {
            throw BackendError.message("cannot allocate a terminal for the login prompt")
        }
        let masterHandle = FileHandle(fileDescriptor: master, closeOnDealloc: false)
        let slaveHandle = FileHandle(fileDescriptor: slave, closeOnDealloc: false)

        let proc = Process()
        proc.executableURL = paths.ipatool
        proc.arguments = args
        let out = Pipe(); let err = Pipe()
        proc.standardOutput = out
        proc.standardError = err
        proc.standardInput = slaveHandle
        do { try proc.run() } catch {
            try? masterHandle.close(); try? slaveHandle.close()
            throw BackendError.message("cannot launch ipatool: \(error.localizedDescription)")
        }
        try? slaveHandle.close() // the child owns its copy now

        var secrets = password + "\n"
        if let code = authCode, !code.isEmpty { secrets += code + "\n" }
        try? masterHandle.write(contentsOf: Data(secrets.utf8))
        try? masterHandle.close()

        var errData = Data()
        let group = DispatchGroup()
        group.enter()
        DispatchQueue.global(qos: .userInitiated).async {
            errData = err.fileHandleForReading.readDataToEndOfFile()
            group.leave()
        }
        let outData = out.fileHandleForReading.readDataToEndOfFile()
        group.wait()
        proc.waitUntilExit()

        let outStr = String(decoding: outData, as: UTF8.self)
        let errStr = String(decoding: errData, as: UTF8.self)
        if proc.terminationStatus == 0 {
            if let d = Self.jsonObject(from: outStr) {
                return .success(AccountInfo(name: Self.str(d["name"]), email: Self.str(d["email"])))
            }
            return .success(AccountInfo(name: "", email: email))
        }
        let blob = (errStr + outStr).lowercased()
        if blob.contains("two-factor") || blob.contains("auth-code")
            || blob.contains("auth code") || blob.contains("2fa code") {
            return .twoFactorRequired
        }
        let m = Self.cleanLoginError(errStr)
        throw BackendError.message(m.isEmpty ? "login failed" : m)
    }

    // Strip ipatool's interactive prompt noise ("Enter password: ****") from
    // stderr so the user sees only the actual error line.
    private static func cleanLoginError(_ err: String) -> String {
        return err
            .split(separator: "\n")
            .map { line -> String in
                var s = String(line)
                for prompt in ["Enter password: ", "Enter 2FA code: "] {
                    if let r = s.range(of: prompt) { s = String(s[r.upperBound...]) }
                }
                return s.trimmingCharacters(in: CharacterSet(charactersIn: "*").union(.whitespaces))
            }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func authRevoke() {
        _ = try? run(paths.ipatool, ["auth", "revoke"])
    }

    // ── Store ──
    func search(_ term: String, limit: Int) throws -> [StoreApp] {
        let d = try runJSON(["search", term, "-l", String(limit)])
        let apps = d["apps"] as? [[String: Any]] ?? []
        return apps.map {
            StoreApp(id: Self.str($0["id"]), bundleID: Self.str($0["bundleID"]),
                     name: Self.str($0["name"]), version: Self.str($0["version"]),
                     price: Self.str($0["price"]))
        }
    }

    func purchase(appID: String) throws {
        let d = try runJSON(["purchase", "-i", appID])
        if (d["success"] as? Bool) != true { throw BackendError.message("purchase failed") }
    }

    func listVersions(appID: String) throws -> [String] {
        let d = try runJSON(["list-versions", "-i", appID])
        let ids = d["externalVersionIdentifiers"] as? [Any] ?? []
        return ids.map { Self.str($0) }
    }

    func versionMetadata(appID: String, versionID: String) throws -> VersionRow {
        let d = try runJSON(["get-version-metadata", "-i", appID, "--external-version-id", versionID])
        return VersionRow(id: Self.str(d["externalVersionID"]).isEmpty ? versionID : Self.str(d["externalVersionID"]),
                          displayVersion: Self.str(d["displayVersion"]),
                          releaseDate: Self.str(d["releaseDate"]))
    }

    // Returns the saved .ipa URL after a successful download.
    func download(appID: String, externalVersionID: String?, purchase: Bool) throws -> URL {
        paths.ensureDirs()
        var args = ["download", "-i", appID, "-o", paths.appsDir.path]
        if let vid = externalVersionID, !vid.isEmpty { args += ["--external-version-id", vid] }
        if purchase { args += ["--purchase"] }     // boolean flag last
        let d = try runJSON(args)
        let out = Self.str(d["output"])
        if out.isEmpty { throw BackendError.message("download produced no file") }
        return URL(fileURLWithPath: out)
    }

    // ── Device ──
    func listDevices() throws -> [String] {
        let r = try run(paths.ideviceID, ["-l"])
        return r.out.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    func install(ipa: URL, udid: String?) -> (ok: Bool, output: String) {
        var args: [String] = []
        if let u = udid, !u.isEmpty { args += ["-u", u] }
        args += ["install", ipa.path]
        do {
            let r = try run(paths.ideviceinstaller, args)
            return (r.code == 0, (r.out + r.err).trimmingCharacters(in: .whitespacesAndNewlines))
        } catch {
            return (false, error.localizedDescription)
        }
    }

    // ── Library (Apps/ + lists + name map) ──
    // Read the app bundle's Info.plist out of an .ipa (zip), or nil on any failure.
    func ipaPlist(_ url: URL) -> [String: Any]? {
        guard let (c, listOut, _) = try? run(paths.unzip, ["-Z1", url.path]), c == 0 else { return nil }
        let member = listOut.split(separator: "\n").map(String.init).first {
            $0.range(of: #"^Payload/[^/]+\.app/Info\.plist$"#, options: .regularExpression) != nil
        }
        guard let m = member,
              let (c2, data, _) = try? runRaw(paths.unzip, ["-p", url.path, m]), c2 == 0,
              let obj = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any]
        else { return nil }
        return obj
    }

    func readIPAInfo(_ url: URL) -> IpaFile {
        let p = ipaPlist(url)
        let name = (p?["CFBundleName"] as? String) ?? (p?["CFBundleDisplayName"] as? String) ?? url.deletingPathExtension().lastPathComponent
        return IpaFile(
            id: url.path, url: url, name: name,
            version: (p?["CFBundleShortVersionString"] as? String) ?? "",
            minIOS: (p?["MinimumOSVersion"] as? String) ?? "",
            bundleID: (p?["CFBundleIdentifier"] as? String) ?? ""
        )
    }

    func sanitizeFilename(_ s: String) -> String {
        let bad = Set("\\/:*?\"<>|")
        let cleaned = String(s.filter { !bad.contains($0) }).trimmingCharacters(in: .whitespaces)
        return cleaned.replacingOccurrences(of: #"\s+"#, with: "_", options: .regularExpression)
    }

    // Rename a freshly-downloaded .ipa to the friendly <Name>_<version>_iOS_<min>+.ipa
    // form inside Apps/, mirroring the original Move-IPA-Files / library.finalize_download.
    // Resolves the display name plist → caller fallback → offline catalog; if none is
    // available, or the target already exists, the file is left where ipatool put it.
    // Returns the final URL and the resolved name (empty when no name could be found).
    func finalizeDownload(_ saved: URL, fallbackName: String?, appID: String) -> (url: URL, name: String) {
        let p = ipaPlist(saved)
        var name = (p?["CFBundleName"] as? String) ?? (p?["CFBundleDisplayName"] as? String) ?? ""
        if name.isEmpty { name = (fallbackName?.isEmpty == false ? fallbackName! : (githubName(appID: appID) ?? "")) }
        guard !name.isEmpty else { return (saved, "") }
        let version = (p?["CFBundleShortVersionString"] as? String) ?? ""
        let minIOS = (p?["MinimumOSVersion"] as? String) ?? ""
        let friendly = "\(sanitizeFilename(name))_\(version)_iOS_\(minIOS)+.ipa"
            .replacingOccurrences(of: #"\s+"#, with: "_", options: .regularExpression)
        let target = paths.appsDir.appendingPathComponent(friendly)
        if target.lastPathComponent != saved.lastPathComponent && !FileManager.default.fileExists(atPath: target.path) {
            if (try? FileManager.default.moveItem(at: saved, to: target)) != nil { return (target, name) }
        }
        return (saved, name)
    }

    func listApps() -> [IpaFile] {
        let fm = FileManager.default
        let items = (try? fm.contentsOfDirectory(at: paths.appsDir, includingPropertiesForKeys: nil)) ?? []
        let ipas = items.filter { $0.pathExtension.lowercased() == "ipa" }
        return ipas.map { readIPAInfo($0) }.sorted {
            ($0.name.lowercased(), $0.fileName) < ($1.name.lowercased(), $1.fileName)
        }
    }

    // Mirrors the original's catalog regex ^(.+?):\s*(\d+) — non-greedy, so a name
    // that itself contains a colon (e.g. "Au.ru (Барахолка 24: объявления): 6760170997")
    // still binds to the digit run that follows the LAST relevant colon.
    private static let catalogLineRE = try! NSRegularExpression(pattern: #"^(.+?):\s*(\d+)"#)

    static func parseCatalogLine(_ line: String) -> CatalogEntry? {
        let range = NSRange(line.startIndex..., in: line)
        guard let m = catalogLineRE.firstMatch(in: line, range: range),
              let nameR = Range(m.range(at: 1), in: line),
              let idR = Range(m.range(at: 2), in: line) else { return nil }
        let name = line[nameR].trimmingCharacters(in: .whitespacesAndNewlines)
        return CatalogEntry(id: String(line[idR]), name: name)
    }

    // The full offline catalog (assets/Apps_ID_List.txt) as [{name,id}].
    func githubCatalog() -> [CatalogEntry] {
        guard let text = try? String(contentsOf: paths.assetsList, encoding: .utf8) else { return [] }
        return text.split(whereSeparator: \.isNewline).compactMap { Self.parseCatalogLine(String($0)) }
    }

    func githubName(appID: String) -> String? {
        githubCatalog().first { $0.id == appID }?.name
    }

    // A saved list ("Purchased"/"Downloaded") as [{name,id}]; [] if missing/invalid.
    func loadSavedList(purchased: Bool) -> [CatalogEntry] {
        let file = purchased ? paths.purchasedList : paths.downloadedList
        guard let data = try? Data(contentsOf: file),
              let arr = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { return [] }
        return arr.map { CatalogEntry(id: Self.str($0["appid"]), name: Self.str($0["name"])) }
            .filter { !$0.id.isEmpty }
    }

    // Save to a saved-list JSON file, original-compatible: [{"name","appid"}], deduped by appid.
    // Mirrors the original Save-App-To-List: blank or "Unknown" names are not recorded.
    @discardableResult
    func saveToList(appID: String, name: String, purchased: Bool) -> Bool {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty || trimmed == "Unknown" { return false }
        paths.ensureDirs()
        let file = purchased ? paths.purchasedList : paths.downloadedList
        var entries: [[String: String]] = []
        if let data = try? Data(contentsOf: file),
           let arr = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] {
            entries = arr.map { ["name": Self.str($0["name"]), "appid": Self.str($0["appid"])] }
        }
        if entries.contains(where: { $0["appid"] == appID }) { return false }
        entries.append(["name": trimmed, "appid": appID])
        entries.sort { ($0["name"] ?? "").lowercased() < ($1["name"] ?? "").lowercased() }
        if let data = try? JSONSerialization.data(withJSONObject: entries, options: [.prettyPrinted]) {
            try? data.write(to: file)
        }
        return true
    }

    // ── Clear data (menu 12) ──
    func clearList(purchased: Bool) {
        try? FileManager.default.removeItem(at: purchased ? paths.purchasedList : paths.downloadedList)
    }

    @discardableResult
    func clearApps() -> Bool {
        let fm = FileManager.default
        let items = (try? fm.contentsOfDirectory(at: paths.appsDir, includingPropertiesForKeys: nil)) ?? []
        var deleted = 0
        for u in items where u.pathExtension.lowercased() == "ipa" {
            if (try? fm.removeItem(at: u)) != nil { deleted += 1 }
        }
        return deleted >= 1
    }

    // ── Pairing (idevicepair pair); user must tap "Trust" on the device ──
    func pair(udid: String?) -> (ok: Bool, output: String) {
        var args: [String] = []
        if let u = udid, !u.isEmpty { args += ["-u", u] }
        args += ["pair"]
        do {
            let r = try run(paths.idevicePair, args)
            return (r.code == 0, (r.out + r.err).trimmingCharacters(in: .whitespacesAndNewlines))
        } catch {
            return (false, error.localizedDescription)
        }
    }

    // ── Language persistence (Lang_Config.txt, shared with the TUI) ──
    func loadLang() -> Lang {
        if let raw = try? String(contentsOf: paths.langConfigFile, encoding: .utf8) {
            let v = raw.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
            if v == "EN" { return .en }
            if v == "RU" { return .ru }
        } else {
            saveLang(.ru)
        }
        return .ru
    }

    func saveLang(_ lang: Lang) {
        try? (lang.rawValue + "\n").data(using: .utf8)?.write(to: paths.langConfigFile)
    }

    // ── Ownership scan ──
    // Probe whether the signed-in Apple ID OWNS an app, without fully downloading it:
    // `download` WITHOUT --purchase fails fast ("you must purchase this app first")
    // when not owned, but starts transferring the IPA when owned. We watch a throwaway
    // output dir for the first file / the process still running, then abort. No data
    // is kept (the temp dir is removed). Never touches the project's Apps/ folder.
    func probeOwnership(appID: String) -> Bool {
        let base = FileManager.default.temporaryDirectory
            .appendingPathComponent("ipa_probe_\(appID)_\(UUID().uuidString)")
        let outDir = base.appendingPathComponent("out")
        try? FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: base) }

        func startedTransfer() -> Bool {
            ((try? FileManager.default.contentsOfDirectory(atPath: outDir.path))?.isEmpty == false)
        }

        let proc = Process()
        proc.executableURL = paths.ipatool
        proc.arguments = ["--format", "json", "download", "-i", appID, "-o", outDir.path]
        proc.standardOutput = FileHandle.nullDevice
        proc.standardError = FileHandle.nullDevice
        proc.standardInput = FileHandle.nullDevice
        do { try proc.run() } catch { return false }

        let deadline = Date().addingTimeInterval(6)
        var owned = false
        while proc.isRunning && Date() < deadline {
            if startedTransfer() { owned = true; break }
            usleep(150_000)   // 0.15s
        }
        if proc.isRunning {
            owned = true       // still transferring after the window → owned
            proc.terminate()
        }
        proc.waitUntilExit()
        if !owned && startedTransfer() { owned = true }   // tiny app finished within the window
        return owned
    }

    // Which of these app ids are currently available in the App Store storefront
    // (default: ru). Uses the PUBLIC iTunes Lookup API — no Apple ID, no account risk.
    func storeAvailability(appIDs: [String], country: String = "ru") -> Set<String> {
        var found = Set<String>()
        var i = 0
        while i < appIDs.count {
            let chunk = Array(appIDs[i..<min(i + 20, appIDs.count)])
            i += 20
            let ids = chunk.joined(separator: ",")
            guard let url = URL(string: "https://itunes.apple.com/lookup?country=\(country)&id=\(ids)"),
                  let data = try? Data(contentsOf: url),
                  let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let results = obj["results"] as? [[String: Any]] else { continue }
            for r in results { let tid = Self.str(r["trackId"]); if !tid.isEmpty { found.insert(tid) } }
        }
        return found
    }

    func saveOwnedScan(removedOwned: [CatalogEntry], removedNotOwned: [CatalogEntry]) {
        paths.ensureDirs()
        func enc(_ xs: [CatalogEntry]) -> [[String: String]] { xs.map { ["appid": $0.id, "name": $0.name] } }
        let obj: [String: Any] = ["removedOwned": enc(removedOwned), "removedNotOwned": enc(removedNotOwned)]
        if let data = try? JSONSerialization.data(withJSONObject: obj, options: [.prettyPrinted]) {
            try? data.write(to: paths.ownedScanFile)
        }
    }

    func loadOwnedScan() -> (removedOwned: [CatalogEntry], removedNotOwned: [CatalogEntry])? {
        guard let data = try? Data(contentsOf: paths.ownedScanFile),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        func dec(_ key: String) -> [CatalogEntry] {
            (obj[key] as? [[String: Any]] ?? []).map { CatalogEntry(id: Self.str($0["appid"]), name: Self.str($0["name"])) }
        }
        return (dec("removedOwned"), dec("removedNotOwned"))
    }
}
