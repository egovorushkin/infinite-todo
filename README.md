# Infinite Todo

<img src="infinite-todo/Assets.xcassets/AppIcon.appiconset/icon_v3.png" width="120" alt="Infinite Todo app icon">

A SwiftUI + SwiftData todo app where tasks can nest inside tasks, to any depth.

## Features

- **Infinite nesting** — any task can have subtasks, which can have their own subtasks, etc. Completing a parent completes its whole subtree; completing the last open child completes the parent.
- **Lists** — named, color- and icon-tagged containers for root-level tasks.
- **Due dates & reminders** — local notifications fire before a task is due, with hourly/daily/weekly/monthly/yearly recurrence.
- **Drag & drop** — reorder tasks and lists, re-parent a task under another, or move a task to a different list.
- **Two home layouts** — a vertical stack of list cards, or a Google Tasks-style horizontal tab bar. Switchable in Settings.
- **Light/Dark/System appearance**, independent of the device setting.
- **Localized** in English (source), German, Spanish, and Russian.

## Requirements

- Xcode 26+
- iOS 26.5+ (see `IPHONEOS_DEPLOYMENT_TARGET` in project settings)
- No external dependencies — pure SwiftUI + SwiftData.

## Building

1. Copy `Config/Local.xcconfig.template` to `Config/Local.xcconfig` and fill in your own Apple Developer Team ID (gitignored, so your signing config never gets committed).
2. Open `infinite-todo.xcodeproj` in Xcode and run the `infinite-todo` scheme on a simulator or device.

## Testing

- `infinite-todoTests` — unit tests for the model/service layer (`TodoItem`, `TaskManager`, `ListManager`): nesting, completion cascade, reordering, re-parenting, cycle prevention, cross-list moves.
- `infinite-todoUITests` — end-to-end UI tests. `testDraggingListRowReordersLists` is currently skipped: XCUITest's synthetic touches don't reliably trigger the `UIDragInteraction` lift that SwiftUI's `Transferable`-based drag-and-drop depends on, so it can't verify a real drag gesture from the simulator. Drag-and-drop changes need a manual check on a simulator or device.

Run both from Xcode (⌘U) or via `xcodebuild test -scheme infinite-todo -destination 'platform=iOS Simulator,name=<device>'`.

## Localization

Strings live in `infinite-todo/Localizable.xcstrings` (a String Catalog). Most UI strings localize automatically — SwiftUI's `Text`, `Button`, `Label`, alert/dialog titles, and `accessibilityLabel`/`accessibilityHint` all take a `LocalizedStringKey` by default, so a plain string literal is looked up in the catalog with no extra code. The exceptions are values computed outside a SwiftUI view initializer (enum `.label` properties, the notification title/body in `NotificationManager`, the default "Tasks" list name), which are wrapped in `String(localized:)` so they still get extracted and translated.

To add a language: open `Localizable.xcstrings` in Xcode, add the locale, and fill in translations (or add the locale to `knownRegions` in `project.pbxproj` and let Xcode prompt you).

## Project structure

```
infinite-todo/
  Models/       TodoItem, TaskList, AppTheme, TaskTransferID — SwiftData models and small value types
  Services/     TaskManager, ListManager, NotificationManager — all structural mutations and side effects
  Views/        SwiftUI views
  Localizable.xcstrings   String Catalog (en source, de/es/ru translations)
  ContentView.swift       Root screen (stack/tabs layout switch)
  InfiniteTodoApp.swift   App entry point
infinite-todoTests/       Unit tests
infinite-todoUITests/     UI tests
Config/                   Local.xcconfig (gitignored signing config) + Info.plist merge additions
```

Structural mutations (reordering, re-parenting, moving between lists, cascading completion) are centralized in `TaskManager`/`ListManager` rather than in views, so ordering and cycle-prevention logic lives in one place.
