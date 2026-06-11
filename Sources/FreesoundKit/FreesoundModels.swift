//
//  FreesoundModels.swift
//  FreesoundKit
//
//  Created by Cody Bromley on 6/9/26.
//

import Foundation

public struct PagedResponse<Item: Decodable & Sendable>: Decodable, Sendable {
  public let count: Int?
  public let next: URL?
  public let previous: URL?
  public let results: [Item]

  public init(count: Int?, next: URL?, previous: URL?, results: [Item]) {
    self.count = count
    self.next = next
    self.previous = previous
    self.results = results
  }
}

extension PagedResponse: Equatable where Item: Equatable {}
extension PagedResponse: Hashable where Item: Hashable {}

/// The response from ``FreesoundClient/combinedSearch(parameters:)``.
///
/// Combined search does not report a total count, and pagination works through
/// the ``more`` link rather than page numbers. Fetch further results with
/// ``FreesoundClient/moreResults(of:)``.
public struct CombinedSearchResponse: Decodable, Sendable, Equatable, Hashable {
  public let results: [Sound]
  /// A link to the next batch of results, or `nil` when there are no more.
  public let more: String?

  public init(results: [Sound], more: String? = nil) {
    self.results = results
    self.more = more
  }
}

public struct APIStatusResponse: Decodable, Sendable, Equatable, Hashable {
  public let detail: String?
  public let status: String?

  public init(detail: String? = nil, status: String? = nil) {
    self.detail = detail
    self.status = status
  }
}

public struct OAuthTokenResponse: Decodable, Sendable, Equatable, Hashable {
  public let accessToken: String
  public let scope: String?
  public let expiresIn: Int
  public let refreshToken: String

  enum CodingKeys: String, CodingKey {
    case accessToken = "access_token"
    case scope
    case expiresIn = "expires_in"
    case refreshToken = "refresh_token"
  }

  public init(accessToken: String, scope: String? = nil, expiresIn: Int, refreshToken: String) {
    self.accessToken = accessToken
    self.scope = scope
    self.expiresIn = expiresIn
    self.refreshToken = refreshToken
  }
}

public struct Sound: Decodable, Sendable, Equatable, Hashable, Identifiable {
  public let id: Int
  public let url: URL?
  public let name: String?
  public let tags: [String]?
  public let description: String?
  public let category: String?
  public let subcategory: String?
  public let categoryCode: String?
  public let categoryIsUserProvided: Bool?
  public let geotag: String?
  public let isGeotagged: Bool?
  public let created: String?
  public let license: String?
  public let aiPreference: String?
  public let type: String?
  public let channels: Int?
  public let filesize: Int?
  public let bitrate: Double?
  public let bitdepth: Int?
  public let duration: Double?
  public let samplerate: Int?
  public let username: String?
  public let md5: String?
  public let isRemix: Bool?
  public let wasRemixed: Bool?
  public let isExplicit: Bool?
  public let pack: URL?
  public let download: URL?
  public let bookmark: URL?
  public let previews: SoundPreviews?
  public let images: SoundImages?
  public let numDownloads: Int?
  public let avgRating: Double?
  public let numRatings: Int?
  public let rate: URL?
  public let comments: URL?
  public let numComments: Int?
  public let comment: URL?
  public let similarSounds: URL?
  public let analysisFiles: [String: URL]?
  public let descriptors: SoundDescriptors

  /// ``created`` parsed as a `Date`, or `nil` if absent or unrecognized.
  public var createdDate: Date? { freesoundDate(created) }

  enum CodingKeys: String, CodingKey {
    case id
    case url
    case name
    case tags
    case description
    case category
    case subcategory
    case categoryCode = "category_code"
    case categoryIsUserProvided = "category_is_user_provided"
    case geotag
    case isGeotagged = "is_geotagged"
    case created
    case license
    case aiPreference = "ai_preference"
    case type
    case channels
    case filesize
    case bitrate
    case bitdepth
    case duration
    case samplerate
    case username
    case md5
    case isRemix = "is_remix"
    case wasRemixed = "was_remixed"
    case isExplicit = "is_explicit"
    case pack
    case download
    case bookmark
    case previews
    case images
    case numDownloads = "num_downloads"
    case avgRating = "avg_rating"
    case numRatings = "num_ratings"
    case rate
    case comments
    case numComments = "num_comments"
    case comment
    case similarSounds = "similar_sounds"
    case analysisFiles = "analysis_files"
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    id = try container.decode(Int.self, forKey: .id)
    url = try container.decodeIfPresent(URL.self, forKey: .url)
    name = try container.decodeIfPresent(String.self, forKey: .name)
    tags = try container.decodeIfPresent([String].self, forKey: .tags)
    description = try container.decodeIfPresent(String.self, forKey: .description)
    category = try container.decodeIfPresent(String.self, forKey: .category)
    subcategory = try container.decodeIfPresent(String.self, forKey: .subcategory)
    categoryCode = try container.decodeIfPresent(String.self, forKey: .categoryCode)
    categoryIsUserProvided = try container.decodeIfPresent(
      Bool.self, forKey: .categoryIsUserProvided)
    geotag = try container.decodeIfPresent(String.self, forKey: .geotag)
    isGeotagged = try container.decodeIfPresent(Bool.self, forKey: .isGeotagged)
    created = try container.decodeIfPresent(String.self, forKey: .created)
    license = try container.decodeIfPresent(String.self, forKey: .license)
    aiPreference = try container.decodeIfPresent(String.self, forKey: .aiPreference)
    type = try container.decodeIfPresent(String.self, forKey: .type)
    channels = try container.decodeIfPresent(Int.self, forKey: .channels)
    filesize = try container.decodeIfPresent(Int.self, forKey: .filesize)
    bitrate = try container.decodeIfPresent(Double.self, forKey: .bitrate)
    bitdepth = try container.decodeIfPresent(Int.self, forKey: .bitdepth)
    duration = try container.decodeIfPresent(Double.self, forKey: .duration)
    samplerate = try container.decodeIfPresent(Int.self, forKey: .samplerate)
    username = try container.decodeIfPresent(String.self, forKey: .username)
    md5 = try container.decodeIfPresent(String.self, forKey: .md5)
    isRemix = try container.decodeIfPresent(Bool.self, forKey: .isRemix)
    wasRemixed = try container.decodeIfPresent(Bool.self, forKey: .wasRemixed)
    isExplicit = try container.decodeIfPresent(Bool.self, forKey: .isExplicit)
    pack = try container.decodeIfPresent(URL.self, forKey: .pack)
    download = try container.decodeIfPresent(URL.self, forKey: .download)
    bookmark = try container.decodeIfPresent(URL.self, forKey: .bookmark)
    previews = try container.decodeIfPresent(SoundPreviews.self, forKey: .previews)
    images = try container.decodeIfPresent(SoundImages.self, forKey: .images)
    numDownloads = try container.decodeIfPresent(Int.self, forKey: .numDownloads)
    avgRating = try container.decodeIfPresent(Double.self, forKey: .avgRating)
    numRatings = try container.decodeIfPresent(Int.self, forKey: .numRatings)
    rate = try container.decodeIfPresent(URL.self, forKey: .rate)
    comments = try container.decodeIfPresent(URL.self, forKey: .comments)
    numComments = try container.decodeIfPresent(Int.self, forKey: .numComments)
    comment = try container.decodeIfPresent(URL.self, forKey: .comment)
    similarSounds = try container.decodeIfPresent(URL.self, forKey: .similarSounds)
    analysisFiles = try container.decodeIfPresent([String: URL].self, forKey: .analysisFiles)
    descriptors = try SoundDescriptors(from: decoder)
  }

  /// Memberwise initializer. Useful for building fixtures in tests and SwiftUI
  /// previews; only `id` is required.
  public init(
    id: Int,
    url: URL? = nil,
    name: String? = nil,
    tags: [String]? = nil,
    description: String? = nil,
    category: String? = nil,
    subcategory: String? = nil,
    categoryCode: String? = nil,
    categoryIsUserProvided: Bool? = nil,
    geotag: String? = nil,
    isGeotagged: Bool? = nil,
    created: String? = nil,
    license: String? = nil,
    aiPreference: String? = nil,
    type: String? = nil,
    channels: Int? = nil,
    filesize: Int? = nil,
    bitrate: Double? = nil,
    bitdepth: Int? = nil,
    duration: Double? = nil,
    samplerate: Int? = nil,
    username: String? = nil,
    md5: String? = nil,
    isRemix: Bool? = nil,
    wasRemixed: Bool? = nil,
    isExplicit: Bool? = nil,
    pack: URL? = nil,
    download: URL? = nil,
    bookmark: URL? = nil,
    previews: SoundPreviews? = nil,
    images: SoundImages? = nil,
    numDownloads: Int? = nil,
    avgRating: Double? = nil,
    numRatings: Int? = nil,
    rate: URL? = nil,
    comments: URL? = nil,
    numComments: Int? = nil,
    comment: URL? = nil,
    similarSounds: URL? = nil,
    analysisFiles: [String: URL]? = nil,
    descriptors: SoundDescriptors = SoundDescriptors()
  ) {
    self.id = id
    self.url = url
    self.name = name
    self.tags = tags
    self.description = description
    self.category = category
    self.subcategory = subcategory
    self.categoryCode = categoryCode
    self.categoryIsUserProvided = categoryIsUserProvided
    self.geotag = geotag
    self.isGeotagged = isGeotagged
    self.created = created
    self.license = license
    self.aiPreference = aiPreference
    self.type = type
    self.channels = channels
    self.filesize = filesize
    self.bitrate = bitrate
    self.bitdepth = bitdepth
    self.duration = duration
    self.samplerate = samplerate
    self.username = username
    self.md5 = md5
    self.isRemix = isRemix
    self.wasRemixed = wasRemixed
    self.isExplicit = isExplicit
    self.pack = pack
    self.download = download
    self.bookmark = bookmark
    self.previews = previews
    self.images = images
    self.numDownloads = numDownloads
    self.avgRating = avgRating
    self.numRatings = numRatings
    self.rate = rate
    self.comments = comments
    self.numComments = numComments
    self.comment = comment
    self.similarSounds = similarSounds
    self.analysisFiles = analysisFiles
    self.descriptors = descriptors
  }
}

public struct SoundPreviews: Decodable, Sendable, Equatable, Hashable {
  public let previewHQMP3: URL?
  public let previewLQMP3: URL?
  public let previewHQOGG: URL?
  public let previewLQOGG: URL?

  enum CodingKeys: String, CodingKey {
    case previewHQMP3 = "preview-hq-mp3"
    case previewLQMP3 = "preview-lq-mp3"
    case previewHQOGG = "preview-hq-ogg"
    case previewLQOGG = "preview-lq-ogg"
  }

  public init(
    previewHQMP3: URL? = nil,
    previewLQMP3: URL? = nil,
    previewHQOGG: URL? = nil,
    previewLQOGG: URL? = nil
  ) {
    self.previewHQMP3 = previewHQMP3
    self.previewLQMP3 = previewLQMP3
    self.previewHQOGG = previewHQOGG
    self.previewLQOGG = previewLQOGG
  }
}

/// A preview encoding offered by ``SoundPreviews``, used with
/// ``FreesoundClient/downloadPreview(for:format:)``.
public enum SoundPreviewFormat: Sendable, Equatable, Hashable, CaseIterable {
  /// High-quality MP3 (~128 kbps).
  case hqMP3
  /// Low-quality MP3 (~64 kbps).
  case lqMP3
  /// High-quality Ogg Vorbis (~192 kbps).
  case hqOGG
  /// Low-quality Ogg Vorbis (~80 kbps).
  case lqOGG
}

public struct SoundImages: Decodable, Sendable, Equatable, Hashable {
  public let waveformL: URL?
  public let waveformM: URL?
  public let spectralL: URL?
  public let spectralM: URL?

  enum CodingKeys: String, CodingKey {
    case waveformL = "waveform_l"
    case waveformM = "waveform_m"
    case spectralL = "spectral_l"
    case spectralM = "spectral_m"
  }

  public init(
    waveformL: URL? = nil,
    waveformM: URL? = nil,
    spectralL: URL? = nil,
    spectralM: URL? = nil
  ) {
    self.waveformL = waveformL
    self.waveformM = waveformM
    self.spectralL = spectralL
    self.spectralM = spectralM
  }
}

public struct SoundAnalysis: Decodable, Sendable, Equatable, Hashable {
  public let descriptors: SoundDescriptors

  public init(from decoder: Decoder) throws {
    descriptors = try SoundDescriptors(from: decoder)
  }

  public init(descriptors: SoundDescriptors = SoundDescriptors()) {
    self.descriptors = descriptors
  }
}

public struct SoundDescriptors: Decodable, Sendable, Equatable, Hashable {
  public let amplitudePeakRatio: Double?
  public let beatCount: Int?
  public let beatLoudness: Double?
  public let beatTimes: [Double]?
  public let boominess: Double?
  public let bpm: Int?
  public let bpmConfidence: Double?
  public let brightness: Double?
  public let chordCount: Int?
  public let chordProgression: [String]?
  public let decayStrength: Double?
  public let depth: Double?
  public let dissonance: Double?
  public let durationEffective: Double?
  public let dynamicRange: Double?
  public let hardness: Double?
  public let hpcp: [Double]?
  public let hpcpCrest: Double?
  public let hpcpEntropy: Double?
  public let inharmonicity: Double?
  public let logAttackTime: Double?
  public let loopable: Bool?
  public let loudness: Double?
  public let mfcc: [Double]?
  public let noteConfidence: Double?
  public let noteMidi: Int?
  public let noteName: String?
  public let onsetCount: Int?
  public let onsetTimes: [Double]?
  public let pitch: Double?
  public let pitchMax: Double?
  public let pitchMin: Double?
  public let pitchSalience: Double?
  public let pitchVar: Double?
  public let reverbness: Bool?
  public let roughness: Double?
  public let sharpness: Double?
  public let silenceRate: Double?
  public let singleEvent: Bool?
  public let spectralCentroid: Double?
  public let spectralComplexity: Double?
  public let spectralCrest: Double?
  public let spectralEnergy: Double?
  public let spectralEntropy: Double?
  public let spectralFlatness: Double?
  public let spectralRolloff: Double?
  public let spectralSkewness: Double?
  public let spectralSpread: Double?
  public let startTime: Double?
  public let temporalCentroid: Double?
  public let temporalCentroidRatio: Double?
  public let temporalDecrease: Double?
  public let temporalSkewness: Double?
  public let temporalSpread: Double?
  public let tonality: String?
  public let tonalityConfidence: Double?
  public let tristimulus: [Double]?
  public let warmth: Double?
  public let zeroCrossingRate: Double?

  enum CodingKeys: String, CodingKey {
    case amplitudePeakRatio = "amplitude_peak_ratio"
    case beatCount = "beat_count"
    case beatLoudness = "beat_loudness"
    case beatTimes = "beat_times"
    case boominess
    case bpm
    case bpmConfidence = "bpm_confidence"
    case brightness
    case chordCount = "chord_count"
    case chordProgression = "chord_progression"
    case decayStrength = "decay_strength"
    case depth
    case dissonance
    case durationEffective = "duration_effective"
    case dynamicRange = "dynamic_range"
    case hardness
    case hpcp
    case hpcpCrest = "hpcp_crest"
    case hpcpEntropy = "hpcp_entropy"
    case inharmonicity
    case logAttackTime = "log_attack_time"
    case loopable
    case loudness
    case mfcc
    case noteConfidence = "note_confidence"
    case noteMidi = "note_midi"
    case noteName = "note_name"
    case onsetCount = "onset_count"
    case onsetTimes = "onset_times"
    case pitch
    case pitchMax = "pitch_max"
    case pitchMin = "pitch_min"
    case pitchSalience = "pitch_salience"
    case pitchVar = "pitch_var"
    case reverbness
    case roughness
    case sharpness
    case silenceRate = "silence_rate"
    case singleEvent = "single_event"
    case spectralCentroid = "spectral_centroid"
    case spectralComplexity = "spectral_complexity"
    case spectralCrest = "spectral_crest"
    case spectralEnergy = "spectral_energy"
    case spectralEntropy = "spectral_entropy"
    case spectralFlatness = "spectral_flatness"
    case spectralRolloff = "spectral_rolloff"
    case spectralSkewness = "spectral_skewness"
    case spectralSpread = "spectral_spread"
    case startTime = "start_time"
    case temporalCentroid = "temporal_centroid"
    case temporalCentroidRatio = "temporal_centroid_ratio"
    case temporalDecrease = "temporal_decrease"
    case temporalSkewness = "temporal_skewness"
    case temporalSpread = "temporal_spread"
    case tonality
    case tonalityConfidence = "tonality_confidence"
    case tristimulus
    case warmth
    case zeroCrossingRate = "zero_crossing_rate"
  }

  /// Memberwise initializer with every descriptor defaulting to `nil`. Useful
  /// for building fixtures in tests and SwiftUI previews.
  public init(
    amplitudePeakRatio: Double? = nil,
    beatCount: Int? = nil,
    beatLoudness: Double? = nil,
    beatTimes: [Double]? = nil,
    boominess: Double? = nil,
    bpm: Int? = nil,
    bpmConfidence: Double? = nil,
    brightness: Double? = nil,
    chordCount: Int? = nil,
    chordProgression: [String]? = nil,
    decayStrength: Double? = nil,
    depth: Double? = nil,
    dissonance: Double? = nil,
    durationEffective: Double? = nil,
    dynamicRange: Double? = nil,
    hardness: Double? = nil,
    hpcp: [Double]? = nil,
    hpcpCrest: Double? = nil,
    hpcpEntropy: Double? = nil,
    inharmonicity: Double? = nil,
    logAttackTime: Double? = nil,
    loopable: Bool? = nil,
    loudness: Double? = nil,
    mfcc: [Double]? = nil,
    noteConfidence: Double? = nil,
    noteMidi: Int? = nil,
    noteName: String? = nil,
    onsetCount: Int? = nil,
    onsetTimes: [Double]? = nil,
    pitch: Double? = nil,
    pitchMax: Double? = nil,
    pitchMin: Double? = nil,
    pitchSalience: Double? = nil,
    pitchVar: Double? = nil,
    reverbness: Bool? = nil,
    roughness: Double? = nil,
    sharpness: Double? = nil,
    silenceRate: Double? = nil,
    singleEvent: Bool? = nil,
    spectralCentroid: Double? = nil,
    spectralComplexity: Double? = nil,
    spectralCrest: Double? = nil,
    spectralEnergy: Double? = nil,
    spectralEntropy: Double? = nil,
    spectralFlatness: Double? = nil,
    spectralRolloff: Double? = nil,
    spectralSkewness: Double? = nil,
    spectralSpread: Double? = nil,
    startTime: Double? = nil,
    temporalCentroid: Double? = nil,
    temporalCentroidRatio: Double? = nil,
    temporalDecrease: Double? = nil,
    temporalSkewness: Double? = nil,
    temporalSpread: Double? = nil,
    tonality: String? = nil,
    tonalityConfidence: Double? = nil,
    tristimulus: [Double]? = nil,
    warmth: Double? = nil,
    zeroCrossingRate: Double? = nil
  ) {
    self.amplitudePeakRatio = amplitudePeakRatio
    self.beatCount = beatCount
    self.beatLoudness = beatLoudness
    self.beatTimes = beatTimes
    self.boominess = boominess
    self.bpm = bpm
    self.bpmConfidence = bpmConfidence
    self.brightness = brightness
    self.chordCount = chordCount
    self.chordProgression = chordProgression
    self.decayStrength = decayStrength
    self.depth = depth
    self.dissonance = dissonance
    self.durationEffective = durationEffective
    self.dynamicRange = dynamicRange
    self.hardness = hardness
    self.hpcp = hpcp
    self.hpcpCrest = hpcpCrest
    self.hpcpEntropy = hpcpEntropy
    self.inharmonicity = inharmonicity
    self.logAttackTime = logAttackTime
    self.loopable = loopable
    self.loudness = loudness
    self.mfcc = mfcc
    self.noteConfidence = noteConfidence
    self.noteMidi = noteMidi
    self.noteName = noteName
    self.onsetCount = onsetCount
    self.onsetTimes = onsetTimes
    self.pitch = pitch
    self.pitchMax = pitchMax
    self.pitchMin = pitchMin
    self.pitchSalience = pitchSalience
    self.pitchVar = pitchVar
    self.reverbness = reverbness
    self.roughness = roughness
    self.sharpness = sharpness
    self.silenceRate = silenceRate
    self.singleEvent = singleEvent
    self.spectralCentroid = spectralCentroid
    self.spectralComplexity = spectralComplexity
    self.spectralCrest = spectralCrest
    self.spectralEnergy = spectralEnergy
    self.spectralEntropy = spectralEntropy
    self.spectralFlatness = spectralFlatness
    self.spectralRolloff = spectralRolloff
    self.spectralSkewness = spectralSkewness
    self.spectralSpread = spectralSpread
    self.startTime = startTime
    self.temporalCentroid = temporalCentroid
    self.temporalCentroidRatio = temporalCentroidRatio
    self.temporalDecrease = temporalDecrease
    self.temporalSkewness = temporalSkewness
    self.temporalSpread = temporalSpread
    self.tonality = tonality
    self.tonalityConfidence = tonalityConfidence
    self.tristimulus = tristimulus
    self.warmth = warmth
    self.zeroCrossingRate = zeroCrossingRate
  }
}

public struct Comment: Decodable, Sendable, Equatable, Hashable {
  public let id: Int?
  public let url: URL?
  public let username: String?
  public let comment: String?
  public let created: String?

  /// ``created`` parsed as a `Date`, or `nil` if absent or unrecognized.
  public var createdDate: Date? { freesoundDate(created) }

  public init(
    id: Int? = nil,
    url: URL? = nil,
    username: String? = nil,
    comment: String? = nil,
    created: String? = nil
  ) {
    self.id = id
    self.url = url
    self.username = username
    self.comment = comment
    self.created = created
  }
}

public struct User: Decodable, Sendable, Equatable, Hashable, Identifiable {
  public let username: String
  public let url: URL?
  public let about: String?
  public let homepage: URL?
  public let avatar: URL?
  public let dateJoined: String?
  public let numSounds: Int?
  public let numPacks: Int?
  public let numPosts: Int?
  public let sounds: URL?
  public let packs: URL?

  /// The user's stable identity, their ``username``.
  public var id: String { username }
  /// ``dateJoined`` parsed as a `Date`, or `nil` if absent or unrecognized.
  public var dateJoinedDate: Date? { freesoundDate(dateJoined) }

  enum CodingKeys: String, CodingKey {
    case username
    case url
    case about
    case homepage
    case avatar
    case dateJoined = "date_joined"
    case numSounds = "num_sounds"
    case numPacks = "num_packs"
    case numPosts = "num_posts"
    case sounds
    case packs
  }

  public init(
    username: String,
    url: URL? = nil,
    about: String? = nil,
    homepage: URL? = nil,
    avatar: URL? = nil,
    dateJoined: String? = nil,
    numSounds: Int? = nil,
    numPacks: Int? = nil,
    numPosts: Int? = nil,
    sounds: URL? = nil,
    packs: URL? = nil
  ) {
    self.username = username
    self.url = url
    self.about = about
    self.homepage = homepage
    self.avatar = avatar
    self.dateJoined = dateJoined
    self.numSounds = numSounds
    self.numPacks = numPacks
    self.numPosts = numPosts
    self.sounds = sounds
    self.packs = packs
  }
}

public struct Pack: Decodable, Sendable, Equatable, Hashable, Identifiable {
  public let id: Int
  public let url: URL?
  public let name: String?
  public let description: String?
  public let username: String?
  public let created: String?
  public let numSounds: Int?
  public let sounds: URL?
  public let download: URL?

  /// ``created`` parsed as a `Date`, or `nil` if absent or unrecognized.
  public var createdDate: Date? { freesoundDate(created) }

  enum CodingKeys: String, CodingKey {
    case id
    case url
    case name
    case description
    case username
    case created
    case numSounds = "num_sounds"
    case sounds
    case download
  }

  public init(
    id: Int,
    url: URL? = nil,
    name: String? = nil,
    description: String? = nil,
    username: String? = nil,
    created: String? = nil,
    numSounds: Int? = nil,
    sounds: URL? = nil,
    download: URL? = nil
  ) {
    self.id = id
    self.url = url
    self.name = name
    self.description = description
    self.username = username
    self.created = created
    self.numSounds = numSounds
    self.sounds = sounds
    self.download = download
  }
}

public struct Me: Decodable, Sendable, Equatable, Hashable, Identifiable {
  public let username: String
  public let url: URL?
  public let about: String?
  public let homepage: URL?
  public let avatar: URL?

  /// The user's stable identity, their ``username``.
  public var id: String { username }

  enum CodingKeys: String, CodingKey {
    case username
    case url
    case about
    case homepage
    case avatar
  }

  public init(
    username: String,
    url: URL? = nil,
    about: String? = nil,
    homepage: URL? = nil,
    avatar: URL? = nil
  ) {
    self.username = username
    self.url = url
    self.about = about
    self.homepage = homepage
    self.avatar = avatar
  }
}

public struct BookmarkCategory: Decodable, Sendable, Equatable, Hashable, Identifiable {
  public let id: Int
  public let name: String
  public let url: URL?
  public let numSounds: Int?

  enum CodingKeys: String, CodingKey {
    case id
    case name
    case url
    case numSounds = "num_sounds"
  }

  public init(id: Int, name: String, url: URL? = nil, numSounds: Int? = nil) {
    self.id = id
    self.name = name
    self.url = url
    self.numSounds = numSounds
  }
}

public struct PendingUploads: Decodable, Sendable, Equatable, Hashable {
  /// Filenames of uploaded sounds that still need to be described.
  public let pendingDescription: [String]
  /// Sounds that are described and currently being processed.
  public let pendingProcessing: [PendingUpload]
  /// Sounds awaiting moderation.
  public let pendingModeration: [PendingUpload]

  enum CodingKeys: String, CodingKey {
    case pendingDescription = "pending_description"
    case pendingProcessing = "pending_processing"
    case pendingModeration = "pending_moderation"
  }

  public init(
    pendingDescription: [String] = [],
    pendingProcessing: [PendingUpload] = [],
    pendingModeration: [PendingUpload] = []
  ) {
    self.pendingDescription = pendingDescription
    self.pendingProcessing = pendingProcessing
    self.pendingModeration = pendingModeration
  }
}

public struct PendingUpload: Decodable, Sendable, Equatable, Hashable {
  public let id: Int?
  public let filename: String?
  public let originalFilename: String?
  public let uploadDate: String?
  public let status: String?
  public let detail: String?
  public let sound: URL?

  /// ``uploadDate`` parsed as a `Date`, or `nil` if absent or unrecognized.
  public var uploadedDate: Date? { freesoundDate(uploadDate) }

  enum CodingKeys: String, CodingKey {
    case id
    case filename
    case originalFilename = "original_filename"
    case uploadDate = "upload_date"
    case status
    case detail
    case sound
  }

  public init(
    id: Int? = nil,
    filename: String? = nil,
    originalFilename: String? = nil,
    uploadDate: String? = nil,
    status: String? = nil,
    detail: String? = nil,
    sound: URL? = nil
  ) {
    self.id = id
    self.filename = filename
    self.originalFilename = originalFilename
    self.uploadDate = uploadDate
    self.status = status
    self.detail = detail
    self.sound = sound
  }
}

public struct UploadSoundResponse: Decodable, Sendable, Equatable, Hashable {
  public let id: Int?
  public let filename: String?
  public let detail: String?
  public let uploadURL: URL?
  public let sound: URL?

  enum CodingKeys: String, CodingKey {
    case id
    case filename
    case detail
    case uploadURL = "upload_url"
    case sound
  }

  public init(
    id: Int? = nil,
    filename: String? = nil,
    detail: String? = nil,
    uploadURL: URL? = nil,
    sound: URL? = nil
  ) {
    self.id = id
    self.filename = filename
    self.detail = detail
    self.uploadURL = uploadURL
    self.sound = sound
  }
}

// MARK: - Timestamp parsing

// Freesound reports times as naive ISO-8601-like strings with no timezone — for
// example "2014-04-16T20:07:11.145" (sounds, with milliseconds) or
// "2008-08-07T17:39:00" (users, without). The stock one-shot parsers expect a
// timezone, so these `Date.ParseStrategy` values parse the two shapes explicitly
// as UTC. They're `Sendable` value types, so a single instance of each is reused
// across every call.
private let freesoundDateWithFraction = Date.ParseStrategy(
  format:
    "\(year: .defaultDigits)-\(month: .twoDigits)-\(day: .twoDigits)T\(hour: .twoDigits(clock: .twentyFourHour, hourCycle: .zeroBased)):\(minute: .twoDigits):\(second: .twoDigits).\(secondFraction: .fractional(3))",
  locale: Locale(identifier: "en_US_POSIX"),
  timeZone: .gmt
)

private let freesoundDateWholeSeconds = Date.ParseStrategy(
  format:
    "\(year: .defaultDigits)-\(month: .twoDigits)-\(day: .twoDigits)T\(hour: .twoDigits(clock: .twentyFourHour, hourCycle: .zeroBased)):\(minute: .twoDigits):\(second: .twoDigits)",
  locale: Locale(identifier: "en_US_POSIX"),
  timeZone: .gmt
)

/// Parses a Freesound timestamp, returning `nil` for `nil`, empty, or
/// unrecognized input.
func freesoundDate(_ string: String?) -> Date? {
  guard let string, !string.isEmpty else { return nil }
  if let date = try? Date(string, strategy: freesoundDateWithFraction) { return date }
  return try? Date(string, strategy: freesoundDateWholeSeconds)
}
