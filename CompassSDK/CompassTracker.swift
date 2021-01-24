//
//  CompassTracker.swift
//  CompassSDK
//
//  Created by  on 14/01/2021.
//

import Foundation

public struct CompassUser: Codable {
    let userId: String
    let userType: String
    
    public init(userId: String, userType: String) {
        self.userId = userId
        self.userType = userType
    }
}

public struct CompassConversionEvent: Codable {
    let name: String
    let params: [String: String]?
    
    public init(name: String, params: [String: String]? = nil) {
        self.name = name
        self.params = params
    }
}

public protocol CompassTracking: class {
    func startPageView(pageName: String)
    func stopTracking()
    func identify(user: CompassUser)
    func track(conversion: CompassConversionEvent)
}

public class CompassTracker {
    public static let shared = CompassTracker()
    
    private let bundle: Bundle
    private let storage: CompassStorage
    
    private lazy var operationQueue: OperationQueue = {
        let queue = OperationQueue()
        queue.qualityOfService = .utility
        queue.maxConcurrentOperationCount = 1
        queue.name = "com.compass.sdk.operation.queue"
        return queue
    }()
    
    private lazy var accountId: String? = {
        bundle.compassAccountId
    }()
    
    private lazy var endpoint: String? = {
        bundle.compassEndpoint
    }()
    
    private init(bundle: Bundle = .main, storage: CompassStorage = PListCompassStorage()) {
        self.bundle = bundle
        self.storage = storage
        storage.addVisit()
        trackInfo.accountId = accountId
        trackInfo.fisrtVisitDate = storage.firstVisit
        trackInfo.currentVisitDate = Date()
        trackInfo.compassVersion = bundle.compassVersion
    }
    
    private var deadline: Double {
        switch trackInfo.tik {
        case 0..<2: return 5
        case 2: return 10
        case 3..<20: return 15
        default: return 20
        }
    }
    
    private var finishObserver: NSKeyValueObservation?
    
    private var trackInfo = TrackInfo()
}

extension CompassTracker: CompassTracking {
    public func identify(user: CompassUser) {
        self.trackInfo.user = user
    }
    
    public func startPageView(pageName: String) {
        trackInfo.pagesViewed += 1
        trackInfo.startPageDate = Date()
        restart(pageName: pageName)
        doTik()
    }
    
    public func stopTracking() {
        restart(pageName: nil)
    }
    
    public func track(conversion: CompassConversionEvent) {
        trackInfo.conversions.append(conversion)
    }
}

private extension CompassTracker {
    var hasCorrectSetUp: Bool {
        accountId != nil && endpoint != nil
    }
    
    func doTik() {
        guard trackInfo.pageUrl != nil else {return}
        let dispatchDate = Date(timeIntervalSinceNow: deadline)
        trackInfo.currentDate = dispatchDate
        let operation = TikOperation(trackInfo: trackInfo, dispatchDate: dispatchDate)
        observeFinish(for: operation)
        operationQueue.addOperation(operation)
        trackInfo.tik = trackInfo.tik + 1
    }
    
    func observeFinish(for operation: Operation) {
        finishObserver = operation.observe(\Operation.isFinished, options: .new) { (operation, change) in
            guard !operation.isCancelled, operation.isFinished else {return}
            self.doTik()
        }
    }
    
    func restart(pageName: String?) {
        trackInfo.conversions = [CompassConversionEvent]()
        finishObserver = nil
        operationQueue.cancelAllOperations()
        trackInfo.tik = 0
        trackInfo.pageUrl = pageName
    }
}
