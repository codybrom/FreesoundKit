//
//  FreesoundUsageTracker.swift
//  FreesoundKit
//
//  Created by Cody Bromley on 6/26/26.
//

import Foundation
import Synchronization

/// Which Freesound APIv2 throttle bucket a request counts against.
public enum APIUsageKind: Sendable, Equatable, Hashable, CaseIterable {
  /// Reads — search, sound/user/pack info, and downloads (the "basic" throttle).
  case standard
  /// Write actions — rate, comment, bookmark, upload, describe, edit (the "POST" throttle).
  case write
}

extension APIUsageKind: Codable {
  /// The stable string this case persists as.
  private var codableToken: String {
    switch self {
    case .standard: "standard"
    case .write: "write"
    }
  }

  public init(from decoder: Decoder) throws {
    let token = try decoder.singleValueContainer().decode(String.self)
    guard let value = Self.allCases.first(where: { $0.codableToken == token }) else {
      throw DecodingError.dataCorrupted(
        .init(codingPath: decoder.codingPath,
          debugDescription: "Unknown APIUsageKind token \"\(token)\""))
    }
    self = value
  }

  public func encode(to encoder: Encoder) throws {
    var container = encoder.singleValueContainer()
    try container.encode(codableToken)
  }
}

/// Freesound's published per-window request limits for an API credential.
///
/// The values come from the server's `APIV2_BASIC_THROTTLING_RATES_PER_LEVELS`
/// and `APIV2_POST_THROTTLING_RATES_PER_LEVELS` tables (`settings.py`), which
/// vary by the credential's level. ``level1`` is what newly registered keys get;
/// request a higher level from Freesound for ``level2`` / ``level3``.
public struct FreesoundUsageLimits: Sendable, Equatable, Hashable {
  public let standardPerMinute: Int
  public let standardPerDay: Int
  public let writePerMinute: Int
  public let writePerDay: Int

  public init(
    standardPerMinute: Int, standardPerDay: Int, writePerMinute: Int, writePerDay: Int
  ) {
    self.standardPerMinute = standardPerMinute
    self.standardPerDay = standardPerDay
    self.writePerMinute = writePerMinute
    self.writePerDay = writePerDay
  }

  /// Default level for new keys: 60/min, 2000/day reads; 30/min, 500/day writes.
  public static let level1 = FreesoundUsageLimits(
    standardPerMinute: 60, standardPerDay: 2000, writePerMinute: 30, writePerDay: 500)
  /// Raised level: 300/min, 5000/day reads; 60/min, 1000/day writes.
  public static let level2 = FreesoundUsageLimits(
    standardPerMinute: 300, standardPerDay: 5000, writePerMinute: 60, writePerDay: 1000)
  /// Highest published level: 300/min, 15000/day reads; 60/min, 3000/day writes.
  public static let level3 = FreesoundUsageLimits(
    standardPerMinute: 300, standardPerDay: 15000, writePerMinute: 60, writePerDay: 3000)

  /// The per-minute limit for `kind`.
  public func perMinute(_ kind: APIUsageKind) -> Int {
    kind == .write ? writePerMinute : standardPerMinute
  }
  /// The per-day limit for `kind`.
  public func perDay(_ kind: APIUsageKind) -> Int {
    kind == .write ? writePerDay : standardPerDay
  }
}

/// A locally estimated record of APIv2 usage, so you can show how close a
/// credential is to Freesound's published limits.
///
/// Freesound throttles on rolling windows (the last 60 seconds and the last 24
/// hours), so this keeps per-bucket request timestamps and counts those inside
/// each window. A ``FreesoundClient`` records into its
/// ``FreesoundClient/usageTracker`` automatically — once per APIv2 request,
/// classified ``APIUsageKind/write`` for POST actions and ``APIUsageKind/standard``
/// otherwise. OAuth token exchanges and CDN asset downloads aren't subject to the
/// APIv2 throttle, so they aren't counted.
///
/// This is an estimate: it can't see requests other apps make with the same
/// credential, and it counts the requests this client actually sends. The type
/// is `Sendable` and safe to read while the client records into it. Persist
/// across launches by saving ``events(_:)`` and restoring them via `init`.
public final class FreesoundUsageTracker: Sendable {
  /// The limits this tracker compares usage against.
  public let limits: FreesoundUsageLimits

  private struct State {
    var standard: [Date]
    var write: [Date]
  }
  private let state: Mutex<State>

  /// Creates a tracker, optionally seeded with persisted event timestamps.
  /// - Parameters:
  ///   - limits: The limits to compare against. Defaults to ``FreesoundUsageLimits/level1``.
  ///   - standardEvents: Restored read-request timestamps.
  ///   - writeEvents: Restored write-request timestamps.
  public init(
    limits: FreesoundUsageLimits = .level1,
    standardEvents: [Date] = [],
    writeEvents: [Date] = []
  ) {
    self.limits = limits
    self.state = Mutex(State(standard: standardEvents, write: writeEvents))
  }

  /// Records one request against `kind`, dropping anything older than 24 hours.
  public func record(_ kind: APIUsageKind, at date: Date = Date()) {
    state.withLock { state in
      switch kind {
      case .standard: state.standard.append(date)
      case .write: state.write.append(date)
      }
      Self.prune(&state, now: date)
    }
  }

  /// The number of `kind` requests within the last `seconds`, as of `now`.
  public func count(_ kind: APIUsageKind, within seconds: TimeInterval, asOf now: Date = Date())
    -> Int
  {
    let cutoff = now.addingTimeInterval(-seconds)
    return state.withLock { state in
      (kind == .write ? state.write : state.standard).reduce(0) { $0 + ($1 > cutoff ? 1 : 0) }
    }
  }

  /// The recorded event timestamps for `kind`, for persisting across launches.
  public func events(_ kind: APIUsageKind) -> [Date] {
    state.withLock { kind == .write ? $0.write : $0.standard }
  }

  /// Clears all recorded usage.
  public func reset() {
    state.withLock { $0 = State(standard: [], write: []) }
  }

  /// A point-in-time view of both buckets against their limits, for display.
  public func snapshot(asOf now: Date = Date()) -> Snapshot {
    state.withLock { state in
      Self.prune(&state, now: now)
      return Snapshot(
        standard: Self.bucket(.standard, events: state.standard, limits: limits, now: now),
        write: Self.bucket(.write, events: state.write, limits: limits, now: now))
    }
  }

  private static func bucket(
    _ kind: APIUsageKind, events: [Date], limits: FreesoundUsageLimits, now: Date
  ) -> Bucket {
    let minuteAgo = now.addingTimeInterval(-60)
    let usedThisMinute = events.reduce(0) { $0 + ($1 > minuteAgo ? 1 : 0) }
    // `events` is already pruned to the last 24 hours, so its count is today's usage.
    return Bucket(
      kind: kind, usedThisMinute: usedThisMinute, perMinute: limits.perMinute(kind),
      usedToday: events.count, perDay: limits.perDay(kind))
  }

  private static func prune(_ state: inout State, now: Date) {
    let dayAgo = now.addingTimeInterval(-86_400)
    state.standard.removeAll { $0 < dayAgo }
    state.write.removeAll { $0 < dayAgo }
  }
}

extension FreesoundUsageTracker {
  /// One throttle bucket's usage against its limits, ready for display.
  public struct Bucket: Sendable, Equatable, Hashable {
    public let kind: APIUsageKind
    public let usedThisMinute: Int
    public let perMinute: Int
    public let usedToday: Int
    public let perDay: Int

    /// Requests left in the current 60-second window (never negative).
    public var remainingThisMinute: Int { max(0, perMinute - usedThisMinute) }
    /// Requests left in the current 24-hour window (never negative).
    public var remainingToday: Int { max(0, perDay - usedToday) }
  }

  /// Both throttle buckets captured at one moment.
  public struct Snapshot: Sendable, Equatable, Hashable {
    public let standard: Bucket
    public let write: Bucket
  }
}
