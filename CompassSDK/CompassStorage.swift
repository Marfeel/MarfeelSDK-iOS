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
    }
    
    let filename = "CompassPersistence"
    
    init() {
        self.model = load()
    }
    
    private var model: Model? {
        didSet {
            guard let model = model else {return}
            persist(values: model)
        }
    }
}

extension PListCompassStorage: CompassStorage {
    func addVisit() {
        model?.numVisits += 1
    }
    
    var user: CompassUser? {
        get {
            model?.user
        }
        set {
            model?.user = newValue
        }
    }
    
    var previousVisit: Date? {
        model?.lastVisit //TODO
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
