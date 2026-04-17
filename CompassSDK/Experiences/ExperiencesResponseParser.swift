import Foundation

internal struct ParseResult {
    let experiences: [Experience]
    let frequencyCapConfig: [String: [String]]
    let experimentGroups: [String: Any]?
    let editorialId: String?
}

internal class ExperiencesResponseParser {
    private let contentResolver: ContentResolver?
    private let metadataKeys: Set<String> = ["targeting", "content", "experiments", "experimentGroups"]

    init(contentResolver: ContentResolver? = nil) {
        self.contentResolver = contentResolver
    }

    func parse(_ json: [String: Any]) -> ParseResult {
        let frequencyCapConfig = extractFrequencyCapConfig(json)

        let experimentGroups = (json["experimentGroups"] as? [String: Any])
            ?? (json["experiments"] as? [String: Any])

        let editorialId = (json["content"] as? [String: Any])?["editorialId"] as? String

        var experiences: [Experience] = []

        for (typeKey, typeValue) in json {
            if metadataKeys.contains(typeKey) { continue }
            guard let typeObj = typeValue as? [String: Any] else { continue }

            let actionsObj = (typeObj["actions"] as? [String: Any])
                ?? (typeObj["cards"] as? [String: Any])
            guard let actions = actionsObj, !actions.isEmpty else { continue }

            let experienceType = ExperienceType.fromKey(typeKey) ?? .unknown

            for (actionName, actionValue) in actions {
                guard let actionObj = actionValue as? [String: Any] else { continue }
                experiences.append(parseExperience(name: actionName, action: actionObj, type: experienceType))
            }
        }

        return ParseResult(
            experiences: experiences,
            frequencyCapConfig: frequencyCapConfig,
            experimentGroups: experimentGroups,
            editorialId: editorialId
        )
    }

    private func parseExperience(name: String, action: [String: Any], type: ExperienceType) -> Experience {
        let contentObj = action["content"] as? [String: Any]
        let contentTypeStr = contentObj?["type"] as? String
        let contentUrl = contentObj?["url"] as? String

        let familyStr = action["family"] as? String
        let family = familyStr.map { ExperienceFamily.fromKey($0) }

        let experience = Experience(
            id: (action["id"] as? String) ?? "",
            name: name,
            type: type,
            family: family,
            placement: action["placement"] as? String,
            contentUrl: contentUrl,
            contentType: contentTypeStr.map { ExperienceContentType.fromKey($0) } ?? .unknown,
            features: parseMapOrNil(action["features"]),
            strategy: action["strategy"] as? String,
            selectors: parseSelectors(action),
            filters: parseFilters(action),
            rawJson: action
        )
        experience.contentResolver = contentResolver
        return experience
    }

    private func parseSelectors(_ action: [String: Any]) -> [ExperienceSelector]? {
        guard let selectorsArray = action["selectors"] as? [[String: Any]] else { return nil }
        let selectors = selectorsArray.compactMap { obj -> ExperienceSelector? in
            guard let selector = obj["selector"] as? String else { return nil }
            return ExperienceSelector(
                selector: selector,
                strategy: (obj["strategy"] as? String) ?? ""
            )
        }
        return selectors.isEmpty ? nil : selectors
    }

    private func parseFilters(_ action: [String: Any]) -> [ExperienceFilter]? {
        var explicit: [ExperienceFilter] = []
        if let filtersArray = action["filters"] as? [[String: Any]] {
            explicit = filtersArray.compactMap { obj -> ExperienceFilter? in
                guard let key = obj["key"] as? String,
                      let values = obj["values"] as? [String] else { return nil }
                return ExperienceFilter(
                    key: key,
                    operator: (obj["operator"] as? String) ?? "EQUALS",
                    values: values
                )
            }
        }

        var combined = explicit
        if let experimentFilter = parseExperimentFilter(action["experiment"] as? [String: Any]) {
            combined.append(experimentFilter)
        }
        return combined.isEmpty ? nil : combined
    }

    private func parseExperimentFilter(_ experiment: [String: Any]?) -> ExperienceFilter? {
        guard let experiment = experiment,
              let groupId = experiment["groupId"] as? String,
              let variantIds = experiment["variantIds"] as? [String],
              !variantIds.isEmpty else { return nil }
        return ExperienceFilter(
            key: "mrf_exp_\(groupId)",
            operator: "EQUALS",
            values: variantIds
        )
    }

    private func parseMapOrNil(_ value: Any?) -> [String: Any]? {
        return value as? [String: Any]
    }

    private func extractFrequencyCapConfig(_ root: [String: Any]) -> [String: [String]] {
        guard let targeting = root["targeting"] as? [String: Any],
              let freqCap = targeting["frequencyCap"] as? [String: Any] else { return [:] }
        var result: [String: [String]] = [:]
        for (key, value) in freqCap {
            if let arr = value as? [String] {
                result[key] = arr
            }
        }
        return result
    }
}
