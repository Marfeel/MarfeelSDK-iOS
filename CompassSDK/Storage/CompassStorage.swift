//
//  CompassStorage.swift
//  CompassSDK
//
//  Created by  on 17/01/2021.
//

import Foundation

protocol CompassStorage {
    func addVisit()
    var suid: String {get}
    var userId: String? {get set}
    var previousVisit: Date? {get}
    var firstVisit: Date {get}
    var sessionId: String {get}
}

class PListCompassStorage: PListStorage {
    struct Model: Codable {
        var numVisits: Int
        var userId: String?
        var suid: String?
        var firstVisit: Date?
        var lastVisit: Date?
        var sessionId: String?
        var sessionExpirationDate: Date?
        
        static var empty: Model {.init(numVisits: 0, userId: nil, suid: nil, firstVisit: nil, lastVisit: nil)}
    }
    
    let filename = "CompassPersistence"
    
    init() {
        self.model = load() ?? .empty
    }
    
    private var model: Model? {
        didSet {
            guard let model = model else {return}
            persist(values: model)
        }
    }
    
    var previousVisit: Date?
}

extension PListCompassStorage: CompassStorage {
    var sessionId: String {
        guard let sessionId = model?.sessionId, let expirationDate = model?.sessionExpirationDate, Date() < expirationDate else {
            let sessionId = UUID().uuidString
            model?.sessionId = sessionId
            model?.sessionExpirationDate = Date().adding(minutes: 30)
            return sessionId
        }
        
        model?.sessionExpirationDate = Date().adding(minutes: 30)
        return sessionId
    }
    
    var suid: String {
        guard let suid = model?.suid else {
            let suid = UUID().uuidString
            model?.suid = suid
            return suid
        }
        
        return suid
    }
    
    var userId: String? {
        get {
            model?.userId
        }
        
        set {
            model?.userId = newValue
        }
    }
    
    func addVisit() {
        model?.numVisits += 1
        previousVisit = model?.lastVisit
        model?.lastVisit = Date()
    }
    
    var firstVisit: Date {
        guard let firstVisit = model?.firstVisit else {
            let date = Date()
            model?.firstVisit = date
            return date
        }
        
        return firstVisit
    }
}
