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

    init(
        baseUrl: URL? = TrackingConfig.shared.endpoint,
        params: [String: Any],
        path: String,
        type: ContentType
    ) {
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

final class SendTik: SendTikCuseCase {
    private let apiRouter: ApiRouting
    private let application: UIApplication
    private let primaryUrl: URL?
    private let fallbackUrl: URL?
    private let fallbackDuration: TimeInterval?

    private var origin: OriginType = .primary
    private var fallbackDispatchTimer: DispatchSourceTimer?
    private let syncQueue = DispatchQueue(label: "SendTik.sync")

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
        performTrackedCall(
            name: "SendTik.primary",
            path: path,
            type: type,
            params: params,
            timeout: 10
        ) { [weak self] error in
            guard let self = self else { return }

            if error != nil,
               self.getOrigin() == .primary,
               self.fallbackUrl != nil {
                self.activateFallback()
                self.performFallback(path: path, type: type, params: params)
            }
        }
    }

    private func makeApiCall(path: String, type: ContentType, params: [String: Any]) -> TikApiCall {
        return TikApiCall(
            baseUrl: currentBaseUrl(),
            params: params,
            path: path,
            type: type
        )
    }

    private func performTrackedCall(
        name: String,
        path: String,
        type: ContentType,
        params: [String: Any],
        timeout: TimeInterval? = nil,
        completion: @escaping (Error?) -> Void
    ) {
        var taskID: UIBackgroundTaskIdentifier = .invalid
        taskID = application.beginBackgroundTask(withName: name) {
            if taskID != .invalid {
                self.application.endBackgroundTask(taskID)
                taskID = .invalid
            }
        }

        let apiCall = makeApiCall(path: path, type: type, params: params)

        var isCompleted = false
        let complete: (Error?) -> Void = { error in
            guard !isCompleted else { return }
            isCompleted = true
            if taskID != .invalid {
                self.application.endBackgroundTask(taskID)
                taskID = .invalid
            }
            completion(error)
        }

        if let timeout = timeout {
            DispatchQueue.global().asyncAfter(deadline: .now() + timeout) {
                if !isCompleted {
                    complete(NSError(domain: "SendTik", code: -1, userInfo: [NSLocalizedDescriptionKey: "Primary request timeout"]))
                }
            }
        }

        apiRouter.call(from: apiCall) { error in
            complete(error)
        }
    }

    private func performFallback(path: String, type: ContentType, params: [String: Any]) {
        var fallbackTaskID: UIBackgroundTaskIdentifier = .invalid
        fallbackTaskID = application.beginBackgroundTask(withName: "SendTik.fallback") {
            if fallbackTaskID != .invalid {
                self.application.endBackgroundTask(fallbackTaskID)
                fallbackTaskID = .invalid
            }
        }

        let fallbackCall = makeApiCall(path: path, type: type, params: params)

        DispatchQueue.global().async {
            self.apiRouter.call(from: fallbackCall) { _ in
            }
        }

        DispatchQueue.global().asyncAfter(deadline: .now() + 0.1) {
            if fallbackTaskID != .invalid {
                self.application.endBackgroundTask(fallbackTaskID)
                fallbackTaskID = .invalid
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
        syncQueue.async { [weak self] in
            guard let self = self else { return }
            self.origin = .primary
            self.fallbackDispatchTimer?.cancel()
            self.fallbackDispatchTimer = nil
        }
    }
}
