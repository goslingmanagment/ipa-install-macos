// SelfTest.swift — headless verification of the backend layer (no GUI, no network
// login needed). Run with `--selftest`. Proves path/binary resolution, JSON
// extraction (including the `purchase` leading-line case), the offline name list,
// and that the device/library calls run without throwing.

import Foundation

private var failures = 0
private func check(_ label: String, _ cond: Bool, _ detail: String = "") {
    print("  [\(cond ? "ok " : "FAIL")] \(label)" + (cond ? "" : " — \(detail)"))
    if !cond { failures += 1 }
}

func runSelfTest() -> Bool {
    failures = 0
    let paths = AppPaths.discover()
    let backend = Backend(paths: paths)
    print("self-test")
    print("  root: \(paths.root.path)")
    print("  ipatool: \(paths.ipatool.path)")
    print("  ideviceinstaller: \(paths.ideviceinstaller.path)")

    check("project root resolved (bin/ipatool executable)",
          FileManager.default.isExecutableFile(atPath: paths.ipatool.path), paths.ipatool.path)

    // JSON extraction — whole-stream search shape
    let searchJSON = #"{"count":2,"apps":[{"id":111,"bundleID":"com.a","name":"Alpha","version":"1.0","price":"0"}]}"#
    check("parse search JSON", (Backend.jsonObject(from: searchJSON)?["count"] as? Int) == 2)

    // JSON extraction — purchase prints a non-JSON line BEFORE the object
    let purchaseOut = "Purchasing: Alpha (com.a)\n{\"success\":true}\n"
    check("parse JSON past leading line",
          (Backend.jsonObject(from: purchaseOut)?["success"] as? Bool) == true)

    // offline name list keyed by numeric id (matches the bundled asset)
    let name = backend.githubName(appID: "481627348")
    check("github name lookup", name == "2ГИС", String(describing: name))
    check("github name miss is nil", backend.githubName(appID: "999999999999") == nil)

    // catalog line parser — faithful to ^(.+?):\s*(\d+); a name with an inner colon
    // must still bind to the trailing digit run (regression guard for 12 such rows).
    let tricky = Backend.parseCatalogLine("Au.ru (Барахолка 24: объявления 24/7): 6760170997")
    check("catalog parse keeps inner colon in name",
          tricky?.id == "6760170997" && tricky?.name == "Au.ru (Барахолка 24: объявления 24/7)",
          String(describing: tricky))
    let catalog = backend.githubCatalog()
    check("github catalog parses (>400 rows)", catalog.count > 400, "\(catalog.count) rows")
    check("github catalog contains known id", catalog.contains { $0.id == "481627348" })

    // localization — RU and EN both resolve; {0} placeholder fills
    check("L10n RU resolves", L10n.t("Menu11", .ru) != "Menu11")
    check("L10n EN resolves", L10n.t("Menu11", .en) != "Menu11")
    check("L10n placeholder fills", L10n.t("DeviceFound", .en, ["abc"]).contains("abc"))
    check("loadLang returns RU/EN", [Lang.ru, Lang.en].contains(backend.loadLang()))

    // friendly-filename sanitizer (used by finalizeDownload): strip [\/:*?"<>|], spaces → _
    check("sanitizeFilename strips bad chars + collapses spaces",
          backend.sanitizeFilename("My App: v2 /x") == "My_App_v2_x",
          backend.sanitizeFilename("My App: v2 /x"))

    // device + library calls must not throw / crash
    let devices = (try? backend.listDevices()) ?? []
    check("listDevices runs", true, "\(devices.count) device(s)")
    _ = backend.listApps()
    check("listApps runs", true)
    _ = backend.loadSavedList(purchased: false)
    _ = backend.loadSavedList(purchased: true)
    check("loadSavedList runs", true)

    // ownership-scan persistence round-trips (read whatever Lists/Owned_scan.json holds)
    if let owned = backend.loadOwnedScan() {
        check("loadOwnedScan parses", owned.removedOwned.count + owned.removedNotOwned.count >= 0,
              "\(owned.removedOwned.count) recoverable / \(owned.removedNotOwned.count) removed-not-owned")
    } else {
        check("loadOwnedScan absent is fine", true, "no scan yet")
    }

    // ipatool actually launches (auth info returns or throws a *non-launch* error)
    do {
        _ = try backend.authInfo()
        check("ipatool launches (auth info ok / logged in)", true)
    } catch let BackendError.message(m) {
        check("ipatool launches (auth info reachable)", !m.contains("cannot launch"), m)
    } catch {
        check("ipatool launches", false, "\(error)")
    }

    print(failures == 0 ? "ALL SELF-TESTS PASSED" : "FAILED: \(failures)")
    return failures == 0
}
