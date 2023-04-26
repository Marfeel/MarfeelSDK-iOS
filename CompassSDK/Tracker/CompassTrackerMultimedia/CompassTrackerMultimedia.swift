

public protocol CompassTrackingMultimedia: AnyObject {
    func initializeItem(id: String, provider: String, providerId: String, type: Type, metadata: MultimediaMetadata)
    func registerEvent(id: String, event: Event, eventTime: Int)
}
