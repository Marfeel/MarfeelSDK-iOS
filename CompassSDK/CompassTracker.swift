//
//  CompassTracker.swift
//  CompassSDK
//
//  Created by  on 14/01/2021.
//

import Foundation

protocol CompassTracking: class {
    func startPageView(pageName: String)
}

class TikOperation: Operation {
    private let params: [String: CustomStringConvertible]
    private let dispatchDate: Date
    private let tikUseCase: SendTikCuseCase
    
    init(params: [String: CustomStringConvertible], dispatchDate: Date, tikUseCase: SendTikCuseCase = SendTik()) {
        self.params = params
        self.dispatchDate = dispatchDate
        self.tikUseCase = tikUseCase
    }
    
    private var timer: Timer?
    private var task: URLSessionDataTask?
    
    override func main() {
        guard !isCancelled else {return}
        var finalParams = params.mapValues({String(describing: $0)})
        finalParams["date"] = String(describing: dispatchDate)
        timer = Timer.init(fire: dispatchDate, interval: 0, repeats: false, block: { [weak self] (timer) in
            self?.task = self?.tikUseCase.tik(params: finalParams)
        })
        timer?.fire()
    }
    
    override func cancel() {
        timer?.invalidate()
        task?.cancel()
    }
}

class CompassTracker: CompassTracking {
    private let sendTik: SendTikCuseCase
    
    private lazy var operationQueue: OperationQueue = {
        let queue = OperationQueue()
        queue.qualityOfService = .utility
        queue.maxConcurrentOperationCount = 1
        queue.name = "com.compass.sdk.operation.queue"
        return queue
    }()
    
    private lazy var queue = DispatchQueue(label: "com.compass.sdk.tik.queue", qos: .utility)
    
    init(sendTik: SendTikCuseCase = SendTik()) {
        self.sendTik = sendTik
    }
    
    private var deadline: Double = 0
    private var tik = 0
    
    func startPageView(pageName: String) {
        restart()
        doTik(pageName: pageName)
    }
    
    private func doTik(pageName: String) {
        let params: [String: CustomStringConvertible] = ["tik": tik, "url": pageName]
        let dispatchDate = Date(timeIntervalSinceNow: deadline)
        operationQueue.addOperation(TikOperation(params: params, dispatchDate: dispatchDate))
        queue.asyncAfter(deadline: .now() + deadline) {
            self.doTik(pageName: pageName)
        }
        tik = tik + 1
        deadline = Double(tik) * 2.0
    }
}

private extension CompassTracker {
    
    func restart() {
        operationQueue.cancelAllOperations()
        deadline = 0
        tik = 0
    }
}
