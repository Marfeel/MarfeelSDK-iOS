import SwiftUI
import MarfeelSDK_iOS

struct CdpView: View {
    private let tracker = CompassTracker.shared
    private let cdp = Cdp.shared

    @State private var identitySummary = "—"
    @State private var consentOn = true
    @State private var siteUserId = "user@example.com"
    @State private var linkValue = ""
    @State private var segmentName = "sports_fan"
    @State private var segmentsSummary = "—"
    @State private var meterName = "paywall"
    @State private var metersSummary = "—"
    @State private var statusLine = ""

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    identitySection
                    Divider()
                    segmentsSection
                    Divider()
                    metersSection
                    if !statusLine.isEmpty {
                        Text(statusLine)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundColor(.secondary)
                    }
                }
                .padding()
            }
            .navigationTitle("CDP")
            .onAppear(perform: refreshIdentity)
        }
    }

    // MARK: - Identity

    private var identitySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Identity").font(.headline)

            Text(identitySummary)
                .font(.system(size: 12, design: .monospaced))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
                .background(Color(.systemGray6))
                .cornerRadius(6)

            Toggle("Personalization consent", isOn: $consentOn)
                .onChange(of: consentOn) { value in
                    tracker.setConsent(value)
                    status("setConsent(\(value))")
                    refreshIdentity()
                }

            HStack {
                Button("Track page") {
                    tracker.trackNewPage(url: URL(string: "https://dev.marfeel.co/cdp-demo")!)
                    status("trackNewPage → resolveIdentity")
                    refreshLater()
                }
                .buttonStyle(CdpButton(color: .blue))

                Button("Refresh") { refreshIdentity() }
                    .buttonStyle(CdpButton(color: .gray))
            }

            HStack {
                TextField("site user id", text: $siteUserId)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .autocapitalization(.none)
                    .disableAutocorrection(true)
                Button("setSiteUserId") {
                    tracker.setSiteUserId(siteUserId)
                    status("setSiteUserId → link(registered_user_id)")
                    refreshLater()
                }
                .buttonStyle(CdpButton(color: .purple))
            }

            VStack(spacing: 6) {
                TextField("email", text: $linkValue)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .autocapitalization(.none)
                    .disableAutocorrection(true)
                    .keyboardType(.emailAddress)
                Button("cdpDoIdentityLink (email, deterministic)") {
                    let value = linkValue.trimmingCharacters(in: .whitespaces)
                    guard !value.isEmpty else { return }
                    cdp.cdpDoIdentityLink(type: "email", value: value, isDeterministic: true)
                    status("cdpDoIdentityLink(email, \(value))")
                    refreshLater()
                }
                .buttonStyle(CdpButton(color: .purple))
            }
        }
    }

    // MARK: - Segments

    private var segmentsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Segments").font(.headline)

            Text(segmentsSummary)
                .font(.system(size: 12, design: .monospaced))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
                .background(Color(.systemGray6))
                .cornerRadius(6)

            TextField("segment", text: $segmentName)
                .textFieldStyle(RoundedBorderTextFieldStyle())
                .autocapitalization(.none)
                .disableAutocorrection(true)

            HStack {
                Button("Add") {
                    cdp.addCdpSegment(segmentName)
                    status("addCdpSegment(\(segmentName))")
                    refreshLater()
                }.buttonStyle(CdpButton(color: .green))

                Button("Remove") {
                    cdp.removeCdpSegment(segmentName)
                    status("removeCdpSegment(\(segmentName))")
                    refreshLater()
                }.buttonStyle(CdpButton(color: .orange))

                Button("Set [a,b,c]") {
                    cdp.setCdpSegments(["a", "b", "c"])
                    status("setCdpSegments([a,b,c])")
                    refreshLater()
                }.buttonStyle(CdpButton(color: .blue))

                Button("Clear") {
                    cdp.clearCdpSegments()
                    status("clearCdpSegments()")
                    refreshLater()
                }.buttonStyle(CdpButton(color: .red))
            }
        }
    }

    // MARK: - Meters

    private var metersSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Meters").font(.headline)

            Text(metersSummary)
                .font(.system(size: 12, design: .monospaced))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
                .background(Color(.systemGray6))
                .cornerRadius(6)

            TextField("meter name", text: $meterName)
                .textFieldStyle(RoundedBorderTextFieldStyle())
                .autocapitalization(.none)
                .disableAutocorrection(true)

            HStack {
                Button("Snapshot") {
                    cdp.getMeterSnapshot { meters in
                        DispatchQueue.main.async {
                            metersSummary = format(meters: meters)
                            status("getMeterSnapshot → \(meters.count) meters")
                        }
                    }
                }.buttonStyle(CdpButton(color: .blue))

                Button("Increment") {
                    cdp.incrementMeter(meterName) { result in
                        DispatchQueue.main.async {
                            switch result {
                            case .success(let meter):
                                status("increment(\(meterName)) → count=\(meter?.count.description ?? "nil")")
                                metersSummary = format(meters: cdp.listMeters())
                            case .failure(let error):
                                if error is MeterNotFoundError {
                                    status("increment(\(meterName)) → MeterNotFoundError")
                                } else {
                                    status("increment(\(meterName)) → \(error.localizedDescription)")
                                }
                            }
                        }
                    }
                }.buttonStyle(CdpButton(color: .green))

                Button("List (cached)") {
                    metersSummary = format(meters: cdp.listMeters())
                    status("listMeters() (sync)")
                }.buttonStyle(CdpButton(color: .gray))
            }
        }
    }

    // MARK: - Helpers

    private func refreshIdentity() {
        let data = cdp.getCdpData()
        let rfv = data.rfv.map { "rfv=\($0.rfv) r=\($0.r) f=\($0.f) v=\($0.v)" } ?? "rfv=nil"
        identitySummary = """
        master_id: \(data.masterId ?? "nil")
        \(rfv)
        cohorts: \(data.cohorts)
        """
        segmentsSummary = "local: \(cdp.getCdpSegments())"
    }

    /// Identity/link/segment calls are async; refresh after a short delay so the UI shows
    /// the resolved state without wiring a callback through the public fire-and-forget API.
    private func refreshLater() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0, execute: refreshIdentity)
    }

    private func format(meters: [MeterState]) -> String {
        guard !meters.isEmpty else { return "—" }
        return meters.map { m in
            let threshold = m.threshold.map { "/\($0)" } ?? ""
            return "\(m.name): \(m.count)\(threshold)"
        }.joined(separator: "\n")
    }

    private func status(_ text: String) { statusLine = text }
}

private struct CdpButton: ButtonStyle {
    let color: Color
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .semibold))
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity)
            .background(configuration.isPressed ? color.opacity(0.7) : color)
            .foregroundColor(.white)
            .cornerRadius(8)
    }
}
