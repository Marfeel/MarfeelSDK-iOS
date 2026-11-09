import Foundation

/// Result of the A/B evaluation for an experience, mirroring the web SDK.
/// `isControl == true` means the app must keep its own native module (do not render the
/// experience content) but still track it, so the control arm can be measured.
/// `name` is the test version sent as `tv` in recirculation events.
public struct Experimentation: Equatable {
    public let isControl: Bool
    public let name: String

    public init(isControl: Bool, name: String) {
        self.isControl = isControl
        self.name = name
    }
}

internal enum ExperimentType: String {
    case request = "REQUEST"
    case user = "USER"
    case testGroup = "GROUP"
}

internal struct ExperienceExperiment {
    let type: ExperimentType
    let weight: Double?
    let groupId: String?
    let variantIds: [String]?
}
