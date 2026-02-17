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
    private let stateLock = NSLock()

    private let tikOperationFactory: TikOperationFactory
    private let compassTracker: CompassTracker
    private var rfv: Rfv?

    init(tikOperationFactory: TikOperationFactory = TickOperationProvider(), compassTracker: CompassTracker = CompassTracker.shared) {
        self.tikOperationFactory = tikOperationFactory
        self.compassTracker = compassTracker
        
        super.init(queueName: "com.compass.sdk.multimedia.operation.queue")
    }
}

extension CompassTrackerMultimedia: MultimediaTracking {
    public func initializeItem(id: String, provider: String, providerId: String, type: Type, metadata: MultimediaMetadata) {
        stateLock.lock()
        items[id] = MultimediaItem(id: id, provider: provider, providerId: providerId, type: type, metadata: metadata)
        stateLock.unlock()
        doTick(id)
    }
    
    public func registerEvent(id: String, event: Event, eventTime: Int) {
        stateLock.lock()
        guard var item = items[id] else {
            stateLock.unlock()
            print(
                String(format: Errors.ITEM_NOT_INITIALIZED.rawValue, arguments: [id])
            )

            return
        }

        item.addEvent(event: event, eventTime: eventTime)
        items[id] = item
        stateLock.unlock()

        doTick(id)
    }
}

extension CompassTrackerMultimedia {
    func reset() {
        stateLock.lock()
        items.removeAll()
        tiksInProgress.removeAll()
        stateLock.unlock()
    }
}

private extension CompassTrackerMultimedia {
    func doTick(_ id: String) {
        let dispatchDate = Date(timeIntervalSinceNow: 5)

        compassTracker.getCommonTrackingData{ [weak self] (trackInfo) in
            guard let self = self else { return }

            self.stateLock.lock()
            self.tiksInProgress[id] = self.tiksInProgress[id] ?? (0, false)

            guard let tikEntry = self.tiksInProgress[id], !tikEntry.scheduled else {
                self.stateLock.unlock()
                return
            }

            guard let item = self.items[id] else {
                self.stateLock.unlock()
                return
            }

            let tik = tikEntry.tik
            self.tiksInProgress[id] = (tik, true)
            self.stateLock.unlock()

            let operation = self.tikOperationFactory.buildOperation(
                dataBuilder: { [weak self] (completion) in
                    self?.getCachedRfv { rfv in
                        let finalTrackInfo = trackInfo

                        completion(MultimediaTrackInfo(
                            trackInfo: finalTrackInfo,
                            rfv: rfv,
                            item: item,
                            tik: tik
                        ))
                    }
                },
                dispatchDate: dispatchDate,
                path: TIK_PATH,
                contentType: ContentType.JSON
            )
            self.observeFinish(for: operation) { [weak self] in
                guard let self = self else { return }
                self.stateLock.lock()
                defer { self.stateLock.unlock() }
                guard self.tiksInProgress[id] != nil else {
                    return
                }
                self.tiksInProgress[id] = (tik + 1, false)
            }
            self.operationQueue.addOperation(operation)
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
