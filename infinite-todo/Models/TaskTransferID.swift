//
//  TaskTransferID.swift
//  todo
//
//  Lightweight drag-and-drop payload. We transfer only the task's
//  identifier and resolve the live model from the ModelContext on drop,
//  which keeps drag sessions cheap and same-app only.
//

import Foundation
import CoreTransferable
import UniformTypeIdentifiers

extension UTType {
    /// Custom content type for a dragged todo task identifier.
    static let todoTaskID = UTType(exportedAs: "com.evgenii.todo.taskid")
}

struct TaskTransferID: Codable, Transferable {
    let id: UUID

    static var transferRepresentation: some TransferRepresentation {
        // Preferred: our own typed representation for in-app drags.
        CodableRepresentation(contentType: .todoTaskID)
        // Fallback so the item degrades to plain text elsewhere.
        ProxyRepresentation(exporting: { $0.id.uuidString })
    }
}
