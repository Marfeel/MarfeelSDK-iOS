//
//  Event.swift
//  CompassSDK
//
//  Created by Marc García Lopez on 26/04/2023.
//

import Foundation

public enum Event: String, Codable {
    case PLAY = "play"
    case PAUSE = "pause"
    case END = "end"
    case UPDATE_CURRENT_TIME = "updateCurrentTime"
    case AD_PLAY = "adPlay"
    case MUTE = "mute"
    case UNMUTE = "unmute"
    case FULL_SCREEN = "fullscreen"
    case BACK_SCREEN = "backscreen"
    case ENTER_VIEWPORT = "enterViewport"
    case LEAVE_VIEWPORT = "leaveViewport"
}
