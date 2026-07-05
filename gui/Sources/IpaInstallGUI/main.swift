// main.swift — process entry. `--selftest` runs headless backend checks and exits;
// otherwise the SwiftUI app launches.

import Foundation

if CommandLine.arguments.contains("--selftest") {
    exit(runSelfTest() ? 0 : 1)
}

IpaInstallApp.main()
