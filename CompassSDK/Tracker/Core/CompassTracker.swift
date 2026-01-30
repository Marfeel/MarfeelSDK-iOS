//
//  CompassTracker.swift
//  CompassSDK
//
//  Created by  on 14/01/2021.
//

import Foundation
import UIKit

private let TIK_PATH = "ingest.php"
private let IOS_TECH = 3
private let IOS_PRESSREADER_TECH = 12
private let IOS_ALLOWED_TECHS = [IOS_TECH, IOS_PRESSREADER_TECH]

enum CompassErrors: Error {
    case invalidArgument(String)
}

public enum UserType {
    case custom(Int)
    case unknown, anonymous, logged, paid
}

public enum ConversionScope {
    case user
    case session
    case page
}

public struct ConversionOptions {
    public let initiator: String?
    public let id: String?
    public let value: String?
    public let meta: [String: String]?
    public let scope: ConversionScope?

    public init(initiator: String? = nil, id: String? = nil, value: String? = nil, meta: [String: String]? = nil, scope: ConversionScope? = nil) {
        self.initiator = initiator
        self.id = id
        self.value = value
        self.meta = meta
        self.scope = scope
    }
}

struct Conversion {
    let conversion: String
    let initiator: String?
    let id: String?
    let value: String?
    let meta: [[String]]?
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
    func trackNewPage(url: URL, rs: String?)
    func trackNewPage(url: URL, scrollView: UIScrollView?, rs: String?)
    func trackScreen(_ name: String, rs: String?)
    func trackScreen(name: String, scrollView: UIScrollView?, rs: String?)
    func stopTracking()
    func getRFV(_ completion: @escaping (Rfv?) -> ())
    @available(*, deprecated, renamed: "setSiteUserId")
    func setUserId(_ userId: String?)
    func setSiteUserId(_ userId: String?)
    func setUserType(_ userType: UserType?)
    @available(*, deprecated, renamed: "trackConversion")
    func track(conversion: String)
    func trackConversion(conversion: String)
    func trackConversion(conversion: String, options: ConversionOptions)
    func setPageVar(name: String, value: String)
    func setPageMetric(name: String, value: Int)
    func setSessionVar(name: String, value: String)
    func setUserVar(name: String, value: String)
    func addUserSegment(_ name: String)
    func setUserSegments(_ segments: [String])
    func removeUserSegment(_ name: String)
    func clearUserSegments()
    func setConsent(_ hasConsent: Bool)
    func getUserId() -> String
    func setLandingPage(_ landingPage: String?)
    func setLandingPage(_ landingPage: URL)
}

public class CompassTracker: Tracker {
    public static let shared: CompassTracker = CompassTracker()

    private let config: TrackingConfig
    private let storage: CompassStorage
    private let tikOperationFactory: TikOperationFactory
    private let getRFV: GetRFVUseCase
    private let lifecyleNotifier: AppLifecycleNotifierUseCase
    
    private var accountId: Int? {
        get {
            config.accountId
        }
    }
    
    public static func initialize(accountId: Int, pageTechnology: Int? = nil, endpoint: String? = nil) {
        let tracker = CompassTracker.shared
        
        tracker.config.override(accountId: accountId, pageTechnology: pageTechnology, endpoint: endpoint)
        tracker.setDataFromConfig()
    }
    
    private func setDataFromConfig() {
        trackInfo.accountId = self.accountId
        trackInfo.pageType = self.pageTechnology
        trackInfo.compassVersion = self.config.version
    }
    
    private var pageTechnology: Int? {
        get  {
            let tech = config.pageTechnology ?? IOS_TECH
            
            guard tech > 100 || IOS_ALLOWED_TECHS.contains(tech) else {
                print(CompassErrors.invalidArgument("page technology value should be greater than 100"))
                
                return IOS_TECH
            }
            
            return tech
        }
    }

    init(config: TrackingConfig = TrackingConfig.shared, storage: CompassStorage = PListCompassStorage(), tikOperationFactory: TikOperationFactory = TickOperationProvider(), getRFV: GetRFVUseCase = GetRFV(), lifecycleNotifier: AppLifecycleNotifierUseCase = AppLifecycleNotifier()) {
        self.config = config
        self.storage = storage
        self.tikOperationFactory = tikOperationFactory
        self.getRFV = getRFV
        self.lifecyleNotifier = lifecycleNotifier
        storage.addVisit()

        super.init(queueName: "com.compass.sdk.ingest.operation.queue")

        trackInfo.firstVisitDate = storage.firstVisit
        trackInfo.currentVisitDate = Date()
        trackInfo.userId = storage.userId
        trackInfo.sessionId = storage.sessionId
        
        setDataFromConfig()
        configureAppLifecycleListeners()
    }

    private var deadline: Double {
        switch tick {
        case 0..<2: return 5
        case 2: return 10
        case 3..<20: return 15
        default: return 20
        }
    }
    
    private var _trackInfo = IngestTrackInfo()
    private let trackInfoQueue = DispatchQueue(label: "com.marfeel.trackinfo", attributes: .concurrent)

    private var trackInfo: IngestTrackInfo {
        get {
            return trackInfoQueue.sync { _trackInfo }
        }
        set {
            trackInfoQueue.async(flags: .barrier) { [weak self] in
                self?._trackInfo = newValue
            }
        }
    }
    
    private var tick = 0

    private var scrollView: UIScrollView?

    private var newConversions = [Conversion]()
    
    private var pageVars = [String: String]()
    
    private var pageMetrics = [String: Int]()
}

extension CompassTracker: ScrollPercentProvider {
    func getScrollPercent(_ completion: @escaping (Float?) -> ()) {
        guard let scrollView = scrollView else {
            completion(nil)
            return
        }

        DispatchQueue.main.async {
            let contentHeight = scrollView.contentSize.height
            let viewHeight = scrollView.frame.size.height
            let offset = scrollView.contentOffset.y
            let adjustedOffset = max(0, offset + scrollView.contentInset.top)
            let maxScroll = max(0, contentHeight - viewHeight + scrollView.contentInset.bottom)
            
            guard maxScroll > 0 else {
                completion(100)
                return
            }
            
            let percent = min(1, adjustedOffset / maxScroll)
            DispatchQueue.global(qos: .utility).async {
                completion((Float(percent) * 100).rounded())
            }
        }
    }
}

extension CompassTracker: CompassTracking {
    public func setLandingPage(_ landingPage: String?) {
        storage.setLandingPage(landingPage)
    }
    
    public func setLandingPage(_ landingPage: URL) {
        storage.setLandingPage(landingPage.absoluteString)
    }
    
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

    public func trackNewPage(url: URL, scrollView: UIScrollView?, rs: String? = nil) {
        self.scrollView = scrollView
        self.trackNewPage(url: url, rs: rs)
    }

    public func trackNewPage(url: URL, rs: String? = nil) {
        restart(pageName: url.absoluteString, rs: rs)
        doTik()
    }
    
    public func trackScreen(_ name: String, rs: String? = nil) {
        guard let url = screenUrl(name) else {
            return
        }
        
        trackNewPage(url: url, rs: rs)
    }
    
    public func trackScreen(name: String, scrollView: UIScrollView?, rs: String? = nil) {
        guard let url = screenUrl(name) else {
            return
        }
        
        trackNewPage(url: url, scrollView: scrollView, rs: rs)
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
        newConversions.append(Conversion(conversion: conversion, initiator: nil, id: nil, value: nil, meta: nil))
    }

    public func trackConversion(conversion: String, options: ConversionOptions) {
        let conversionId = getConversionId(options: options)
        if storage.hasTrackedConversion(conversion, id: conversionId) {
            return
        }
        storage.addTrackedConversion(conversion, id: conversionId)
        let convertedMeta = convertMetaToArray(options.meta)
        newConversions.append(Conversion(
            conversion: conversion,
            initiator: options.initiator,
            id: conversionId,
            value: options.value,
            meta: convertedMeta
        ))
    }

    private func convertMetaToArray(_ meta: [String: String]?) -> [[String]]? {
        guard let meta = meta else { return nil }
        return meta.map { [$0.key, $0.value] }
    }

    private func getConversionId(options: ConversionOptions) -> String? {
        if let id = options.id {
            return id
        }

        switch options.scope {
        case .user:
            return storage.userId
        case .session:
            return trackInfo.sessionId
        case .page:
            return trackInfo.pageId
        case nil:
            return nil
        }
    }
    
    public func setPageVar(name: String, value: String) {
        pageVars[name] = value
    }
    
    public func setPageMetric(name: String, value: Int) {
        pageMetrics[name] = value
    }
    
    public func setSessionVar(name: String, value: String) {
        storage.addSessionVar(name: name, value: value)
    }
    
    public func setUserVar(name: String, value: String) {
        storage.addUserVar(name: name, value: value)
    }
    
    public func addUserSegment(_ name: String) {
        storage.addUserSegment(name)
    }
    
    public func setUserSegments(_ segments: [String]) {
        storage.addUserSegments(segments)
    }
    
    public func removeUserSegment(_ name: String) {
        storage.removeUserSegment(name)
    }
    
    public func clearUserSegments() {
        storage.clearUserSegments()
    }
    
    public func setConsent(_ hasConsent: Bool) {
        storage.setConsent(hasConsent)
    }
    
    public func getUserId() -> String {
        return storage.userId
    }
}

extension CompassTracker: ConversionsProvider {
    func getConversions(_ completion: @escaping ([Conversion]) -> ()) {
        completion(newConversions)
        newConversions = [Conversion]()
    }
}

internal extension CompassTracker {
    func getTrackingData(for conversion: Conversion? = nil, tick: Int? = 0, _ completion: @escaping (IngestTrackInfo) -> ()) {
        let trackInfoCopy = self.trackInfo

        getScrollPercent { [weak self] scrollPercent in
            guard let self = self else {
                completion(trackInfoCopy)
                return
            }

            var finalTrackInfo = trackInfoCopy

            if let scrollPercent = scrollPercent, scrollPercent > (finalTrackInfo.scrollPercent ?? 0) {
                finalTrackInfo.scrollPercent = scrollPercent
            }

            if let conversion = conversion {
                finalTrackInfo.conversions = [conversion.conversion]
                finalTrackInfo.conversionInitiator = conversion.initiator
                finalTrackInfo.conversionId = conversion.id
                finalTrackInfo.conversionValue = conversion.value
                finalTrackInfo.conversionMeta = conversion.meta
            }

            DispatchQueue.main.async { [weak self] in
                guard let self = self else {
                    completion(finalTrackInfo)
                    return
                }

                finalTrackInfo.userVars = storage.userVars
                finalTrackInfo.sessionVars = storage.sessionVars
                finalTrackInfo.pageVars = pageVars
                finalTrackInfo.pageMetrics = pageMetrics
                finalTrackInfo.userSegments = storage.userSegments
                finalTrackInfo.hasConsent = storage.hasConsent
                finalTrackInfo.landingPage = storage.landingPage
                finalTrackInfo.tik = tick!

                completion(finalTrackInfo)
            }
        }
    }
    
    func getCommonTrackingData(_ completion: @escaping (TrackInfo) -> ()) {
        getTrackingData { (ingestTrackInfo) in
            completion(ingestTrackInfo.core)
        }
    }
}

private extension CompassTracker {
    func doTik() {
        guard trackInfo.pageUrl != nil else { return }
        
        getConversions { [weak self] conversions in
            guard let self = self else { return }
            
            let dispatchDate = Date(timeIntervalSinceNow: deadline)
            
            let dispatchGroup = DispatchGroup()
            
            if conversions.isEmpty {
                dispatchGroup.enter()
                createOperation(conversion: nil, dispatchDate: dispatchDate, dispatchGroup: dispatchGroup)
            } else {
                for conversion in conversions {
                    dispatchGroup.enter()
                    createOperation(conversion: conversion, dispatchDate: dispatchDate, dispatchGroup: dispatchGroup)
                }
            }
            
            dispatchGroup.notify(queue: .main) {
                self.doTik()
            }
        }
    }
    
    private func createOperation(conversion: Conversion?, dispatchDate: Date, dispatchGroup: DispatchGroup) {
        let operation = tikOperationFactory.buildOperation(
            dataBuilder: { [self] (completion) in
                DispatchQueue.global(qos: .utility).async {
                    self.getTrackingData(for: conversion, tick: self.tick, completion)
                    self.tick += 1
                }
            },
            dispatchDate: dispatchDate,
            path: TIK_PATH,
            contentType: ContentType.FORM
        )
        
        observeFinish(for: operation) {
            dispatchGroup.leave()
        }
        operationQueue.addOperation(operation)
    }

    func restart(pageName: String?, rs: String? = nil) {
        stopObserving()
        operationQueue.operations.forEach{ $0.cancel() }
        trackInfo.pageUrl = pageName
        trackInfo.recirculationSource = rs
        pageVars.removeAll()
        pageMetrics.removeAll()
        trackInfo.sessionId = storage.sessionId
        tick = 0
        CompassTrackerMultimedia.shared.reset()
    }
    
    func screenUrl(_ screen: String) -> URL? {
        guard let encodedPath = screen.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed), let accountId = accountId else {
            return nil
        }
        
        return URL(string: "https://marfeelwhois.mrf.io/dynamic/\(accountId)/\(encodedPath)")
    }
}

private extension CompassTracker {

    private func configureAppLifecycleListeners() {
        func onAppInactive() {
            stopObserving()
        }
        
        func onAppActive(){
            doTik()
        }
        
        self.lifecyleNotifier.listen(onForeground: onAppActive, onBackground: onAppInactive)
    }
}
