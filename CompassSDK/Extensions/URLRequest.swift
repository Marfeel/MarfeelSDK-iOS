//
//  URLRequest.swift
//  CompassSDK
//
//  Created by  on 04/02/2021.
//

import Foundation

extension URLRequest {
    private func percentEscapeString(_ string: String) -> String {
        var characterSet = CharacterSet.alphanumerics
        characterSet.insert(charactersIn: "-._* ")
        
        return string
          .addingPercentEncoding(withAllowedCharacters: characterSet)!
          .replacingOccurrences(of: " ", with: "+")
          .replacingOccurrences(of: " ", with: "+", options: [], range: nil)
      }
      
      mutating func encodeParameters(parameters: [String : CustomStringConvertible]) {
        httpMethod = "POST"
        
        let parameterArray = parameters.map { (arg) -> String in
          let (key, value) = arg
            var description = value.description
            
            if let arr = value as? [[String]] {
                description = arr.description
            }
            
            return "\(key)=\(self.percentEscapeString(description))"
        }
        
        httpBody = parameterArray.joined(separator: "&").data(using: String.Encoding.utf8)
      }
}
