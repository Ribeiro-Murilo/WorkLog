//
//  WorkLogApp.swift
//  WorkLog
//
//  Created by Murilo Ribeiro on 01/07/26.
//

import SwiftUI
import SwiftData

@main
struct WorkLogApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    private let persistenceController = PersistenceController.shared
    private let dependencies: DependencyContainer

    init() {
        let dependencies = DependencyContainer(modelContext: persistenceController.mainContext)
        self.dependencies = dependencies
        dependencies.displayModeManager.configureNotchContent {
            MenuBarPopoverView().environment(\.dependencies, dependencies)
        }
        appDelegate.onDidFinishLaunching = { [dependencies] in
            dependencies.displayModeManager.refresh()
        }
    }

    var body: some Scene {
        Window("Dashboard", id: "dashboard") {
            ContentView()
                .environment(\.dependencies, dependencies)
        }
        .modelContainer(persistenceController.container)

        MenuBarExtra(isInserted: Binding(
            get: { dependencies.displayModeManager.isMenuBarVisible },
            set: { _ in }
        )) {
            MenuBarPopoverView()
                .environment(\.dependencies, dependencies)
        } label: {
            MenuBarLabelView()
                .environment(\.dependencies, dependencies)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsRootView()
                .environment(\.dependencies, dependencies)
        }
    }
}
