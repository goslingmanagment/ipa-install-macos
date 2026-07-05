// Views.swift — SwiftUI app shell and the four tabs (Account / Store / Lists / Device),
// plus a top bar (language · GitHub · clear-data) and the shared version sheet.
// Every visible string goes through state.S(...) so RU/EN switch live.

import AppKit
import SwiftUI

struct IpaInstallApp: App {
    @StateObject private var state = AppState()

    var body: some Scene {
        WindowGroup("IPA Install") {
            ContentView()
                .environmentObject(state)
                .frame(minWidth: 860, minHeight: 600)
                .onAppear {
                    NSApp.setActivationPolicy(.regular)
                    NSApp.activate(ignoringOtherApps: true)
                }
        }
        .windowStyle(.titleBar)
    }
}

struct ContentView: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        VStack(spacing: 0) {
            TopBar()
            TabView {
                AccountView().tabItem { Label(state.S("TabAccount"), systemImage: "person.crop.circle") }
                StoreView().tabItem { Label(state.S("TabStore"), systemImage: "magnifyingglass") }
                ListsView().tabItem { Label(state.S("TabLists"), systemImage: "list.bullet.rectangle") }
                DeviceView().tabItem { Label(state.S("TabDevice"), systemImage: "iphone") }
            }
            .padding(12)
            StatusBar()
        }
        .sheet(isPresented: $state.showVersionSheet) { VersionSheet() }
    }
}

// ── Top bar: language · GitHub · clear-data ─────────────────────────────────────
struct TopBar: View {
    @EnvironmentObject var state: AppState
    var body: some View {
        HStack(spacing: 12) {
            Text(state.S("AppTitle")).font(.headline)
            Spacer()
            Picker("", selection: Binding(get: { state.lang }, set: { state.setLanguage($0) })) {
                Text("RU").tag(Lang.ru)
                Text("EN").tag(Lang.en)
            }
            .pickerStyle(.segmented).fixedSize()
            .help(state.S("LanguageMenu"))
            Menu {
                Button(state.S("BtnClearDownloaded")) { state.clearDownloadedList() }
                Button(state.S("BtnClearPurchased")) { state.clearPurchasedList() }
                Divider()
                Button(state.S("BtnClearApps"), role: .destructive) { state.clearAppsFolder() }
            } label: {
                Label(state.S("DataMenu"), systemImage: "trash")
            }
            .menuStyle(.borderlessButton).fixedSize()
            Button { state.openGitHub() } label: { Label(state.S("BtnGitHub"), systemImage: "link") }
                .help("github.com/kda2495/IPA_Downloader")
        }
        .padding(.horizontal, 14).padding(.vertical, 8)
        .background(.bar)
    }
}

// ── Shared status bar ───────────────────────────────────────────────────────────
struct StatusBar: View {
    @EnvironmentObject var state: AppState
    var body: some View {
        HStack(spacing: 8) {
            if state.busy { ProgressView().controlSize(.small) }
            Text(state.status.isEmpty ? " " : state.status)
                .font(.callout)
                .foregroundStyle(state.statusIsError ? Color.red : Color.secondary)
                .lineLimit(2)
            Spacer()
            Circle()
                .fill(state.loggedIn ? Color.green : Color.gray)
                .frame(width: 9, height: 9)
            Text(state.loggedIn ? (state.account?.email ?? state.S("StatusBarSignedIn")) : state.S("StatusBarSignedOut"))
                .font(.caption).foregroundStyle(.secondary)
        }
        .padding(.horizontal, 14).padding(.vertical, 8)
        .background(.bar)
    }
}

// ── Account ─────────────────────────────────────────────────────────────────────
struct AccountView: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        if state.loggedIn {
            VStack(alignment: .leading, spacing: 14) {
                Label(state.S("SignedIn"), systemImage: "checkmark.seal.fill").foregroundStyle(.green).font(.title3)
                if let a = state.account {
                    Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 6) {
                        GridRow { Text(state.S("NameLabel")).foregroundStyle(.secondary); Text(a.name.isEmpty ? state.S("Dash") : a.name) }
                        GridRow { Text(state.S("AppleIDLabel")).foregroundStyle(.secondary); Text(a.email) }
                    }
                }
                Button(role: .destructive) { state.logout() } label: {
                    Label(state.S("BtnLogOut"), systemImage: "rectangle.portrait.and.arrow.right")
                }
                .disabled(state.busy)
                Spacer()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            VStack(alignment: .leading, spacing: 12) {
                Text(state.S("SignInTitle")).font(.title3.bold())
                Text(state.S("DisposableHint"))
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                Form {
                    TextField(state.S("EmailField"), text: $state.email)
                        .textContentType(.username)
                    SecureField(state.S("PasswordField"), text: $state.password)
                    if state.needsTwoFactor {
                        TextField(state.S("TwoFactorField"), text: $state.authCode)
                    }
                }
                .frame(maxWidth: 420)
                Button { state.login() } label: { Label(state.S("BtnSignIn"), systemImage: "arrow.right.circle.fill") }
                    .keyboardShortcut(.defaultAction)
                    .disabled(state.busy || state.email.isEmpty || state.password.isEmpty)
                Spacer()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

// ── Store (search / by-ID / download) ───────────────────────────────────────────
struct StoreView: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        if !state.loggedIn {
            SignInHint()
        } else {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    TextField(state.S("SearchPlaceholder"), text: $state.searchTerm, onCommit: state.runSearch)
                    Stepper("\(state.S("LimitLabel")) \(state.searchLimit)", value: $state.searchLimit, in: 1...50).fixedSize()
                    Button(state.S("BtnSearch"), action: state.runSearch).disabled(state.busy)
                }
                HStack {
                    TextField(state.S("ByIDPlaceholder"), text: $state.directAppID, onCommit: state.downloadByID)
                        .frame(maxWidth: 280)
                    Button(state.S("BtnDownloadByID"), action: state.downloadByID)
                    Button(state.S("BtnPurchaseByID"), action: state.purchaseByID)
                    Button(state.S("BtnDownloadVersion"), action: state.openVersionsByID)
                }
                .disabled(state.busy)
                Divider()
                List(state.results, selection: $state.selectedResultIDs) { app in
                    HStack(alignment: .firstTextBaseline) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(app.name).fontWeight(.medium)
                            Text(app.bundleID).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 2) {
                            Text("v\(app.version)").font(.caption)
                            Text("id \(app.id)").font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                }
                .frame(minHeight: 220)
                HStack {
                    Button { state.purchaseSelected() } label: { Label(state.S("BtnPurchase"), systemImage: "cart") }
                    Button { state.downloadLatestSelected() } label: { Label(state.S("BtnDownloadLatest"), systemImage: "arrow.down.circle") }
                    Button { state.openVersions() } label: { Label(state.S("BtnDownloadVersion"), systemImage: "clock.arrow.circlepath") }
                    Spacer()
                    Text("\(state.selectedResultIDs.count)/\(state.results.count)").font(.caption).foregroundStyle(.secondary)
                }
                .disabled(state.busy || state.selectedResultIDs.isEmpty)
            }
        }
    }
}

// ── Lists (catalog / saved lists — original menus 7-9) ──────────────────────────
struct ListsView: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        if !state.loggedIn {
            SignInHint()
        } else {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Picker(state.S("ListSourceLabel"), selection: $state.listSource) {
                        ForEach(ListSource.allCases) { Text(state.S($0.labelKey)).tag($0) }
                    }
                    .fixedSize()
                    Button(state.S("BtnReload")) { state.loadListSource() }.disabled(state.busy || state.scanning)
                    Spacer()
                    if state.scanning {
                        ProgressView(value: Double(state.scanDone), total: Double(max(1, state.scanTotal)))
                            .frame(width: 130)
                        Text("\(state.scanDone)/\(state.scanTotal)").font(.caption).foregroundStyle(.secondary).monospacedDigit()
                        Button(state.S("BtnCancel")) { state.cancelOwnershipScan() }
                    } else {
                        Button { state.requestOwnershipScan() } label: {
                            Label(state.S("BtnScan"), systemImage: "person.crop.circle.badge.questionmark")
                        }
                        .disabled(state.busy)
                    }
                }
                List(state.listEntries, selection: $state.selectedListIDs) { e in
                    HStack {
                        Text(e.name).fontWeight(.medium)
                        Spacer()
                        Text(e.id).font(.caption).foregroundStyle(.secondary)
                    }
                }
                .frame(minHeight: 280)
                HStack {
                    Button { state.purchaseFromList() } label: { Label(state.S("BtnPurchase"), systemImage: "cart") }
                    Button { state.downloadLatestFromList() } label: { Label(state.S("BtnDownloadLatest"), systemImage: "arrow.down.circle") }
                    Button { state.downloadVersionFromList() } label: { Label(state.S("BtnDownloadVersion"), systemImage: "clock.arrow.circlepath") }
                    Spacer()
                    Text("\(state.selectedListIDs.count)/\(state.listEntries.count)").font(.caption).foregroundStyle(.secondary)
                }
                .disabled(state.busy || state.scanning || state.selectedListIDs.isEmpty)
            }
            .onAppear { if state.listEntries.isEmpty { state.loadListSource() } }
            .onChange(of: state.listSource) { _ in state.loadListSource() }
            .alert(state.S("ScanWarnTitle"), isPresented: $state.showScanWarning) {
                Button(state.S("BtnCancel"), role: .cancel) {}
                Button(state.S("ScanContinue")) { state.startOwnershipScan() }
            } message: {
                Text(state.S("ScanWarnBody", "\(state.catalogCount)"))
            }
        }
    }
}

struct VersionSheet: View {
    @EnvironmentObject var state: AppState
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(state.S("VersionSheetTitle", state.versionAppName)).font(.headline)
                Spacer()
                Stepper("\(state.S("VersionCountLabel")) \(state.versionCount)",
                        value: $state.versionCount, in: 1...200)
                    .fixedSize()
                    .disabled(state.loadingVersions)
                    .onChange(of: state.versionCount) { _ in state.loadVersions() }
            }
            if state.loadingVersions {
                HStack { ProgressView().controlSize(.small); Text(state.S("LoadingVersions")) }
                    .frame(maxWidth: .infinity, minHeight: 180)
            } else {
                List(state.versions, selection: $state.selectedVersionIDs) { v in
                    HStack {
                        Text(v.displayVersion).fontWeight(.medium)
                        Spacer()
                        if !v.releaseDate.isEmpty { Text(v.releaseDate).font(.caption).foregroundStyle(.secondary) }
                        Text(v.id).font(.caption2).foregroundStyle(.secondary)
                    }
                }
                .frame(minHeight: 220)
            }
            HStack {
                Spacer()
                Button(state.S("BtnCancel")) { state.showVersionSheet = false }
                Button(state.S("BtnDownload")) { state.downloadSelectedVersions() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(state.selectedVersionIDs.isEmpty)
            }
        }
        .padding(16)
        .frame(width: 480, height: 380)
    }
}

// ── Device (library / pair / install) ───────────────────────────────────────────
struct DeviceView: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        if !state.loggedIn {
            SignInHint()
        } else {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    if state.devices.isEmpty {
                        Label(state.S("NoDeviceConnected"), systemImage: "iphone.slash").foregroundStyle(.secondary)
                    } else {
                        Picker(state.S("DeviceLabel"), selection: $state.selectedDevice) {
                            ForEach(state.devices, id: \.self) { Text($0).tag(Optional($0)) }
                        }
                        .frame(maxWidth: 360)
                    }
                    Button { state.refreshDevices() } label: { Image(systemName: "arrow.clockwise") }
                        .help(state.S("BtnRefresh"))
                    Button { state.pairDevice() } label: { Label(state.S("BtnPair"), systemImage: "link.badge.plus") }
                        .disabled(state.busy)
                    Spacer()
                }
                Text(state.S("PairHint"))
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                Divider()
                HStack {
                    Text(state.S("AppsSection")).font(.headline)
                    Spacer()
                    Button { state.refreshApps() } label: { Image(systemName: "arrow.clockwise") }
                        .help(state.S("BtnRefresh"))
                }
                List(state.apps, selection: $state.selectedAppPaths) { ipa in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(ipa.fileName).fontWeight(.medium)
                            Text(ipa.bundleID.isEmpty ? ipa.name : ipa.bundleID).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(ipa.minIOS.isEmpty ? state.S("Dash") : "iOS \(ipa.minIOS)+").font(.caption)
                    }
                }
                .frame(minHeight: 220)
                HStack {
                    Button { state.installSelected() } label: { Label(state.S("BtnInstall"), systemImage: "square.and.arrow.down.on.square") }
                        .keyboardShortcut(.defaultAction)
                        .disabled(state.busy || state.selectedAppPaths.isEmpty)
                    Spacer()
                    Text("\(state.selectedAppPaths.count)/\(state.apps.count)").font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }
}

struct SignInHint: View {
    @EnvironmentObject var state: AppState
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "lock").font(.largeTitle).foregroundStyle(.secondary)
            Text(state.S("SignInHint")).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
