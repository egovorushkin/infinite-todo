//
//  todoApp.swift
//  todo
//
//  Created by Evgenii Govorushkin on 1/7/26.
//

import SwiftUI
import SwiftData

@main
struct todoApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(for: TodoItem.self)
    }
}
