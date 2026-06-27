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
