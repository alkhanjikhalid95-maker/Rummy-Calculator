//
//  Rummy_CalculatorApp.swift
//  Rummy Calculator
//
//  Created by khalid alkhanji on 20/03/2026.
//

import SwiftUI
import UIKit

@main
struct Rummy_CalculatorApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup {
            ContentView()
                .preferredColorScheme(.light)
        }
    }
}

final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        // iOS relaunches the app in the background when Bluetooth news arrives
        // for a game this phone was following; pick the connection back up
        // before any screen exists.
        NearbyGuest.shared.resumeIfNeeded()
        return true
    }
}
