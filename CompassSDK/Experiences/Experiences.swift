import Foundation

public protocol ExperiencesTracking {
    func addTargeting(key: String, value: String)
    func fetchExperiences(
        filterByType: ExperienceType?,
        filterByFamily: ExperienceFamily?,
        resolve: Bool,
        url: String?,
        completion: @escaping ([Experience]) -> Void
    )
    func trackEligible(experience: Experience, links: [RecirculationLink])
    func trackImpression(experience: Experience, links: [RecirculationLink])
    func trackImpression(experience: Experience, link: RecirculationLink)
    func trackClick(experience: Experience, link: RecirculationLink)
    func trackClose(experience: Experience)

    // QA/Debug
    func clearFrequencyCaps()
    func getFrequencyCapCounts(experienceId: String) -> [String: Int]
    func getFrequencyCapConfig() -> [String: [String]]
    func clearReadEditorials()
    func getReadEditorials() -> [String]
    func getExperimentAssignments() -> [String: String]
    func setExperimentAssignment(groupId: String, variantId: String)
    func clearExperimentAssignments()
}

public class Experiences {
    public static let shared: ExperiencesTracking = ExperiencesTracker()
}

internal class ExperiencesTracker: ExperiencesTracking {
    private let contentResolver: ContentResolver
    private let responseParser: ExperiencesResponseParser
    private let experimentManager: ExperimentManager
    private let frequencyCapManager: FrequencyCapManager
    private let readEditorialsManager: ReadEditorialsManager
    private let apiClient: ExperiencesApiClient
    private let recirculationTracker: RecirculationTracker

    private let targetingQueue = DispatchQueue(label: "com.marfeel.experiences.targeting", attributes: .concurrent)
    private var _customTargeting: [String: String] = [:]

    // Experimentation of fetched experiences, so tracking calls made with a rebuilt
    // Experience (e.g. from the Flutter / React Native bridges) still send the test version.
    private let experimentationQueue = DispatchQueue(label: "com.marfeel.experiences.experimentation", attributes: .concurrent)
    private var _experimentationById: [String: Experimentation] = [:]

    private let fetchQueue = DispatchQueue(label: "com.marfeel.experiences.fetch", qos: .userInitiated)

    private static let resolveTimeoutSeconds: TimeInterval = 10

    init(
        experimentManager: ExperimentManager = ExperimentManager(),
        frequencyCapManager: FrequencyCapManager = FrequencyCapManager(),
        readEditorialsManager: ReadEditorialsManager = ReadEditorialsManager()
    ) {
        self.experimentManager = experimentManager
        self.frequencyCapManager = frequencyCapManager
        self.readEditorialsManager = readEditorialsManager
        self.contentResolver = ContentResolver()
        self.responseParser = ExperiencesResponseParser(contentResolver: contentResolver)
        self.apiClient = ExperiencesApiClient(
            experimentManager: experimentManager,
            frequencyCapManager: frequencyCapManager,
            readEditorialsManager: readEditorialsManager
        )
        self.recirculationTracker = Recirculation.tracker
    }

    func addTargeting(key: String, value: String) {
        targetingQueue.sync(flags: .barrier) { _customTargeting[key] = value }
    }

    func fetchExperiences(
        filterByType: ExperienceType?,
        filterByFamily: ExperienceFamily?,
        resolve: Bool,
        url: String?,
        completion: @escaping ([Experience]) -> Void
    ) {
        let pageUrl = url ?? CompassTracker.shared.experiencesPageUrl
        guard let pageUrl = pageUrl else {
            completion([])
            return
        }

        let targeting = targetingQueue.sync { _customTargeting }

        fetchQueue.async { [weak self] in
            guard let self = self else {
                completion([])
                return
            }

            self.apiClient.fetch(url: pageUrl, customTargeting: targeting) { [weak self] json in
                guard let self = self, let json = json else {
                    completion([])
                    return
                }

                let parseResult = self.responseParser.parse(json)

                self.frequencyCapManager.applyResponseConfig(parseResult.frequencyCapConfig)

                if let editorialId = parseResult.editorialId {
                    self.readEditorialsManager.add(editorialId)
                }

                self.experimentManager.handleExperimentGroups(parseResult.experimentGroups)

                var experiences = self.experimentManager.evaluate(parseResult.experiences)
                self.storeExperimentation(experiences)

                if let filterByType = filterByType {
                    experiences = experiences.filter { $0.type == filterByType }
                }
                if let filterByFamily = filterByFamily {
                    experiences = experiences.filter { $0.family == filterByFamily }
                }

                if resolve {
                    self.resolveAll(experiences) {
                        completion(experiences)
                    }
                } else {
                    completion(experiences)
                }
            }
        }
    }

    private func resolveAll(_ experiences: [Experience], completion: @escaping () -> Void) {
        let resolvable = experiences.filter { $0.contentUrl != nil }
        if resolvable.isEmpty {
            completion()
            return
        }

        let group = DispatchGroup()
        for experience in resolvable {
            group.enter()
            experience.resolve { _ in
                group.leave()
            }
        }

        var didComplete = false
        let finish = { [fetchQueue] in
            fetchQueue.async {
                guard !didComplete else { return }
                didComplete = true
                completion()
            }
        }
        group.notify(queue: fetchQueue, execute: finish)
        fetchQueue.asyncAfter(deadline: .now() + ExperiencesTracker.resolveTimeoutSeconds, execute: finish)
    }

    private func storeExperimentation(_ experiences: [Experience]) {
        let entries = experiences.compactMap { experience in
            experience.experimentation.map { (experience.id, $0) }
        }
        if entries.isEmpty { return }
        experimentationQueue.sync(flags: .barrier) {
            for (id, experimentation) in entries {
                _experimentationById[id] = experimentation
            }
        }
    }

    private func testVersion(for experience: Experience) -> String? {
        if let experimentation = experience.experimentation {
            return experimentation.name
        }
        return experimentationQueue.sync { _experimentationById[experience.id]?.name }
    }

    /// Same module name as the web SDK (`data-mrf-recirculation`): the base experience id,
    /// shared by every arm of an A/B test so they can be compared.
    private func moduleName(for experience: Experience) -> String {
        return ExperimentEvaluator.baseExperienceId(experience.id)
    }

    func trackImpression(experience: Experience, links: [RecirculationLink]) {
        frequencyCapManager.trackImpression(experienceId: experience.id)
        if !links.isEmpty {
            recirculationTracker.trackImpression(
                name: moduleName(for: experience),
                links: links,
                testVersion: testVersion(for: experience)
            )
        }
    }

    func trackImpression(experience: Experience, link: RecirculationLink) {
        trackImpression(experience: experience, links: [link])
    }

    func trackClose(experience: Experience) {
        frequencyCapManager.trackClose(experienceId: experience.id)
    }

    func trackEligible(experience: Experience, links: [RecirculationLink]) {
        recirculationTracker.trackEligible(
            name: moduleName(for: experience),
            links: links,
            testVersion: testVersion(for: experience)
        )
    }

    func trackClick(experience: Experience, link: RecirculationLink) {
        recirculationTracker.trackClick(
            name: moduleName(for: experience),
            link: link,
            testVersion: testVersion(for: experience)
        )
    }

    func clearFrequencyCaps() {
        frequencyCapManager.clear()
    }

    func getFrequencyCapCounts(experienceId: String) -> [String: Int] {
        return frequencyCapManager.getCounts(experienceId: experienceId)
    }

    func getFrequencyCapConfig() -> [String: [String]] {
        return frequencyCapManager.getConfig()
    }

    func clearReadEditorials() {
        readEditorialsManager.clear()
    }

    func getReadEditorials() -> [String] {
        return readEditorialsManager.getIds()
    }

    func getExperimentAssignments() -> [String: String] {
        return experimentManager.getAssignments()
    }

    func setExperimentAssignment(groupId: String, variantId: String) {
        experimentManager.setAssignment(groupId: groupId, variantId: variantId)
    }

    func clearExperimentAssignments() {
        experimentManager.clear()
    }
}
