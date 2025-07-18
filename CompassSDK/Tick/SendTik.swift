import Foundation
import UIKit

protocol SendTikCuseCase {
    func tik(path: String, type: ContentType, params: [String: Any])
}

struct TikApiCall: ApiCall {
    let path: String
    let params: [String: Any]
    let baseUrl: URL?
    let type: ContentType

    init(baseUrl: URL? = TrackingConfig.shared.endpoint, params: [String: Any], path: String, type: ContentType) {
        self.baseUrl = baseUrl
        self.params = params
        self.path = path
        self.type = type
    }
}

enum OriginType {
    case primary
    case fallback
}

class SendTik: SendTikCuseCase {
    private let apiRouter: ApiRouting
    private let application: UIApplication
    private let primaryUrl: URL?
    private let fallbackUrl: URL?
    private let fallbackDuration: TimeInterval?

    private var origin: OriginType = .primary
    private var fallbackDispatchTimer: DispatchSourceTimer?
    private let syncQueue = DispatchQueue(label: "SendTik.sync")

    private var backgroundIdentifier: UIBackgroundTaskIdentifier?

    init(
        apiRouter: ApiRouting = ApiRouter(),
        application: UIApplication = .shared,
        primaryUrl: URL? = TrackingConfig.shared.endpoint,
        fallbackUrl: URL? = TrackingConfig.shared.fallbackEndpoint,
        fallbackDuration: TimeInterval? = TrackingConfig.shared.fallbackEndpointWindow
    ) {
        self.apiRouter = apiRouter
        self.application = application
        self.primaryUrl = primaryUrl
        self.fallbackUrl = fallbackUrl
        self.fallbackDuration = fallbackDuration
    }

    func tik(path: String, type: ContentType, params: [String: Any]) {
        backgroundIdentifier = application.beginBackgroundTask {
            self.endBackgroundTask()
        }

        performTikCall(path: path, type: type, params: params)
    }

    private func performTikCall(path: String, type: ContentType, params: [String: Any]) {
        let apiCall = TikApiCall(
            baseUrl: currentBaseUrl(),
            params: params,
            path: path,
            type: type
        )

        apiRouter.call(from: apiCall) { [weak self] error in
            guard let self = self else { return }

            if error != nil,
               self.getOrigin() == .primary,
               self.fallbackUrl != nil {
                self.activateFallback()

                let fallbackCall = TikApiCall(
                    baseUrl: self.currentBaseUrl(),
                    params: params,
                    path: path,
                    type: type
                )

                self.apiRouter.call(from: fallbackCall) { _ in
                    self.endBackgroundTask()
                }
            } else {
                self.endBackgroundTask()
            }
        }
    }

    private func currentBaseUrl() -> URL? {
        syncQueue.sync {
            switch origin {
            case .primary:
                return primaryUrl
            case .fallback:
                return fallbackUrl ?? primaryUrl
            }
        }
    }

    private func getOrigin() -> OriginType {
        syncQueue.sync { origin }
    }

    private func activateFallback() {
        syncQueue.sync {
            guard origin == .primary else { return }

            origin = .fallback

            fallbackDispatchTimer?.cancel()
            fallbackDispatchTimer = nil

            if let duration = fallbackDuration {
                let timer = DispatchSource.makeTimerSource(queue: syncQueue)
                timer.schedule(deadline: .now() + duration)
                timer.setEventHandler { [weak self] in
                    self?.deactivateFallback()
                }
                timer.resume()
                fallbackDispatchTimer = timer
            }
        }
    }

    private func deactivateFallback() {
        origin = .primary
        fallbackDispatchTimer?.cancel()
        fallbackDispatchTimer = nil
    }

    private func endBackgroundTask() {
        guard let backgroundIdentifier = self.backgroundIdentifier else { return }

        self.application.endBackgroundTask(backgroundIdentifier)
        self.backgroundIdentifier = .invalid
    }
}
