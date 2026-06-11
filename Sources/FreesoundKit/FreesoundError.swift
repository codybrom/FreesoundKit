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
    /// wait in seconds, when the API provides a `Retry-After` header.
    case rateLimited(retryAfter: TimeInterval?, detail: String)
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
        case .decodingError(let underlying):
            return "Failed to decode Freesound response: \(String(describing: underlying))"
        case .transportError(let underlying):
            return "Transport error: \(String(describing: underlying))"
        }
    }
}
