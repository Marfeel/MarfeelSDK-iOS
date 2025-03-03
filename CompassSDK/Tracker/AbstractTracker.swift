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
    private let observerLock = NSLock()

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

        observerLock.lock()
        defer { observerLock.unlock() }
        finishObserver[opId] = operation.observe(\Operation.isFinished, options: .new) { [weak self] (operation, change) in
            guard !operation.isCancelled, operation.isFinished else { return }
           
            self?.invalidateObserver(for: opId)
            cb?()
        }
    }
    
    private func invalidateObserver(for opId: Int) {
        observerLock.lock()
        defer { observerLock.unlock() }
        finishObserver[opId]?.invalidate()
        finishObserver.removeValue(forKey: opId)
    }
    
    internal func stopObserving(for operation: Operation) {
        invalidateObserver(for: getOperationId(for: operation))
    }
    
    internal func stopObserving() {
        observerLock.lock()
        defer { observerLock.unlock() }
        finishObserver.values.forEach { $0.invalidate() }
        finishObserver.removeAll()
    }
}
