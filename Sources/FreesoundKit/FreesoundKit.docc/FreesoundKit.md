# ``FreesoundKit``

An unofficial Swift client for the Freesound API v2.

## Overview

FreesoundKit is a small, dependency-free client for the
[Freesound API v2](https://freesound.org/docs/api/). It exposes the full API
surface — search, sound and pack metadata, audio analysis descriptors,
downloads, uploads, user actions, and the OAuth2 flow — through a single
``FreesoundClient`` whose every method throws a typed ``FreesoundError``.

The client is `Sendable`: one instance can be shared across tasks and actors,
and its ``FreesoundClient/authentication`` can be updated from any thread (handy
after refreshing an OAuth token).

### Authenticating

Read-only search and lookup endpoints work with an API key. Write actions,
downloads of original audio, and user-scoped endpoints (`/me`) require an OAuth2
token — see ``FreesoundAuthentication``.

```swift
import FreesoundKit

let client = FreesoundClient(authentication: .apiKey("<YOUR_API_KEY>"))

// Page through text-search results.
var page = try await client.textSearch(query: "piano")
print(page.results.first?.name ?? "no results")

while let next = try await client.nextPage(of: page) {
    page = next
}

// Preview downloads work without OAuth — just include "previews" in the fields.
let results = try await client.textSearch(
    query: "piano", parameters: ["fields": "id,name,previews"])
if let sound = results.results.first {
    let mp3 = try await client.downloadPreview(for: sound)
    print("Downloaded \(mp3.count) bytes")
}
```

### Using OAuth2

```swift
// 1. Send the user to the authorization page.
let authURL = try client.oauthAuthorizationURL(
    clientID: "<CLIENT_ID>", responseState: "session-123")

// 2. Exchange the returned code for tokens.
let token = try await client.exchangeAuthorizationCode(
    clientID: "<CLIENT_ID>", clientSecret: "<CLIENT_SECRET>", code: "<CODE>")
client.authentication = .oauthToken(token.accessToken)

// 3. Later, refresh the access token and update the client.
let refreshed = try await client.refreshAccessToken(
    clientID: "<CLIENT_ID>", clientSecret: "<CLIENT_SECRET>",
    refreshToken: token.refreshToken)
client.authentication = .oauthToken(refreshed.accessToken)
```

### Handling rate limits

Freesound throttles requests and returns HTTP 429, surfaced as
``FreesoundError/rateLimited(retryAfter:detail:)``. Wrap a call in
``FreesoundClient/withRateLimitRetry(maxAttempts:fallbackDelay:maxDelay:operation:)``
to honor the server's `Retry-After` automatically.

```swift
let page = try await client.withRateLimitRetry {
    try await client.textSearch(query: "rain")
}
```

### Caching results

Every response model is `Codable`, so you can persist results between launches or build snapshot-test
fixtures with `JSONEncoder`/`JSONDecoder`. Encoding mirrors the API's response shape — including the
descriptor fields that ``Sound`` and ``SoundAnalysis`` flatten to the top level — so a round-trip is
lossless. ``PagedResponse`` is encodable whenever its element type is.

```swift
let data = try JSONEncoder().encode(sound)
let restored = try JSONDecoder().decode(Sound.self, from: data)
```

## Topics

### Essentials

- ``FreesoundClient``
- ``FreesoundAuthentication``
- ``FreesoundError``

### Searching for sounds

- ``FreesoundClient/textSearch(query:parameters:)``
- ``FreesoundClient/similaritySearch(toSoundID:space:parameters:)``
- ``SimilaritySpace``

### Deprecated search

- ``FreesoundClient/contentSearch(parameters:)``
- ``FreesoundClient/combinedSearch(parameters:)``
- ``FreesoundClient/moreResults(of:)``
- ``CombinedSearchResponse``

### Paginating results

- ``PagedResponse``
- ``FreesoundClient/page(at:)``
- ``FreesoundClient/nextPage(of:)``
- ``FreesoundClient/previousPage(of:)``

### Fetching sound details

- ``FreesoundClient/sound(id:fields:)``
- ``FreesoundClient/soundAnalysis(id:descriptors:normalized:)``
- ``FreesoundClient/similarSounds(id:parameters:)``
- ``FreesoundClient/soundComments(id:parameters:)``

### Downloading audio

- ``FreesoundClient/downloadPreview(for:format:)``
- ``FreesoundClient/downloadOriginalSound(id:)``
- ``FreesoundClient/downloadPack(id:)``
- ``SoundPreviewFormat``

### Uploading and editing

- ``FreesoundClient/uploadSound(fileURL:request:fileFieldName:)``
- ``FreesoundClient/describeSound(request:)``
- ``FreesoundClient/editSound(soundID:request:)``
- ``FreesoundClient/pendingUploads()``
- ``SoundUploadRequest``
- ``SoundDescribeRequest``
- ``SoundEditRequest``

### Reacting to sounds

- ``FreesoundClient/bookmarkSound(soundID:name:category:)``
- ``FreesoundClient/rateSound(soundID:rating:)``
- ``FreesoundClient/commentSound(soundID:comment:)``

### Users and packs

- ``FreesoundClient/user(username:)``
- ``FreesoundClient/userSounds(username:parameters:)``
- ``FreesoundClient/userPacks(username:parameters:)``
- ``FreesoundClient/pack(id:)``
- ``FreesoundClient/packSounds(id:parameters:)``

### The authenticated user

- ``FreesoundClient/me()``
- ``FreesoundClient/myBookmarkCategories(parameters:)``
- ``FreesoundClient/myBookmarkCategorySounds(categoryID:parameters:)``

### The OAuth2 flow

- ``FreesoundClient/oauthAuthorizationURL(clientID:responseState:redirectURI:forceLogin:)``
- ``FreesoundClient/exchangeAuthorizationCode(clientID:clientSecret:code:)``
- ``FreesoundClient/refreshAccessToken(clientID:clientSecret:refreshToken:)``
- ``OAuthTokenResponse``

### Coping with rate limits

- ``FreesoundClient/withRateLimitRetry(maxAttempts:fallbackDelay:maxDelay:operation:)``

### Response models

- ``Sound``
- ``SoundDescriptors``
- ``BirdNetDetection``
- ``FSDSINetDetection``
- ``SoundPreviews``
- ``SoundImages``
- ``SoundAnalysis``
- ``Comment``
- ``User``
- ``Me``
- ``Avatar``
- ``Pack``
- ``BookmarkCategory``
- ``PendingUploads``
- ``PendingUpload``
- ``UploadSoundResponse``
- ``APIStatusResponse``

### Customizing the transport

- ``FreesoundHTTPClient``
