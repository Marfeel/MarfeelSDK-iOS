//
//  Date.swift
//  CompassSDK
//
//  Created by  on 17/01/2021.
//

import Foundation

extension Date {
    var timeStamp: Int64 {Int64((self.timeIntervalSince1970 * 1000.0).rounded())}
    
    func adding(minutes: Int) -> Date {
        Calendar.current.date(byAdding: .minute, value: minutes, to: self)!
    }
}
