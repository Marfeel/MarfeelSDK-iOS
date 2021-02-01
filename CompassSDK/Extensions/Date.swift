//
//  Date.swift
//  CompassSDK
//
//  Created by  on 17/01/2021.
//

import Foundation

extension Date {
    var timeStamp: Int {Int(timeIntervalSince1970)}
    
    func adding(minutes: Int) -> Date {
        Calendar.current.date(byAdding: .minute, value: minutes, to: self)!
    }
}
