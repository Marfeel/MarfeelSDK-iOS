//
//  CompassTracker.swift
//  CompassSDK
//
//  Created by  on 14/01/2021.
//

import Foundation
import UIKit

private let TIK_PATH = "ingest.php"

public enum UserType {
    case custom(Int)
    case unknown, anonymous, logged, paid
}

extension UserType: RawRepresentable, Codable {
    public typealias RawValue = Int

    public init?(rawValue: Int) {
        switch rawValue {
            case 0:
                self = .unknown
            case 1:
                self = .anonymous
            case 2:
                self = .logged
            case 3:
                self = .paid
            default:
                self = .custom(rawValue)
        }
    }
    
    public var rawValue: Int {
        switch self {
            case .unknown:
              return 0
            case .anonymous:
              return 1
            case .logged:
              return 2
            case .paid:
              return 3
            case .custom(let customValue):
              return customValue
        }
    }
}

public protocol CompassTracking: AnyObject {
    @available(*, deprecated, renamed: "trackNewPage")
    func startPageView(url: URL)
    @available(*, deprecated, renamed: "trackNewPage")
    func startPageView(url: URL, scrollView: UIScrollView?)
    func trackNewPage(url: URL)
    func trackNewPage(url: URL, scrollView: UIScrollView?)
    func stopTracking()
    func getRFV(_ completion: @escaping (Rfv?) -> ())
    @available(*, deprecated, renamed: "setSiteUserId")
    func setUserId(_ userId: String?)
    func setSiteUserId(_ userId: String?)
    func setUserType(_ userType: UserType?)
    @available(*, deprecated, renamed: "trackConversion")
    func track(conversion: String)
    func trackConversion(conversion: String)
}

public class CompassTracker: Tracker {
    public static let shared: CompassTracker = CompassTracker()

    private let bundle: Bundle
    private let storage: CompassStorage
    private let tikOperationFactory: TikOperationFactory
    private let getRFV: GetRFVUseCase
//    private lazy var operationQueue: OperationQueue = {
//        let queue = OperationQueue()
//        queue.qualityOfService = .utility
//        queue.maxConcurrentOperationCount = 1
//        queue.name = "com.compass.sdk.ingest.operation.queue"
//        return queue
//    }()

    private lazy var accountId: Int? = {
        bundle.compassAccountId
    }()

    init(bundle: Bundle = .main, storage: CompassStorage = PListCompassStorage(), tikOperationFactory: TikOperationFactory = TickOperationProvider(), getRFV: GetRFVUseCase = GetRFV()) {
        self.bundle = bundle
        self.storage = storage
        self.tikOperationFactory = tikOperationFactory
        self.getRFV = getRFV
        storage.addVisit()

        super.init(queueName: "com.compass.sdk.ingest.operation.queue")

        trackInfo.firstVisitDate = storage.firstVisit
        trackInfo.currentVisitDate = Date()
        trackInfo.compassVersion = bundle.compassVersion
        trackInfo.userId = storage.userId
        trackInfo.sessionId = storage.sessionId
        
        trackInfo.accountId = accountId
    }

    private var deadline: Double {
        switch trackInfo.tik {
        case 0..<2: return 5
        case 2: return 10
        case 3..<20: return 15
        default: return 20
        }
    }

//    private var finishObserver: NSKeyValueObservation?

    internal var trackInfo = IngestTrackInfo()

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
                completion((percent * 100).rounded())
            }
        }
    }
}

extension CompassTracker: CompassTracking {
    @available(*, deprecated, renamed: "setSiteUserId")
    public func setUserId(_ userId: String?) {
        setSiteUserId(userId)
    }

    public func setSiteUserId(_ userId: String?) {
        trackInfo.siteUserId = userId
    }

    public func getRFV(_ completion: @escaping (Rfv?) -> ()) {
        guard let userId = trackInfo.userId, let accountId = accountId else {
            completion(nil)
            return
        }
        getRFV.fetch(userId: userId, account: accountId) { rfv, _ in
            completion(rfv)
        }
    }

    public func setUserType(_ userType: UserType?) {
        trackInfo.userType = userType
    }

    @available(*, deprecated, renamed: "trackNewPage")
    public func startPageView(url: URL, scrollView: UIScrollView?) {
        trackNewPage(url: url, scrollView: scrollView)
    }

    @available(*, deprecated, renamed: "trackNewPage")
    public func startPageView(url: URL) {
        trackNewPage(url: url)
    }

    public func trackNewPage(url: URL, scrollView: UIScrollView?) {
        self.scrollView = scrollView
        self.trackNewPage(url: url)
    }

    public func trackNewPage(url: URL) {
        restart(pageName: url.absoluteString)
        doTik()
    }

    public func stopTracking() {
        restart(pageName: nil)
        scrollView = nil
    }

    @available(*, deprecated, renamed: "trackConversion")
    public func track(conversion: String) {
        trackConversion(conversion: conversion)
    }

    public func trackConversion(conversion: String) {
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
    func doTik() {
        guard trackInfo.pageUrl != nil else {return}
        let dispatchDate = Date(timeIntervalSinceNow: deadline)
        trackInfo.currentDate = dispatchDate
        let operation = tikOperationFactory.buildOperation(
            dataBuilder: { [self] (completion) in
                getScrollPercent { (scrollPercent) in
                    getConversions { (conversions) in
                        var finalTrackInfo = self.trackInfo
                     
                        finalTrackInfo.scrollPercent = scrollPercent
                        finalTrackInfo.conversions = conversions.isEmpty ? nil : conversions
                        
                        completion(finalTrackInfo)
                   }
                }
                
                return nil
            },
            dispatchDate: dispatchDate,
            path: TIK_PATH,
            contentType: ContentType.FORM
        )
        observeFinish(for: operation) { [self] in
            trackInfo.tik = trackInfo.tik + 1
            self.doTik()
        }
        operationQueue.addOperation(operation)
    }

//    func observeFinish(for operation: Operation) {
//        finishObserver = operation.observe(\Operation.isFinished, options: .new) { [self] (operation, change) in
//            guard !operation.isCancelled, operation.isFinished else {return}
//            trackInfo.tik = trackInfo.tik + 1
//            self.doTik()
//        }
//    }
//
    func restart(pageName: String?) {
        stopObserving()
        operationQueue.cancelAllOperations()
        trackInfo.pageUrl = pageName
    }
}
