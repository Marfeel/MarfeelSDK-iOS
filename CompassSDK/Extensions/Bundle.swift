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
        guard let urlString = object(forInfoDictionaryKey: "COMPASS_ENDPOINT") as? String else {
            return nil
        }
        return URL(string: urlString)
    }
}
