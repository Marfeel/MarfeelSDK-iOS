//
//  CompassStorage.swift
//  CompassSDK
//
//  Created by  on 17/01/2021.
//

import Foundation

protocol CompassStorage {
    func addVisit()
    var user: CompassUser? {get set}
    var previousVisit: Date? {get}
    var firstVisit: Date {get}
}

class PListCompassStorage: PListStorage {
    struct Model: Codable {
        var numVisits: Int
        var user: CompassUser?
        var firstVisit: Date?
        var lastVisit: Date?
        
        static var empty: Model {.init(numVisits: 0, user: nil, firstVisit: nil, lastVisit: nil)}
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
    func addVisit() {
        model?.numVisits += 1
        previousVisit = model?.lastVisit
        model?.lastVisit = Date()
    }
    
    var user: CompassUser? {
        get {
            model?.user
        }
        set {
            model?.user = newValue
        }
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
