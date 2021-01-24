//
//  PListStorage.swift
//  CompassSDK
//
//  Created by  on 17/01/2021.
//

import Foundation

protocol PListStorage {
    associatedtype Model: Codable
    var fileManager: FileManager {get}
    var filename: String {get}
    func load() -> Model?
    func persist(values: Model)
}

extension PListStorage {
    var fileManager: FileManager {.default}
    
    var menuFilePath: URL? {
        fileManager.urls(for: .documentDirectory, in: .userDomainMask).first?.appendingPathComponent("\(filename).plist")
    }
    
    func load() -> Model? {
        guard let path = menuFilePath, let items = Model.plistDecode(from: path) else {return nil}
        return items
    }
    
    func persist(values: Model) {
        guard let path = menuFilePath, let data = values.plistEncode() else {
            return
        }
        
        try? data.write(to: path)
    }
}
