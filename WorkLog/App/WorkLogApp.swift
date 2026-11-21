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
    private let ptax = PTAXService()

    init() {
        let dependencies = DependencyContainer(modelContext: persistenceController.mainContext)
        self.dependencies = dependencies
        appDelegate.storageMigrationNotice = persistenceController.migrationNotice
        let notchViewModel = NotchPanelViewModel(
            timerService: dependencies.timerService,
            projectRepository: dependencies.projectRepository,
            sessionRepository: dependencies.sessionRepository,
            settingsRepository: dependencies.settingsRepository
        )
        dependencies.displayModeManager.configureNotchContent {
            NotchPanelView(viewModel: notchViewModel, isPinned: Binding(
                get: { dependencies.displayModeManager.isNotchPinned },
                set: { dependencies.displayModeManager.setNotchPinned($0) }
            ))
            .environment(\.dependencies, dependencies)
        } collapsedTrailing: {
            NotchTimerBadge().environment(\.dependencies, dependencies)
        }
        appDelegate.onDidFinishLaunching = { [dependencies, ptax] in
            dependencies.displayModeManager.refresh()
            dependencies.folderSyncService.start()
            ptax.start()
        }
    }

    var body: some Scene {
        Window("Dashboard", id: "dashboard") {
            ContentView()
                .environment(\.dependencies, dependencies)
                .environment(ptax)
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
