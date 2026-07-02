//
//  ContentView.swift
//  WorkLog
//
//  Created by Murilo Ribeiro on 01/07/26.
//

import SwiftUI
import SwiftData

struct ContentView: View {
    var body: some View {
        DashboardView()
    }
}

#Preview {
    ContentView()
        .modelContainer(PersistenceController.preview().container)
        .environment(\.dependencies, .preview())
}
