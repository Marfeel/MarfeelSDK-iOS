//
//  CompassTrackerMultimedia.swift
//  CompassSDK
//
//  Created by Marc García Lopez on 26/04/2023.
//

import Foundation

private enum Errors: String {
    case ITEM_NOT_INITIALIZED = "Multimedia item %@ has not been initialized. MultimediaTracker.initializeItem must be called before tracking the item."
}

private let TIK_PATH = "multimedia.php"

typealias TiksDictionary = [String:(tik: Int, scheduled: Bool)]

public protocol MultimediaTracking: AnyObject {
    func initializeItem(id: String, provider: String, providerId: String, type: Type, metadata: MultimediaMetadata)
    func registerEvent(id: String, event: Event, eventTime: Int)
}

public class CompassTrackerMultimedia: Tracker {
    public static let shared = CompassTrackerMultimedia()
    private var items = [String: MultimediaItem]()
    private var tiksInProgress: TiksDictionary = [:]
    
    private let bundle: Bundle
    private let tikOperationFactory: TikOperationFactory
    private let compassTracker: CompassTracker
    private var rfv: Rfv?

    init(bundle: Bundle = .main, tikOperationFactory: TikOperationFactory = TickOperationProvider(), compassTracker: CompassTracker = CompassTracker.shared) {
        self.bundle = bundle
        self.tikOperationFactory = tikOperationFactory
        self.compassTracker = compassTracker
        
        super.init(queueName: "com.compass.sdk.multimedia.operation.queue")
    }
}

extension CompassTrackerMultimedia: MultimediaTracking {
    public func initializeItem(id: String, provider: String, providerId: String, type: Type, metadata: MultimediaMetadata) {
        items[id] = MultimediaItem(id: id, provider: provider, providerId: providerId, type: type, metadata: metadata)
        doTick(id)
    }
    
    public func registerEvent(id: String, event: Event, eventTime: Int) {
        guard var item = items[id] else {
            print(
                String(format: Errors.ITEM_NOT_INITIALIZED.rawValue, arguments: [id])
            )
            
            return
        }
        
        item.addEvent(event: event, eventTime: eventTime)
        items[id] = item;
        
        doTick(id)
    }
}

extension CompassTrackerMultimedia {
    func reset() {
        items.removeAll()
        tiksInProgress.removeAll()
    }
}

private extension CompassTrackerMultimedia {
    func doTick(_ id: String) {
        let dispatchDate = Date(timeIntervalSinceNow: 5)
        
        compassTracker.getCommonTrackingData{ [self] (trackInfo) in
            tiksInProgress[id] = tiksInProgress[id] ?? (0, false)
            
            guard !tiksInProgress[id]!.scheduled else {
                return
            }
            let tik = tiksInProgress[id]!.tik

            guard let item = items[id] else {
                return
            }
            
            tiksInProgress[id]!.scheduled = true
            let operation = tikOperationFactory.buildOperation(
                dataBuilder: { [self] (completion) in
                    getCachedRfv { rfv in
                        var finalTrackInfo = trackInfo
                                            
                        
                        finalTrackInfo.currentDate = Date()
                        completion(MultimediaTrackInfo(
                            trackInfo: finalTrackInfo,
                            rfv: rfv,
                            item: item,
                            tik: tik
                        ))
                    }

                    return nil
                },
                dispatchDate: dispatchDate,
                path: TIK_PATH,
                contentType: ContentType.JSON
            )
            observeFinish(for: operation) { [weak self] in
                guard self?.tiksInProgress[id] != nil else {
                    return
                }
                self?.tiksInProgress[id] = (tik + 1, false)
            }
            operationQueue.addOperation(operation)
        }
    }
    
    func getCachedRfv(_ completion: ((Rfv?) -> ())?) {
        if let rfv = rfv {
            completion?(rfv)
        } else {
            compassTracker.getRFV {
                rfv in
                
                self.rfv = rfv
                completion?(rfv)
            }
        }
    }
}
