import Foundation

internal class WholeModuleAugmenter {
    static let wholeModulePosition = 255
    static let wholeModuleUrl = " "

    private let pageUrlProvider: () -> String?
    private var currentPageUrl: String?
    private var moduleStates: [String: Bool] = [:] // name → has been impressed
    private let lock = NSLock()

    init(pageUrlProvider: @escaping () -> String?) {
        self.pageUrlProvider = pageUrlProvider
    }

    func onEligible(_ modules: [RecirculationModule]) -> [RecirculationModule] {
        lock.lock()
        defer { lock.unlock() }
        resetIfPageChanged()

        return modules.map { module in
            if moduleStates[module.name] == nil {
                moduleStates[module.name] = false
                return RecirculationModule(name: module.name, links: module.links + [WholeModuleAugmenter.wholeModuleLink()])
            }
            return module
        }
    }

    func onImpression(_ module: RecirculationModule) -> RecirculationModule {
        lock.lock()
        defer { lock.unlock() }
        resetIfPageChanged()

        if moduleStates[module.name] == false {
            moduleStates[module.name] = true
            return RecirculationModule(name: module.name, links: module.links + [WholeModuleAugmenter.wholeModuleLink()])
        }
        return module
    }

    private func resetIfPageChanged() {
        let pageUrl = pageUrlProvider()
        if pageUrl != currentPageUrl {
            currentPageUrl = pageUrl
            moduleStates.removeAll()
        }
    }

    static func wholeModuleLink() -> RecirculationLink {
        return RecirculationLink(url: wholeModuleUrl, position: wholeModulePosition)
    }
}
