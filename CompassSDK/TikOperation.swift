//
//  TikOperation.swift
//  CompassSDK
//
//  Created by  on 17/01/2021.
//

import Foundation

class TikOperation: Operation {
    private let trackInfo: TrackInfo
    private let dispatchDate: Date
    private let tikUseCase: SendTikCuseCase
    
    init(trackInfo: TrackInfo, dispatchDate: Date, tikUseCase: SendTikCuseCase = SendTik()) {
        self.trackInfo = trackInfo
        self.dispatchDate = dispatchDate
        self.tikUseCase = tikUseCase
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
        guard !isCancelled, let finalParams = try? JSONEncoder().encode(trackInfo) else {return}
        runing = true
        timer = Timer(fire: dispatchDate, interval: 0, repeats: false, block: { [weak self] (timer) in
            self?.timer?.invalidate()
            self?.task = self?.tikUseCase.tik(data: finalParams)
            self?.runing = false
        })
        RunLoop.current.add(timer!, forMode: .common)
        RunLoop.current.run()
    }
    
    override func cancel() {
        timer?.invalidate()
        task?.cancel()
        runing = false
    }
}
