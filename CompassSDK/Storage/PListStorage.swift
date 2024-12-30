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
    func load(_ filename: String) -> Model?
    func persist(filename: String, values: Model)
    func remove(filename: String)
}

extension PListStorage {
    var fileManager: FileManager {.default}
    
    func getFilePath(_ filename: String) -> URL? {
        return fileManager.urls(for: .documentDirectory, in: .userDomainMask).first?.appendingPathComponent("\(filename).plist")
    }
    
    func load(_ filename: String) -> Model? {
        guard let path = getFilePath(filename), let items = Model.plistDecode(from: path) else {return nil}
        return items
    }
    
    func persist(filename: String, values: Model) {
        guard let path = getFilePath(filename), let data = values.plistEncode() else {
            return
        }
        
        try? data.write(to: path)
    }
    
    func remove(filename: String) {
        guard let path = getFilePath(filename) else {
            return
        }
        
        do {
            try fileManager.removeItem(at: path)

        } catch {}
    }
}
