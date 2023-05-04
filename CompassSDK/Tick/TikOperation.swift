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
        
        self.timer = Timer(fire: self.dispatchDate, interval: 0, repeats: false, block: { [self] (timer) in
            let track = { [self] (data: Encodable?) in
                let params = data?.params
               
                if let params = params {
                    tikUseCase.tik(path: path, type: contentType, params: params)
                }
                timer.invalidate()
                runing = false
            }
            let data = dataBuilder(track)
            
            if data != nil {
                track(data)
            }
        })
        
        RunLoop.current.add(self.timer!, forMode: .common)
        RunLoop.current.run()
    }
    
    override func cancel() {
        timer?.invalidate()
        runing = false
    }
}
