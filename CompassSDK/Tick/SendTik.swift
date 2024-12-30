//
//  SendTik.swift
//  CompassSDK
//
//  Created by  on 14/01/2021.
//

import Foundation
import UIKit

protocol SendTikCuseCase {
    func tik(path: String, type: ContentType, params: [String: Any])
}

struct TikApiCall: ApiCall {
    let path: String
    let params: [String : Any]
    let baseUrl: URL?
    let type: ContentType
    
    init(baseUrl: URL? = TrackingConfig.shared.endpoint, params: [String : Any], path: String, type: ContentType) {
        self.baseUrl = baseUrl
        self.params = params
        self.path = path
        self.type = type
    }
}

class SendTik: SendTikCuseCase {
    private let apiRouter: ApiRouting
    private let application: UIApplication
    
    init(apiRouter: ApiRouting = ApiRouter(), application: UIApplication = .shared) {
        self.apiRouter = apiRouter
        self.application = application
    }
    
    private var backgroundIdentifier: UIBackgroundTaskIdentifier?
    
    func tik(path: String, type: ContentType, params: [String: Any]) {
        backgroundIdentifier = application.beginBackgroundTask {
            guard let backgroundIdentifier = self.backgroundIdentifier else {return}
            self.application.endBackgroundTask(backgroundIdentifier)
            self.backgroundIdentifier = .invalid
        }
        let apiCall = TikApiCall(params: params, path: path, type: type)
        apiRouter.call(from: apiCall) { (error) in
            guard let backgroundIdentifier = self.backgroundIdentifier else {return}
            self.application.endBackgroundTask(backgroundIdentifier)
            self.backgroundIdentifier = .invalid
        }
    }
}
