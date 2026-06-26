# Changelog

All notable changes to FreesoundKit are documented in this file. This project
adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.2.0]

### Added

- **`Codable` response models.** Every response model now conforms to `Codable`
  (previously `Decodable`-only), so results can be cached or persisted between
  launches with `JSONEncoder`/`JSONDecoder`. `Sound` and `SoundAnalysis`
  re-flatten their audio descriptors on encode to mirror the API's shape, and
  `PagedResponse` is `Encodable` when its element type is. Round-trips are
  lossless by value, verified against a live API response.
- **Image and asset downloads.** `downloadImage(for:type:)` fetches a sound's
  waveform/spectrogram, and `downloadAsset(at:)` fetches any public Freesound
  CDN asset URL without authentication. Adds `SoundImageType` and `url(for:)`
  accessors on `SoundPreviews` and `SoundImages`.
- **`FreesoundAssetCache`.** A disk-backed actor that caches preview audio,
  images, and avatars: fetch on miss, serve from disk on hit, in-flight
  de-duplication of concurrent requests, and least-recently-used eviction under
  a byte budget. Cross-platform (no CryptoKit).
- **`AvatarMonogram`.** A deterministic, network-free default-avatar fallback —
  the username's first letter over a palette color — reproducing freesound.org's
  own rendering exactly, with `User`/`Me` accessors and an `RGBColor` value type.
- **`FreesoundUsageTracker`.** Automatic APIv2 rate-limit usage tracking against
  Freesound's published per-window throttle limits (read vs write buckets, per
  minute and per day, by credential level). A client records each APIv2 request
  automatically at its single request chokepoint; `snapshot()` exposes remaining
  quota for display.

[1.2.0]: https://github.com/codybrom/FreesoundKit/compare/v1.1.0...v1.2.0
