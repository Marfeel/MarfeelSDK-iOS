//
//  AbstractTracker.swift
//  CompassSDK
//
//  Created by Marc García Lopez on 01/05/2023.
//

import Foundation

public class Tracker {
    private let queueName: String
    private var finishObserver: [Int: NSKeyValueObservation] = [:]

    init(queueName: String) {
        self.queueName = queueName
    }
    
    internal lazy var operationQueue: OperationQueue = {
        let queue = OperationQueue()
        
        queue.qualityOfService = .utility
        queue.maxConcurrentOperationCount = 1
        queue.name = self.queueName
        
        return queue
    }()
    
    private func getOperationId(for operation: Operation) -> Int {
        return ObjectIdentifier(operation).hashValue
    }

    internal func observeFinish(for operation: Operation, cb: (() -> Void)?) {
        let opId = getOperationId(for: operation)

        finishObserver[opId] = operation.observe(\Operation.isFinished, options: .new) { [weak self] (operation, change) in
            guard !operation.isCancelled, operation.isFinished else {return}
            
            self?.finishObserver.removeValue(forKey: opId)
            cb?()
        }
    }
    
    internal func stopObserving(for operation: Operation) {
        finishObserver.removeValue(forKey: getOperationId(for: operation))
    }
    
    internal func stopObserving() {
        finishObserver.removeAll()
    }
}
