import Foundation

public struct ExperienceFilter {
    public let key: String
    public let `operator`: ExperienceFilterOperator
    public let values: [String]
}
