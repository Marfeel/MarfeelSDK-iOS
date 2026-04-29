import Foundation

public protocol RecirculationTracking {
    func trackEligible(name: String, links: [RecirculationLink])
    func trackImpression(name: String, links: [RecirculationLink])
    func trackImpression(name: String, link: RecirculationLink)
    func trackClick(name: String, link: RecirculationLink)
}

public class Recirculation {
    public static let shared: RecirculationTracking = RecirculationTracker()
}

internal class RecirculationTracker: RecirculationTracking {
    private let apiClient: RecirculationApiClient
    private let augmenter: WholeModuleAugmenter
    private let sendQueue = DispatchQueue(label: "com.marfeel.recirculation", qos: .utility)

    init(apiClient: RecirculationApiClient = RecirculationApiClient()) {
        self.apiClient = apiClient
        self.augmenter = WholeModuleAugmenter {
            CompassTracker.shared.experiencesPageUrl
        }
    }

    func trackEligible(name: String, links: [RecirculationLink]) {
        let module = RecirculationModule(name: name, links: links)
        let augmented = augmenter.onEligible([module])
        sendQueue.async { [weak self] in
            self?.apiClient.send(eventType: "elegible", modules: augmented)
        }
    }

    func trackImpression(name: String, links: [RecirculationLink]) {
        let module = RecirculationModule(name: name, links: links)
        let augmented = augmenter.onImpression(module)
        sendQueue.async { [weak self] in
            self?.apiClient.send(eventType: "impression", modules: [augmented])
        }
    }

    func trackImpression(name: String, link: RecirculationLink) {
        trackImpression(name: name, links: [link])
    }

    func trackClick(name: String, link: RecirculationLink) {
        let module = RecirculationModule(name: name, links: [link])
        sendQueue.async { [weak self] in
            self?.apiClient.send(eventType: "click", modules: [module])
        }
    }
}
