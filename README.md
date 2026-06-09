# FreesoundKit

[![CI](https://github.com/codybrom/FreesoundKit/actions/workflows/ci.yml/badge.svg)](https://github.com/codybrom/FreesoundKit/actions/workflows/ci.yml)

Unofficial Swift client for the [Freesound API v2](https://freesound.org/docs/api/) with support for:

- API key auth (`Authorization: Token ...`)
- OAuth2 bearer auth (`Authorization: Bearer ...`)
- OAuth2 authorization-code + refresh token exchange
- Typed models for sound metadata + audio descriptor fields

## Requirements

- Swift 6 / Xcode 16+
- macOS 15+, iOS 18+, tvOS 18+, watchOS 11+, visionOS 2+

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

- `textSearch`, `contentSearch`, `combinedSearch`
- `sound`, `soundAnalysis`, `similarSounds`, `soundComments`, `downloadOriginalSound`
- `uploadSound`, `describeSound`, `pendingUploads`, `bookmarkSound`, `rateSound`, `commentSound`
- `user`, `userSounds`, `userPacks`
- `pack`, `packSounds`, `downloadPack`
- `me`, `myBookmarkCategories`, `myBookmarkCategorySounds`
- `oauthAuthorizationURL`, `exchangeAuthorizationCode`, `refreshAccessToken`

## Error handling

All client methods throw `FreesoundError`, a typed enum:

```swift
do {
    let page = try await client.textSearch(query: "thunder")
} catch let error as FreesoundError {
    switch error {
    case .apiError(let statusCode, let detail):
        print("API error \(statusCode): \(detail)")
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
