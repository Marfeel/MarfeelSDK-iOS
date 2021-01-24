//
//  TikOperation.swift
//  CompassSDK
//
//  Created by  on 17/01/2021.
//

import Foundation

protocol ScrollPercentProvider: class {
    func getScrollPercent(_ completion: @escaping (Float?) -> ())
}

class TikOperation: Operation {
    private let trackInfo: TrackInfo
    private let dispatchDate: Date
    private let tikUseCase: SendTikCuseCase
    private weak var scrollPercentProvider: ScrollPercentProvider?
    
    init(trackInfo: TrackInfo, dispatchDate: Date, tikUseCase: SendTikCuseCase = SendTik(), scrollPercentProvider: ScrollPercentProvider?) {
        self.trackInfo = trackInfo
        self.dispatchDate = dispatchDate
        self.tikUseCase = tikUseCase
        self.scrollPercentProvider = scrollPercentProvider
    }
    
    private var timer: Timer?
    private var task: URLSessionDataTask?
    
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
                var finalTrackInfo = self?.trackInfo
                finalTrackInfo?.scrollPercent = scrollPercent
                let data = finalTrackInfo?.data
                if let data = data {
                    self?.task = self?.tikUseCase.tik(data: data)
                }
                self?.timer?.invalidate()
                self?.runing = false
            }
        })
        
        RunLoop.current.add(self.timer!, forMode: .common)
        RunLoop.current.run()
    }
    
    override func cancel() {
        timer?.invalidate()
        task?.cancel()
        runing = false
    }
    
    private func getScrollPercent(_ completion: @escaping (Float?) -> ()) {
        guard let scrollPercentProvider = scrollPercentProvider else {
            completion(nil)
            return
        }
        
        scrollPercentProvider.getScrollPercent(completion)
    }
}
