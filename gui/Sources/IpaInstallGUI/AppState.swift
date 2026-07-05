// AppState.swift — the observable view-model. All backend calls run on a detached
// task (Process blocks) and results are published back on the main actor.
//
// This view-model covers the same 15 actions as the terminal menu:
//   search/by-ID/list → purchase · download latest · download version  (1-9)
//   min-iOS table + install                                            (10-11)
//   clear data · log out · GitHub page · language                      (12-15)

import AppKit
import Foundation
import SwiftUI

// Which collection the Lists tab is showing (covers the original menus 7-9 sub-menus).
enum ListSource: String, CaseIterable, Identifiable {
    case catalog
    case savedDownloaded
    case savedPurchased
    case notDownloaded
    case notPurchased
    case recoverable       // scan result: removed from the store AND owned → re-downloadable
    case removedNotOwned   // scan result: removed from the store but NOT owned

    var id: String { rawValue }
    var labelKey: String {
        switch self {
        case .catalog:         return "DownloadedListMenu1"   // Full apps list (catalog)
        case .savedDownloaded: return "DownloadedListMenu2"   // Downloaded apps list
        case .savedPurchased:  return "PurchasedListMenu2"    // Purchased apps list
        case .notDownloaded:   return "DownloadedListMenu3"   // Not downloaded apps list
        case .notPurchased:    return "PurchasedListMenu3"    // Not purchased apps list
        case .recoverable:     return "RecoverableSource"
        case .removedNotOwned: return "RemovedNotOwnedSource"
        }
    }
    var isScanResult: Bool { self == .recoverable || self == .removedNotOwned }
}

// Sendable work units for the batch runner (cross the actor boundary into a detached task).
private struct DLItem: Sendable { let id: String; let name: String?; let vid: String?; let purchase: Bool }
private struct PurchaseItem: Sendable { let id: String; let name: String }

@MainActor
final class AppState: ObservableObject {
    let backend: Backend
    let paths: AppPaths
    let catalogCount: Int

    // Language (persisted to Lang_Config.txt, shared with the TUI)
    @Published var lang: Lang = .ru

    // Session
    @Published var loggedIn = false
    @Published var account: AccountInfo?

    // Login form
    @Published var email = ""
    @Published var password = ""
    @Published var authCode = ""
    @Published var needsTwoFactor = false

    // Global UI state
    @Published var busy = false
    @Published var status = ""
    @Published var statusIsError = false

    // Store
    @Published var searchTerm = ""
    @Published var searchLimit = 20
    @Published var directAppID = ""
    @Published var results: [StoreApp] = []
    @Published var selectedResultIDs: Set<StoreApp.ID> = []

    // Version sheet
    @Published var showVersionSheet = false
    @Published var versionAppID = ""
    @Published var versionAppName = ""
    @Published var versions: [VersionRow] = []
    @Published var selectedVersionIDs: Set<VersionRow.ID> = []
    @Published var loadingVersions = false
    @Published var versionCount = 15   // how many newest versions to fetch (user-adjustable, like AskVerCount)
    @Published var versionTotal = 0    // total versions the app has (caps the count)

    // Lists tab (catalog / saved lists)
    @Published var listSource: ListSource = .catalog
    @Published var listEntries: [CatalogEntry] = []
    @Published var selectedListIDs: Set<String> = []

    // Ownership scan
    @Published var scanning = false
    @Published var scanDone = 0
    @Published var scanTotal = 0
    @Published var scanResultExists = false
    @Published var showScanWarning = false
    private var cancelScan = false

    // Device / library
    @Published var devices: [String] = []
    @Published var selectedDevice: String?
    @Published var apps: [IpaFile] = []
    @Published var selectedAppPaths: Set<IpaFile.ID> = []

    init() {
        let p = AppPaths.discover()
        p.ensureDirs()
        self.paths = p
        self.backend = Backend(paths: p)
        self.lang = backend.loadLang()
        self.scanResultExists = backend.loadOwnedScan() != nil
        self.catalogCount = backend.githubCatalog().count
        refreshSession()
    }

    // ── Localization ──
    func S(_ key: String, _ args: String...) -> String { L10n.t(key, lang, args) }

    // Translate a raw ipatool/device error into a clearer, localized hint where we can.
    private func friendlyError(_ raw: String) -> String {
        let low = raw.lowercased()
        if low.contains("license") && low.contains("required") { return S("ErrLicenseRequired") }
        if low.contains("temporarily unavailable") { return S("ErrUnavailable") }
        if low.contains("app not found") { return S("ErrAppNotFound") }
        return raw
    }

    func setStatus(_ text: String, error: Bool = false) {
        status = text
        statusIsError = error
    }

    // ── Generic sequential batch runner ──
    // Runs `run` over every item in a single detached task (downloads/installs must be
    // serial, same as the original loop), then posts a localized summary on the main actor.
    // `run` returns nil on success or an error message; the last error is fed to `summary`
    // so a partial/total failure can explain *why*.
    private func batch<T: Sendable>(
        _ startStatus: String,
        _ items: [T],
        run: @escaping @Sendable (T) -> String?,
        summaryKey: String,
        refreshAppsAfter: Bool = false
    ) {
        guard !items.isEmpty else { return }
        busy = true; status = startStatus; statusIsError = false
        Task {
            let result = await Task.detached(priority: .userInitiated) { () -> (Int, String?) in
                var ok = 0; var lastErr: String? = nil
                for it in items {
                    if let e = run(it) { lastErr = e } else { ok += 1 }
                }
                return (ok, lastErr)
            }.value
            self.busy = false
            let (ok, err) = result
            var msg = self.S(summaryKey, "\(ok)", "\(items.count)")
            if ok < items.count, let err = err { msg += " — " + self.friendlyError(err) }
            self.setStatus(msg, error: ok < items.count)
            if refreshAppsAfter { self.refreshApps() }
        }
    }

    private func downloadBatch(_ items: [DLItem]) {
        let b = backend
        batch(S("StatusDownloading"), items, run: { it in
            do {
                let saved = try b.download(appID: it.id, externalVersionID: it.vid, purchase: it.purchase)
                // Rename to the friendly <Name>_<version>_iOS_<min>+.ipa form (like the TUI).
                let (_, name) = b.finalizeDownload(saved, fallbackName: it.name, appID: it.id)
                b.saveToList(appID: it.id, name: name, purchased: false)
                return nil
            } catch { return error.localizedDescription }
        }, summaryKey: "StatusDownloadedN", refreshAppsAfter: true)
    }

    private func purchaseBatch(_ items: [PurchaseItem]) {
        let b = backend
        let label = items.count == 1 ? items[0].name : "\(items.count)"
        batch(S("StatusPurchasing", label), items, run: { it in
            // The original always records the purchase, even when the app is already
            // licensed (ipatool exits non-zero with "license already exists"). Save
            // regardless, and treat an already-owned app as a success.
            var err: String? = nil
            do { try b.purchase(appID: it.id) }
            catch let BackendError.message(m) { if !m.lowercased().contains("already") { err = m } }
            catch { err = error.localizedDescription }
            b.saveToList(appID: it.id, name: it.name, purchased: true)
            return err
        }, summaryKey: "StatusPurchasedN")
    }

    // ── Session ──
    func refreshSession() {
        loggedIn = backend.isLoggedIn
        if loggedIn {
            let b = backend
            Task {
                let info = try? await Task.detached { try b.authInfo() }.value
                self.account = info
            }
            refreshDevices()
            refreshApps()
        }
    }

    func login() {
        let b = backend
        let e = email, p = password
        let code = needsTwoFactor ? authCode : nil
        busy = true; status = S("StatusSigningIn"); statusIsError = false
        Task {
            do {
                let outcome = try await Task.detached { try b.authLogin(email: e, password: p, authCode: code) }.value
                self.busy = false
                switch outcome {
                case .twoFactorRequired:
                    self.needsTwoFactor = true
                    self.setStatus(self.S("StatusTwoFactor"))
                case .success(let info):
                    self.account = info
                    self.loggedIn = true
                    self.password = ""; self.authCode = ""; self.needsTwoFactor = false
                    self.setStatus(self.S("StatusSignedInAs", info.email))
                    self.refreshDevices(); self.refreshApps()
                }
            } catch {
                self.busy = false
                self.setStatus(error.localizedDescription, error: true)
            }
        }
    }

    func logout() {
        let b = backend
        busy = true; status = S("StatusSigningOut"); statusIsError = false
        Task {
            await Task.detached { b.authRevoke() }.value
            self.busy = false
            self.loggedIn = false
            self.account = nil
            self.results = []
            self.selectedResultIDs = []
            self.setStatus(self.S("StatusSignedOut"))
        }
    }

    // ── Store: search ──
    func runSearch() {
        guard !busy else { return }   // the search field's onCommit isn't gated by .disabled
        let b = backend
        let term = searchTerm.trimmingCharacters(in: .whitespaces)
        let limit = searchLimit
        guard !term.isEmpty else { setStatus(S("StatusEnterTerm"), error: true); return }
        busy = true; status = S("StatusSearching"); statusIsError = false
        Task {
            do {
                let r = try await Task.detached { try b.search(term, limit: limit) }.value
                self.busy = false
                self.results = r
                self.selectedResultIDs = []
                self.setStatus(r.isEmpty ? self.S("StatusNoneFound") : self.S("StatusFoundApps", "\(r.count)"),
                               error: r.isEmpty)
            } catch {
                self.busy = false
                self.setStatus(error.localizedDescription, error: true)
            }
        }
    }

    private func selectedApps() -> [StoreApp] { results.filter { selectedResultIDs.contains($0.id) } }

    // 1 · purchase the selected search result(s)
    func purchaseSelected() {
        let sel = selectedApps()
        guard !sel.isEmpty else { setStatus(S("StatusSelectApp"), error: true); return }
        purchaseBatch(sel.map { PurchaseItem(id: $0.id, name: $0.name) })
    }

    // 2 · download latest of the selected search result(s)
    func downloadLatestSelected() {
        let sel = selectedApps()
        guard !sel.isEmpty else { setStatus(S("StatusSelectApp"), error: true); return }
        downloadBatch(sel.map { DLItem(id: $0.id, name: $0.name, vid: nil, purchase: true) })
    }

    // 3 · download a chosen version of the (first) selected search result
    func openVersions() {
        guard let app = selectedApps().first else { setStatus(S("StatusSelectApp"), error: true); return }
        openVersionSheet(appID: app.id, name: app.name)
    }

    // ── Store: by numeric ID ──
    private func parseIDs(_ raw: String) -> [String]? {
        let parts = raw.split(whereSeparator: { $0 == "," || $0 == " " || $0 == "\n" || $0 == "\t" })
            .map(String.init).filter { !$0.isEmpty }
        // ASCII decimal digits only (matches the original ^\d+$; rejects ½, ², Roman, etc.)
        if parts.isEmpty || !parts.allSatisfy({ $0.allSatisfy { $0.isASCII && $0.isNumber } }) { return nil }
        return parts
    }

    // 4 · purchase by ID
    func purchaseByID() {
        guard let ids = parseIDs(directAppID) else { setStatus(S("StatusEnterIDs"), error: true); return }
        let b = backend
        purchaseBatch(ids.map { PurchaseItem(id: $0, name: b.githubName(appID: $0) ?? "Unknown") })
    }

    // 5 · download latest by ID
    func downloadByID() {
        guard let ids = parseIDs(directAppID) else { setStatus(S("StatusEnterIDs"), error: true); return }
        let b = backend
        downloadBatch(ids.map { DLItem(id: $0, name: b.githubName(appID: $0), vid: nil, purchase: true) })
    }

    // 6 · download by ID with version selection (first ID)
    func openVersionsByID() {
        guard let ids = parseIDs(directAppID), let first = ids.first else {
            setStatus(S("StatusEnterIDs"), error: true); return
        }
        openVersionSheet(appID: first, name: backend.githubName(appID: first) ?? "")
    }

    // ── Version sheet ──
    func openVersionSheet(appID: String, name: String) {
        versionAppID = appID
        versionAppName = name.isEmpty ? appID : name
        versions = []
        selectedVersionIDs = []
        versionTotal = 0
        // versionCount is kept across opens (a remembered preference); the Stepper's
        // onChange reloads only on real user changes, so opening never double-loads.
        showVersionSheet = true
        loadVersions()
    }

    func loadVersions() {
        let b = backend
        let appID = versionAppID
        let count = versionCount
        loadingVersions = true
        Task {
            do {
                let ids = try await Task.detached { try b.listVersions(appID: appID) }.value
                self.versionTotal = ids.count
                // newest first; show as many as the user asked for (AskVerCount), capped at what exists
                let latest = Array(ids.reversed().prefix(max(1, min(count, ids.count))))
                let rows = await Task.detached { () -> [VersionRow] in
                    latest.map { vid in
                        (try? b.versionMetadata(appID: appID, versionID: vid))
                            ?? VersionRow(id: vid, displayVersion: "NA", releaseDate: "")
                    }
                }.value
                self.loadingVersions = false
                self.versions = rows
            } catch {
                self.loadingVersions = false
                self.setStatus(self.friendlyError(error.localizedDescription), error: true)
                self.showVersionSheet = false
            }
        }
    }

    func downloadSelectedVersions() {
        let sel = versions.filter { selectedVersionIDs.contains($0.id) }
        guard !sel.isEmpty else { return }
        showVersionSheet = false
        let appID = versionAppID, name = versionAppName
        // Version downloads do not auto-purchase (matches the original behavior).
        downloadBatch(sel.map { DLItem(id: appID, name: name, vid: $0.id, purchase: false) })
    }

    // ── Lists tab (menus 7-9) ──
    nonisolated static func entries(for src: ListSource, backend b: Backend) -> [CatalogEntry] {
        switch src {
        case .catalog:         return b.githubCatalog()
        case .savedDownloaded: return b.loadSavedList(purchased: false)
        case .savedPurchased:  return b.loadSavedList(purchased: true)
        case .notDownloaded:
            let saved = Set(b.loadSavedList(purchased: false).map { $0.id })
            return b.githubCatalog().filter { !saved.contains($0.id) }
        case .notPurchased:
            let saved = Set(b.loadSavedList(purchased: true).map { $0.id })
            return b.githubCatalog().filter { !saved.contains($0.id) }
        case .recoverable:
            return b.loadOwnedScan()?.removedOwned ?? []
        case .removedNotOwned:
            return b.loadOwnedScan()?.removedNotOwned ?? []
        }
    }

    func loadListSource() {
        let b = backend; let src = listSource
        busy = true; status = ""; statusIsError = false
        Task {
            let entries = await Task.detached { AppState.entries(for: src, backend: b) }.value
            self.busy = false
            self.listEntries = entries
            self.selectedListIDs = []
            if entries.isEmpty {
                switch src {
                case .savedDownloaded: self.setStatus(self.S("ErrorHistoryEmpty"), error: true)
                case .savedPurchased:  self.setStatus(self.S("ErrorPurchasedEmpty"), error: true)
                case .recoverable, .removedNotOwned: self.setStatus(self.S("OwnedEmptyHint"))
                default:               self.setStatus(self.S("ErrorNoAppsFound"), error: true)
                }
            }
        }
    }

    // Recompute the visible list entries off the main actor (catalog parse / file reads),
    // without disturbing the current status line. Used after a clear-data action.
    private func reloadListEntriesQuiet() {
        let b = backend; let src = listSource
        Task {
            let e = await Task.detached { AppState.entries(for: src, backend: b) }.value
            self.listEntries = e
            self.selectedListIDs = self.selectedListIDs.intersection(Set(e.map { $0.id }))
        }
    }

    private func selectedListEntries() -> [CatalogEntry] { listEntries.filter { selectedListIDs.contains($0.id) } }

    // 7 · purchase from the list selection
    func purchaseFromList() {
        let sel = selectedListEntries()
        guard !sel.isEmpty else { setStatus(S("StatusSelectApp"), error: true); return }
        purchaseBatch(sel.map { PurchaseItem(id: $0.id, name: $0.name) })
    }

    // 8 · download latest from the list selection
    func downloadLatestFromList() {
        let sel = selectedListEntries()
        guard !sel.isEmpty else { setStatus(S("StatusSelectApp"), error: true); return }
        downloadBatch(sel.map { DLItem(id: $0.id, name: $0.name, vid: nil, purchase: true) })
    }

    // 9 · download with version selection from the list (first selected)
    func downloadVersionFromList() {
        guard let first = selectedListEntries().first else { setStatus(S("StatusSelectApp"), error: true); return }
        openVersionSheet(appID: first.id, name: first.name)
    }

    // ── Ownership scan ──
    // Probe every catalog app for ownership, then split the owned ones into
    // "removed from the store" (the apps this tool is essential for) vs "still in store".
    func requestOwnershipScan() {
        guard !scanning else { return }
        showScanWarning = true   // confirm first — this touches the personal Apple ID a lot
    }

    func startOwnershipScan() {
        guard !scanning else { return }
        let b = backend
        let catalog = b.githubCatalog()
        scanning = true
        cancelScan = false
        scanDone = 0
        scanTotal = 0
        statusIsError = false
        status = S("ScanFiltering")
        Task {
            // Phase 1 (free, no account risk): which catalog apps are removed from the store.
            let removed = await Task.detached { () -> [CatalogEntry] in
                let inStore = b.storeAvailability(appIDs: catalog.map { $0.id })
                return catalog.filter { !inStore.contains($0.id) }
            }.value
            self.scanTotal = removed.count
            self.status = self.S("ScanRunning", "0", "\(removed.count)")

            // Phase 2 (account): probe ownership ONLY on the removed apps.
            var recoverable: [CatalogEntry] = []
            var notOwned: [CatalogEntry] = []
            for (i, e) in removed.enumerated() {
                if self.cancelScan { break }
                let owned = await Task.detached { b.probeOwnership(appID: e.id) }.value
                if owned { recoverable.append(e) } else { notOwned.append(e) }
                self.scanDone = i + 1
                self.status = self.S("ScanRunning", "\(i + 1)", "\(removed.count)")
                try? await Task.sleep(nanoseconds: 700_000_000)   // be gentle on the account
            }
            let cancelled = self.cancelScan
            b.saveOwnedScan(removedOwned: recoverable, removedNotOwned: notOwned)
            self.scanResultExists = true
            self.scanning = false
            if cancelled {
                self.setStatus(self.S("ScanCancelledMsg", "\(self.scanDone)", "\(self.scanTotal)"))
            } else {
                self.setStatus(self.S("ScanDoneMsg", "\(removed.count)", "\(recoverable.count)"))
            }
            if self.listSource.isScanResult { self.reloadListEntriesQuiet() }
        }
    }

    func cancelOwnershipScan() { cancelScan = true }

    // ── Device / library ──
    func refreshDevices() {
        let b = backend
        Task {
            let d = (try? await Task.detached { try b.listDevices() }.value) ?? []
            self.devices = d
            if self.selectedDevice == nil || !(d.contains(self.selectedDevice ?? "")) {
                self.selectedDevice = d.first
            }
        }
    }

    func refreshApps() {
        let b = backend
        Task {
            let a = await Task.detached { b.listApps() }.value
            self.apps = a
            self.selectedAppPaths = self.selectedAppPaths.intersection(Set(a.map { $0.id }))
        }
    }

    func pairDevice() {
        let b = backend; let udid = selectedDevice
        busy = true; status = S("StatusPairing"); statusIsError = false
        Task {
            let r = await Task.detached { b.pair(udid: udid) }.value
            self.busy = false
            if r.ok { self.setStatus(self.S("StatusPaired")); self.refreshDevices() }
            else { self.setStatus(self.S("StatusPairFailed", r.output), error: true) }
        }
    }

    // 11 · install the selected IPA(s) to the device
    func installSelected() {
        let sel = apps.filter { selectedAppPaths.contains($0.id) }
        guard !sel.isEmpty else { setStatus(S("StatusSelectInstall"), error: true); return }
        guard !devices.isEmpty else { setStatus(S("NoDevice"), error: true); return }
        let b = backend; let udid = selectedDevice
        let label = sel.count == 1 ? sel[0].fileName : "\(sel.count)"
        batch(S("StatusInstalling", label), sel, run: { ipa in
            let r = b.install(ipa: ipa.url, udid: udid)
            return r.ok ? nil : (r.output.isEmpty ? "install failed" : r.output)
        }, summaryKey: "StatusInstalledN")
    }

    // ── 12 · clear data ──
    func clearDownloadedList() {
        backend.clearList(purchased: false)
        reloadListEntriesQuiet()
        setStatus(S("DownloadedListCleared"))
    }

    func clearPurchasedList() {
        backend.clearList(purchased: true)
        reloadListEntriesQuiet()
        setStatus(S("PurchasedListCleared"))
    }

    func clearAppsFolder() {
        let removed = backend.clearApps()
        refreshApps()
        setStatus(removed ? S("AppsCleared") : S("ErrorNoApps"), error: !removed)
    }

    // ── 14 · GitHub page ──
    func openGitHub() {
        if let url = URL(string: "https://github.com/kda2495/IPA_Downloader") {
            NSWorkspace.shared.open(url)
        }
    }

    // ── 15 · language ──
    func toggleLanguage() { setLanguage(lang.other) }

    func setLanguage(_ new: Lang) {
        guard new != lang else { return }
        lang = new
        backend.saveLang(new)
        setStatus(S("LangChanged"))
    }
}
