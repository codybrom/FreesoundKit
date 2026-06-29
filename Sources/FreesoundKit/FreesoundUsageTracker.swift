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
        .init(
          codingPath: decoder.codingPath,
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

  /// Returns a copy with the given fields replaced (others left unchanged).
  public func with(
    standardPerMinute: Int? = nil, standardPerDay: Int? = nil,
    writePerMinute: Int? = nil, writePerDay: Int? = nil
  ) -> FreesoundUsageLimits {
    FreesoundUsageLimits(
      standardPerMinute: standardPerMinute ?? self.standardPerMinute,
      standardPerDay: standardPerDay ?? self.standardPerDay,
      writePerMinute: writePerMinute ?? self.writePerMinute,
      writePerDay: writePerDay ?? self.writePerDay)
  }
}

/// A locally estimated record of APIv2 usage, so you can observe how close a
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
///
/// > Important: ``limits`` begins as an **unconfirmed assumption** — the level
/// > you passed to `init` (default ``FreesoundUsageLimits/level1``). The API has
/// > no endpoint that reveals your credential's real level; the only API signal
/// > is a 429, which ``observeThrottle(_:kind:)`` uses to correct ``limits``.
/// > So treat the limits as advisory until then, and **do not hard-block requests
/// > on the assumed ceiling.** If your app refuses to send once `snapshot()`
/// > reports a bucket exhausted, an account that is actually on a higher level
/// > would cap itself at the assumed level-1 numbers and never hit the real 429
/// > that would reveal the truth — a self-fulfilling under-estimate. And a level
/// > can change over time, so even a value learned from a real 429 is provisional
/// > (the newest throttle supersedes it, up or down) and can go stale between
/// > throttles. Treat these numbers as advisory always: use the snapshot to
/// > inform/warn, let real 429s do the enforcing, and consult the web
/// > API-credentials dashboard for the authoritative level.
public final class FreesoundUsageTracker: Sendable {
  /// The limits this tracker compares usage against. Starts at the value passed
  /// to `init` (an **unconfirmed assumption**) and is corrected toward reality by
  /// ``observeThrottle(_:kind:)`` as the server reveals real limits via 429s. See
  /// the type's note before gating requests on these values.
  public var limits: FreesoundUsageLimits { state.withLock(\.limits) }

  private struct State {
    var standard: [Date]
    var write: [Date]
    var limits: FreesoundUsageLimits
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
    self.state = Mutex(State(standard: standardEvents, write: writeEvents, limits: limits))
  }

  /// Reconciles the tracked ``limits`` with a real limit the server disclosed in
  /// a 429 throttle response, the only place the API reveals your credential's
  /// actual quota. Pass the thrown ``FreesoundError`` and the request ``kind``
  /// that was throttled; the matching per-minute/per-day field is updated.
  ///
  /// A ``FreesoundClient`` with a configured ``FreesoundClient/usageTracker``
  /// calls this automatically when a request is throttled, so apps that start at
  /// the wrong assumed level converge to their true limits without intervention.
  ///
  /// The newest throttle always wins, revising the limit **up or down** — your
  /// credential's level can change over time, so no single observation is treated
  /// as permanent. Learned limits live only for this tracker's lifetime (they
  /// aren't part of ``events(_:)`` persistence), so a relaunch starts from the
  /// assumed `init` value and re-learns — which also means a stale learned level
  /// is never carried indefinitely. Only the credential request-limit throttle is
  /// honored; IP/concurrency throttles are ignored (see
  /// ``FreesoundError/throttleLimit``).
  /// - Returns: `true` if a limit changed; `false` if the error carried no
  ///   parseable credential limit, or the value already matched.
  @discardableResult
  public func observeThrottle(_ error: FreesoundError, kind: APIUsageKind) -> Bool {
    guard let limit = error.throttleLimit else { return false }
    return state.withLock { state in
      let updated: FreesoundUsageLimits
      switch (kind, limit.scope) {
      case (.standard, .perMinute): updated = state.limits.with(standardPerMinute: limit.count)
      case (.standard, .perDay): updated = state.limits.with(standardPerDay: limit.count)
      case (.write, .perMinute): updated = state.limits.with(writePerMinute: limit.count)
      case (.write, .perDay): updated = state.limits.with(writePerDay: limit.count)
      // The level tables have only per-minute and per-day limits; a per-hour
      // throttle (or suspended credential) maps to no field to reconcile.
      case (_, .perHour), (_, .suspended): return false
      }
      guard updated != state.limits else { return false }
      state.limits = updated
      return true
    }
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

  /// Clears all recorded usage. Keeps any limits learned via
  /// ``observeThrottle(_:kind:)``.
  public func reset() {
    state.withLock { $0 = State(standard: [], write: [], limits: $0.limits) }
  }

  /// A point-in-time view of both buckets against their limits, for display.
  public func snapshot(asOf now: Date = Date()) -> Snapshot {
    state.withLock { state in
      Self.prune(&state, now: now)
      return Snapshot(
        standard: Self.bucket(.standard, events: state.standard, limits: state.limits, now: now),
        write: Self.bucket(.write, events: state.write, limits: state.limits, now: now))
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
