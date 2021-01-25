//
//  CompassTracker.swift
//  CompassSDK
//
//  Created by  on 14/01/2021.
//

import Foundation
import UIKit

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
    func startPageView(url: URL)
    func startPageView(url: URL, scrollView: UIScrollView?)
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
    
    private let compassVersion = "2.0"
    
    init(bundle: Bundle = .main, storage: CompassStorage = PListCompassStorage()) {
        self.bundle = bundle
        self.storage = storage
        storage.addVisit()
        trackInfo.accountId = accountId
        trackInfo.fisrtVisitDate = storage.firstVisit
        trackInfo.currentVisitDate = Date()
        trackInfo.compassVersion = compassVersion
        trackInfo.siteUserId = storage.suid
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
    
    private var scrollView: UIScrollView?
}

extension CompassTracker: ScrollPercentProvider {
    func getScrollPercent(_ completion: @escaping (Float?) -> ()) {
        guard  let scrollView = scrollView else {
            completion(nil)
            return
        }
        
        DispatchQueue.main.async {
            let offset = scrollView.contentOffset.y
            let scrolledDistance = offset + scrollView.contentInset.top
            let percent = max(0, Float(min(1, scrolledDistance / scrollView.contentSize.height)))
            DispatchQueue.global(qos: .utility).async {
                completion(percent)
            }
        }
    }
}

extension CompassTracker: CompassTracking {
    public func identify(user: CompassUser) {
        self.trackInfo.user = user
    }
    
    public func startPageView(url: URL, scrollView: UIScrollView?) {
        self.scrollView = scrollView
        startPageView(url: url)
    }
    
    public func startPageView(url: URL) {
        restart(pageName: url.absoluteString)
        doTik()
    }
    
    public func stopTracking() {
        restart(pageName: nil)
        scrollView = nil
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
        let operation = TikOperation(trackInfo: trackInfo, dispatchDate: dispatchDate, scrollPercentProvider: self)
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
        trackInfo.pageUrl = pageName
    }
}
