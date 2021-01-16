//
//  SendTik.swift
//  CompassSDK
//
//  Created by  on 14/01/2021.
//

import Foundation

protocol SendTikCuseCase {
    func tik(params: [String: String]) -> URLSessionDataTask?
}

class SendTik: SendTikCuseCase {
    private let session: URLSession
    
    init(session: URLSession = .shared) {
        self.session = session
    }
    
    func tik(params: [String: String]) -> URLSessionDataTask? {
        guard let request = buildRequest(params: params) else {return nil}
        let task = session.dataTask(with: request)
        print("tik --> params: \(params)")
        return task
    }
}

private extension SendTik {
    func buildRequest(params: [String: String]) -> URLRequest? {
        guard let encodedParams = try? JSONEncoder().encode(params) else {return nil}
        var request = URLRequest(url: URL(string: "http://127.0.0.1/tik")!)
        request.httpMethod = "POST"
        request.httpBody = encodedParams
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        return request
    }
}
