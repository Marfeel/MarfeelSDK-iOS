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

enum GetRFVError: Error {
    case unableToBuildRCVRequest, unableToParseResponse
}

struct RFVResponse: Codable {
    let rfv: String?
}

class GetRFV {
    private let compassEndpoint: String?
    private let session: URLSession
    
    init(compassEndpoint: String? = Bundle.main.compassEndpoint, session: URLSession = .shared) {
        self.compassEndpoint = compassEndpoint
        self.session = session
    }
    
    private var endpoint: URL? {
        guard let compassEndpoint = compassEndpoint, let compassURL = URL(string: compassEndpoint) else {return nil}
        return compassURL.appendingPathComponent("data.php")
    }
}

extension GetRFV: GetRFVUseCase {
    func fetch(userId: String, account: Int, _ completion: @escaping (String?, Error?) -> ()) {
        guard let request = buildRequest(userId: userId, account: account) else {
            completion(nil, GetRFVError.unableToBuildRCVRequest)
            return
        }
        
        session.dataTask(with: request) { (data, response, error) in
            guard let data = data else {
                completion(nil, error)
                return
            }
            
            guard let rfv = RFVResponse.decode(from: data) else {
                completion(nil, GetRFVError.unableToParseResponse)
                return
            }
            
            completion(rfv.rfv, nil)
        }.resume()
    }
}

private extension GetRFV {
    private func buildRequest(userId: String, account: Int) -> URLRequest? {
        guard let url = endpoint else {return nil}
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.encodeParameters(parameters: ["u": userId, "ac": account])
        request.addValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        return request
    }
}
