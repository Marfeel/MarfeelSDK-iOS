import Foundation

public class Experience {
    public let id: String
    public let name: String
    public let type: ExperienceType
    public let family: ExperienceFamily?
    public let placement: String?
    public let contentUrl: String?
    public let contentType: ExperienceContentType
    public let features: [String: Any]?
    public let strategy: String?
    public let selectors: [ExperienceSelector]?
    public let filters: [ExperienceFilter]?
    public let rawJson: [String: Any]
    public internal(set) var resolvedContent: String?

    internal var contentResolver: ContentResolver?

    internal init(
        id: String,
        name: String,
        type: ExperienceType,
        family: ExperienceFamily?,
        placement: String?,
        contentUrl: String?,
        contentType: ExperienceContentType,
        features: [String: Any]?,
        strategy: String?,
        selectors: [ExperienceSelector]?,
        filters: [ExperienceFilter]?,
        rawJson: [String: Any]
    ) {
        self.id = id
        self.name = name
        self.type = type
        self.family = family
        self.placement = placement
        self.contentUrl = contentUrl
        self.contentType = contentType
        self.features = features
        self.strategy = strategy
        self.selectors = selectors
        self.filters = filters
        self.rawJson = rawJson
        self.resolvedContent = nil
        self.contentResolver = nil
    }

    public func resolve(_ completion: @escaping (String?) -> Void) {
        if let cached = resolvedContent {
            completion(cached)
            return
        }
        guard let url = contentUrl else {
            completion(nil)
            return
        }
        guard let resolver = contentResolver else {
            completion(nil)
            return
        }
        resolver.fetch(url: url, experienceId: id) { [weak self] content in
            self?.resolvedContent = content
            completion(content)
        }
    }
}
