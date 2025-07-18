//
//  Bundle.swift
//  CompassSDK
//
//  Created by  on 17/01/2021.
//

import Foundation

extension Bundle {
    var compassAccountId: Int? {object(forInfoDictionaryKey: "COMPASS_ACCOUNT_ID") as? Int}
    
    var compassEndpoint: URL? {
        let urlString = object(forInfoDictionaryKey: "COMPASS_ENDPOINT") as? String ?? "https://events.newsroom.bi/"
        
        return URL(string: urlString)
    }
    
    var compassFallbackEndpoint: URL? {
        let urlString = object(forInfoDictionaryKey: "COMPASS_FALLBACK_ENDPOINT") as? String ?? "https://icu.newsroom.bi/"
        
        return URL(string: urlString)
    }
    
    var pageTechnology: Int? { object(forInfoDictionaryKey: "COMPASS_PAGE_TYPE") as? Int }
    
    var fallbackWindow: Double? { object(forInfoDictionaryKey: "COPASS_FALLBACK_ENDPOINT_WINDOW") as? Double ?? 60 }

    static var compassSDK: Bundle? {
        return Bundle(for: CompassTracker.self)
    }
    
}
