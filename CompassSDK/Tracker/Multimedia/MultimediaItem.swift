//
//  MultimediaItem.swift
//  CompassSDK
//
//  Created by Marc García Lopez on 27/04/2023.
//

import Foundation

private enum Errors: String {
    case EVENT_OUT_OF_MEDIA_DURATION = "Event %@ for media %@ has not been processed because event time is not in media duration time."
}

public class MultimediaItem: Encodable {
    private enum CodingKeys : String, CodingKey {
        case provider = "m_p"
        case providerId = "m_pi"
        case type = "m_t"
        case imp
        case playbackInfo = "m"
    }

    let id: String
    let provider: String
    let providerId: String
    let type: Type
    let metadata: MultimediaMetadata
    let imp = UUID().uuidString
    var playbackInfo = PlaybackInfo()
    
    init(id: String, provider: String, providerId: String, type: Type, metadata: MultimediaMetadata) {
        
        self.id = id
        self.provider = provider
        self.providerId = providerId
        self.type = type
        self.metadata = metadata
    }
    
    public func addEvent(event: Event, eventTime: Int) {
        guard metadata.duration != nil && (eventTime < metadata.duration! + 1) else {
            print(
                String(format: Errors.EVENT_OUT_OF_MEDIA_DURATION.rawValue, arguments: [eventTime, id]
                )
            )
            
            return
        }
        
        if ![Event.LEAVE_VIEWPORT, Event.LEAVE_VIEWPORT].contains(event) {
            playbackInfo.addEvent(event: event, time: eventTime)
        }
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        
        try metadata.encode(to: encoder)
        try container.encodeIfPresent(provider, forKey: .provider)
        try container.encodeIfPresent(providerId, forKey: .providerId)
        try container.encodeIfPresent(type.rawValue, forKey: .type)
        try container.encodeIfPresent(imp, forKey: .imp)
        try container.encodeIfPresent(playbackInfo, forKey: .playbackInfo)
    }
}
