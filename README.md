# FreesoundKit

[![CI](https://github.com/codybrom/FreesoundKit/actions/workflows/ci.yml/badge.svg)](https://github.com/codybrom/FreesoundKit/actions/workflows/ci.yml)
[![Swift Version Compatibility](https://img.shields.io/endpoint?url=https%3A%2F%2Fswiftpackageindex.com%2Fapi%2Fpackages%2Fcodybrom%2FFreesoundKit%2Fbadge%3Ftype%3Dswift-versions)](https://swiftpackageindex.com/codybrom/FreesoundKit)
[![Platform Compatibility](https://img.shields.io/endpoint?url=https%3A%2F%2Fswiftpackageindex.com%2Fapi%2Fpackages%2Fcodybrom%2FFreesoundKit%2Fbadge%3Ftype%3Dplatforms)](https://swiftpackageindex.com/codybrom/FreesoundKit)

Unofficial Swift client for the [Freesound API v2](https://freesound.org/docs/api/) with support for:

- API key auth (`Authorization: Token ...`)
- OAuth2 bearer auth (`Authorization: Bearer ...`)
- OAuth2 authorization-code + refresh token exchange
- Typed models for sound metadata + audio descriptor fields
- `Codable` models you can cache or persist between launches with `JSONEncoder`/`JSONDecoder`
- A `Sendable` client you can share across tasks and actors
- Pagination helpers (`nextPage`, `previousPage`, `moreResults`)
- Preview downloads that work without OAuth (`downloadPreview`)
- Disk-backed asset cache for previews, images, and avatars (`FreesoundAssetCache`)

## Requirements

- Swift 6 toolchain (Xcode 16+ on Apple platforms)
- macOS 15+, iOS 18+, tvOS 18+, watchOS 11+, visionOS 2+ (Linux and Android via Swift Package Manager)

## Install

In `Package.swift`:

```swift
.package(url: "https://github.com/codybrom/FreesoundKit.git", branch: "main")
```

Then add `"FreesoundKit"` as a dependency to your target.

## API key usage

```swift
import FreesoundKit

let client = FreesoundClient(authentication: .apiKey("<YOUR_API_KEY>"))
let page = try await client.textSearch(query: "piano")
print(page.results.first?.name ?? "no results")

// Walk pages without rebuilding query parameters
if let next = try await client.nextPage(of: page) {
    print("next page has \(next.results.count) results")
}

// Preview audio is public — no OAuth needed (request the "previews" field)
let sounds = try await client.textSearch(
    query: "piano", parameters: ["fields": "id,name,previews"])
if let sound = sounds.results.first {
    let mp3Data = try await client.downloadPreview(for: sound)
}
```

## OAuth2 usage

```swift
import FreesoundKit

let client = FreesoundClient()

// 1. Send user to Freesound authorization page
let authURL = try client.oauthAuthorizationURL(
    clientID: "<CLIENT_ID>",
    responseState: "session-123"
)

// 2. After redirect, exchange the returned `code` for tokens
let token = try await client.exchangeAuthorizationCode(
    clientID: "<CLIENT_ID>",
    clientSecret: "<CLIENT_SECRET>",
    code: "<AUTHORIZATION_CODE>"
)

// 3. Use OAuth token for protected endpoints
client.authentication = .oauthToken(token.accessToken)
let me = try await client.me()
print(me.username)

// 4. Refresh when needed
let refreshed = try await client.refreshAccessToken(
    clientID: "<CLIENT_ID>",
    clientSecret: "<CLIENT_SECRET>",
    refreshToken: token.refreshToken
)
```

## Implemented endpoints

- `textSearch`, `contentSearch`, `combinedSearch` (+ `moreResults`)
- `page(at:)`, `nextPage`, `previousPage` for any paged response
- `sound`, `soundAnalysis`, `similarSounds`, `soundComments`, `downloadOriginalSound`, `downloadPreview`
- `uploadSound`, `describeSound`, `editSound`, `pendingUploads`, `bookmarkSound`, `rateSound`, `commentSound`
- `user`, `userSounds`, `userPacks`
- `pack`, `packSounds`, `downloadPack`
- `me`, `myBookmarkCategories`, `myBookmarkCategorySounds`
- `oauthAuthorizationURL`, `exchangeAuthorizationCode`, `refreshAccessToken`

## Caching & persistence

All response models conform to `Codable`, so you can cache results in memory or persist them between
launches with `JSONEncoder`/`JSONDecoder`:

```swift
// Persist a fetched sound, then restore it later without a network round-trip.
let data = try JSONEncoder().encode(sound)
let restored = try JSONDecoder().decode(Sound.self, from: data)
```

Encoding mirrors the API's response shape — including the audio-descriptor fields that `Sound` and
`SoundAnalysis` flatten to the top level — so a `decode → encode → decode` round-trip is lossless.
(`PagedResponse` is encodable whenever its element type is.)

### Caching binary assets

Models carry only URLs for previews, waveforms/spectrograms, and avatars. To cache the *bytes*, use
`FreesoundAssetCache` — a disk-backed actor that downloads on a miss, serves from disk on a hit,
de-duplicates concurrent requests for the same URL, and evicts least-recently-used files to stay
under a byte budget:

```swift
let cache = FreesoundAssetCache(
    client: client,
    directory: URL.cachesDirectory.appending(path: "freesound-assets"))

let waveform = try await cache.imageData(for: sound)          // .waveformM by default
let preview  = try await cache.previewData(for: sound)        // .hqMP3 by default
let avatar   = try await cache.avatarData(for: user.avatar!)  // works for User and Me
```

Fetch any asset URL directly with `cache.data(for: url)` (or, without a cache,
`client.downloadAsset(at:)` / the typed `client.downloadImage(for:type:)`). The cache owns its
directory — `removeAll()` deletes it wholesale, so give it a dedicated folder.

> Freesound also returns `*_bw_*` image keys, but its source documents them as byte-identical
> duplicates of the standard waveform/spectrogram images, so `SoundImageType` models only the four
> distinct images.

## Error handling

All client methods throw `FreesoundError`, a typed enum:

```swift
do {
    let page = try await client.textSearch(query: "thunder")
} catch let error as FreesoundError {
    switch error {
    case .apiError(let statusCode, let detail):
        print("API error \(statusCode): \(detail)")
    case .rateLimited(let retryAfter, let detail):
        print("Throttled (\(detail)); retry after \(retryAfter ?? 60)s")
    case .oauthRequired:
        print("This endpoint needs an OAuth token")
    default:
        print(error.localizedDescription)
    }
}
```

## Local tester CLI

You can verify the package without creating another project:

```bash
swift run freesound-tester help
```

Examples:

```bash
# API key smoke test
FREESOUND_API_KEY=... swift run freesound-tester search --query "piano"

# Build OAuth URL and open it in browser
FREESOUND_CLIENT_ID=... swift run freesound-tester oauth-url --state test

# Exchange returned code for tokens
FREESOUND_CLIENT_ID=... FREESOUND_CLIENT_SECRET=... \
swift run freesound-tester oauth-exchange --code "<CODE>"

# Test protected endpoint
FREESOUND_ACCESS_TOKEN=... swift run freesound-tester me

# Refresh token
FREESOUND_CLIENT_ID=... FREESOUND_CLIENT_SECRET=... FREESOUND_REFRESH_TOKEN=... \
swift run freesound-tester oauth-refresh
```

## Terms of use & rate limits

This library is an unofficial wrapper. Your use of the Freesound API is governed
by Freesound's [Terms of Use](https://freesound.org/docs/api/terms_of_use.html).
A few obligations that affect apps built with this library:

- **Non-commercial by default.** The API is free for non-commercial use only;
  commercial use requires a separate licensing agreement with Freesound.
- **Attribution.** You must credit Freesound and the individual sound authors, and
  respect each sound's license (visible via `Sound.license`). Surface this
  wherever you play or display sounds.
- **One key per app.** Don't register multiple API keys to work around limits.

Freesound throttles requests ([overview](https://freesound.org/docs/api/overview.html)):

| Operation | Per minute | Per day |
| --- | --- | --- |
| Standard (search, fetch, download) | 60 | 2,000 |
| Write (upload, describe, edit, comment, rate, bookmark) | 30 | 500 |

When a limit is exceeded the API responds `429`, surfaced here as
`FreesoundError.rateLimited(retryAfter:detail:)` — `retryAfter` carries the
server's `Retry-After` hint in seconds when present, and `detail` says which
limit was hit. Contact Freesound if you need higher limits.

To honor `Retry-After` automatically, wrap an idempotent call in
`withRateLimitRetry`:

```swift
let page = try await client.withRateLimitRetry {
    try await client.textSearch(query: "rain")
}
```
