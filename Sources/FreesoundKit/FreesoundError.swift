//
//  FreesoundError.swift
//  FreesoundKit
//
//  Created by Cody Bromley on 6/9/26.
//

import Foundation

public enum FreesoundError: Error, LocalizedError {
  case invalidBaseURL(String)
  case invalidResponse
  case invalidInput(String)
  case oauthRequired
  /// The API rejected the request with a non-2xx status (other than 429,
  /// which is surfaced as ``rateLimited(retryAfter:detail:)``).
  case apiError(statusCode: Int, detail: String)
  /// The API throttled the request (HTTP 429). `retryAfter` is the suggested
  /// wait in seconds, when the API provides a `Retry-After` header. Inspect
  /// ``throttleScope`` to tell a per-minute throttle (clears quickly) from a
  /// per-day or suspended-credential one (a short retry is futile).
  case rateLimited(retryAfter: TimeInterval?, detail: String)
  /// The OAuth2 token endpoint rejected the request with its structured
  /// `{"error", "error_description"}` envelope (e.g. `error == "invalid_grant"`
  /// when a refresh token has expired — re-authorize). Distinct from
  /// ``apiError(statusCode:detail:)`` so callers can branch on `error` without
  /// string-matching.
  case oauthError(error: String, description: String?, statusCode: Int)
  /// The response body could not be decoded. Carries the underlying error
  /// (typically a `DecodingError`).
  case decodingError(any Error)
  /// The request failed before an HTTP response was received. Carries the
  /// underlying error (typically a `URLError`).
  case transportError(any Error)

  public var errorDescription: String? {
    switch self {
    case .invalidBaseURL(let url):
      return "Invalid Freesound base URL: \(url)"
    case .invalidResponse:
      return "Received an invalid response from Freesound."
    case .invalidInput(let message):
      return "Invalid input: \(message)"
    case .oauthRequired:
      return "This endpoint requires OAuth2 authentication."
    case .apiError(let statusCode, let detail):
      return "Freesound API error (\(statusCode)): \(detail)"
    case .rateLimited(let retryAfter, let detail):
      if let retryAfter {
        return "Freesound rate limit exceeded (retry after \(Int(retryAfter))s): \(detail)"
      }
      return "Freesound rate limit exceeded: \(detail)"
    case .oauthError(let error, let description, let statusCode):
      if let description {
        return "Freesound OAuth error (\(statusCode)): \(error) — \(description)"
      }
      return "Freesound OAuth error (\(statusCode)): \(error)"
    case .decodingError(let underlying):
      return "Failed to decode Freesound response: \(String(describing: underlying))"
    case .transportError(let underlying):
      return "Transport error: \(String(describing: underlying))"
    }
  }

  /// For a ``rateLimited(retryAfter:detail:)`` error, the throttle window parsed
  /// from the server's message (`nil` for any other error or an unrecognized
  /// message). A ``APIThrottleScope/perMinute`` throttle clears within the minute,
  /// so retrying is worthwhile; ``APIThrottleScope/perDay``,
  /// ``APIThrottleScope/perHour``, and ``APIThrottleScope/suspended`` will not
  /// clear on a short retry. ``FreesoundClient/withRateLimitRetry(maxAttempts:fallbackDelay:maxDelay:operation:)``
  /// uses this to avoid futile retries.
  public var throttleScope: APIThrottleScope? {
    guard case .rateLimited(_, let detail) = self else { return nil }
    let message = detail.lowercased()
    if message.contains("suspended") { return .suspended }
    if message.contains("/day") { return .perDay }
    if message.contains("/hour") { return .perHour }
    if message.contains("/minute") { return .perMinute }
    return nil
  }

  /// For a ``rateLimited(retryAfter:detail:)`` error, the actual configured limit
  /// parsed from the server's throttle message (`nil` for any other error, a
  /// suspended-credential message, or an unrecognized format).
  ///
  /// Freesound phrases the credential throttle as `"…request limit rate
  /// (5000/day)"`, so this recovers both the count and the window — the only
  /// place the API ever discloses your credential's real limit.
  /// ``FreesoundUsageTracker`` uses it to reconcile its assumed limits with
  /// reality (``FreesoundUsageTracker/observeThrottle(_:kind:)``).
  ///
  /// Returns `nil` unless the message is the per-credential **request-limit**
  /// throttle. This deliberately excludes Freesound's IP/concurrency throttle
  /// (`"…concurrent ip limit rate …"`), whose number is unrelated to your
  /// credential's quota — mistaking it for the quota could revise the tracked
  /// limit *down* and throttle a user who isn't actually near their limit. It
  /// fails safe: an unrecognized wording yields `nil` (no reconciliation) rather
  /// than a wrong number.
  public var throttleLimit: ParsedThrottleLimit? {
    guard case .rateLimited(_, let detail) = self else { return nil }
    let message = detail.lowercased()
    // Only the per-credential request-limit throttle reflects your quota.
    guard message.contains("request limit rate") else { return nil }
    let units: [(needle: String, scope: APIThrottleScope)] = [
      ("/minute", .perMinute), ("/hour", .perHour), ("/day", .perDay),
    ]
    for (needle, scope) in units {
      guard let unitRange = message.range(of: needle) else { continue }
      // Walk backwards over the digits immediately preceding the unit.
      var index = unitRange.lowerBound
      var digits = ""
      while index > message.startIndex {
        let prev = message.index(before: index)
        guard message[prev].isNumber else { break }
        digits.insert(message[prev], at: digits.startIndex)
        index = prev
      }
      if let count = Int(digits) { return ParsedThrottleLimit(count: count, scope: scope) }
    }
    return nil
  }
}

/// The configured rate limit parsed from a Freesound 429 message via
/// ``FreesoundError/throttleLimit`` — a request `count` per `scope` window.
public struct ParsedThrottleLimit: Sendable, Equatable, Hashable {
  /// The maximum requests the window allows (e.g. `5000`).
  public let count: Int
  /// The window the limit applies to (``APIThrottleScope/perMinute``,
  /// ``APIThrottleScope/perHour``, or ``APIThrottleScope/perDay``).
  public let scope: APIThrottleScope

  public init(count: Int, scope: APIThrottleScope) {
    self.count = count
    self.scope = scope
  }
}

/// The window a Freesound 429 throttle applies to, parsed from the server's
/// throttle message via ``FreesoundError/throttleScope``.
public enum APIThrottleScope: Sendable, Equatable, Hashable {
  /// A per-minute rate limit — clears within the minute, so retrying helps.
  case perMinute
  /// A per-hour rate limit.
  case perHour
  /// A per-day rate limit — a short retry will not clear it.
  case perDay
  /// The API credential has been suspended — retrying will not help.
  case suspended
}
