//
//  FreesoundAssetCache.swift
//  FreesoundKit
//
//  Created by Cody Bromley on 6/26/26.
//

import Foundation

/// A disk-backed cache for Freesound's public binary assets — preview audio,
/// waveform/spectrogram images, and avatars.
///
/// The metadata models are `Codable`, so you can persist them yourself; this
/// caches the *bytes* those models point at. Fetches funnel through one closure
/// (by default ``FreesoundClient/downloadAsset(at:)``), so concurrent requests
/// for the same URL share a single download (in-flight de-duplication), and the
/// store is bounded by ``maxByteSize`` with least-recently-used eviction.
///
/// ```swift
/// let cache = FreesoundAssetCache(
///   client: client,
///   directory: URL.cachesDirectory.appending(path: "freesound-assets"))
/// let waveform = try await cache.imageData(for: sound)        // fetched + stored
/// let again = try await cache.imageData(for: sound)           // served from disk
/// let avatar = try await cache.avatarData(for: user.avatar!)  // avatars too
/// ```
///
/// The cache owns its ``directory`` — ``removeAll()`` deletes it wholesale, so
/// point it at a dedicated folder. Cache keys are a 64-bit FNV-1a hash of the
/// asset URL; collisions are astronomically unlikely for a local store but, as
/// with any cache, treat a hit as an optimization rather than a guarantee.
public actor FreesoundAssetCache {
  /// The default on-disk budget: 100 MB.
  public static let defaultMaxByteSize = 100 * 1024 * 1024

  /// The directory holding cached asset files. Owned exclusively by this cache.
  public let directory: URL
  /// The maximum total size of cached files in bytes. When a store would exceed
  /// it, the least-recently-used files are evicted. `0` means unlimited.
  public let maxByteSize: Int

  private let fetch: @Sendable (URL) async throws -> Data
  private let fileManager = FileManager.default
  /// In-flight downloads keyed by URL, so concurrent callers share one fetch.
  private var tasks: [URL: Task<Data, Error>] = [:]

  /// Creates a cache that fetches misses through `fetch`.
  /// - Parameters:
  ///   - directory: A dedicated folder for cached files (created on first write).
  ///   - maxByteSize: The on-disk budget in bytes; `0` for unlimited.
  ///   - fetch: How to download an asset's bytes for a given URL.
  public init(
    directory: URL,
    maxByteSize: Int = FreesoundAssetCache.defaultMaxByteSize,
    fetch: @escaping @Sendable (URL) async throws -> Data
  ) {
    self.directory = directory
    self.maxByteSize = maxByteSize
    self.fetch = fetch
  }

  /// Creates a cache that fetches misses through `client`.
  /// - Parameters:
  ///   - client: The client used to download assets (via
  ///     ``FreesoundClient/downloadAsset(at:)``).
  ///   - directory: A dedicated folder for cached files (created on first write).
  ///   - maxByteSize: The on-disk budget in bytes; `0` for unlimited.
  public init(
    client: FreesoundClient,
    directory: URL,
    maxByteSize: Int = FreesoundAssetCache.defaultMaxByteSize
  ) {
    self.init(directory: directory, maxByteSize: maxByteSize) { url in
      try await client.downloadAsset(at: url)
    }
  }

  /// Returns the bytes for `url`, fetching and storing them on a cache miss.
  ///
  /// A disk hit is returned immediately (and marked most-recently-used).
  /// Concurrent calls for the same URL await a single shared download.
  public func data(for url: URL) async throws -> Data {
    if let cached = diskData(for: url) {
      touch(url)
      return cached
    }
    if let inFlight = tasks[url] {
      return try await inFlight.value
    }
    let fetch = self.fetch
    let task = Task { try await fetch(url) }
    tasks[url] = task
    defer { tasks[url] = nil }
    let data = try await task.value
    store(data, for: url)
    return data
  }

  /// Caches the preview audio for a sound. See ``FreesoundClient/downloadPreview(for:format:)``.
  /// - Throws: ``FreesoundError/invalidInput(_:)`` if the sound has no URL for `format`.
  public func previewData(for sound: Sound, format: SoundPreviewFormat = .hqMP3)
    async throws -> Data
  {
    guard let url = sound.previews?.url(for: format) else {
      throw FreesoundError.invalidInput(
        "Sound \(sound.id) has no \(format) preview URL; include \"previews\" in the requested fields."
      )
    }
    return try await data(for: url)
  }

  /// Caches a visualization image for a sound. See ``FreesoundClient/downloadImage(for:type:)``.
  /// - Throws: ``FreesoundError/invalidInput(_:)`` if the sound has no URL for `type`.
  public func imageData(for sound: Sound, type: SoundImageType = .waveformM)
    async throws -> Data
  {
    guard let url = sound.images?.url(for: type) else {
      throw FreesoundError.invalidInput(
        "Sound \(sound.id) has no \(type) image URL; include \"images\" in the requested fields."
      )
    }
    return try await data(for: url)
  }

  /// Caches an avatar image. Works for both ``User/avatar`` and ``Me/avatar``.
  /// - Throws: ``FreesoundError/invalidInput(_:)`` if the avatar has no URL for `size`.
  public func avatarData(for avatar: Avatar, size: AvatarSize = .medium)
    async throws -> Data
  {
    guard let url = avatar.url(for: size) else {
      throw FreesoundError.invalidInput("Avatar has no \(size) URL.")
    }
    return try await data(for: url)
  }

  /// Caches a user's avatar image.
  /// - Throws: ``FreesoundError/invalidInput(_:)`` if the user has no avatar or
  ///   no URL for `size`.
  public func avatarData(for user: User, size: AvatarSize = .medium)
    async throws -> Data
  {
    guard let avatar = user.avatar else {
      throw FreesoundError.invalidInput("User \(user.username) has no avatar.")
    }
    return try await avatarData(for: avatar, size: size)
  }

  /// Caches the authenticated user's avatar image.
  /// - Throws: ``FreesoundError/invalidInput(_:)`` if the account has no avatar
  ///   or no URL for `size`.
  public func avatarData(for me: Me, size: AvatarSize = .medium)
    async throws -> Data
  {
    guard let avatar = me.avatar else {
      throw FreesoundError.invalidInput("User \(me.username) has no avatar.")
    }
    return try await avatarData(for: avatar, size: size)
  }

  /// Whether bytes for `url` are currently stored on disk.
  public func contains(_ url: URL) -> Bool {
    fileManager.fileExists(atPath: fileURL(for: url).path)
  }

  /// Removes any cached bytes for `url`. No-op if absent.
  public func removeData(for url: URL) throws {
    let path = fileURL(for: url)
    if fileManager.fileExists(atPath: path.path) {
      try fileManager.removeItem(at: path)
    }
  }

  /// Removes the entire cache directory and everything in it.
  public func removeAll() throws {
    if fileManager.fileExists(atPath: directory.path) {
      try fileManager.removeItem(at: directory)
    }
  }

  /// The total size in bytes of all cached files currently on disk.
  public func totalDiskBytes() -> Int {
    sizedEntries().reduce(0) { $0 + $1.size }
  }

  // MARK: - Disk helpers

  private func fileURL(for url: URL) -> URL {
    directory.appendingPathComponent(Self.cacheKey(for: url))
  }

  private func diskData(for url: URL) -> Data? {
    try? Data(contentsOf: fileURL(for: url))
  }

  /// Marks an entry most-recently-used by bumping its modification date.
  private func touch(_ url: URL) {
    try? fileManager.setAttributes(
      [.modificationDate: Date()], ofItemAtPath: fileURL(for: url).path)
  }

  /// Best-effort store: a write or eviction failure must not fail the fetch.
  private func store(_ data: Data, for url: URL) {
    do {
      try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
      try data.write(to: fileURL(for: url))
      evictIfNeeded(protecting: url)
    } catch {
      // Caching is an optimization; swallow so the caller still gets its bytes.
    }
  }

  private func evictIfNeeded(protecting protectedURL: URL) {
    guard maxByteSize > 0 else { return }
    var entries = sizedEntries()
    var total = entries.reduce(0) { $0 + $1.size }
    guard total > maxByteSize else { return }
    let protectedName = Self.cacheKey(for: protectedURL)
    entries.sort { $0.date < $1.date }  // least-recently-used first
    for entry in entries where total > maxByteSize {
      if entry.url.lastPathComponent == protectedName { continue }
      try? fileManager.removeItem(at: entry.url)
      total -= entry.size
    }
  }

  private func sizedEntries() -> [(url: URL, size: Int, date: Date)] {
    let keys: Set<URLResourceKey> = [.fileSizeKey, .contentModificationDateKey]
    guard
      let files = try? fileManager.contentsOfDirectory(
        at: directory, includingPropertiesForKeys: Array(keys))
    else { return [] }
    return files.map { file in
      let values = try? file.resourceValues(forKeys: keys)
      return (file, values?.fileSize ?? 0, values?.contentModificationDate ?? .distantPast)
    }
  }

  /// A filesystem-safe, deterministic, cross-platform key for an asset URL:
  /// the 64-bit FNV-1a hash of its absolute string, in hex.
  static func cacheKey(for url: URL) -> String {
    var hash: UInt64 = 0xcbf2_9ce4_8422_2325
    for byte in url.absoluteString.utf8 {
      hash ^= UInt64(byte)
      hash = hash &* 0x0000_0100_0000_01b3
    }
    return String(hash, radix: 16)
  }
}
