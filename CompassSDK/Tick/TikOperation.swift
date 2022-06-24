//
//  TikOperation.swift
//  CompassSDK
//
//  Created by  on 17/01/2021.
//

import Foundation

protocol ScrollPercentProvider: AnyObject {
    func getScrollPercent(_ completion: @escaping (Float?) -> ())
}

protocol ConversionsProvider: AnyObject {
    func getConversions(_ completion: @escaping ([String]) -> ())
}


class TikOperation: Operation {
    private let trackInfo: TrackInfo
    private let dispatchDate: Date
    private let tikUseCase: SendTikCuseCase
    private weak var scrollPercentProvider: ScrollPercentProvider?
    private weak var conversionsProvider: ConversionsProvider?
    
    init(trackInfo: TrackInfo, dispatchDate: Date, tikUseCase: SendTikCuseCase = SendTik(), scrollPercentProvider: ScrollPercentProvider?, conversionsProvider: ConversionsProvider?) {
        self.trackInfo = trackInfo
        self.dispatchDate = dispatchDate
        self.tikUseCase = tikUseCase
        self.scrollPercentProvider = scrollPercentProvider
        self.conversionsProvider = conversionsProvider
    }
    
    private var timer: Timer?
    
    private var runing: Bool = false {
        didSet {
            willChangeValue(forKey: "isFinished")
            willChangeValue(forKey: "isExecuting")
            didChangeValue(forKey: "isFinished")
            didChangeValue(forKey: "isExecuting")
        }
    }
    
    override var isAsynchronous: Bool {true}
    
    override var isFinished: Bool {!runing}
    
    override var isExecuting: Bool {runing}
    
    override func start() {
        guard !isCancelled else {return}
        runing = true
        
        self.timer = Timer(fire: self.dispatchDate, interval: 0, repeats: false, block: { [weak self] (timer) in
            self?.getScrollPercent { (scrollPercent) in
                self?.getConversions({ (conversions) in
                    var finalTrackInfo = self?.trackInfo
                    finalTrackInfo?.scrollPercent = scrollPercent
                    finalTrackInfo?.conversions = conversions.isEmpty ? nil : conversions
                    let data = finalTrackInfo?.params
                    if let data = data {
                        self?.tikUseCase.tik(params: data)
                    }
                    self?.timer?.invalidate()
                    self?.runing = false
                })
                
            }
        })
        
        RunLoop.current.add(self.timer!, forMode: .common)
        RunLoop.current.run()
    }
    
    override func cancel() {
        timer?.invalidate()
        runing = false
    }
    
    private func getScrollPercent(_ completion: @escaping (Float?) -> ()) {
        guard let scrollPercentProvider = scrollPercentProvider else {
            completion(nil)
            return
        }
        
        scrollPercentProvider.getScrollPercent(completion)
    }
    
    private func getConversions(_ completion: @escaping ([String]) -> ()) {
        guard let conversionsProvider = conversionsProvider else {
            completion([])
            return
        }
        
        conversionsProvider.getConversions(completion)
    }
}
