//
//  CompassTracker.swift
//  CompassSDK
//
//  Created by  on 14/01/2021.
//

import Foundation
import UIKit

public enum UserType: String, Codable {
    case logged, paid
}

public protocol CompassTracking: class {
    func startPageView(url: URL)
    func startPageView(url: URL, scrollView: UIScrollView?)
    func stopTracking()
    func setUserId(_ userId: String?)
    func setUserType(_ userType: UserType?)
    func track(conversion: String)
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
        trackInfo.sessionId = storage.sessionId
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
    
    private var newConversions = [String]()
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
    public func setUserId(_ userId: String?) {
        trackInfo.userId = userId
    }
    
    public func setUserType(_ userType: UserType?) {
        trackInfo.userType = userType
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
    
    public func track(conversion: String) {
        newConversions.append(conversion)
    }
}

extension CompassTracker: ConversionsProvider {
    func getConversions(_ completion: @escaping ([String]) -> ()) {
        completion(newConversions)
        newConversions = [String]()
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
        let operation = TikOperation(trackInfo: trackInfo, dispatchDate: dispatchDate, scrollPercentProvider: self, conversionsProvider: self)
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
        finishObserver = nil
        operationQueue.cancelAllOperations()
        trackInfo.pageUrl = pageName
    }
}
