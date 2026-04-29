import Foundation

public enum ExperienceFilterOperator: CaseIterable {
    case equals
    case notEquals
    case like
    case nlike
    case gt
    case gte
    case lt
    case lte
    case unknown

    public var key: String {
        switch self {
        case .equals: return "eq"
        case .notEquals: return "neq"
        case .like: return "contains"
        case .nlike: return "ncontains"
        case .gt: return "gt"
        case .gte: return "gte"
        case .lt: return "lt"
        case .lte: return "lte"
        case .unknown: return "unknown"
        }
    }

    fileprivate var legacyName: String {
        switch self {
        case .equals: return "EQUALS"
        case .notEquals: return "NOT_EQUALS"
        case .like: return "LIKE"
        case .nlike: return "NLIKE"
        case .gt: return "GT"
        case .gte: return "GTE"
        case .lt: return "LT"
        case .lte: return "LTE"
        case .unknown: return "UNKNOWN"
        }
    }

    public static func fromKey(_ key: String) -> ExperienceFilterOperator {
        if let match = allCases.first(where: { $0.key == key }) { return match }
        if let match = allCases.first(where: { $0.legacyName == key }) { return match }
        return .unknown
    }
}
