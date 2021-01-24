//
//  Codable.swift
//  CompassSDK
//
//  Created by  on 17/01/2021.
//

import Foundation

extension Decodable {
    static func jsonDecode(from json: [String: Any]) -> Self? {
        guard let serializedData = try? JSONSerialization.data(withJSONObject: json) else {return nil}
        return decode(from: serializedData)
    }
    
    static func jsonStringDecode(from string: String) -> Self? {
        guard let data = string.data(using: .utf8), let json = try? JSONSerialization.jsonObject(with: data, options: .mutableContainers) as? [String: Any] else {return nil}
        return jsonDecode(from: json)
    }
    
    static func plistDecode(from path: URL) -> Self? {
        guard let data = try? Data(contentsOf: path) else {return nil}
        return try? PropertyListDecoder().decode(Self.self, from: data)
    }
    
    static func decode(from data: Data) -> Self? {
        return try? JSONDecoder().decode(Self.self, from: data)
    }
}

extension Encodable {
    func jsonEncode() -> [String: Any]? {
        guard let encodedData = encode() else {return nil}
        return (try? JSONSerialization.jsonObject(with: encodedData)) as? [String : Any]
    }
    
    func plistEncode() -> Data? {
        let encoder = PropertyListEncoder()
        encoder.outputFormat = .xml
        return try? encoder.encode(self)
    }
    
    func encode() -> Data? {
        let encoder = JSONEncoder()
        return try? encoder.encode(self)
    }
}
