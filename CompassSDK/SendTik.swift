//
//  SendTik.swift
//  CompassSDK
//
//  Created by  on 14/01/2021.
//

import Foundation

protocol SendTikCuseCase {
    func tik(data: Data) -> URLSessionDataTask?
}

class SendTik: SendTikCuseCase {
    private let session: URLSession
    
    init(session: URLSession = .shared) {
        self.session = session
    }
    
    func tik(data: Data) -> URLSessionDataTask? {
        guard let request = buildRequest(data: data) else {return nil}
        let task = session.dataTask(with: request)
        print("tik --> params: \(String(data: data, encoding: .utf8)!)")
        return task
    }
}

private extension SendTik {
    func buildRequest(data: Data) -> URLRequest? {
        var request = URLRequest(url: URL(string: "http://127.0.0.1/tik")!)
        request.httpMethod = "POST"
        request.httpBody = data
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        return request
    }
}
