import Foundation

public enum ExperienceFamily: String {
    case twitter
    case facebook
    case youtube
    case recommender
    case telegram
    case gathering
    case affiliate
    case podcast
    case experimentation
    case widget
    case marfeelPass
    case script
    case paywall
    case marfeelSocial
    case unknown

    private static let keyMapping: [String: ExperienceFamily] = [
        "twitterexperience": .twitter,
        "facebookexperience": .facebook,
        "youtubeexperience": .youtube,
        "recommenderexperience": .recommender,
        "telegramexperience": .telegram,
        "gatheringexperience": .gathering,
        "affiliateexperience": .affiliate,
        "podcastexperience": .podcast,
        "experimentsexperience": .experimentation,
        "widgetexperience": .widget,
        "passexperience": .marfeelPass,
        "scriptexperience": .script,
        "paywallexperience": .paywall,
        "marfeelsocial": .marfeelSocial,
        "unknown": .unknown,
    ]

    static func fromKey(_ key: String) -> ExperienceFamily {
        return keyMapping[key] ?? .unknown
    }
}
