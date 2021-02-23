//
//  GetRCV.swift
//  CompassSDK
//
//  Created by  on 08/02/2021.
//

import Foundation

protocol GetRFVUseCase {
    func fetch(userId: String, account: Int, _ completion: @escaping (String?, Error?) -> ())
}

struct RFVResponse: Codable {
    let rfv: String?
}

struct GetRFVApiCall: ApiCall {
    let userId: String
    let account: Int
    let baseUrl: URL?
    let path: String = "data.php"
    var params: [String : Any] {
        ["u": userId, "ac": account]
    }
    
    init(userId: String, account: Int, baseUrl: URL? = Bundle.main.compassEndpoint) {
        self.userId = userId
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
    func fetch(userId: String, account: Int, _ completion: @escaping (String?, Error?) -> ()) {
        let apiCall = GetRFVApiCall(userId: userId, account: account)
        apiRouter.request(from: apiCall) { (rfv: RFVResponse?, error: Error?) in
            completion(rfv?.rfv, error)
        }
    }
}
