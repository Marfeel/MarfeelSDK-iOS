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
typealias DataBuilderCompletion = (_ res: Encodable) -> Void
typealias DataBuilder = (_ completion: @escaping DataBuilderCompletion) -> Encodable?

class TikOperation: Operation, @unchecked Sendable {
    private let dataBuilder: DataBuilder
    private let dispatchDate: Date
    private let tikUseCase: SendTikCuseCase
    private let path: String
    private let contentType: ContentType
    
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
    
    private var timer: DispatchSourceTimer?
    
    private var running: Bool = false {
        didSet {
            willChangeValue(forKey: "isFinished")
            willChangeValue(forKey: "isExecuting")
            didChangeValue(forKey: "isFinished")
            didChangeValue(forKey: "isExecuting")
        }
    }
    
    override var isAsynchronous: Bool { true }
    
    override var isFinished: Bool { !running }
    
    override var isExecuting: Bool { running }
    
    override func start() {
        guard !isCancelled else { return }
        running = true
        
        let timer = DispatchSource.makeTimerSource(queue: DispatchQueue.global(qos: .utility))
        let timeInterval = dispatchDate.timeIntervalSinceNow
        let deadline = DispatchTime.now() + timeInterval
        
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
            
            let data = self.dataBuilder(track)
            
            if data != nil {
                track(data)
            }
        }

        self.timer = timer
        timer.resume()
    }
    
    override func cancel() {
        finish()
        super.cancel()
    }
    
    private func finish() {
        timer?.cancel()
        timer = nil
        running = false
    }
}
