import Foundation

public struct ChatMessage: Codable, Identifiable, Sendable {
    public var id: UUID
    public var role: Role
    public var content: String
    public var timestamp: Date?

    public enum Role: String, Codable, Sendable {
        case user
        case assistant
        case system
    }

    public init(
        id: UUID = UUID(),
        role: Role,
        content: String,
        timestamp: Date? = nil
    ) {
        self.id = id
        self.role = role
        self.content = content
        self.timestamp = timestamp
    }
}
