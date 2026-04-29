import Foundation

public struct RecirculationLink {
    public let url: String
    public let position: Int

    public init(url: String, position: Int) {
        self.url = url
        self.position = position
    }
}
