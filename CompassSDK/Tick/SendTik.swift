//
//  SendTik.swift
//  CompassSDK
//
//  Created by  on 14/01/2021.
//

import Foundation
import UIKit

protocol SendTikCuseCase {
    func tik(params: [String: Any])
}

struct TikApiCall: ApiCall {
    let path: String = "ingest.php"
    let params: [String : Any]
    let baseUrl: URL?
    
    init(baseUrl: URL? = Bundle.main.compassEndpoint, params: [String : Any]) {
        self.baseUrl = baseUrl
        self.params = params
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
    
    func tik(params: [String: Any]) {
        backgroundIdentifier = application.beginBackgroundTask {
            guard let backgroundIdentifier = self.backgroundIdentifier else {return}
            self.application.endBackgroundTask(backgroundIdentifier)
            self.backgroundIdentifier = .invalid
        }
        let apiCall = TikApiCall(params: params)
        apiRouter.call(from: apiCall) { (error) in
            guard let backgroundIdentifier = self.backgroundIdentifier else {return}
            self.application.endBackgroundTask(backgroundIdentifier)
            self.backgroundIdentifier = .invalid
        }
    }
}
