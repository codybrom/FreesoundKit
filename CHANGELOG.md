# Changelog

All notable changes to FreesoundKit are documented in this file. This project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

Audited the full client surface against the Freesound server source (`apiv2/urls.py`, `views.py`, `serializers.py`). Coverage was already near-complete; this closes the remaining gaps.

### Added

- **`soundDownloadLink(id:)`** maps the `sounds/<id>/download/link/` endpoint, returning a `SoundDownloadLink` whose URL carries a signed, time-limited token. Unlike `downloadOriginalSound(id:)`, the URL needs no `Authorization` header, so it can be handed to `AVPlayer`, a background `URLSession` download task, or `WKWebView`.
- **`Sound.score`** — the search-relevance score the API emits on search/similarity results.
- **`BookmarkCategory.sounds`** — the category's sounds URL, emitted by the bookmark-category serializer.
- **`SoundSearchSort`** — a typed enum of the `sort` values accepted by `textSearch`. The API silently falls back to `score` on an unrecognized value, so these constants guard against typos (e.g. `downloads_desc`, not `num_downloads desc`).
- **`FreesoundUsageMonitor`** — an opt-in `@MainActor @Observable` companion over the (still-`Sendable`) `FreesoundUsageTracker`. It re-snapshots on a timer (the rolling windows decay with wall-clock time) so SwiftUI views can observe `snapshot` directly, and only publishes when the snapshot actually changes so an idle meter doesn't wake SwiftUI every tick. The tracker itself is unchanged.

### Changed

- Documented that `Pack.download` is not emitted by the current Freesound pack serializer (typically `nil`); use `downloadPack(id:)`.

### Deprecated

- **`bookmarkSound(soundID:name:category:)`** — the Freesound bookmark endpoint's request serializer reads only `category`, so the `name` argument was being silently dropped on the wire. Use `bookmarkSound(soundID:category:)`. The deprecated overload now forwards to it and no longer sends `name`.

## [1.2.0] - 2026-06-26

### Added

- **`Codable` response models.** Every response model now conforms to `Codable` (previously `Decodable`-only), so results can be cached or persisted between launches with `JSONEncoder`/`JSONDecoder`. `Sound` and `SoundAnalysis` re-flatten their audio descriptors on encode to mirror the API's shape, and `PagedResponse` is `Encodable` when its element type is. Round-trips are lossless by value, verified against a live API response.
- **Image and asset downloads.** `downloadImage(for:type:)` fetches a sound's waveform/spectrogram, and `downloadAsset(at:)` fetches any public Freesound CDN asset URL without authentication. Adds `SoundImageType` and `url(for:)` accessors on `SoundPreviews` and `SoundImages`.
- **`FreesoundAssetCache`.** A disk-backed actor that caches preview audio, images, and avatars: fetch on miss, serve from disk on hit, in-flight de-duplication of concurrent requests, and least-recently-used eviction under a byte budget. Cross-platform (no CryptoKit).
- **`AvatarMonogram`.** A deterministic, network-free default-avatar fallback — the username's first letter over a palette color — reproducing freesound.org's own rendering exactly, with `User`/`Me` accessors and an `RGBColor` value type.
- **`FreesoundUsageTracker`.** Automatic APIv2 rate-limit usage tracking against Freesound's published per-window throttle limits (read vs write buckets, per minute and per day, by credential level). A client records each APIv2 request automatically at its single request chokepoint; `snapshot()` exposes remaining quota for display.

## [1.1.0] - 2026-06-22

Models and endpoints were audited against the live Freesound API, the server's `serializers.py`/`urls.py`, and the official Python client (live behavior and source take priority over the stale published docs).

### Added

- **`similaritySearch(toSoundID:space:)`** and `SimilaritySpace`, the supported replacement for content search (via `/search/` `similar_to`).
- **`Avatar`** type — a sound/user avatar is an object, not a string — plus rounded-out `Me` fields (`email`, `unique_id`, `num_comments`, `bookmark_categories`, counts, sounds/packs, `ai_preference`).
- Previously-dropped fields: `Sound.packName`, `Pack.numDownloads`, `User.aiPreference`, `User.numComments`.
- Extended `SoundDescriptors` with `category`/`subcategory`, `has_audio_problems`, embedding vectors, and nested `BirdNetDetection` / `FSDSINetDetection`.

### Changed

- Decode `/me/` and `/users/<username>/` correctly: the field is `home_page` (not `homepage`), and URL-ish fields can be empty strings — lenient URL decoding now maps empty/invalid values to `nil`.

### Deprecated

- `contentSearch`, `combinedSearch`, and `moreResults` — Freesound removed `/search/content/` and `/search/combined/`; these now throw a clear HTTP 410.

## [1.0.1] - 2026-06-22

### Fixed

- Binary downloads send `Accept: */*` instead of `application/octet-stream`, which Freesound's DRF API rejects with HTTP 406 (#1).
- Multi-word tags are joined with dashes via `encodeTags()` so a tag with internal spaces isn't silently split into separate tags by the server.
- Upload escapes `"`/`\` and strips CR/LF in the multipart filename parameter to prevent malformed or injectable `Content-Disposition` headers.

### Added

- `.env` support in the `freesound-tester` CLI (and `.env` files are gitignored).

## [1.0.0] - 2026-06-11

First stable release.

### Added

- **`withRateLimitRetry`** — retries on HTTP 429 honoring `Retry-After`, with task-cancellation support and `invalidInput` validation for `maxAttempts`.
- `Equatable`/`Hashable`/`Identifiable`/`CaseIterable` conformances and public memberwise initializers across the response models.
- Freesound timestamps are parsed into `Date` (`createdDate`, `dateJoinedDate`, …).

### Changed

- `/` is escaped within single path segments (`encodedPathComponent`).

### Removed

- The checked-in `FreesoundKit.xcodeproj`; `*.xcodeproj/` is now gitignored.

## [0.3.1] - 2026-06-10

### Fixed

- Linux build: corelibs `URLSession` is not `Sendable`, the async `URLSession.data(for:)` is bridged, and the tester uses `FileHandle.standardError` (glibc `stderr` is not concurrency-safe).

## [0.3.0] - 2026-06-10

### Added

- `FreesoundClient` is now `Sendable` (`Mutex`-guarded `authentication`; `FreesoundHTTPClient` now requires `Sendable`).
- Pagination helpers: `page(at:)`, `nextPage(of:)`, `previousPage(of:)`.
- `combinedSearch` returns a `CombinedSearchResponse` with a `more` link, followed via `moreResults(of:)`.
- `downloadPreview(for:format:)` fetches public preview audio without OAuth.
- 429s surface as `FreesoundError.rateLimited(retryAfter:detail:)`.

### Changed

- `decodingError`/`transportError` now carry the underlying `Error`.
- `uploadSound` reads the file off the cooperative thread pool.
- Linux CI job (`swift:6.1` container); the test suite grew from 9 to 21 tests.

## [0.2.0] - 2026-06-10

### Added

- `editSound(soundID:request:)` + `SoundEditRequest` for `POST /sounds/<id>/edit/`, completing coverage of the documented API resources.
- DocC doc-comments across the public API, noting OAuth requirements per endpoint.
- `.spi.yml` to opt into Swift Package Index DocC hosting, plus compatibility badges and a terms-of-use & rate-limits section in the README.

## [0.1.1] - 2026-06-10

### Fixed

- Cross-platform builds: import `FoundationNetworking` on Linux, rename the tester entry point, and lower `swift-tools-version` to 6.0.

## [0.1.0] - 2026-06-09

Initial release.

### Added

- `FreesoundClient` with full Freesound API v2 coverage: search, sounds, users, packs, descriptors, downloads, and OAuth/token authentication.
- `Codable & Sendable` response models, the typed `FreesoundError` enum, and `SoundUploadRequest`/`SoundDescribeRequest` input structs.
- `freesound-tester` CLI executable for local smoke testing.
- Unit tests covering auth, error mapping, and endpoint behavior.
- GitHub Actions CI, an Xcode project for IDE-based development, and a README with install instructions, usage examples, and the endpoint list.

[1.2.0]: https://github.com/codybrom/FreesoundKit/compare/v1.1.0...v1.2.0
[1.1.0]: https://github.com/codybrom/FreesoundKit/compare/v1.0.1...v1.1.0
[1.0.1]: https://github.com/codybrom/FreesoundKit/compare/v1.0.0...v1.0.1
[1.0.0]: https://github.com/codybrom/FreesoundKit/compare/v0.3.1...v1.0.0
[0.3.1]: https://github.com/codybrom/FreesoundKit/compare/v0.3.0...v0.3.1
[0.3.0]: https://github.com/codybrom/FreesoundKit/compare/v0.2.0...v0.3.0
[0.2.0]: https://github.com/codybrom/FreesoundKit/compare/v0.1.1...v0.2.0
[0.1.1]: https://github.com/codybrom/FreesoundKit/compare/v0.1.0...v0.1.1
[0.1.0]: https://github.com/codybrom/FreesoundKit/releases/tag/v0.1.0
