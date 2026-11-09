import Foundation

struct RecirculationModule {
    let name: String
    let links: [RecirculationLink]
    /// A/B test version (`experimentation.name`), sent as `tv` on every link like the web SDK.
    var testVersion: String? = nil
}
