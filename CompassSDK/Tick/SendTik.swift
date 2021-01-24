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
    
    func tik(data: Data) -> URLSessionDataTask? {
        print("tik --> params: \(String(data: data, encoding: .utf8)!)")
        guard let request = buildRequest(data: data) else {return nil}
        backgroundIdentifier = application.beginBackgroundTask {
            guard let backgroundIdentifier = self.backgroundIdentifier else {return}
            self.application.endBackgroundTask(backgroundIdentifier)
            self.backgroundIdentifier = .invalid
        }
        let task = session.dataTask(with: request) { (_, _, _) in
            guard let backgroundIdentifier = self.backgroundIdentifier else {return}
            self.application.endBackgroundTask(backgroundIdentifier)
            self.backgroundIdentifier = .invalid
        }
        task.resume()
        return task
    }
    
    private lazy var endpoint: String? = bundle.compassEndpoint ?? "http://localhost:3000/"
}

private extension SendTik {
    func buildRequest(data: Data) -> URLRequest? {
        guard let endpoint = endpoint, let url = URL(string: endpoint) else {return nil}
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = data
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        return request
    }
}
