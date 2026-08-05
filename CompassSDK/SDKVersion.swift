//
//  SDKVersion.swift
//  CompassSDK
//

import Foundation

/// The SDK version reported in the `User-Agent` header.
///
/// Note this is *not* the `v` ingest param, which carries the tracking payload
/// version and is set independently in `TrackingConfig`.
///
/// Resolved at compile time on purpose: reading `CFBundleShortVersionString` via
/// `Bundle(for:)` returns the *host app* bundle when the SDK is statically
/// linked, which leaked the integrator's app version instead of ours.
///
/// Kept in sync with MarfeelSDK-iOS.podspec and CompassSDK/Info.plist by bump-version.sh.
let SDK_VERSION = "2.18.13"
