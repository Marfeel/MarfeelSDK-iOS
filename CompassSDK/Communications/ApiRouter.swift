//
//  ApiRouter.swift
//  CompassSDK
//
//  Created by  on 09/02/2021.
//

import Foundation

protocol ApiCall {
    var path: String {get}
    var params: [String: Any] {get}
    var baseUrl: URL? {get}
}

extension ApiCall {
    var request: URLRequest? {
        guard let baseUrl = baseUrl?.appendingPathComponent(path), let params = params as? [String: CustomStringConvertible] else {return nil}
        var request = URLRequest(url: baseUrl)
        request.httpMethod = "POST"
        request.encodeParameters(parameters: params)
        request.addValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        return request
    }
}

protocol ApiRouting: class {
    func request<T>(from apiCall: ApiCall, _ completion: @escaping (T?, Error?) -> ()) where T: Decodable
    func call(from apiCall: ApiCall, _ completion: @escaping (Error?) -> ())
}

enum ApiRputerError: Error {
    case unableToBuildRequest, unableToParseResponse
}

class ApiRouter {
    private let session: URLSession
    
    init(session: URLSession = .shared) {
        self.session = session
    }
}

extension ApiRouter: ApiRouting {
    func request<T>(from apiCall: ApiCall, _ completion: @escaping (T?, Error?) -> ()) where T: Decodable {
        guard let request = apiCall.request else {
            completion(nil, ApiRputerError.unableToBuildRequest)
            return
        }
        session.dataTask(with: request) { (data, response, error) in
            guard let data = data else {
                completion(nil, error)
                return
            }
            guard let result = T.decode(from: data) else {
                completion(nil, ApiRputerError.unableToParseResponse)
                return
            }
            completion(result, nil)
        }.resume()
    }
    
    func call(from apiCall: ApiCall, _ completion: @escaping (Error?) -> ()) {
        guard let request = apiCall.request else {
            completion(ApiRputerError.unableToBuildRequest)
            return
        }
        session.dataTask(with: request) { (data, response, error) in
            completion(error)
        }.resume()
    }
}
