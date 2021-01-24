//
//  Bundle.swift
//  CompassSDK
//
//  Created by  on 17/01/2021.
//

import Foundation

extension Bundle {
    var compassAccountId: String? {object(forInfoDictionaryKey: "COMPASS_ACCOUNT_ID") as? String}
    var compassEndpoint: String? {object(forInfoDictionaryKey: "COMPASS_ENDPOINT") as? String}
    var compassVersion: String? {object(forInfoDictionaryKey: "COMPASS_VERSION") as? String}
}
