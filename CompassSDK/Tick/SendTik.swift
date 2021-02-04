//
//  SendTik.swift
//  CompassSDK
//
//  Created by  on 14/01/2021.
//

import Foundation
import UIKit

protocol SendTikCuseCase {
    func tik(data: Data) -> URLSessionDataTask?
    func tik(params: [String: Any]) -> URLSessionDataTask?
}

class SendTik: SendTikCuseCase {
    private let session: URLSession
    private let bundle: Bundle
    private let application: UIApplication
    
    init(session: URLSession = .shared, bundle: Bundle = .main, application: UIApplication = .shared) {
        self.session = session
        self.bundle = bundle
        self.application = application
    }
    
    private var backgroundIdentifier: UIBackgroundTaskIdentifier?
    
    func tik(params: [String: Any]) -> URLSessionDataTask? {
        guard let request = buildRequest(params: params) else {return nil}
        return task(from: request)
    }
    
    func tik(data: Data) -> URLSessionDataTask? {
        print("tik --> params: \(String(data: data, encoding: .utf8)!)")
        guard let request = buildRequest(data: data) else {return nil}
        return task(from: request)
    }
    
    private lazy var endpoint: String? = bundle.compassEndpoint ?? "http://localhost:3000/"
}

private extension SendTik {
    func task(from request: URLRequest) -> URLSessionDataTask? {
        backgroundIdentifier = application.beginBackgroundTask {
            guard let backgroundIdentifier = self.backgroundIdentifier else {return}
            self.application.endBackgroundTask(backgroundIdentifier)
            self.backgroundIdentifier = .invalid
        }
        let task = session.dataTask(with: request) { (data, response , error) in
            guard let backgroundIdentifier = self.backgroundIdentifier else {return}
            self.application.endBackgroundTask(backgroundIdentifier)
            self.backgroundIdentifier = .invalid
        }
        task.resume()
        return task
    }
    
    func buildRequest(data: Data) -> URLRequest? {
        guard let endpoint = endpoint, let url = URL(string: endpoint) else {return nil}
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = data
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        return request
    }
    
    func buildRequest(params: [String: Any]) -> URLRequest? {
        guard let endpoint = endpoint, let url = URL(string: endpoint), let params = params as? [String: CustomStringConvertible] else {return nil}
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.encodeParameters(parameters: params)
        request.addValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        return request
    }
}
