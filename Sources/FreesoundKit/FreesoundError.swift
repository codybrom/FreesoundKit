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
    case apiError(statusCode: Int, detail: String)
    case decodingError(String)
    case transportError(String)

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
        case .decodingError(let message):
            return "Failed to decode Freesound response: \(message)"
        case .transportError(let message):
            return "Transport error: \(message)"
        }
    }
}
