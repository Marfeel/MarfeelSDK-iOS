import Foundation

public enum ExperienceContentType: String {
    case textHTML
    case json
    case amp
    case widgetProvider
    case adServer
    case container
    case unknown

    private static let keyMapping: [String: ExperienceContentType] = [
        "TextHTML": .textHTML,
        "Json": .json,
        "AMP": .amp,
        "WidgetProvider": .widgetProvider,
        "AdServer": .adServer,
        "Container": .container,
        "Unknown": .unknown,
    ]

    static func fromKey(_ key: String) -> ExperienceContentType {
        return keyMapping[key] ?? .unknown
    }
}
