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
    private var _items = [String: MultimediaItem]()
    private var _tiksInProgress: TiksDictionary = [:]
    private let stateQueue = DispatchQueue(label: "com.marfeel.multimedia.state", attributes: .concurrent)

    private var items: [String: MultimediaItem] {
        get { stateQueue.sync { _items } }
        set { stateQueue.async(flags: .barrier) { [weak self] in self?._items = newValue } }
    }

    private var tiksInProgress: TiksDictionary {
        get { stateQueue.sync { _tiksInProgress } }
        set { stateQueue.async(flags: .barrier) { [weak self] in self?._tiksInProgress = newValue } }
    }

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
        items[id] = item

        doTick(id)
    }
}

extension CompassTrackerMultimedia {
    func reset() {
        stateQueue.async(flags: .barrier) { [weak self] in
            self?._items.removeAll()
            self?._tiksInProgress.removeAll()
        }
    }
}

private extension CompassTrackerMultimedia {
    func doTick(_ id: String) {
        let dispatchDate = Date(timeIntervalSinceNow: 5)

        compassTracker.getCommonTrackingData{ [weak self] (trackInfo) in
            guard let self = self else { return }

            var tik: Int = 0
            var item: MultimediaItem?

            self.stateQueue.sync(flags: .barrier) {
                self._tiksInProgress[id] = self._tiksInProgress[id] ?? (0, false)

                guard let tikEntry = self._tiksInProgress[id], !tikEntry.scheduled else {
                    return
                }

                item = self._items[id]
                guard item != nil else { return }

                tik = tikEntry.tik
                self._tiksInProgress[id] = (tik, true)
            }

            guard let item = item else { return }

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
                self.stateQueue.async(flags: .barrier) {
                    guard self._tiksInProgress[id] != nil else {
                        return
                    }
                    self._tiksInProgress[id] = (tik + 1, false)
                }
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
