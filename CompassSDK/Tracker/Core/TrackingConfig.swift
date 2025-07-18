//
//  TrackingConfig.swift
//  CompassSDK
//
//  Created by Marc García Lopez on 8/4/24.
//

import Foundation

public class TrackingConfig {
    var accountId: Int?
    var endpoint: URL?
    var fallbackEndpoint: URL?
    var fallbackEndpointWindow: Double?
    var pageTechnology: Int?
    let version = "0.1"
    
    public static let shared: TrackingConfig = TrackingConfig()
    
    init(bundle: Bundle = .main) {
        self.accountId = bundle.compassAccountId
        self.pageTechnology = bundle.pageTechnology
        self.endpoint = bundle.compassEndpoint
        self.fallbackEndpoint = bundle.compassFallbackEndpoint
        self.fallbackEndpointWindow = bundle.fallbackWindow
    }
    
    public func override(accountId: Int, pageTechnology: Int?, endpoint: String?) {
        self.accountId = accountId;
        
        if let pageTechnology = pageTechnology {
            self.pageTechnology = pageTechnology
        }
        
        if let endpoint = endpoint {
            self.endpoint = URL(string: endpoint)
        }
    }
}
