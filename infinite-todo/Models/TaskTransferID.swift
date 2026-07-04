//
//  TaskTransferID.swift
//  todo
//
//  Lightweight drag-and-drop payload. We transfer only an identifier plus
//  what kind of thing it names, and resolve the live model from the
//  ModelContext on drop.
//
//  One shared payload type (rather than separate task/list types) because
//  nested SwiftUI dropDestinations don't fall through by content type: an
//  inner target rejects foreign payloads with the ⊘ badge instead of letting
//  an outer target take them. With a single type, every target accepts the
//  session and routes by `kind`.
//

import Foundation
import CoreTransferable
import UniformTypeIdentifiers

extension UTType {
    /// Custom content type for a dragged task or list identifier.
    static let todoDragID = UTType(exportedAs: "com.evgenii.todo.dragid")
}

struct TodoDragPayload: Codable, Transferable {
    enum Kind: String, Codable {
        case task, list
    }

    let kind: Kind
    let id: UUID

    static func task(_ id: UUID) -> Self { .init(kind: .task, id: id) }
    static func list(_ id: UUID) -> Self { .init(kind: .list, id: id) }

    static var transferRepresentation: some TransferRepresentation {
        // Preferred: our own typed representation for in-app drags.
        CodableRepresentation(contentType: .todoDragID)
        // Fallback so the item degrades to plain text elsewhere.
        ProxyRepresentation(exporting: { $0.id.uuidString })
    }
}
