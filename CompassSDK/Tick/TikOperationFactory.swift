//
//  TikOperationFactory.swift
//  CompassSDK
//
//  Created by  on 09/02/2021.
//

import Foundation

protocol TikOperationFactory {
    func buildOperation(trackInfo: TrackInfo, dispatchDate: Date, scrollPercentProvider: ScrollPercentProvider?, conversionsProvider: ConversionsProvider?) -> Operation
}

class TickOperationProvider: TikOperationFactory {
    func buildOperation(trackInfo: TrackInfo, dispatchDate: Date, scrollPercentProvider: ScrollPercentProvider?, conversionsProvider: ConversionsProvider?) -> Operation {
        TikOperation(trackInfo: trackInfo, dispatchDate: dispatchDate, tikUseCase: SendTik(), scrollPercentProvider: scrollPercentProvider, conversionsProvider: conversionsProvider)
    }
}
