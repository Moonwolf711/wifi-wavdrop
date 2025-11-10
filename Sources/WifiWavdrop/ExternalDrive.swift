import Foundation

public struct ExternalDrive: Identifiable {
    public let id: UUID
    
    public init(id: UUID = UUID()) {
        self.id = id
    }
}
