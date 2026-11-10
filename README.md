# MarfeelSDK

Integration guide: https://community.marfeel.com/t/ios-native-application-instrumentation/734

## Installation

### Swift Package Manager (recommended)

In Xcode, add a package dependency on `https://github.com/Marfeel/MarfeelSDK-iOS` and select the `MarfeelSDK-iOS` product.

In a `Package.swift` manifest:

```swift
dependencies: [
    .package(url: "https://github.com/Marfeel/MarfeelSDK-iOS", from: "2.19.0")
],
targets: [
    .target(
        name: "YourApp",
        dependencies: [
            .product(name: "MarfeelSDK-iOS", package: "MarfeelSDK-iOS")
        ]
    )
]
```

### CocoaPods (deprecated)

The [CocoaPods trunk becomes read-only on December 2, 2026](https://blog.cocoapods.org/CocoaPods-Specs-Repo/), so no new versions are published there after 2.18.x. Switch to Swift Package Manager to get future versions.

If you can't switch yet, point your Podfile at a git tag:

```ruby
pod 'MarfeelSDK-iOS', :git => 'https://github.com/Marfeel/MarfeelSDK-iOS.git', :tag => '2.19.0'
```

## Releasing

1. Run `./bump-version.sh <major|minor|patch>` in your branch. It updates the podspec, `Info.plist` and `SDKVersion.swift`.
2. Merge the PR to `master`.
3. Tag the merge commit with the bare version, without a `v` prefix, and push the tag:

   ```sh
   git tag X.Y.Z
   git push origin X.Y.Z
   ```

Swift Package Manager resolves versions from git tags, so the pushed tag is the release. Never move or delete a tag after you push it, because SPM caches resolved tags. Ship fixes as a new version instead.

Releases are no longer pushed to the CocoaPods trunk.
