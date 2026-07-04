//
//  TestSupport.swift
//  infinite-todoTests
//
//  Shared in-memory SwiftData stack for tests.
//

import SwiftData
@testable import infinite_todo

@MainActor
func makeTestContext() throws -> ModelContext {
    let schema = Schema([TodoItem.self, TaskList.self])
    let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
    let container = try ModelContainer(for: schema, configurations: [configuration])
    return ModelContext(container)
}
