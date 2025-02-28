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
    
    var pageTechnology: Int? { object(forInfoDictionaryKey: "COMPASS_PAGE_TYPE") as? Int }
    
    static var compassSDK: Bundle? {
        return Bundle(for: CompassTracker.self)
    }
    
}
