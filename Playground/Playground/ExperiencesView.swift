import SwiftUI
import MarfeelSDK_iOS

struct ExperiencesView: View {
    @State private var url = "https://dev.marfeel.co/"
    @State private var resultText = ""
    @State private var isLoading = false
    @State private var lastExperiences: [Experience] = []
    @State private var selectedType: ExperienceType? = nil
    @State private var selectedFamily: ExperienceFamily? = nil
    @State private var capsVersion = 0
    @State private var experimentsVersion = 0
    @State private var forceGroupId = ""
    @State private var forceVariantId = ""

    private let experiencesTracker = Experiences.shared
    private let recirculationTracker = Recirculation.shared

    private let allTypes: [ExperienceType] = [
        .inline, .flowcards, .compass, .adManager, .affiliationEnhancer,
        .conversions, .content, .experiments, .experimentation,
        .recirculation, .goalTracking, .ecommerce, .multimedia, .piano, .appBanner
    ]

    private let allFamilies: [ExperienceFamily] = [
        .twitter, .facebook, .youtube, .recommender, .telegram, .gathering,
        .affiliate, .podcast, .experimentation, .widget, .marfeelPass,
        .script, .paywall, .marfeelSocial
    ]

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    fetchSection
                    if !resultText.isEmpty { resultDisplay }
                    if !lastExperiences.isEmpty { trackingButtons }
                    if !lastExperiences.isEmpty { frequencyCapsSection }
                    experimentsSection
                    genericRecirculationSection
                }
                .padding()
            }
            .navigationTitle("Experiences")
        }
    }

    private var fetchSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField("URL", text: $url)
                .textFieldStyle(RoundedBorderTextFieldStyle())
                .autocapitalization(.none)
                .disableAutocorrection(true)

            HStack {
                Menu {
                    Button("All") { selectedType = nil }
                    ForEach(allTypes, id: \.rawValue) { type in
                        Button(type.rawValue) { selectedType = type }
                    }
                } label: {
                    Text(selectedType?.rawValue ?? "Type: All")
                        .frame(maxWidth: .infinity)
                        .padding(8)
                        .background(Color(.systemGray6))
                        .cornerRadius(8)
                }

                Menu {
                    Button("All") { selectedFamily = nil }
                    ForEach(allFamilies, id: \.rawValue) { family in
                        Button(family.rawValue) { selectedFamily = family }
                    }
                } label: {
                    Text(selectedFamily?.rawValue ?? "Family: All")
                        .frame(maxWidth: .infinity)
                        .padding(8)
                        .background(Color(.systemGray6))
                        .cornerRadius(8)
                }
            }

            HStack(spacing: 12) {
                Button(action: { fetchExperiences(resolve: false) }) {
                    Text("Fetch")
                        .frame(maxWidth: .infinity)
                        .padding(10)
                        .background(Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(8)
                }

                Button(action: { fetchExperiences(resolve: true) }) {
                    Text("Fetch + Resolve")
                        .frame(maxWidth: .infinity)
                        .padding(10)
                        .background(Color.purple)
                        .foregroundColor(.white)
                        .cornerRadius(8)
                }
            }

            if isLoading {
                Text("Loading...").foregroundColor(.gray)
            }
        }
    }

    private var resultDisplay: some View {
        Text(resultText)
            .font(.system(size: 11, design: .monospaced))
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.systemGray6))
            .cornerRadius(6)
    }

    private var trackingButtons: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Track (first experience)").font(.headline)
            HStack(spacing: 12) {
                Button("Eligible") {
                    guard let exp = lastExperiences.first else { return }
                    let links = [RecirculationLink(url: exp.contentUrl ?? "", position: 0)]
                    experiencesTracker.trackEligible(experience: exp, links: links)
                }
                .buttonStyle(TrackButtonStyle(color: .green))

                Button("Impression") {
                    guard let exp = lastExperiences.first else { return }
                    let links = [RecirculationLink(url: exp.contentUrl ?? "", position: 0)]
                    experiencesTracker.trackImpression(experience: exp, links: links)
                    capsVersion += 1
                }
                .buttonStyle(TrackButtonStyle(color: .orange))

                Button("Click") {
                    guard let exp = lastExperiences.first else { return }
                    experiencesTracker.trackClick(
                        experience: exp,
                        link: RecirculationLink(url: exp.contentUrl ?? "", position: 0)
                    )
                }
                .buttonStyle(TrackButtonStyle(color: .red))

                Button("Close") {
                    guard let exp = lastExperiences.first else { return }
                    experiencesTracker.trackClose(experience: exp)
                    capsVersion += 1
                }
                .buttonStyle(TrackButtonStyle(color: .gray))
            }
        }
    }

    private var frequencyCapsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Frequency Caps").font(.headline)
                Spacer()
                Button("Clear") {
                    experiencesTracker.clearFrequencyCaps()
                    capsVersion += 1
                }
                .font(.caption)
            }

            Text("Tap Impression/Close, then re-Fetch and inspect the uexp query param.")
                .font(.caption)
                .foregroundColor(.gray)

            let capConfig = experiencesTracker.getFrequencyCapConfig()
            let capped = lastExperiences.filter { capConfig.keys.contains($0.id) }

            if capped.isEmpty {
                Text("No experiences capped in current response.")
                    .font(.caption).foregroundColor(.gray)
            } else {
                ForEach(capped, id: \.id) { exp in
                    let counts = experiencesTracker.getFrequencyCapCounts(experienceId: exp.id)
                    let capKeys = (capConfig[exp.id] ?? []).joined(separator: ",")
                    VStack(alignment: .leading, spacing: 2) {
                        HStack {
                            Text("\(exp.type.rawValue)/\(String(exp.id.prefix(16)))... [\(capKeys)]")
                                .font(.system(size: 11))
                            Spacer()
                            Button("Imp") {
                                experiencesTracker.trackImpression(experience: exp, links: [])
                                capsVersion += 1
                            }.font(.system(size: 10))
                            Button("Close") {
                                experiencesTracker.trackClose(experience: exp)
                                capsVersion += 1
                            }.font(.system(size: 10))
                        }
                        Text("l=\(counts["l"] ?? 0) cl=\(counts["cl"] ?? 0) m=\(counts["m"] ?? 0) cm=\(counts["cm"] ?? 0) w=\(counts["w"] ?? 0) cw=\(counts["cw"] ?? 0) d=\(counts["d"] ?? 0) cd=\(counts["cd"] ?? 0) ls=\(counts["ls"] ?? 0)")
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundColor(.gray)
                    }
                }
            }
        }
        .id(capsVersion)
    }

    private var experimentsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Experiments").font(.headline).padding(.top, 16)
            Text("Draws happen during Fetch. Force a variant to pin a branch; Clear to re-roll on next Fetch.")
                .font(.caption).foregroundColor(.gray)

            let assignments = experiencesTracker.getExperimentAssignments()
            if assignments.isEmpty {
                Text("No assignments yet. Fetch to draw, or force one below.")
                    .font(.caption).foregroundColor(.gray)
            } else {
                ForEach(Array(assignments.keys.sorted()), id: \.self) { groupId in
                    Text("\(groupId) -> \(assignments[groupId] ?? "")")
                        .font(.system(size: 11))
                }
            }

            HStack {
                TextField("groupId", text: $forceGroupId)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .font(.system(size: 13))
                TextField("variantId", text: $forceVariantId)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .font(.system(size: 13))
            }

            HStack(spacing: 12) {
                Button("Force variant") {
                    let g = forceGroupId.trimmingCharacters(in: .whitespaces)
                    let v = forceVariantId.trimmingCharacters(in: .whitespaces)
                    guard !g.isEmpty, !v.isEmpty else { return }
                    experiencesTracker.setExperimentAssignment(groupId: g, variantId: v)
                    forceGroupId = ""
                    forceVariantId = ""
                    experimentsVersion += 1
                }
                .font(.caption)

                Button("Clear assignments") {
                    experiencesTracker.clearExperimentAssignments()
                    experimentsVersion += 1
                }
                .font(.caption)
            }
        }
        .id(experimentsVersion)
    }

    private var genericRecirculationSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Generic Recirculation").font(.headline).padding(.top, 16)

            HStack(spacing: 12) {
                Button("Eligible") {
                    recirculationTracker.trackEligible(
                        name: "demo-module",
                        links: [
                            RecirculationLink(url: "https://example.com/1", position: 0),
                            RecirculationLink(url: "https://example.com/2", position: 1),
                        ]
                    )
                }
                .buttonStyle(TrackButtonStyle(color: .green))

                Button("Impression") {
                    recirculationTracker.trackImpression(
                        name: "demo-module",
                        links: [RecirculationLink(url: "https://example.com/1", position: 0)]
                    )
                }
                .buttonStyle(TrackButtonStyle(color: .orange))

                Button("Click") {
                    recirculationTracker.trackClick(
                        name: "demo-module",
                        link: RecirculationLink(url: "https://example.com/1", position: 0)
                    )
                }
                .buttonStyle(TrackButtonStyle(color: .red))
            }
        }
    }

    private func fetchExperiences(resolve: Bool) {
        isLoading = true
        resultText = ""
        experiencesTracker.fetchExperiences(
            filterByType: selectedType,
            filterByFamily: selectedFamily,
            resolve: resolve,
            url: url.isEmpty ? nil : url
        ) { experiences in
            DispatchQueue.main.async {
                lastExperiences = experiences
                experimentsVersion += 1
                capsVersion += 1
                if resolve {
                    resultText = "Found \(experiences.count) experiences:\n" +
                        experiences.map { exp in
                            let familyTag = exp.family.map { " family=\($0.rawValue)" } ?? ""
                            let resolved = exp.resolvedContent.map { " [resolved: \(String($0.prefix(100)))]" } ?? ""
                            return "- [\(exp.type.rawValue)] \(exp.name)\(familyTag)\(resolved)"
                        }.joined(separator: "\n")
                } else {
                    resultText = "Found \(experiences.count) experiences:\n" +
                        experiences.map { exp in
                            let familyTag = exp.family.map { " family=\($0.rawValue)" } ?? ""
                            return "- [\(exp.type.rawValue)] \(exp.name)\(familyTag) (id=\(exp.id))"
                        }.joined(separator: "\n")
                }
                isLoading = false
            }
        }
    }
}

struct TrackButtonStyle: ButtonStyle {
    let color: Color

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .semibold))
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(configuration.isPressed ? color.opacity(0.7) : color)
            .foregroundColor(.white)
            .cornerRadius(8)
    }
}
