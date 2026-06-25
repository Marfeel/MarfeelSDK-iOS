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
    func shouldTrackConversion(_ conversion: String, id: String?) -> Bool
    func addTrackedConversion(_ conversion: String, id: String?)
    func readCdpMasterId() -> String?
    func writeCdpMasterId(_ newMasterId: String) -> String?
    func readCdpCachedIdentity(sessionId: String) -> CdpCachedIdentity?
    func writeCdpCachedIdentity(rfv: CdpRfv?, cohorts: [Int], sessionId: String)
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
        var cdpMasterId: String?
        var cdpRfv: String?
        var cdpCohorts: String?
        var cdpCacheSessionId: String?

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

    func shouldTrackConversion(_ conversion: String, id: String?) -> Bool {
        
        if id == nil {
            return true
        }

        let key = conversionKey(conversion, id: id)

        return model?.trackedConversions?.contains(key) == false
    }

    func addTrackedConversion(_ conversion: String, id: String?) {
        if model?.trackedConversions == nil {
            model?.trackedConversions = []
        }
        
        if id != nil {
            let key = conversionKey(conversion, id: id)

            model?.trackedConversions?.append(key)
        }
    }

    private func conversionKey(_ conversion: String, id: String?) -> String {
        return id != nil ? "\(conversion):\(id!)" : conversion
    }

    // MARK: - CDP identity

    /// Returns the stored master_id only if it is a valid UUID. A corrupt / non-UUID
    /// value is transparently treated as absent (triggers a fresh resolve).
    func readCdpMasterId() -> String? {
        guard let id = model?.cdpMasterId, UUID(uuidString: id) != nil else { return nil }
        return id
    }

    /// Persists a new master_id and returns the **old** (validated) value — needed for
    /// segment carry-over when the master_id changes.
    func writeCdpMasterId(_ newMasterId: String) -> String? {
        let old = readCdpMasterId()
        model?.cdpMasterId = newMasterId
        return old
    }

    /// Session-tagged cached identity. Returns nil once the session rotates, nil if
    /// nothing is cached, and nil if the cohorts cache is corrupt (not an array).
    func readCdpCachedIdentity(sessionId: String) -> CdpCachedIdentity? {
        guard model?.cdpCacheSessionId == sessionId else { return nil }

        let rfvJson = model?.cdpRfv
        let cohortsJson = model?.cdpCohorts

        if rfvJson == nil && cohortsJson == nil { return nil }
        guard let cohorts = parseCdpCohorts(cohortsJson) else { return nil }
        let rfv = rfvJson.flatMap { CdpRfv.jsonStringDecode(from: $0) }

        return CdpCachedIdentity(rfv: rfv, cohorts: cohorts)
    }

    func writeCdpCachedIdentity(rfv: CdpRfv?, cohorts: [Int], sessionId: String) {
        model?.cdpRfv = rfv.flatMap { $0.encode() }.flatMap { String(data: $0, encoding: .utf8) }
        model?.cdpCohorts = (cohorts.encode()).flatMap { String(data: $0, encoding: .utf8) }
        model?.cdpCacheSessionId = sessionId
    }

    private func parseCdpCohorts(_ json: String?) -> [Int]? {
        guard let json = json, let data = json.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode([Int].self, from: data)
    }
}
        
