import Foundation

public enum ExperienceType: String {
    case inline
    case flowcards
    case compass
    case adManager
    case affiliationEnhancer
    case conversions
    case content
    case experiments
    case experimentation
    case recirculation
    case goalTracking
    case ecommerce
    case multimedia
    case piano
    case appBanner
    case unknown

    static func fromKey(_ key: String) -> ExperienceType? {
        return ExperienceType(rawValue: key)
    }
}
