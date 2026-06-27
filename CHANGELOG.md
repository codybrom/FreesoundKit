# Changelog

All notable changes to FreesoundKit are documented in this file. This project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [2.0.0] - 2026-06-26

An audit of the client against the actual Freesound server source surfaced wire-level correctness fixes, read-model fidelity improvements, and new write/auth capabilities. Several changes are source-breaking — see **Migration** below.

### Added

- **`similaritySearch(toVector:space:parameters:)`** — search by a raw embedding vector. The server's `similar_to` accepts a JSON-serialized vector (`[v1, v2, …]`, 5-decimal components) in place of a sound id. Validates the vector is non-empty and finite, throwing `invalidInput` otherwise.
- **`exchangePasswordGrant(clientID:clientSecret:username:password:)`** — the OAuth2 Resource Owner Password Credentials grant, for the (rare) credentials Freesound has enabled `allow_oauth_password_grant` for.
- **`OAuthScope`** and a `scopes:` parameter on `oauthAuthorizationURL(…)` — request a least-privilege token (e.g. `[.read]`) instead of the server default (read+write).
- **`FreesoundError.oauthError(error:description:statusCode:)`** — the OAuth token endpoint's structured `{"error", "error_description"}` envelope is surfaced as its own case, so callers can branch on `invalid_grant` (refresh expired → re-authorize) vs `invalid_client` without string-matching.
- **`FreesoundError.throttleScope`** / **`APIThrottleScope`** — classify a 429 as per-minute / per-hour / per-day or a suspended credential. `withRateLimitRetry` now skips retries that cannot clear in time (per-hour, per-day, suspended); it still retries per-minute and unrecognized throttles.
- **`APIStatusResponse.id`** — `describeSound(request:)` surfaces the newly described sound's id. Since pending uploads are keyed by filename, the describe response is the only place that id appears.
- **`OAuthTokenResponse.tokenType`** — the `token_type` field (typically `"Bearer"`).
- **`Sound` decodes the search serializer's `sim_`-prefixed similarity embeddings.** The Sound serializer emits embeddings `sim_`-prefixed (`sim_laion_clap`); they now decode onto `SoundDescriptors.laionClap`/`freesoundClassic`/`freesoundClassicV1`, alongside the unprefixed spelling the `/analysis/` endpoint uses. Re-encoding always writes the canonical unprefixed key.
- **Client-side tag-count validation.** `uploadSound`/`describeSound`/`editSound` throw `invalidInput` when the encoded tag count is outside the server's 3–30 range, failing fast like `rateSound`'s rating check rather than round-tripping to a 400.
- **Documentation** for advanced search features already reachable through `parameters:` — `group_by_pack`, per-field `weights`, geospatial `filter`, descriptor-proximity `sort` targets, and the `fields` magic tokens (`*`, `all_descriptors`, `all_similarity_spaces`) — plus the synthesized `id == 0` "Uncategorized" bookmark bucket and the 409 returned when re-rating a sound.

### Changed

- **`similaritySearch(toSoundID:space:)` now sends the `similarity_space` query field** — it previously sent `similar_space`, which the server silently dropped, so a non-default `space` had no effect and results fell back to the default space with no error. Non-default spaces now actually take effect.
- **The write request structs take a typed `SoundLicense` instead of a `String` `license`** (`SoundUploadRequest`/`SoundDescribeRequest` require it; `SoundEditRequest` is optional). The API validates an exact set, so the enum prevents a silent 400. _(breaking)_
- **`SoundUploadRequest.bstCategory` is now required** — uploading with a description always requires it server-side — and **`SoundDescribeRequest.bstCategory` is now optional**, matching the describe endpoint. Both initializers' parameter order changed accordingly. _(breaking)_
- **`Sound.samplerate` is now `Double?`** (was `Int?`); the server field is a float (e.g. `48000.0`). _(breaking)_
- **`PendingUpload` now models the real `/me/pending_uploads/` shape** — `id`, `name`, `tags`, `description`, `created`, `license`, `processingState`, `images` — replacing the previous `filename`/`originalFilename`/`uploadDate`/`status`/`detail`/`sound` fields, of which only `id` was ever populated. _(breaking)_
- **`FreesoundError` gained the `oauthError` case** — exhaustive `switch`es over it must add a branch. _(breaking)_

### Removed

- **Fields the API never returns** (they always decoded to `nil`): `Comment.id`, `Comment.url`, `UploadSoundResponse.uploadURL`, `UploadSoundResponse.sound`. _(breaking)_

### Fixed

- **Similarity search silently ignored the requested space** — the `similar_space` → `similarity_space` query-key bug above. A passing test had locked the wrong key in place.
- **A search/similarity page containing a `null` result no longer fails to decode.** The server appends JSON `null` for sounds desynced between the search index and the database; `PagedResponse` now drops the nulls and keeps the valid results instead of throwing and losing the whole page.
- **`sim_`-prefixed similarity embeddings now decode** (previously only the unprefixed `/analysis/` spelling did, so embeddings requested via search/detail decoded to `nil`).

### Migration

- Pass `SoundLicense` cases instead of license strings: `license: "Creative Commons 0"` → `license: .creativeCommons0`.
- `SoundUploadRequest(…)` now requires `bstCategory:`; `SoundDescribeRequest(…)` no longer requires it. Both initializers reordered — use argument labels (you likely already do).
- `Sound.samplerate` is `Double?`; update any `Int` bindings or comparisons.
- Re-decode any persisted `PendingUpload`; its fields changed.
- Handle the new `FreesoundError.oauthError` case in exhaustive `switch`es.
- `Comment` and `UploadSoundResponse` no longer expose the removed always-`nil` fields.

## [1.3.1] - 2026-06-26

### Added

- **`Codable` on the value enums.** `SoundSearchSort`, `SoundLicense`, `SimilaritySpace`, `SoundPreviewFormat`, `SoundImageType`, `AvatarSize`, and `APIUsageKind` now conform to `Codable`, so a consumer type that stores one — e.g. a persisted saved-search `sort` — synthesizes `Codable` automatically instead of needing a `@retroactive Codable` workaround (which would collide the moment the conformance is added upstream). This completes the 1.2.0 move that made the response models `Codable`. The `String`-raw enums encode as their exact API token (`"downloads_desc"`, `"Creative Commons 0"`, `"laion_clap"`); the four remaining selector enums encode as stable lowercase tokens via a single-value container (e.g. `"hq-mp3"`, `"waveform_l"`), not the synthesized `{"case":{}}` shape, and decoding an unrecognized token throws.

## [1.3.0] - 2026-06-26

Audited the full client surface against the Freesound server source (`apiv2/urls.py`, `views.py`, `serializers.py`) and verified the models against the live API. Coverage was already near-complete; this closes the remaining gaps.

### Added

- **`soundDownloadLink(id:)`** maps the `sounds/<id>/download/link/` endpoint, returning a `SoundDownloadLink` whose URL carries a signed, time-limited token. Unlike `downloadOriginalSound(id:)`, the URL needs no `Authorization` header, so it can be handed to `AVPlayer`, a background `URLSession` download task, or `WKWebView`.
- **`Sound.score`** — the search-relevance score the API emits on search/similarity results.
- **`BookmarkCategory.sounds`** — the category's sounds URL, emitted by the bookmark-category serializer.
- **`SoundSearchSort`** — a typed enum of the `sort` values accepted by `textSearch`. The API silently falls back to `score` on an unrecognized value, so these constants guard against typos (e.g. `downloads_desc`, not `num_downloads desc`).
- **`FreesoundUsageMonitor`** — an opt-in `@MainActor @Observable` companion over the (still-`Sendable`) `FreesoundUsageTracker`. It re-snapshots on a timer (the rolling windows decay with wall-clock time) so SwiftUI views can observe `snapshot` directly, and only publishes when the snapshot actually changes so an idle meter doesn't wake SwiftUI every tick. The tracker itself is unchanged.
- **`SoundLicense`** — a typed enum of the three `license` values the upload/describe/edit endpoints accept (e.g. `creativeCommons0` is `"Creative Commons 0"`, not `"CC0"`). The API validates the exact string, so a typo is a 400.
- **Search pack-grouping and similarity fields.** `Sound` now decodes `moreFromSamePack`/`nFromSamePack` (present per result when searching with `group_by_pack=1`) and `distanceToTarget` (present with `similar_to`), and `PagedResponse` decodes the search-level `note`. All are optional and round-trip through `Codable`.

### Changed

- Documented that `Pack.download` is not emitted by the current Freesound pack serializer (typically `nil`); use `downloadPack(id:)`.
- Documented the geotag read/write format asymmetry: `Sound.geotag` is space-separated `"lat lon"`, but the upload/describe/edit endpoints require comma-separated `"lat,lon,zoom"` (`zoom` ≥ 11), so a read value can't be round-tripped into a request unchanged. The request structs' `geotag`/`license`/`tags` fields now document their server constraints.
- Documented that `SoundEditRequest.bstCategory` is currently ignored by the Freesound edit endpoint (its request serializer omits the `bst_category` declaration); describe/upload accept it normally.

### Fixed

- **API error messages no longer collapse to "Unknown error."** The write endpoints return `{"detail": {<field>: [messages]}}` for 400 validation failures, but the error mapper only decoded a string `detail`, so those messages were lost. It now flattens field-error maps (e.g. `tags: You should add at least 3 tags.`) and falls back to the raw response body, reserving "Unknown error" for a genuinely empty body.

### Deprecated

- **`bookmarkSound(soundID:name:category:)`** — the Freesound bookmark endpoint's request serializer reads only `category`, so the `name` argument was being silently dropped on the wire. Use `bookmarkSound(soundID:category:)`. The deprecated overload now forwards to it and no longer sends `name`.
- **`soundAnalysis(id:descriptors:normalized:)`** — the analysis endpoint no longer reads `descriptors` or `normalized` (it always returns the full consolidated analysis), so those arguments were ignored. Use `soundAnalysis(id:)`; the deprecated overload forwards to it and sends no query.

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
