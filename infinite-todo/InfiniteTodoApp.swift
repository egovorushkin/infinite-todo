//
//  InfiniteTodoApp.swift
//  infinite-todo
//
//  Created by Evgenii Govorushkin on 1/7/26.
//

import SwiftUI
import SwiftData
import UserNotifications

@main
struct InfiniteTodoApp: App {
    private let notificationDelegate = NotificationDelegate()
    @AppStorage("appTheme") private var appThemeRaw: String = AppTheme.system.rawValue

    init() {
        UNUserNotificationCenter.current().delegate = notificationDelegate
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .preferredColorScheme((AppTheme(rawValue: appThemeRaw) ?? .system).colorScheme)
        }
        .modelContainer(for: [TodoItem.self, TaskList.self])
    }
}

/// Without this, iOS silently drops due-soon reminders while the app is in
/// the foreground instead of showing them.
private final class NotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }
}
