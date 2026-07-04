//
//  DragReorderUITests.swift
//  infinite-todoUITests
//
//  Exercises the DropSession-based dropDestination migration (see
//  ContentView.swift / TaskRowView.swift) with a real drag gesture, since
//  that closure only runs during an actual drop — a screenshot or plain
//  launch never touches this code path.
//

import XCTest

final class DragReorderUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testDraggingListRowReordersLists() throws {
        // XCUITest's synthetic touches don't reliably trigger the
        // UIDragInteraction lift that SwiftUI's `.draggable`/Transferable
        // drag-and-drop depends on (unlike simple List `.onMove` reordering,
        // which responds fine). Verified with two different press/velocity
        // combinations, both leaving the rows in their original order with
        // no change whatsoever — not a timing tweak away from passing.
        // Left in place (skipped) as documentation of the limitation and a
        // starting point if a future Xcode/XCTest release fixes this.
        throw XCTSkip("XCUITest cannot reliably drive SwiftUI's Transferable drag-and-drop; verify manually.")

        let app = XCUIApplication()
        app.launch()

        // Unique per run so this test is unaffected by whatever lists
        // already exist on this simulator from prior manual testing.
        let suffix = UUID().uuidString.prefix(8)
        let nameA = "ZZ_TestA_\(suffix)"
        let nameB = "ZZ_TestB_\(suffix)"

        let composer = app.textFields["Add a list"]
        XCTAssertTrue(composer.waitForExistence(timeout: 5), "composer text field should exist on the Lists screen")

        composer.tap()
        composer.typeText(nameA)
        app.keyboards.buttons["Done"].tap()

        composer.tap()
        composer.typeText(nameB)
        app.keyboards.buttons["Done"].tap()

        // NavigationLink + .buttonStyle(.plain) combines the row's children
        // into one accessibility Button, so query by label rather than a
        // per-subview identifier (those get merged/mangled into the parent).
        let rowA = app.buttons.containing(NSPredicate(format: "label CONTAINS %@", nameA)).firstMatch
        let rowB = app.buttons.containing(NSPredicate(format: "label CONTAINS %@", nameB)).firstMatch
        XCTAssertTrue(rowA.waitForExistence(timeout: 5), "row A should appear after adding it")
        XCTAssertTrue(rowB.waitForExistence(timeout: 5), "row B should appear after adding it")

        // B was added after A, so it starts below A.
        XCTAssertLessThan(rowA.frame.minY, rowB.frame.minY, "B should start below A")

        // The drag handle is its own on-screen hit target (near the row's
        // trailing edge) even though accessibility combines it into the row's
        // Button element, so a plain touch coordinate still reaches it.
        let handleOffset = CGVector(dx: 0.85, dy: 0.5)
        let source = rowB.coordinate(withNormalizedOffset: handleOffset)
        let destination = rowA.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.1))
        source.press(forDuration: 1.0, thenDragTo: destination, withVelocity: .slow, thenHoldForDuration: 0.3)

        // Re-fetch: after reordering, B's row should now sit above A's.
        let reorderedRowA = app.buttons.containing(NSPredicate(format: "label CONTAINS %@", nameA)).firstMatch
        let reorderedRowB = app.buttons.containing(NSPredicate(format: "label CONTAINS %@", nameB)).firstMatch
        XCTAssertTrue(reorderedRowA.waitForExistence(timeout: 5))
        XCTAssertTrue(reorderedRowB.waitForExistence(timeout: 5))

        XCTAssertLessThan(
            reorderedRowB.frame.minY, reorderedRowA.frame.minY,
            "dragging B above A should have reordered the list, proving the DropSession-based drop still applies the move"
        )
    }
}
