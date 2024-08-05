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

class TikOperation: Operation {
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
    
    private var timer: Timer?
    
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
    
        self.timer = Timer(fire: self.dispatchDate, interval: 0, repeats: false, block: { [weak self] (timer) in
            guard let self = self else { return }
            
            let track = { [weak self] (data: Encodable?) in
                guard let self = self else { return }
                
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
        })
        
        RunLoop.main.add(self.timer!, forMode: .common)
    }
    
    override func cancel() {
        timer?.invalidate()
        finish()
    }
    
    private func finish() {
        running = false
    }
}
