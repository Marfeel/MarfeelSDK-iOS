//
//  Bundle.swift
//  CompassSDK
//
//  Created by  on 17/01/2021.
//

import Foundation

extension Bundle {
    var compassAccountId: Int? {object(forInfoDictionaryKey: "COMPASS_ACCOUNT_ID") as? Int}
    var compassEndpoint: String? {object(forInfoDictionaryKey: "COMPASS_ENDPOINT") as? String}
}
