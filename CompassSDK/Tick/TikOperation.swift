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
    func getConversions(_ completion: @escaping ([Conversion]) -> ())
}
typealias DataBuilderCompletion = (_ res: Encodable) -> Void
typealias DataBuilder = (_ completion: @escaping DataBuilderCompletion) -> Void

class TikOperation: Operation, @unchecked Sendable {
    private let dataBuilder: DataBuilder
    private let dispatchDate: Date
    private let tikUseCase: SendTikCuseCase
    private let path: String
    private let contentType: ContentType
    
    private var timer: DispatchSourceTimer?
    private let lock = NSRecursiveLock()

    init(
        dataBuilder: @escaping DataBuilder,
        dispatchDate: Date,
        tikUseCase: SendTikCuseCase = SendTik(),
        path: String?,
        contentType: ContentType?
    ) {
        self.dataBuilder = dataBuilder
        self.dispatchDate = dispatchDate
        self.tikUseCase = tikUseCase
        self.path = path ?? ""
        self.contentType = contentType ?? ContentType.JSON
        super.init()
    }
    
    private var _running: Bool = false
    private var running: Bool {
        get {
            lock.lock()
            defer { lock.unlock() }
            return _running
        }
        set {
            var didChange = false
            lock.lock()
            if _running != newValue {
                willChangeValue(forKey: "isFinished")
                willChangeValue(forKey: "isExecuting")
                _running = newValue
                didChange = true
            }
            lock.unlock()
            
            if didChange {
                didChangeValue(forKey: "isFinished")
                didChangeValue(forKey: "isExecuting")
            }
        }
    }

    override var isAsynchronous: Bool { true }
    override var isFinished: Bool { !running }
    override var isExecuting: Bool { running }
    
    override func start() {
        guard !isCancelled else {
            finish()
            return
        }
        
        running = true
        
        let timer = DispatchSource.makeTimerSource(queue: DispatchQueue.global(qos: .utility))
        let timeInterval = dispatchDate.timeIntervalSinceNow
        let deadline = DispatchTime.now() + max(timeInterval, 0)

        timer.schedule(deadline: deadline)
        
        timer.setEventHandler { [weak self] in
            guard let self = self, !self.isCancelled else {
                self?.finish()
                return
            }
            
            let track = { [weak self] (data: Encodable?) in
                guard let self = self, !self.isCancelled else {
                    self?.finish()
                    return
                }
                
                let params = data?.params
                
                if let params = params {
                    self.tikUseCase.tik(path: self.path, type: self.contentType, params: params)
                }
                self.finish()
            }
            
           self.dataBuilder(track)
        }

        self.timer = timer
        timer.resume()
    }
    
    override func cancel() {
        super.cancel()
        finish()
    }
    
    private func finish() {
        lock.lock()
        defer { lock.unlock() }

        guard running else { return }
        
        timer?.setEventHandler {} 
        timer?.cancel()
        timer = nil
        running = false
    }
}
