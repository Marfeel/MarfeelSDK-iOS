//
//  CompassStorage.swift
//  CompassSDK
//
//  Created by  on 17/01/2021.
//

import Foundation

protocol CompassStorage {
    func addVisit()
    var suid: String? {get set}
    var userId: String {get}
    var previousVisit: Date? {get}
    var firstVisit: Date {get}
    var sessionId: String {get}
    var sessionVars: Vars { get }
    var userVars: Vars { get }
    var userSegments: [String] { get }
    var hasConsent: Bool? { get }
    var landingPage: String? { get }
    func addSessionVar(name: String, value: String)
    func addUserVar(name: String, value: String)
    func addUserSegment(_ name: String)
    func addUserSegments(_ segments: [String])
    func removeUserSegment(_ name: String)
    func clearUserSegments()
    func setConsent(_ hasConsent: Bool)
    func setLandingPage(_ landingPage: String?)
    func hasTrackedConversion(_ conversion: String, id: String?) -> Bool
    func addTrackedConversion(_ conversion: String, id: String?)
}

enum Store: String {
    case v1 = "CompassPersistence"
    case v2 = "CompassPersistenceV2"
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
        var userVars: Vars?
        var sessionVars: Vars?
        var userSegments: [String]?
        var hasConsent: Bool?
        var landingPage: String?
        var trackedConversions: [String]?

        static var empty: Model {.init(numVisits: 0, userId: nil, suid: nil, firstVisit: nil, lastVisit: nil, userVars: Vars(), sessionVars: Vars(), userSegments: [], hasConsent: nil, landingPage: nil, trackedConversions: [])}
    }

    init() {
        self.model = loadModel() ?? .empty
    }
    
    private func loadModel() -> Model? {
        if let modelV2 = load(Store.v2.rawValue) {
            return modelV2
        }
        
        guard var modelV1 = load(Store.v1.rawValue) else {
            return nil
        }
                
        (modelV1.userId, modelV1.suid) = (modelV1.suid, modelV1.userId)
        
        return modelV1
    }

    private var model: Model? {
        willSet {
            guard let model = model, model.hasConsent != newValue?.hasConsent, newValue?.hasConsent == false else {
                return
            }
            
            remove(filename: Store.v2.rawValue)
        }
        didSet {
            guard let model = model, model.hasConsent == true || model.hasConsent == nil else {
                return
                
            }
            
            persist(filename: Store.v2.rawValue, values: model)
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
            model?.sessionVars = Vars()
            model?.landingPage = nil
            
            return sessionId
        }

        model?.sessionExpirationDate = Date().adding(minutes: 30)
        return sessionId
    }

    var suid: String? {
        get {
            model?.suid
        }

        set {
            model?.suid = newValue
        }
    }

    var userId: String {
        guard let userId = model?.userId else {
            let userId = UUID().uuidString

            model?.userId = userId

            return userId
        }

        return userId
    }
    
    var sessionVars: Vars {
        guard let vars = model?.sessionVars, let expirationDate = model?.sessionExpirationDate, Date() < expirationDate else {
            return Vars()
        }

        return vars
    }
    
    var userVars: Vars {
        guard let vars = model?.userVars else {
            return Vars()
        }

        return vars
    }
    
    var userSegments: [String] {
        guard let segments = model?.userSegments else {
            return []
        }

        return segments
    }

    func addVisit() {
        model?.numVisits += 1
        previousVisit = model?.lastVisit
        model?.lastVisit = Date()
    }
    
    func addSessionVar(name: String, value: String) {
        if model?.sessionVars == nil {
            model?.sessionVars = Vars()
        }
        
        model?.sessionVars?[name] = value
    }

    func addUserVar(name: String, value: String) {
        if model?.userVars == nil {
            model?.userVars = Vars()
        }
        
        model?.userVars?[name] = value
    }
    
    func addUserSegment(_ name: String) {
        if model?.userSegments == nil {
            model?.userSegments = []
        }
        
        if (model?.userSegments?.contains(name) ?? true) {
            return
        }
        
        model?.userSegments?.append(name)
    }
    
    func addUserSegments(_ segments: [String]) {
        model?.userSegments = segments
    }
    
    func removeUserSegment(_ name: String) {
        model?.userSegments?.removeAll{ $0 == name }
    }
    
    func clearUserSegments() {
        model?.userSegments?.removeAll()
    }
    
    var hasConsent: Bool? {
        get {
            model?.hasConsent
        }
        set {
            model?.hasConsent = newValue
        }
    }
    
    func setConsent(_ hasConsent: Bool) {
        model?.hasConsent = hasConsent
    }
    
    var firstVisit: Date {
        guard let firstVisit = model?.firstVisit else {
            let date = Date()
            model?.firstVisit = date
            return date
        }

        return firstVisit
    }
    
    var landingPage: String? {
        return model?.landingPage
    }
    
    func setLandingPage(_ landingPage: String?) {
        model?.landingPage = landingPage
    }

    func hasTrackedConversion(_ conversion: String, id: String?) -> Bool {
        let key = conversionKey(conversion, id: id)
        return model?.trackedConversions?.contains(key) ?? false
    }

    func addTrackedConversion(_ conversion: String, id: String?) {
        if model?.trackedConversions == nil {
            model?.trackedConversions = []
        }

        let key = conversionKey(conversion, id: id)
        model?.trackedConversions?.append(key)
    }

    private func conversionKey(_ conversion: String, id: String?) -> String {
        return id != nil ? "\(conversion):\(id!)" : conversion
    }
}
        
