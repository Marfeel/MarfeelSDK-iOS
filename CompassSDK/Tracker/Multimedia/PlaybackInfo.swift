//
//  PlaybackInfo.swift
//  CompassSDK
//
//  Created by Marc García Lopez on 27/04/2023.
//

import Foundation

public struct PlaybackInfo: Encodable {
    private enum CodingKeys : String, CodingKey {
        case ads
        case maxPlayTime = "mp"
        case play
        case pause
        case mute
        case unmute
        case backScreen = "bscr"
        case fullScreen = "fscr"
        case ended = "e"
        case started = "s"
        case adsStarted = "a"
        case adsLength = "ap"
    }
    
    var ads: [Int] = []
    var maxPlayTime: Int = 0
    var play: [Int] = []
    var pause: [Int] = []
    var mute: [Int] = []
    var unmute: [Int] = []
    var backScreen: [Int] = []
    var fullScreen: [Int] = []
    var inViewport: Bool = false
    var ended: Bool = false
    var started: Bool {
        return play.count > 0
    }
    var adsStarted: Bool {
        return ads.count > 0
    }
    var adsLength: Int {
        return ads.count
    }
    
    public init() {}
    
    public mutating func addEvent(event: Event, time: Int) {
        switch event {
        case .PLAY:
            play.append(time)
        case .PAUSE:
            pause.append(time)
        case .END:
            pause.append(time)
            ended = true
        case .AD_PLAY:
            ads.append(time)
        case .MUTE:
            mute.append(time)
        case .UNMUTE:
            unmute.append(time)
        case .FULL_SCREEN:
            fullScreen.append(time)
        case .BACK_SCREEN:
            backScreen.append(time)
        case .ENTER_VIEWPORT:
            inViewport = true
        case .LEAVE_VIEWPORT:
            inViewport = false
        default: break
        }
        
        if time > maxPlayTime {
            maxPlayTime = time
        }
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        
        try container.encode(ads, forKey: .ads)
        try container.encode(maxPlayTime, forKey: .maxPlayTime)
        try container.encode(play, forKey: .play)
        try container.encode(pause, forKey: .pause)
        try container.encode(mute, forKey: .mute)
        try container.encode(unmute, forKey: .unmute)
        try container.encode(backScreen, forKey: .backScreen)
        try container.encode(fullScreen, forKey: .fullScreen)
        try container.encode(started, forKey: .started)
        try container.encode(adsStarted, forKey: .adsStarted)
        try container.encode(adsLength, forKey: .adsLength)
    }
}
