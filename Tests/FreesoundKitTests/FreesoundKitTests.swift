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

@Test func meDecodesAvatarObjectAndProfileFields() async throws {
  let mockSession = MockHTTPClient { _ in
    let responseJSON = """
      {
        "url": "https://freesound.org/people/blankie.rest/",
        "username": "blankie.rest",
        "about": "hello",
        "home_page": "https://blankie.rest",
        "avatar": {
          "small": "https://freesound.org/data/avatars/15820/15820073_S.jpg",
          "medium": "https://freesound.org/data/avatars/15820/15820073_M.jpg",
          "large": "https://freesound.org/data/avatars/15820/15820073_L.jpg"
        },
        "date_joined": "2024-03-21T23:48:08.384002+01:00",
        "num_sounds": 1,
        "sounds": "https://freesound.org/apiv2/users/blankie.rest/sounds/",
        "num_packs": 0,
        "packs": "https://freesound.org/apiv2/users/blankie.rest/packs/",
        "num_posts": 0,
        "num_comments": 1,
        "ai_preference": "freesound-cc-recommendation",
        "email": "user@example.com",
        "unique_id": 15820073,
        "bookmark_categories": "https://freesound.org/apiv2/me/bookmark_categories/"
      }
      """
    return (Data(responseJSON.utf8), makeResponse())
  }

  let client = FreesoundClient(authentication: .oauthToken("oauth-token"), session: mockSession)
  let me = try await client.me()
  #expect(me.username == "blankie.rest")
  #expect(me.homepage == URL(string: "https://blankie.rest"))
  #expect(
    me.avatar?.large
      == URL(string: "https://freesound.org/data/avatars/15820/15820073_L.jpg"))
  #expect(me.email == "user@example.com")
  #expect(me.uniqueID == 15_820_073)
  #expect(me.numComments == 1)
  #expect(
    me.bookmarkCategories
      == URL(string: "https://freesound.org/apiv2/me/bookmark_categories/"))
  #expect(me.dateJoined == "2024-03-21T23:48:08.384002+01:00")
}

@Test func decodesFieldsConfirmedAgainstLiveAPI() throws {
  // Fields present in real API responses but previously unmodeled (verified
  // against the live API and the Freesound server serializers).
  let soundJSON = #"""
    {"id": 14854, "name": "Nightingale song.wav", "pack": "https://freesound.org/apiv2/packs/455/", "pack_name": "nightingales", "samplerate": 48000.0}
    """#
  let sound = try JSONDecoder().decode(Sound.self, from: Data(soundJSON.utf8))
  #expect(sound.packName == "nightingales")
  #expect(sound.samplerate == 48000)  // API returns 48000.0 (float) for an Int field

  let packJSON = #"{"id": 455, "name": "nightingales", "num_sounds": 12, "num_downloads": 3456}"#
  let pack = try JSONDecoder().decode(Pack.self, from: Data(packJSON.utf8))
  #expect(pack.numDownloads == 3456)

  let userJSON = #"""
    {"username": "reinsamba", "home_page": "", "num_comments": 54, "ai_preference": "freesound-cc-recommendation",
     "avatar": {"small": "https://freesound.org/data/avatars/18/18799_S.jpg", "medium": null, "large": null}}
    """#
  let user = try JSONDecoder().decode(User.self, from: Data(userJSON.utf8))
  #expect(user.homepage == nil)  // "" -> nil
  #expect(user.numComments == 54)
  #expect(user.aiPreference == "freesound-cc-recommendation")
  #expect(user.avatar?.small != nil)
  #expect(user.avatar?.medium == nil)
}

@Test func soundAnalysisDecodesNewDescriptors() throws {
  // Shapes taken verbatim from a live /sounds/<id>/analysis/ response.
  let json = #"""
    {
      "category": "Sound effects", "subcategory": "Animals",
      "tonality": "B major", "warmth": null, "zero_crossing_rate": 0.139,
      "has_audio_problems": false, "tristimulus": [0.672, 0.261, 0.061],
      "birdnet_detected_class": ["Common Nightingale"],
      "birdnet_detections": [
        {"start_time": 0.0, "end_time": 27.0, "confidence": 1.0,
         "common_name": "Common Nightingale", "scientific_name": "Luscinia megarhynchos"}
      ],
      "birdnet_detections_count": 12,
      "fsdsinet_detected_class": ["Animal"],
      "fsdsinet_detections": [{"name": "Animal", "start_time": 0.0, "end_time": 9.5, "confidence": 0.91}],
      "fsdsinet_detections_count": 134,
      "freesound_classic": [0.81, -0.1], "laion_clap": [-0.016, -0.001]
    }
    """#
  let d = try JSONDecoder().decode(SoundAnalysis.self, from: Data(json.utf8)).descriptors
  #expect(d.category == "Sound effects")
  #expect(d.hasAudioProblems == false)
  #expect(d.warmth == nil)
  #expect(d.birdnetDetectionsCount == 12)
  #expect(d.birdnetDetections?.first?.commonName == "Common Nightingale")
  #expect(d.birdnetDetections?.first?.scientificName == "Luscinia megarhynchos")
  #expect(d.fsdsinetDetections?.first?.name == "Animal")
  #expect(d.fsdsinetDetections?.first?.confidence == 0.91)
  #expect(d.laionClap?.count == 2)
}

@Test func meToleratesEmptyHomePageAndAvatarlessAccount() async throws {
  // The serializer emits "" (not null) for an unset home_page, and an avatar
  // object whose three sizes are all null when the user has no avatar. Neither
  // shape should fail the decode (previously both threw a typeMismatch).
  let mockSession = MockHTTPClient { _ in
    let responseJSON = """
      {
        "username": "nobody",
        "url": "https://freesound.org/people/nobody/",
        "about": "",
        "home_page": "",
        "avatar": {"small": null, "medium": null, "large": null}
      }
      """
    return (Data(responseJSON.utf8), makeResponse())
  }

  let client = FreesoundClient(authentication: .oauthToken("oauth-token"), session: mockSession)
  let me = try await client.me()
  #expect(me.homepage == nil)
  #expect(me.avatar != nil)
  #expect(me.avatar?.small == nil)
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

@Test func similaritySearchUsesSimilarToParameter() async throws {
  let mockSession = MockHTTPClient { request in
    #expect(request.url?.path == "/apiv2/search/text")
    let query = request.url?.query ?? ""
    #expect(query.contains("similar_to=14854"))
    #expect(query.contains("similar_space=laion_clap"))
    return (
      Data(#"{"count":1,"next":null,"previous":null,"results":[{"id":99}]}"#.utf8), makeResponse()
    )
  }

  let client = FreesoundClient(authentication: .apiKey("k"), session: mockSession)
  let page = try await client.similaritySearch(toSoundID: 14854, space: .laionClap)
  #expect(page.results.first?.id == 99)
}

// Marked deprecated so it can exercise the deprecated methods without warnings.
@available(*, deprecated)
@Test func removedSearchEndpointsThrowClearError() async throws {
  let client = FreesoundClient(authentication: .apiKey("k"), session: MockHTTPClient.unused)
  do {
    _ = try await client.contentSearch(parameters: ["target": "x"])
    Issue.record("contentSearch should throw")
  } catch is FreesoundError {
  }
  do {
    _ = try await client.combinedSearch(parameters: ["target": "x"])
    Issue.record("combinedSearch should throw")
  } catch is FreesoundError {
  }
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

// MARK: - Codable round-trips (models are now persistable to disk)

@Test func soundRoundTripsThroughCodable() throws {
  let json = #"""
    {"id":7,"name":"Kick","url":"https://freesound.org/s/7/","tags":["drum","kick"],
     "license":"https://creativecommons.org/publicdomain/zero/1.0/","type":"wav",
     "duration":0.5,"category":"Music","subcategory":"Percussion","category_code":"mu-perc",
     "previews":{"preview-hq-mp3":"https://freesound.org/data/previews/7/7_hq.mp3"},
     "images":{"waveform_m":"https://freesound.org/data/displays/7/7_wave_M.png"},
     "num_downloads":10,"avg_rating":4.5,"num_ratings":6,"num_comments":2,
     "brightness":42.5,"bpm":120,"loopable":true,"tonality":"C minor",
     "beat_times":[0.1,0.2],"note_name":"C3"}
    """#
  let original = try JSONDecoder().decode(Sound.self, from: Data(json.utf8))
  let roundTripped = try JSONDecoder().decode(Sound.self, from: JSONEncoder().encode(original))
  // Exact equality covers every keyed field AND the flattened descriptors.
  #expect(roundTripped == original)
  #expect(roundTripped.descriptors.bpm == 120)
  #expect(roundTripped.descriptors.beatTimes == [0.1, 0.2])
  #expect(roundTripped.previews?.previewHQMP3 != nil)
  #expect(roundTripped.images?.waveformM != nil)
}

@Test func soundAnalysisRoundTripsThroughCodable() throws {
  let original = try JSONDecoder().decode(
    SoundAnalysis.self, from: Data(#"{"loudness":-23.1,"single_event":true,"bpm":90}"#.utf8))
  let roundTripped = try JSONDecoder().decode(
    SoundAnalysis.self, from: JSONEncoder().encode(original))
  #expect(roundTripped == original)
  #expect(roundTripped.descriptors.loudness == -23.1)
  #expect(roundTripped.descriptors.singleEvent == true)
}

@Test func meRoundTripsThroughCodable() throws {
  // Exercises the lenient-URL fields: synthesized encoding writes URLs as the strings the custom
  // decoder reads back, so the round-trip must be exact.
  let json = """
    {"url":"https://freesound.org/people/blankie.rest/","username":"blankie.rest",
     "about":"hello","home_page":"https://blankie.rest",
     "avatar":{"small":"https://freesound.org/data/avatars/1/1_S.jpg",
               "medium":"https://freesound.org/data/avatars/1/1_M.jpg",
               "large":"https://freesound.org/data/avatars/1/1_L.jpg"},
     "date_joined":"2024-03-21T23:48:08.384002+01:00","num_sounds":1,
     "sounds":"https://freesound.org/apiv2/users/blankie.rest/sounds/","num_packs":0,
     "num_comments":1,"email":"user@example.com","unique_id":15820073,
     "bookmark_categories":"https://freesound.org/apiv2/me/bookmark_categories/"}
    """
  let original = try JSONDecoder().decode(Me.self, from: Data(json.utf8))
  let roundTripped = try JSONDecoder().decode(Me.self, from: JSONEncoder().encode(original))
  #expect(roundTripped == original)
  #expect(roundTripped.homepage == URL(string: "https://blankie.rest"))
  #expect(
    roundTripped.avatar?.large == URL(string: "https://freesound.org/data/avatars/1/1_L.jpg"))
}

@Test func userRoundTripsThroughCodable() throws {
  // `home_page:""` exercises the lenient-URL path: the empty string decodes to nil, so the
  // re-encoded JSON omits the key and the second decode must land on the same nil value.
  let json = """
    {"username":"sampleuser","url":"https://freesound.org/people/sampleuser/",
     "about":"hi","home_page":"","ai_preference":"allow",
     "avatar":{"small":"https://freesound.org/data/avatars/2/2_S.jpg","medium":null,"large":null},
     "date_joined":"2024-03-21T23:48:08.384002+01:00","num_sounds":3,"num_packs":1,
     "num_posts":2,"sounds":"https://freesound.org/apiv2/users/sampleuser/sounds/",
     "packs":"https://freesound.org/apiv2/users/sampleuser/packs/","num_comments":4}
    """
  let original = try JSONDecoder().decode(User.self, from: Data(json.utf8))
  let roundTripped = try JSONDecoder().decode(User.self, from: JSONEncoder().encode(original))
  #expect(roundTripped == original)
  #expect(roundTripped.homepage == nil)
  #expect(roundTripped.avatar?.small == URL(string: "https://freesound.org/data/avatars/2/2_S.jpg"))
  #expect(roundTripped.avatar?.medium == nil)
}

@Test func realAPIResponseRoundTripsThroughCodable() throws {
  // Captured verbatim from a live GET /sounds/14854/?fields=...,bpm,loudness,beat_times,tonality,
  // single_event,birdnet_detections,fsdsinet_detections (beat_times truncated). Proves an actual
  // server response — flattened descriptors, dash-keyed previews, CDN preview URLs, nested
  // detection arrays — survives decode → encode → decode by value.
  let json = #"""
    {"id":14854,"name":"reinsamba at the nightingales feet 2.wav",
     "url":"https://freesound.org/people/reinsamba/sounds/14854/",
     "tags":["field-recording","nightingale","nature","bird"],
     "license":"https://creativecommons.org/licenses/by/4.0/","type":"wav","duration":136.515,
     "category":"Soundscapes","subcategory":"Animals",
     "previews":{"preview-hq-mp3":"https://cdn.freesound.org/previews/14/14854_18799-hq.mp3",
                 "preview-hq-ogg":"https://cdn.freesound.org/previews/14/14854_18799-hq.ogg",
                 "preview-lq-mp3":"https://cdn.freesound.org/previews/14/14854_18799-lq.mp3",
                 "preview-lq-ogg":"https://cdn.freesound.org/previews/14/14854_18799-lq.ogg"},
     "images":{"waveform_l":"https://cdn.freesound.org/displays/14/14854_18799_wave_L.png",
               "waveform_m":"https://cdn.freesound.org/displays/14/14854_18799_wave_M.png",
               "spectral_l":"https://cdn.freesound.org/displays/14/14854_18799_spec_L.jpg",
               "spectral_m":"https://cdn.freesound.org/displays/14/14854_18799_spec_M.jpg"},
     "num_downloads":50871,"avg_rating":4.5,"bpm":135,"brightness":null,"loudness":-20.71,
     "beat_times":[0.476,0.952,1.428,1.904],"tonality":"B major","single_event":false,
     "birdnet_detections":[{"end_time":27.0,"confidence":1.0,"start_time":0.0,
                            "common_name":"Common Nightingale","scientific_name":"Luscinia megarhynchos"}],
     "fsdsinet_detections":[{"name":"Animal","end_time":9.5,"confidence":0.91,"start_time":0.0}]}
    """#
  let original = try JSONDecoder().decode(Sound.self, from: Data(json.utf8))
  let roundTripped = try JSONDecoder().decode(Sound.self, from: JSONEncoder().encode(original))
  #expect(roundTripped == original)
  // Spot-check that the flattened descriptors and shared category keys survived intact.
  #expect(roundTripped.category == "Soundscapes")
  #expect(roundTripped.descriptors.bpm == 135)
  #expect(roundTripped.descriptors.tonality == "B major")
  #expect(roundTripped.descriptors.beatTimes == [0.476, 0.952, 1.428, 1.904])
  #expect(roundTripped.descriptors.birdnetDetections?.first?.commonName == "Common Nightingale")
  #expect(roundTripped.descriptors.fsdsinetDetections?.first?.name == "Animal")
  #expect(roundTripped.previews?.previewHQMP3?.host == "cdn.freesound.org")
}

@Test func pagedResponseOfSoundRoundTripsThroughCodable() throws {
  // Verifies the conditional `Encodable where Item: Encodable` conformance.
  let json = #"""
    {"count":2,"next":null,"previous":null,
     "results":[{"id":1,"name":"One"},{"id":2,"name":"Two","bpm":100}]}
    """#
  let original = try JSONDecoder().decode(PagedResponse<Sound>.self, from: Data(json.utf8))
  let roundTripped = try JSONDecoder().decode(
    PagedResponse<Sound>.self, from: JSONEncoder().encode(original))
  #expect(roundTripped == original)
  #expect(roundTripped.results.last?.descriptors.bpm == 100)
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
