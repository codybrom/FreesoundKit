//
//  FreesoundKitTests.swift
//  FreesoundKitTests
//
//  Created by Cody Bromley on 6/9/26.
//

import Foundation
import FreesoundKit
import Synchronization
import Testing

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

@Test func textSearchUsesTokenAuthHeader() async throws {
  let mockSession = MockHTTPClient { request in
    #expect(request.url?.path == "/apiv2/search/text")
    #expect(request.value(forHTTPHeaderField: "Authorization") == "Token test-key")
    #expect(request.url?.query?.contains("query=piano") == true)

    let responseJSON =
      #"{"count":1,"next":null,"previous":null,"results":[{"id":42,"name":"Piano hit"}]}"#
    return (Data(responseJSON.utf8), makeResponse())
  }

  let client = FreesoundClient(authentication: .apiKey("test-key"), session: mockSession)
  let result = try await client.textSearch(query: "piano")

  #expect(result.results.count == 1)
  #expect(result.results.first?.id == 42)
}

@Test func oauthEndpointRequiresOAuthToken() async throws {
  let client = FreesoundClient(authentication: .apiKey("token"), session: MockHTTPClient.unused)
  do {
    _ = try await client.me()
    Issue.record("Expected oauthRequired error")
  } catch let error as FreesoundError {
    switch error {
    case .oauthRequired:
      break
    default:
      Issue.record("Expected oauthRequired, got \(error)")
    }
  }
}

@Test func meUsesBearerHeader() async throws {
  let mockSession = MockHTTPClient { request in
    #expect(request.url?.path == "/apiv2/me")
    #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer oauth-token")

    let responseJSON =
      #"{"username":"alice","url":"https://freesound.org/people/alice/","about":"hello"}"#
    return (Data(responseJSON.utf8), makeResponse())
  }

  let client = FreesoundClient(authentication: .oauthToken("oauth-token"), session: mockSession)
  let me = try await client.me()
  #expect(me.username == "alice")
}

@Test func buildsAuthorizationURL() throws {
  let client = FreesoundClient(session: MockHTTPClient.unused)
  let url = try client.oauthAuthorizationURL(
    clientID: "abc123", responseState: "xyz", forceLogin: true)
  let absolute = url.absoluteString
  #expect(absolute.contains("/oauth2/logout_and_authorize/"))
  #expect(absolute.contains("client_id=abc123"))
  #expect(absolute.contains("response_type=code"))
  #expect(absolute.contains("state=xyz"))
}

@Test func exchangesAuthorizationCode() async throws {
  let mockSession = MockHTTPClient { request in
    #expect(request.httpMethod == "POST")
    #expect(request.url?.path == "/apiv2/oauth2/access_token")
    #expect(
      request.value(forHTTPHeaderField: "Content-Type") == "application/x-www-form-urlencoded"
    )
    let body = String(data: request.httpBody ?? Data(), encoding: .utf8) ?? ""
    #expect(body.contains("grant_type=authorization_code"))
    #expect(body.contains("code=temp-code"))

    let responseJSON =
      #"{"access_token":"a1","scope":"read write","expires_in":86399,"refresh_token":"r1"}"#
    return (Data(responseJSON.utf8), makeResponse())
  }

  let client = FreesoundClient(session: mockSession)
  let token = try await client.exchangeAuthorizationCode(
    clientID: "id", clientSecret: "secret", code: "temp-code")

  #expect(token.accessToken == "a1")
  #expect(token.refreshToken == "r1")
}

@Test func mapsDetailFromAPIError() async throws {
  let mockSession = MockHTTPClient { _ in
    let responseJSON = #"{"detail":"Invalid token"}"#
    return (Data(responseJSON.utf8), makeResponse(status: 400))
  }
  let client = FreesoundClient(session: mockSession)

  do {
    _ = try await client.textSearch(query: "bird")
    Issue.record("Expected API error")
  } catch let error as FreesoundError {
    switch error {
    case .apiError(let statusCode, let detail):
      #expect(statusCode == 400)
      #expect(detail == "Invalid token")
    default:
      Issue.record("Expected apiError, got \(error)")
    }
  }
}

@Test func bookmarkUsesOAuthAndPostBody() async throws {
  let mockSession = MockHTTPClient { request in
    #expect(request.httpMethod == "POST")
    #expect(request.url?.path == "/apiv2/sounds/99/bookmark")
    #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer oauth-token")
    let body = String(data: request.httpBody ?? Data(), encoding: .utf8) ?? ""
    #expect(body.contains("category=favorites"))
    let responseJSON = #"{"detail":"ok","status":"created"}"#
    return (Data(responseJSON.utf8), makeResponse())
  }

  let client = FreesoundClient(authentication: .oauthToken("oauth-token"), session: mockSession)
  let response = try await client.bookmarkSound(soundID: 99, category: "favorites")
  #expect(response.detail == "ok")
}

@Test func editSoundUsesOAuthAndSendsOnlySetFields() async throws {
  let mockSession = MockHTTPClient { request in
    #expect(request.httpMethod == "POST")
    #expect(request.url?.path == "/apiv2/sounds/42/edit")
    #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer oauth-token")
    let body = String(data: request.httpBody ?? Data(), encoding: .utf8) ?? ""
    #expect(body.contains("name=New+title"))
    #expect(body.contains("tags=field+recording"))
    // Unset fields must not be sent (partial update).
    #expect(!body.contains("description="))
    #expect(!body.contains("license="))
    let responseJSON = #"{"detail":"ok"}"#
    return (Data(responseJSON.utf8), makeResponse())
  }

  let client = FreesoundClient(authentication: .oauthToken("oauth-token"), session: mockSession)
  let response = try await client.editSound(
    soundID: 42,
    request: SoundEditRequest(name: "New title", tags: ["field", "recording"])
  )
  #expect(response.detail == "ok")
}

@Test func ratingValidatesRange() async throws {
  let client = FreesoundClient(
    authentication: .oauthToken("oauth-token"), session: MockHTTPClient.unused)
  do {
    _ = try await client.rateSound(soundID: 1, rating: 9)
    Issue.record("Expected invalidInput")
  } catch let error as FreesoundError {
    switch error {
    case .invalidInput:
      break
    default:
      Issue.record("Expected invalidInput, got \(error)")
    }
  }
}

@Test func soundDecodesFlattenedDescriptors() async throws {
  let mockSession = MockHTTPClient { request in
    #expect(request.url?.path == "/apiv2/sounds/7")
    let responseJSON = #"""
      {"id":7,"name":"Kick","duration":0.5,
       "brightness":42.5,"bpm":120,"loopable":true,"tonality":"C minor",
       "beat_times":[0.1,0.2],"note_name":"C3"}
      """#
    return (Data(responseJSON.utf8), makeResponse())
  }

  let client = FreesoundClient(authentication: .apiKey("k"), session: mockSession)
  let sound = try await client.sound(id: 7)

  #expect(sound.name == "Kick")
  #expect(sound.duration == 0.5)
  #expect(sound.descriptors.brightness == 42.5)
  #expect(sound.descriptors.bpm == 120)
  #expect(sound.descriptors.loopable == true)
  #expect(sound.descriptors.tonality == "C minor")
  #expect(sound.descriptors.beatTimes == [0.1, 0.2])
  #expect(sound.descriptors.noteName == "C3")
}

@Test func soundAnalysisDecodesDescriptorsAndQuery() async throws {
  let mockSession = MockHTTPClient { request in
    #expect(request.url?.path == "/apiv2/sounds/7/analysis")
    let query = request.url?.query ?? ""
    #expect(query.contains("descriptors=loudness"))
    #expect(query.contains("normalized=1"))
    return (Data(#"{"loudness":-23.1,"single_event":true}"#.utf8), makeResponse())
  }

  let client = FreesoundClient(authentication: .apiKey("k"), session: mockSession)
  let analysis = try await client.soundAnalysis(id: 7, descriptors: "loudness", normalized: true)

  #expect(analysis.descriptors.loudness == -23.1)
  #expect(analysis.descriptors.singleEvent == true)
}

@Test func downloadOriginalSoundReturnsRawData() async throws {
  let audio = Data([0x00, 0x01, 0x02, 0x03])
  let mockSession = MockHTTPClient { request in
    #expect(request.url?.path == "/apiv2/sounds/7/download")
    #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer oauth-token")
    #expect(request.value(forHTTPHeaderField: "Accept") == "*/*")
    return (audio, makeResponse())
  }

  let client = FreesoundClient(authentication: .oauthToken("oauth-token"), session: mockSession)
  let data = try await client.downloadOriginalSound(id: 7)
  #expect(data == audio)
}

@Test func downloadRequiresOAuth() async throws {
  let client = FreesoundClient(authentication: .apiKey("k"), session: MockHTTPClient.unused)
  do {
    _ = try await client.downloadOriginalSound(id: 7)
    Issue.record("Expected oauthRequired error")
  } catch let error as FreesoundError {
    guard case .oauthRequired = error else {
      Issue.record("Expected oauthRequired, got \(error)")
      return
    }
  }
}

@Test func uploadSoundBuildsMultipartBody() async throws {
  let fileURL = FileManager.default.temporaryDirectory
    .appendingPathComponent("freesoundkit-test-\(UUID().uuidString).wav")
  let fileBytes = Data([0x52, 0x49, 0x46, 0x46])
  try fileBytes.write(to: fileURL)
  defer { try? FileManager.default.removeItem(at: fileURL) }

  let mockSession = MockHTTPClient { request in
    #expect(request.httpMethod == "POST")
    #expect(request.url?.path == "/apiv2/sounds/upload")
    #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer oauth-token")
    let contentType = request.value(forHTTPHeaderField: "Content-Type") ?? ""
    #expect(contentType.hasPrefix("multipart/form-data; boundary="))
    let boundary = contentType.replacingOccurrences(
      of: "multipart/form-data; boundary=", with: "")
    let body = request.httpBody ?? Data()
    let bodyString = String(decoding: body, as: UTF8.self)
    #expect(bodyString.contains("--\(boundary)\r\n"))
    #expect(bodyString.contains("name=\"description\""))
    #expect(bodyString.contains("filename=\"\(fileURL.lastPathComponent)\""))
    #expect(bodyString.contains("Content-Type: audio/wav"))
    #expect(body.range(of: fileBytes) != nil)
    #expect(bodyString.hasSuffix("--\(boundary)--\r\n"))
    let responseJSON = #"{"id":123,"detail":"File successfully uploaded"}"#
    return (Data(responseJSON.utf8), makeResponse(status: 201))
  }

  let client = FreesoundClient(authentication: .oauthToken("oauth-token"), session: mockSession)
  let response = try await client.uploadSound(
    fileURL: fileURL,
    request: SoundUploadRequest(
      tags: ["test"], description: "A test clip", license: "Creative Commons 0")
  )
  #expect(response.id == 123)
}

@Test func uploadEscapesSpecialCharactersInFilename() async throws {
  // A double-quote is legal in a filename on macOS/Linux; it must be escaped so
  // it can't terminate the quoted-string `filename="..."` parameter.
  let fileURL = FileManager.default.temporaryDirectory
    .appendingPathComponent("a\"b-\(UUID().uuidString).wav")
  let fileBytes = Data([0x52, 0x49, 0x46, 0x46])
  try fileBytes.write(to: fileURL)
  defer { try? FileManager.default.removeItem(at: fileURL) }

  let mockSession = MockHTTPClient { request in
    let bodyString = String(decoding: request.httpBody ?? Data(), as: UTF8.self)
    #expect(bodyString.contains("filename=\"a\\\"b-"))
    let responseJSON = #"{"id":1,"detail":"File successfully uploaded"}"#
    return (Data(responseJSON.utf8), makeResponse(status: 201))
  }

  let client = FreesoundClient(authentication: .oauthToken("oauth-token"), session: mockSession)
  _ = try await client.uploadSound(
    fileURL: fileURL,
    request: SoundUploadRequest(
      tags: ["test"], description: "A test clip", license: "Creative Commons 0"))
}

@Test func multiWordTagsJoinWithDashesAndDoNotSplit() async throws {
  let mockSession = MockHTTPClient { request in
    let body = String(data: request.httpBody ?? Data(), encoding: .utf8) ?? ""
    // "field recording" is one tag (internal space -> dash); separate tags stay
    // space-delimited (form-encoded as '+').
    #expect(body.contains("tags=field-recording+nature"))
    return (Data(#"{"detail":"ok"}"#.utf8), makeResponse())
  }

  let client = FreesoundClient(authentication: .oauthToken("oauth-token"), session: mockSession)
  let response = try await client.editSound(
    soundID: 7,
    request: SoundEditRequest(tags: ["field recording", "nature"])
  )
  #expect(response.detail == "ok")
}

@Test func nonJSONErrorBodyFallsBackToUnknownDetail() async throws {
  let mockSession = MockHTTPClient { _ in
    (Data("gateway timeout".utf8), makeResponse(status: 502))
  }
  let client = FreesoundClient(session: mockSession)

  do {
    _ = try await client.textSearch(query: "bird")
    Issue.record("Expected API error")
  } catch let error as FreesoundError {
    guard case .apiError(let statusCode, let detail) = error else {
      Issue.record("Expected apiError, got \(error)")
      return
    }
    #expect(statusCode == 502)
    #expect(detail == "Unknown error")
  }
}

@Test func rateLimitedMapsRetryAfter() async throws {
  let mockSession = MockHTTPClient { _ in
    let responseJSON = #"{"detail":"Request was throttled"}"#
    return (
      Data(responseJSON.utf8), makeResponse(status: 429, headers: ["Retry-After": "12"])
    )
  }
  let client = FreesoundClient(authentication: .apiKey("k"), session: mockSession)

  do {
    _ = try await client.textSearch(query: "bird")
    Issue.record("Expected rateLimited error")
  } catch let error as FreesoundError {
    guard case .rateLimited(let retryAfter, let detail) = error else {
      Issue.record("Expected rateLimited, got \(error)")
      return
    }
    #expect(retryAfter == 12)
    #expect(detail == "Request was throttled")
  }
}

@Test func decodingFailureCarriesUnderlyingError() async throws {
  let mockSession = MockHTTPClient { _ in
    (Data("not json".utf8), makeResponse())
  }
  let client = FreesoundClient(session: mockSession)

  do {
    _ = try await client.textSearch(query: "bird")
    Issue.record("Expected decodingError")
  } catch let error as FreesoundError {
    guard case .decodingError(let underlying) = error else {
      Issue.record("Expected decodingError, got \(error)")
      return
    }
    #expect(underlying is DecodingError)
  }
}

@Test func nextPageFollowsNextURLWithAuth() async throws {
  let page1URL = "https://freesound.org/apiv2/search/text/?query=piano&page=1"
  let page2URL = "https://freesound.org/apiv2/search/text/?query=piano&page=2"
  let mockSession = MockHTTPClient { request in
    #expect(request.value(forHTTPHeaderField: "Authorization") == "Token test-key")
    let responseJSON: String
    if request.url?.query?.contains("page=2") == true {
      responseJSON =
        #"{"count":2,"next":null,"previous":"\#(page1URL)","results":[{"id":2}]}"#
    } else {
      responseJSON =
        #"{"count":2,"next":"\#(page2URL)","previous":null,"results":[{"id":1}]}"#
    }
    return (Data(responseJSON.utf8), makeResponse())
  }

  let client = FreesoundClient(authentication: .apiKey("test-key"), session: mockSession)
  let first = try await client.textSearch(query: "piano")
  #expect(first.results.first?.id == 1)

  let second = try await client.nextPage(of: first)
  #expect(second?.results.first?.id == 2)

  let afterLast = try await client.nextPage(of: second!)
  #expect(afterLast == nil)

  let backToFirst = try await client.previousPage(of: second!)
  #expect(backToFirst?.results.first?.id == 1)
}

@Test func combinedSearchFollowsMoreLink() async throws {
  let mockSession = MockHTTPClient { request in
    #expect(request.url?.path == "/apiv2/search/combined")
    let responseJSON: String
    if request.url?.query?.contains("more=more_token") == true {
      responseJSON = #"{"results":[{"id":2}],"more":null}"#
    } else {
      responseJSON =
        #"{"results":[{"id":1}],"more":"/apiv2/search/combined/?more=more_token"}"#
    }
    return (Data(responseJSON.utf8), makeResponse())
  }

  let client = FreesoundClient(authentication: .apiKey("k"), session: mockSession)
  let first = try await client.combinedSearch(parameters: ["target": "rhythm.bpm:120"])
  #expect(first.results.first?.id == 1)

  let second = try await client.moreResults(of: first)
  #expect(second?.results.first?.id == 2)

  let third = try await client.moreResults(of: second!)
  #expect(third == nil)
}

@Test func downloadPreviewFetchesPreviewWithoutAuth() async throws {
  let previewURLString = "https://cdn.freesound.org/previews/7/7_1-hq.mp3"
  let soundJSON = #"{"id":7,"previews":{"preview-hq-mp3":"\#(previewURLString)"}}"#
  let sound = try JSONDecoder().decode(Sound.self, from: Data(soundJSON.utf8))

  let audio = Data([0xFF, 0xFB])
  let mockSession = MockHTTPClient { request in
    #expect(request.url?.absoluteString == previewURLString)
    #expect(request.value(forHTTPHeaderField: "Authorization") == nil)
    return (audio, makeResponse())
  }

  let client = FreesoundClient(authentication: .apiKey("k"), session: mockSession)
  let data = try await client.downloadPreview(for: sound)
  #expect(data == audio)
}

@Test func downloadPreviewWithoutPreviewsThrowsInvalidInput() async throws {
  let sound = try JSONDecoder().decode(Sound.self, from: Data(#"{"id":7}"#.utf8))
  let client = FreesoundClient(session: MockHTTPClient.unused)
  do {
    _ = try await client.downloadPreview(for: sound, format: .lqOGG)
    Issue.record("Expected invalidInput error")
  } catch let error as FreesoundError {
    guard case .invalidInput = error else {
      Issue.record("Expected invalidInput, got \(error)")
      return
    }
  }
}

@Test func parsesFreesoundTimestamps() async throws {
  // Sound timestamps carry milliseconds; user timestamps do not. Both are
  // timezone-less and interpreted as UTC.
  let sound = try JSONDecoder().decode(
    Sound.self, from: Data(#"{"id":1,"created":"2014-04-16T20:07:11.145"}"#.utf8))
  let user = try JSONDecoder().decode(
    User.self,
    from: Data(#"{"username":"alice","date_joined":"2008-08-07T17:39:00"}"#.utf8))

  var utc = Calendar(identifier: .gregorian)
  utc.timeZone = TimeZone(secondsFromGMT: 0)!

  let createdComponents = utc.dateComponents(
    [.year, .month, .day, .hour, .minute, .second, .nanosecond],
    from: try #require(sound.createdDate))
  #expect(createdComponents.year == 2014)
  #expect(createdComponents.month == 4)
  #expect(createdComponents.day == 16)
  #expect(createdComponents.hour == 20)
  #expect(createdComponents.minute == 7)
  #expect(createdComponents.second == 11)
  // The fractional-seconds strategy must preserve the ".145" millisecond part.
  let nanos = try #require(createdComponents.nanosecond)
  #expect(abs(nanos - 145_000_000) < 1_000_000)

  let joinedComponents = utc.dateComponents(
    [.year, .hour, .minute], from: try #require(user.dateJoinedDate))
  #expect(joinedComponents.year == 2008)
  #expect(joinedComponents.hour == 17)
  #expect(joinedComponents.minute == 39)

  // The same helper backs Comment, Pack, and PendingUpload; verify each wires
  // it to the right field rather than trusting only the Sound/User paths.
  #expect(Comment(created: "2014-04-16T20:07:11.145").createdDate != nil)
  #expect(Pack(id: 1, created: "2014-04-16T20:07:11.145").createdDate != nil)
  #expect(PendingUpload(uploadDate: "2008-08-07T17:39:00").uploadedDate != nil)
}

@Test func unparsableTimestampYieldsNil() {
  #expect(Sound(id: 1, created: "not a date").createdDate == nil)
  #expect(Sound(id: 1, created: nil).createdDate == nil)
}

@Test func modelsAreIdentifiableAndEquatable() {
  let a = Sound(id: 7, name: "Kick")
  let b = Sound(id: 7, name: "Kick")
  let c = Sound(id: 7, name: "Snare")
  #expect(a == b)
  #expect(a != c)
  #expect(a.id == 7)
  // Hashable: equal values hash equally; usable as Set/dictionary keys.
  #expect(Set([a, b, c]).count == 2)

  // Identifiable via username for user models.
  #expect(User(username: "alice").id == "alice")
  #expect(Me(username: "bob").id == "bob")
}

@Test func rateLimitRetrySucceedsAfterThrottle() async throws {
  let attempts = Mutex(0)
  let result = try await FreesoundClient(session: MockHTTPClient.unused).withRateLimitRetry(
    maxAttempts: 3, fallbackDelay: 0, maxDelay: 0
  ) {
    let attempt = attempts.withLock {
      $0 += 1
      return $0
    }
    if attempt < 3 {
      throw FreesoundError.rateLimited(retryAfter: nil, detail: "throttled")
    }
    return attempt
  }
  #expect(result == 3)
  #expect(attempts.withLock { $0 } == 3)
}

@Test func rateLimitRetryGivesUpAfterMaxAttempts() async throws {
  let attempts = Mutex(0)
  do {
    _ =
      try await FreesoundClient(session: MockHTTPClient.unused).withRateLimitRetry(
        maxAttempts: 2, fallbackDelay: 0, maxDelay: 0
      ) {
        attempts.withLock { $0 += 1 }
        throw FreesoundError.rateLimited(retryAfter: nil, detail: "throttled")
      } as Int
    Issue.record("Expected rateLimited to be rethrown")
    return
  } catch let error as FreesoundError {
    guard case .rateLimited = error else {
      Issue.record("Expected rateLimited, got \(error)")
      return
    }
  }
  #expect(attempts.withLock { $0 } == 2)
}

@Test func rateLimitRetryDoesNotSwallowOtherErrors() async throws {
  let attempts = Mutex(0)
  do {
    _ =
      try await FreesoundClient(session: MockHTTPClient.unused).withRateLimitRetry {
        attempts.withLock { $0 += 1 }
        throw FreesoundError.oauthRequired
      } as Int
    Issue.record("Expected oauthRequired to be rethrown")
    return
  } catch let error as FreesoundError {
    guard case .oauthRequired = error else {
      Issue.record("Expected oauthRequired, got \(error)")
      return
    }
  }
  // Non-rate-limit errors are not retried.
  #expect(attempts.withLock { $0 } == 1)
}

@Test func rateLimitRetryWaitsForRetryAfter() async throws {
  // Exercises the delay path the other retry tests skip: a non-nil Retry-After
  // is extracted, clamped, and actually slept through before the next attempt.
  let clock = ContinuousClock()
  let attempts = Mutex(0)
  let start = clock.now
  let result = try await FreesoundClient(session: MockHTTPClient.unused).withRateLimitRetry(
    maxAttempts: 2, fallbackDelay: 0, maxDelay: 60
  ) {
    let attempt = attempts.withLock {
      $0 += 1
      return $0
    }
    if attempt == 1 {
      throw FreesoundError.rateLimited(retryAfter: 0.05, detail: "throttled")
    }
    return attempt
  }
  #expect(result == 2)
  #expect(clock.now - start >= .milliseconds(40))
}

@Test func rateLimitRetryHonorsCancellationWithoutDelay() async throws {
  let attempts = Mutex(0)
  let task = Task {
    try await FreesoundClient(session: MockHTTPClient.unused).withRateLimitRetry(
      maxAttempts: 1_000_000, fallbackDelay: 0, maxDelay: 0
    ) {
      attempts.withLock { $0 += 1 }
      throw FreesoundError.rateLimited(retryAfter: nil, detail: "throttled")
    } as Int
  }
  task.cancel()
  do {
    _ = try await task.value
    Issue.record("Expected cancellation to propagate")
    return
  } catch is CancellationError {
    // expected: the loop checks cancellation between attempts even with no
    // delay, so it stops far short of its million-attempt ceiling.
  }
  #expect(attempts.withLock { $0 } < 1_000_000)
}

@Test func rateLimitRetryRejectsNonPositiveMaxAttempts() async throws {
  do {
    _ =
      try await FreesoundClient(session: MockHTTPClient.unused).withRateLimitRetry(
        maxAttempts: 0
      ) {
        42
      } as Int
    Issue.record("Expected invalidInput to be thrown")
    return
  } catch let error as FreesoundError {
    guard case .invalidInput = error else {
      Issue.record("Expected invalidInput, got \(error)")
      return
    }
  }
}

private struct UnexpectedHTTPCall: Error {}

private final class MockHTTPClient: FreesoundHTTPClient, @unchecked Sendable {
  static let unused = MockHTTPClient { _ in
    Issue.record("Unexpected HTTP call")
    throw UnexpectedHTTPCall()
  }

  private let handler: @Sendable (URLRequest) throws -> (Data, URLResponse)

  init(handler: @escaping @Sendable (URLRequest) throws -> (Data, URLResponse)) {
    self.handler = handler
  }

  func data(for request: URLRequest) async throws -> (Data, URLResponse) {
    try handler(request)
  }
}

private func makeResponse(status: Int = 200, headers: [String: String]? = nil) -> HTTPURLResponse {
  HTTPURLResponse(
    url: URL(string: "https://freesound.org/apiv2/mock/")!,
    statusCode: status,
    httpVersion: nil,
    headerFields: headers
  )!
}
