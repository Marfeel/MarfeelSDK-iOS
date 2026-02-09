//
//  GetRCV.swift
//  CompassSDK
//
//  Created by  on 08/02/2021.
//

import Foundation

protocol GetRFVUseCase {
    func fetch(userId: String, registeredUserId: String?, account: Int, _ completion: @escaping (Rfv?, Error?) -> ())
}

struct GetRFVApiCall: ApiCall {
    let userId: String
    let registeredUserId: String?
    let account: Int
    let baseUrl: URL?
    let path: String = "data/rfv.php"
    let type: ContentType = ContentType.FORM
    var params: [String : Any] {
        var result: [String: Any] = ["u": userId, "ac": account]
        if let registeredUserId = registeredUserId {
            result["sui"] = registeredUserId
        }
        return result
    }

    init(userId: String, registeredUserId: String? = nil, account: Int, baseUrl: URL? = TrackingConfig.shared.endpoint) {
        self.userId = userId
        self.registeredUserId = registeredUserId
        self.account = account
        self.baseUrl = baseUrl
    }
}

class GetRFV {
    private let apiRouter: ApiRouting
    
    init(apiRouter: ApiRouting = ApiRouter()) {
        self.apiRouter = apiRouter
    }
}

extension GetRFV: GetRFVUseCase {
    func fetch(userId: String, registeredUserId: String?, account: Int, _ completion: @escaping (Rfv?, Error?) -> ()) {
        let apiCall = GetRFVApiCall(userId: userId, registeredUserId: registeredUserId, account: account)
        
        apiRouter.request(from: apiCall) { (rfv: Rfv?, error: Error?) in
            completion(rfv, error)
        }
    }
}
