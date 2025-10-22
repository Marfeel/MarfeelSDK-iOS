# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What This Project Is

MarfeelSDK-iOS (also called CompassSDK) is an analytics tracking SDK for iOS apps. It tracks user behavior like page views, scroll depth, video playback, and custom events.

**How it works:**
1. An app initializes the SDK with an account ID
2. When users navigate to pages, the app calls `trackNewPage(url:)`
3. The SDK periodically sends "tiks" (tracking beats) to a server with data like scroll position, time on page, custom variables, etc.

**Key concepts:**
- **Tik/Tick**: A tracking "heartbeat" - the SDK sends these periodically to report user activity
- **CompassTracker**: The main singleton that apps interact with
- **Operations**: Tracking requests are queued as async operations to handle threading safely
- **Fallback endpoint**: If the primary tracking server fails, it switches to a backup

## Swift Basics for This Codebase

- `class` = reference type, `struct` = value type
- `protocol` = interface (like Java/TypeScript interfaces)
- `@objc` = makes Swift code callable from Objective-C
- `DispatchQueue` = threading/concurrency primitive
- `UserDefaults` = simple key-value storage (like localStorage)

## Build & Test Commands

```bash
# Build via CocoaPods (primary)
pod install  # from root directory
xcodebuild -workspace CompassSDK.xcworkspace -scheme CompassSDK

# Build via Swift Package Manager
xcodebuild build -scheme MarfeelSDK-iOS

# Run tests
xcodebuild test -workspace CompassSDK.xcworkspace -scheme CompassSDK

# Run Playground test app
xcodebuild -workspace CompassSDK.xcworkspace -scheme Playground
```

## Architecture Overview

This is the MarfeelSDK-iOS (CompassSDK), an analytics tracking SDK for iOS apps. It uses a dual build system supporting both CocoaPods and SPM with no external dependencies.

### Core Components

**Entry Points:**
- `CompassTracker.shared` - Main SDK singleton, initialized via `CompassTracker.initialize(accountId:pageTechnology:endpoint:)`
- `CompassTrackerMultimedia.shared` - Separate singleton for video/media tracking
- `TrackingConfig.shared` - Configuration singleton

**Data Flow:**
```
trackNewPage/setPageVar calls
  → CompassTracker (stores state, manages lifecycle)
  → doTik() creates TikOperation
  → TikOperation (waits for dispatch deadline)
  → SendTik.tik() (HTTP POST with fallback support)
  → ApiRouter (URLSession wrapper)
  → Ingest endpoint
```

**Key Directories:**
- `Tracker/Core/` - Main entry point and configuration
- `Tracker/Multimedia/` - Video/media tracking
- `Tick/` - Network operations (TikOperation, SendTik)
- `Storage/` - Persistence layer (PListStorage using UserDefaults)
- `Communications/` - API layer (ApiRouter)
- `Lifecycle/` - App state monitoring

### Threading Model

- Public API is main-safe (can call from any thread)
- `trackInfo` uses `DispatchQueue.concurrent` with `.barrier` flags for thread-safe updates
- Single-threaded operation queue for sequential tracking operations
- Background tasks via `UIBackgroundTaskIdentifier` for app backgrounding

### Design Patterns

- **Protocol-based design** for testability: `CompassTracking`, `CompassStorage`, `ApiRouting`, `AppLifecycleNotifierUseCase`
- **Factory pattern**: `TikOperationFactory` / `TickOperationProvider` for creating tracking operations
- **Use Case pattern**: `SendTik`, `GetRFV` encapsulate business logic
- **KVO observers** for operation completion tracking

### Configuration

Reads from Info.plist:
- `COMPASS_ACCOUNT_ID` - Account identifier
- `COMPASS_ENDPOINT` - Primary tracking endpoint
- `COMPASS_FALLBACK_ENDPOINT` - Fallback if primary fails
- `COMPASS_PAGE_TECHNOLOGY` - Tech ID (default: 3 for iOS, 12 for PressReader)
- `COMPASS_FALLBACK_WINDOW` - Duration to use fallback endpoint

### Testing

Tests in `/CompassSDKTests/` use XCTest with dependency injection. Mock implementations in `Mocks.swift`:
- `MockedOperationProvider` - Factory mock
- `MockStorage` - Storage mock
- `MockApiRouter` - Network mock

### Payload Encoding Pattern

Data sent to the server uses short JSON keys defined in `CodingKeys` enums (e.g., `"ac"` for accountId, `"conv"` for conversions). Dictionaries are converted to arrays of arrays for encoding:
```swift
// Input: ["key1": "value1", "key2": "value2"]
// Output: [["key1", "value1"], ["key2", "value2"]]
meta.map { [$0.key, $0.value] }
```

### Adding New Tracking Fields

Pattern for adding a new field to the tracking payload:
1. Add to public API struct (e.g., `ConversionOptions`) if user-facing
2. Add to internal struct (e.g., `Conversion`) for storage
3. Add `CodingKeys` case in `IngestTrackInfo` with the short JSON key
4. Add property in `IngestTrackInfo`
5. Add `encodeIfPresent` call in `encode(to:)`

### TrackInfo vs IngestTrackInfo

- `TrackInfo` - Core tracking data (user, session, page info)
- `IngestTrackInfo` - Wraps TrackInfo, adds ingest-specific fields (tik count, scroll %, conversions)

Both have custom `encode(to:)` implementations. To expose a private TrackInfo field, use `private(set)` and add a getter in IngestTrackInfo.

### Important Considerations

- **Thread safety is critical**: Always use barrier flags when modifying `trackInfo`
- **Memory management**: Check KVO observer cleanup and background task handling
- **Session timeout**: 10 seconds idle in background triggers new session
- **Fallback strategy**: Primary endpoint failure automatically switches to fallback for configured duration
