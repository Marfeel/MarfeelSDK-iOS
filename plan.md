# Experiences Feature — iOS Implementation Plan

## Context

Marfeel's web Experiences platform needs native iOS parity. Android branch `experiences-api` already implements this. The spec defines: fetching server-configured experiences, client-side experiment assignment, frequency cap tracking, recirculation event tracking, and optional content resolution. This plan ports that to iOS following existing SDK patterns.

**iOS SDK min target:** iOS 11.0, Swift 5.0. No async/await (iOS 13+). Must use callback/completion patterns consistent with existing codebase.

**Reference implementation:** `/Users/miquelmasriera/Marfeel/MarfeelSDK-Android` branch `experiences-api`.

---

## New Directory Structure

```
CompassSDK/
├── Experiences/
│   ├── Models/
│   │   ├── Experience.swift              # Experience class + ExperienceType/Family/ContentType enums
│   │   ├── ExperienceSelector.swift      # ExperienceSelector struct
│   │   ├── ExperienceFilter.swift        # ExperienceFilter struct
│   │   ├── RecirculationLink.swift       # RecirculationLink struct
│   │   └── RecirculationModule.swift     # RecirculationModule struct (name + links)
│   ├── Experiences.swift                 # Public Experiences singleton (protocol + impl)
│   ├── Recirculation.swift               # Public Recirculation singleton (protocol + impl)
│   ├── WholeModuleAugmenter.swift        # Position-255 sentinel injection logic
│   ├── ExperiencesApiClient.swift        # GET request builder for /json/experiences/app
│   ├── RecirculationApiClient.swift      # POST sender for recirculation events
│   ├── ExperiencesResponseParser.swift   # JSON response → [Experience] parsing + ParseResult
│   ├── ContentResolver.swift             # Fetches experience content (with bundle + jukebox support)
│   ├── ExperimentManager.swift           # Weighted variant assignment + persistence
│   ├── FrequencyCapManager.swift         # Impression/close counter tracking + uexp encoding
│   ├── ReadEditorialsManager.swift       # Editorial ID accumulation + delta encoding
│   └── NetworkInfoProvider.swift         # Connection type + bandwidth detection
```

---

## Phase 1: Models & Enums

### 1.1 `RecirculationLink`
```swift
public struct RecirculationLink {
    public let url: String
    public let position: Int
    public init(url: String, position: Int)
}
```

### 1.2 `RecirculationModule`
```swift
internal struct RecirculationModule {
    let name: String
    let links: [RecirculationLink]
}
```
**Internal only.** Public API uses `(name: String, links: [RecirculationLink])` as separate params. Module is constructed internally for serialization. Serialized as `{"n": "name", "e": [{"url": "...", "p": "0"}, ...]}`.

### 1.3 `ExperienceType` enum
```swift
public enum ExperienceType: String {
    case inline
    case flowcards
    case compass
    case adManager
    case affiliationEnhancer
    case conversions
    case content
    case experiments
    case experimentation
    case recirculation
    case goalTracking
    case ecommerce
    case multimedia
    case piano
    case appBanner
    case unknown

    static func fromKey(_ key: String) -> ExperienceType?
}
```
Map from server string keys (e.g., `"adManager"` → `.adManager`). `fromKey` returns `nil` for unrecognized keys (caller skips unknown types during parsing).

### 1.4 `ExperienceFamily` enum
```swift
public enum ExperienceFamily: String {
    case twitter          // "twitterexperience"
    case facebook         // "facebookexperience"
    case youtube          // "youtubeexperience"
    case recommender      // "recommenderexperience"
    case telegram         // "telegramexperience"
    case gathering        // "gatheringexperience"
    case affiliate        // "affiliateexperience"
    case podcast          // "podcastexperience"
    case experimentation  // "experimentsexperience"
    case widget           // "widgetexperience"
    case marfeelPass      // "passexperience"
    case script           // "scriptexperience"
    case paywall          // "paywallexperience"
    case marfeelSocial    // "marfeelsocial"
    case unknown          // fallback

    static func fromKey(_ key: String) -> ExperienceFamily
}
```
`fromKey` always returns a value: known key → case, unrecognized key → `.unknown`. Absent family in JSON → `nil` (not `.unknown`).

### 1.5 `ExperienceContentType` enum
```swift
public enum ExperienceContentType: String {
    case textHTML         // "TextHTML"
    case json             // "Json"
    case amp              // "AMP"
    case widgetProvider   // "WidgetProvider"
    case adServer         // "AdServer"
    case container        // "Container"
    case unknown          // fallback

    static func fromKey(_ key: String) -> ExperienceContentType
}
```
`fromKey` returns `.unknown` for unrecognized keys.

### 1.6 `ExperienceSelector`, `ExperienceFilter`
```swift
public struct ExperienceSelector {
    public let selector: String
    public let strategy: String
}

public struct ExperienceFilter {
    public let key: String
    public let `operator`: String   // "EQUALS" or "NOT_EQUALS"
    public let values: [String]
}
```

### 1.7 `Experience`
```swift
public class Experience {
    public let id: String
    public let name: String
    public let type: ExperienceType
    public let family: ExperienceFamily?      // nil when absent in JSON, .unknown when present but unrecognized
    public let placement: String?
    public let contentUrl: String?
    public let contentType: ExperienceContentType
    public let features: [String: Any]?
    public let strategy: String?
    public let selectors: [ExperienceSelector]?
    public let filters: [ExperienceFilter]?
    public let rawJson: [String: Any]
    public internal(set) var resolvedContent: String?

    internal var contentResolver: ContentResolver?

    public func resolve(_ completion: @escaping (String?) -> Void)
}
```
**Class (not struct):** holds mutable `resolvedContent` and internal `ContentResolver` reference (injected at parse time). `resolve()` uses completion handler for iOS 11 compat. Returns cached `resolvedContent` if already resolved.

---

## Phase 2: Persistence Managers

### 2.1 `ExperimentManager`
- **Storage:** UserDefaults key `"CompassExperiments"` (JSON-serialized `[String: String]`)
- **Data:** `[String: String]` (groupId → variantId)
- **Core logic:**
  - `handleExperimentGroups(_ groups: [String: Any]?)` — for each group not yet assigned, sample variant by weight, persist. Idempotent: existing assignments never re-rolled
  - `filterByExperiments(_ experiences: [Experience]) -> [Experience]` — keep only experiences whose `mrf_exp_<groupId>` filters match current assignments. Experiences without experiment filters pass through. Supports EQUALS and NOT_EQUALS operators
  - `getAssignments() -> [String: String]`
  - `getTargetingEntries() -> [String: String]` — returns `["experiment::groupId": "variantId", ...]` for request targeting
  - `setAssignment(groupId:, variantId:)` — QA override
  - `clear()`
- **Assignment algorithm:** totalWeight = sum of variant weights → random in [0, totalWeight) → iterate variants accumulating weight → first where random < cumulative wins
- **Thread safety:** NSLock

### 2.2 `FrequencyCapManager`
- **Storage:** UserDefaults key `"CompassExperiencesFreqCaps"` (JSON-serialized). Both counters AND config are persisted together
- **Constructor:** injectable clock (`() -> TimeInterval = { Date().timeIntervalSince1970 }`) and timezone (`TimeZone = .current`) for deterministic testing of rollovers and `ls`/`cls` computation
- **Data model:**
  ```
  ExperienceCounter {
      total: EventCounter(impression, close)    // lifetime counts
      last: EventCounter(impression, close)     // timestamps of last events (seconds)
      buckets: [year: [month: [day: EventCounter]]]  // daily granularity
  }
  EventCounter { impression: Int64, close: Int64 }
  ```
- **Core logic:**
  - `trackImpression(experienceId:)` — bump daily bucket + total impressions + last impression timestamp. Only tracks if experienceId is in current config
  - `trackClose(experienceId:)` — same for close counters
  - `applyResponseConfig(_ config: [String: [String]])` — prune counters to server-declared IDs. Empty config wipes all
  - `buildUexp() -> String` — encode non-zero counters per experience, semicolon-separated. Format per experience: `expId,l|N|cl|N|m|N|cm|N|w|N|cw|N|d|N|cd|N|ls|N|cls|N`. Zero values omitted. Full example: `"IL_abc,l|5|d|1|ls|3600;IL_def,l|2|cl|1"`
  - `getCounts(experienceId:) -> [String: Int]` — computed snapshot with keys: `l` (lifetime impressions), `cl` (lifetime closes), `m` (this month impressions), `cm` (this month closes), `w` (this ISO week impressions), `cw` (this ISO week closes), `d` (today impressions), `cd` (today closes), `ls` (seconds since last impression), `cls` (seconds since last close)
  - `getConfig() -> [String: [String]]`
  - `clear()`
- **ISO week semantics:** Monday-first, minimal-days = 4. Use `Calendar(identifier: .iso8601)`
- **Thread safety:** NSLock

### 2.3 `ReadEditorialsManager`
- **Storage:** UserDefaults key `"CompassReadEditorials"` (JSON-serialized)
- **Data:** array of `Entry(id: String, timestamp: TimeInterval)`, max 100 entries, 30-day TTL
- **Core logic:**
  - `add(_ editorialId: String)` — ignore blank. Deduplicate (refresh timestamp if exists). Evict expired + over-limit (FIFO)
  - `buildRedParam() -> String` — sort numeric IDs, delta-encode: `[120, 130, 135]` → `"120,10,5"`. Skip non-numeric IDs
  - `getIds() -> [String]` — return stored IDs (pruned of expired)
  - `clear()`
- **Thread safety:** NSLock

---

## Phase 3: API Clients & Network

### 3.1 `NetworkInfoProvider`
```swift
internal protocol NetworkInfoProviding {
    func getConnectionSpeedKbps() -> Int?
    func getConnectionType() -> String?   // "wifi", "cellular", "ethernet", or nil
}
```
- iOS 12+: use `NWPathMonitor` for path type, `CTTelephonyNetworkInfo` for cellular detail
- iOS 11: `CTTelephonyNetworkInfo` only, graceful fallback
- Returns `"wifi"`, `"cellular"`, `"ethernet"`, or `nil`

### 3.2 `ExperiencesApiClient`
- **Endpoint:** `GET https://flowcards.mrf.io/json/experiences/app`
- **Does NOT use existing `ApiCall` protocol** — that protocol's extension hardcodes `httpMethod = "POST"`. Experiences needs GET with query params
- Build URL with `URLComponents` + `URLQueryItem`
- Use `URLSession.dataTask(with: URL)` directly
- **Method:** `fetch(url: String, customTargeting: [String: String], completion: @escaping ([String: Any]?) -> Void)`
- **Query params** (from tracker state + managers):
  - `sid` (accountId), `ptch` (pageTechnology), `url`, `canonical_url`
  - `seid` (sessionId), `uid` (userId), `suid` (registeredUserId), `utyp` (userType numeric)
  - `fvst` (firstVisitTimestamp), `useg` (comma-separated segments), `cnv` (comma-separated pending conversions)
  - `ref` (previous page URL), `kbps` (connection speed), `ctyp` (connection type)
  - **Note:** `canonical_url` always duplicates `url` value (native has no DOM to read a separate canonical)
  - `uexp` (frequency caps via `FrequencyCapManager.buildUexp()`), `red` (read editorials via `ReadEditorialsManager.buildRedParam()`)
  - `trg` (targeting string), `v` = `"2"`
- **Targeting string (`trg`):** `&`-joined entries in order:
  1. `userVar::key=value` for each user variable
  2. `sessionVar::key=value` for each session variable
  3. `pageVar::key=value` for each page variable
  4. `experiment::groupId=variantId` for each experiment assignment
  5. `key=value` for each custom targeting entry
- Returns raw JSON `[String: Any]?` (parsed by `ExperiencesResponseParser`)

### 3.3 `RecirculationApiClient`
- **Endpoint:** `POST https://events.newsroom.bi/recirculation/recirculation.php`
- **Can use existing `ApiCall`/`ApiRouter`** pattern — POST with form-encoded body
- **Method:** `send(eventType: String, modules: [RecirculationModule])`
- **Form fields:**
  - `t` — event type string (`"elegible"`, `"impression"`, `"click"`) ⚠️ "elegible" is intentional server-side typo, must match
  - `n` — current timestamp (seconds since epoch)
  - `m` — modules JSON array: `[{"n": "moduleName", "e": [{"url": "https://...", "p": "0"}, {"url": " ", "p": "255"}]}]`
  - `ac` — account ID
  - `url` — current page URL
  - `c` — current page URL (duplicate of `url`)
  - `ut` — user type numeric value
  - `fv` — first session timestamp
  - `lv` — previous session last ping timestamp
  - `u` — original user ID
  - `s` — session ID
  - `pageType` — page technology
  - `sui` — registered user ID (optional)
  - `uc` — user consent (boolean or null)
  - `cc` — consent code: `"1"` (consent true), `"0"` (consent false), `"3"` (consent nil/unknown)
  - `lp` — landing page URL (optional)
- **Position serialization:** `RecirculationLink.position` is `Int` but serialized as `String` in the JSON (`"p": "0"`, not `"p": 0`)
- Fire-and-forget, errors silently caught

---

## Phase 4: Response Parser

### `ExperiencesResponseParser`

**Constructor:** takes `ContentResolver?` to inject into parsed `Experience` objects.

**Return type:**
```swift
struct ParseResult {
    let experiences: [Experience]
    let frequencyCapConfig: [String: [String]]   // experienceId → list of counter types
    let experimentGroups: [String: Any]?          // raw JSON for ExperimentManager
    let editorialId: String?                      // from content.editorialId
}
```

**Method:** `func parse(_ json: [String: Any]) -> ParseResult`

**Parsing algorithm:**
1. Extract `targeting.frequencyCap` → `[String: [String]]` frequency cap config
2. Extract `experimentGroups` (fallback to `experiments`) → raw JSON for experiment manager
3. Extract `content.editorialId` → optional String
4. Iterate remaining top-level keys (skip: `targeting`, `content`, `experiments`, `experimentGroups`):
   - Each key maps to `ExperienceType.fromKey(key)` — skip if nil
   - Under each type, look for `actions` or `cards` sub-object
   - Each entry in actions/cards → one `Experience`:
     - Entry key = `experience.name`
     - `id` from action object (required, fallback `""`)
     - `content.type` → `ExperienceContentType.fromKey()`
     - `content.url` → `contentUrl`
     - `family` → `ExperienceFamily.fromKey()` if present, `nil` if absent
     - `features`, `strategy`, `selectors`, `filters` from action
     - Full action object → `rawJson`
     - Inject `contentResolver` reference
5. **Experiment filter synthesis:** if action has `experiment` block with `groupId` + `variantIds`:
   - Create synthetic filter: `key: "mrf_exp_<groupId>"`, `operator: "EQUALS"`, `values: variantIds`
   - Append to any existing explicit filters

---

## Phase 5: Content Resolution

### `ContentResolver`

**Method:** `func fetch(url: String, experienceId: String?, completion: @escaping (String?) -> Void)`

**Single content fetch:** when URL is not bundled, simple GET → return body string.

**Bundle detection:** URL is "bundled" if:
- The `id` query param contains a comma (e.g., `?id=IL_a,IL_b`)
- Or URL is a jukebox transformer (`flowcards.mrf.io/transformer/`) whose nested `url` param has comma-separated IDs

**Bundled payload format:**
```json
{
  "IL_abc": ["<html>content1</html>", "<html>content2</html>"],
  "IL_def": ["<html>content3</html>"],
  "vars": {"varName": "varValue"}
}
```

**Bundle data model:**
```swift
internal class BundleEntry {
    let lock = NSLock()
    var payload: BundledPayload?
    var varsReplayed: Bool = false
}

internal struct BundledPayload {
    var contents: [String: [String]]   // experienceId → content slices
    let vars: [String: String]         // variable substitutions
}
```

**Bundle fetch logic:**
1. Lock on URL (NSLock per URL, stored in dictionary). First caller fetches; concurrent callers wait and share result
2. If payload cached and has slice for experienceId → pop first item (splice/FIFO semantics) → return
3. If no cached payload or slice empty:
   - GET the URL
   - Parse JSON into `BundledPayload`
   - If payload has `vars` and not yet replayed:
     - Apply vars to URL query params
     - Re-fetch with vars applied
     - Merge new payload with existing
     - Mark `varsReplayed = true`
4. Pop first slice for experienceId → return

**Jukebox URL handling:** URLs containing `flowcards.mrf.io/transformer/` have a nested inner URL in the `url` query param. Variables are applied to the inner URL, not the outer transformer URL.

---

## Phase 6: Recirculation Tracker

### `WholeModuleAugmenter`
Separate class encapsulating position-255 sentinel logic:
```swift
internal class WholeModuleAugmenter {
    private let pageUrlProvider: () -> String?
    private var currentPageUrl: String?
    private var moduleStates: [String: Bool] = [:]  // module name → has been impressed
    private let lock = NSLock()

    func onEligible(_ modules: [RecirculationModule]) -> [RecirculationModule]
    func onImpression(_ module: RecirculationModule) -> RecirculationModule
}
```
- **Sentinel link:** `RecirculationLink(url: " ", position: 255)`
- `onEligible`: for each module, if first call for this module on current page → append sentinel. Track module as seen (not yet impressed)
- `onImpression`: if module not yet impressed on current page → append sentinel, mark as impressed
- **Page change detection:** compare `pageUrlProvider()` with `currentPageUrl`. If different, reset all module states

### `Recirculation` (public)
```swift
public protocol RecirculationTracking {
    func trackEligible(name: String, links: [RecirculationLink])
    func trackImpression(name: String, links: [RecirculationLink])
    func trackImpression(name: String, link: RecirculationLink)
    func trackClick(name: String, link: RecirculationLink)
}
```
- Singleton: `RecirculationTracker.shared`
- Internally creates `RecirculationModule(name:, links:)` from parameters
- Passes modules through `WholeModuleAugmenter` (eligible + impression only)
- Delegates augmented modules to `RecirculationApiClient.send(eventType:, modules:)`
- `trackClick` never augmented — passed directly

---

## Phase 7: Experiences Singleton

### `Experiences` (public)
```swift
public protocol ExperiencesTracking {
    func addTargeting(key: String, value: String)
    func fetchExperiences(filterByType: ExperienceType?,
                          filterByFamily: ExperienceFamily?,
                          resolve: Bool,
                          url: String?,
                          completion: @escaping ([Experience]) -> Void)
    func trackEligible(experience: Experience, links: [RecirculationLink])
    func trackImpression(experience: Experience, links: [RecirculationLink])
    func trackImpression(experience: Experience, link: RecirculationLink)
    func trackClick(experience: Experience, link: RecirculationLink)
    func trackClose(experience: Experience)

    // QA/Debug
    func clearFrequencyCaps()
    func getFrequencyCapCounts(experienceId: String) -> [String: Int]
    func getFrequencyCapConfig() -> [String: [String]]
    func clearReadEditorials()
    func getReadEditorials() -> [String]
    func getExperimentAssignments() -> [String: String]
    func setExperimentAssignment(groupId: String, variantId: String)
    func clearExperimentAssignments()
}
```

- Singleton: `Experiences.shared` (backed by internal `ExperiencesTracker`)
- Custom targeting stored in thread-safe dictionary (in-memory only, NSLock)

### `fetchExperiences` flow (matches Android):
1. Determine page URL: use `url` param if provided, else read from `CompassTracker.shared` current page. Return empty list if no URL available
2. `ExperiencesApiClient.fetch(url:, customTargeting:)` → raw JSON
3. `ExperiencesResponseParser.parse(json)` → `ParseResult`
4. `FrequencyCapManager.applyResponseConfig(parseResult.frequencyCapConfig)` — prune counters
5. `ReadEditorialsManager.add(parseResult.editorialId)` — if present
6. `ExperimentManager.handleExperimentGroups(parseResult.experimentGroups)` — assign unassigned variants
7. `ExperimentManager.filterByExperiments(parseResult.experiences)` — keep matching
8. Apply optional type/family filters (AND logic when both provided)
9. If `resolve == true`: resolve all experiences in parallel (DispatchGroup), then call completion
10. Else: call completion immediately

### Tracking delegation:
- `trackImpression(experience:, links:)` → bump `FrequencyCapManager.trackImpression(experience.id)`, then `RecirculationTracker.shared.trackImpression(name: experience.name, links: links)`
- `trackImpression(experience:, link:)` → same but with single link wrapped in array
- `trackClose(experience:)` → `FrequencyCapManager.trackClose(experience.id)` only (no recirculation event)
- `trackEligible(experience:, links:)` → `RecirculationTracker.shared.trackEligible(name: experience.name, links: links)` directly
- `trackClick(experience:, link:)` → `RecirculationTracker.shared.trackClick(name: experience.name, link: link)` directly

---

## Phase 8: Integration with CompassTracker

### What ExperiencesApiClient needs from existing tracker
All data is already accessible. The API client will read from `CompassTracker.shared` and `PListCompassStorage`:

| Data needed | Source |
|-------------|--------|
| accountId | `TrackingConfig.shared.accountId` |
| pageTechnology | `TrackingConfig.shared.pageTechnology` (default 3 for iOS) |
| pageUrl | `CompassTracker.shared` internal `trackInfo.pageUrl` |
| sessionId | `CompassStorage.sessionId` |
| userId | `CompassStorage.userId` |
| registeredUserId | `CompassStorage.suid` |
| userType | Stored in tracker state |
| firstVisitTimestamp | `CompassStorage.firstVisit` |
| userSegments | `CompassStorage.userSegments` |
| userVars | `CompassStorage.userVars` |
| sessionVars | `CompassStorage.sessionVars` |
| pageVars | `CompassTracker` page vars (already exposed) |
| hasConsent | `CompassStorage.hasConsent` |
| landingPage | `CompassStorage.landingPage` |
| previousPageUrl | Need to expose from tracker or trackInfo |
| pendingConversions | Need to expose from tracker |

### Minimal changes to existing files
1. **`CompassTracker.swift`** — expose internal read accessor for `trackInfo` fields needed by experiences (pageUrl, previousUrl, pending conversions). May add `internal` computed properties
2. **`TrackingConfig.swift`** — optionally add `experiencesEndpoint` property (or hardcode `https://flowcards.mrf.io` since it's fixed)
3. **`CompassStorage.swift`** — likely no changes; all required data already exposed
4. **No changes to `Bundle.swift`** unless we want configurable experiences endpoint

---

## Phase 9: Testing

### Unit tests (matching Android test coverage)
| Area | Test class | Tests |
|------|-----------|-------|
| `ExperiencesResponseParser` | `ExperiencesResponseParserTests` | Family parsing (present/absent/unknown), type mapping, experiment filter synthesis, metadata key skipping, content type parsing, selector/filter parsing |
| `ExperimentManager` | `ExperimentManagerTests` | Weighted assignment, persistence across reinit, no re-roll (idempotence), filter evaluation (EQUALS/NOT_EQUALS), QA overrides, targeting entries format |
| `FrequencyCapManager` | `FrequencyCapManagerTests` | Counter increments, uexp encoding format (zero omission, semicolons), config pruning, daily/weekly/monthly rollover, ISO week boundaries, getCounts keys |
| `ReadEditorialsManager` | `ReadEditorialsManagerTests` | Delta encoding, max 100 entries, 30-day TTL eviction, deduplication with timestamp refresh, non-numeric ID skipping |
| `RecirculationApiClient` | `RecirculationApiClientTests` | POST body format, consent codes ("1"/"0"/"3"), position-as-string serialization, module JSON format |
| `WholeModuleAugmenter` | `WholeModuleAugmenterTests` | First eligible appends pos-255, second doesn't, impression appends once, click never augmented, page change resets all state |
| `RecirculationTracker` | `RecirculationTrackerTests` | Event routing through augmenter, module construction from name+links |
| `ExperiencesApiClient` | `ExperiencesApiClientTests` | URL building with all query params, targeting string assembly (order: userVar, sessionVar, pageVar, experiment, custom) |
| `ContentResolver` | `ContentResolverTests` | Single fetch, bundle detection (comma in id, jukebox URL), bundle fetch+slice (FIFO pop), vars replay, concurrent access coalescing |
| `ExperiencesTracker` | `ExperiencesTrackerTests` | Full pipeline: fetch → parse → filter → resolve → track. Impression bumps freq cap + delegates recirculation. Close bumps freq cap only |

### Test resources
- `experiences_response_small.json` — small payload with multiple experience types (port from Android)
- `experiences_response_large.json` — stress test payload (port from Android)

### Manual verification
- Run Playground app
- `CompassTracker.initialize(accountId:)` + `trackNewPage(url:)`
- `Experiences.getInstance().fetchExperiences(completion:)` — verify non-empty response
- Call tracking methods — verify network requests in Charles/Proxyman
- Verify UserDefaults persistence survives app restart
- Verify experiment assignments persist and don't re-roll

---

## Phase 10: Playground Demo UI

Full dedicated Experiences tab in SwiftUI Playground app:
- URL input field (optional override for fetchExperiences url param)
- Type/Family filter pickers (dropdown or segmented control)
- Fetch button (with resolve toggle)
- Results list showing fetched experiences (id, name, type, family, contentUrl)
- Per-experience actions: Track Eligible, Track Impression, Track Click, Track Close
- Resolve Content button + resolved content display
- QA section:
  - Clear/view frequency caps (per experience counts display)
  - Clear/view experiments (assignments display)
  - Set experiment assignment (groupId + variantId inputs)
  - Clear/view read editorials
- Similar to Android's `MainScreen.kt` (lines 374-750+)

---

## Implementation Order

1. **Models & Enums** (no dependencies) — Experience, RecirculationLink, RecirculationModule, enums
2. **Persistence managers** (ExperimentManager, FrequencyCapManager, ReadEditorialsManager)
3. **NetworkInfoProvider** + **API clients** (ExperiencesApiClient, RecirculationApiClient)
4. **Response parser** (ExperiencesResponseParser + ParseResult)
5. **Content resolver** (ContentResolver with bundle + jukebox support)
6. **WholeModuleAugmenter** + **Recirculation singleton**
7. **Experiences singleton** (wires everything together)
8. **Integration touchpoints** (minor internal accessor changes in CompassTracker)
9. **Tests** (unit tests + test JSON resources)
10. **Playground demo UI**

---

## Key Design Decisions

| Decision | Rationale |
|----------|-----------|
| Completion handlers, not async/await | iOS 11 min target |
| Class for Experience, not struct | Mutable `resolvedContent`, holds `ContentResolver` ref (matches Android `@Transient` pattern) |
| Separate `Recirculation` and `Experiences` singletons | Matches Android, allows standalone recirculation usage |
| `RecirculationModule` as internal model | Matches Android. Bundles name + links for internal serialization; public API uses separate `(name:, links:)` params |
| `WholeModuleAugmenter` as separate class | Matches Android. Isolates stateful sentinel logic, independently testable |
| UserDefaults for persistence (not PList files) | Simpler for JSON blobs (counters, assignments). PList pattern in SDK is for main storage model; UserDefaults more appropriate for isolated managers |
| GET request bypasses `ApiCall` protocol | Existing `ApiCall` extension hardcodes POST; experiences is GET |
| `ptch` default = 3 (not 4) for iOS | Android uses 4, iOS uses 3 per existing SDK constants |
| `fetchExperiences` accepts optional `url` param | Matches Android. Falls back to current page from CompassTracker if nil |
| `ParseResult` as explicit return type | Matches Android. Cleanly separates parser output (experiences, config, groups, editorial) from manager side-effects |
| NSLock for persistence managers | Simpler than DispatchQueue for counter/map operations. Existing SDK uses both patterns; NSLock for focused critical sections |
| `.shared` singleton access | Swift convention. Android uses `getInstance()`; iOS uses `static let shared` pattern matching existing `CompassTracker.shared` |

---

## Wire Format Parity (must match Android exactly)

| Format | Detail |
|--------|--------|
| Experiences GET query params | All param names, value formats, order in `trg` string |
| Recirculation POST fields | All field names, `"elegible"` spelling (not "eligible"), module JSON format |
| Module JSON | `{"n": "name", "e": [{"url": "...", "p": "0"}]}` — position as String |
| `uexp` encoding | `expId,l\|N\|cl\|N\|m\|N\|cm\|N\|w\|N\|cw\|N\|d\|N\|cd\|N\|ls\|N\|cls\|N` semicolon-separated, zero values omitted |
| `red` encoding | Delta-encoded sorted numeric IDs: `[120, 130, 135]` → `"120,10,5"` |
| `trg` targeting | `&`-joined: `userVar::k=v&sessionVar::k=v&pageVar::k=v&experiment::gid=vid&custom=val` |
| Family enum keys | Exact server strings: `"recommenderexperience"`, `"twitterexperience"`, etc. |
| Type enum keys | Exact server strings: `"adManager"`, `"goalTracking"`, `"affiliationEnhancer"`, etc. |
| Whole-module sentinel | `RecirculationLink(url: " ", position: 255)` — space URL, position 255 |
| Consent codes | `"1"` = consent true, `"0"` = consent false, `"3"` = consent nil/unknown |
| ISO week | Monday-first, minimal-days-in-first-week = 4 (ISO 8601) |
| Experiment filter prefix | `"mrf_exp_"` + groupId |
| Bundled content | Splice semantics (FIFO pop per experienceId). Vars replay once per URL |

---

## Known Parity Gaps (not sent by native SDKs)

These params exist in the web platform but are intentionally not sent by native (Android or iOS):
- `ts` — request timestamp
- `nv` — number of visits
- `ns` — new-session flag
- Dedicated `exp=` param (experiments go inside `trg` instead)
- `tv` — per-link test variant (different scope in native)
- Custom targeting on recirculation pings — not sent
- `useg` on recirculation pings — not sent
