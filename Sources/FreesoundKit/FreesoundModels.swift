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
}

/// The response from ``FreesoundClient/combinedSearch(parameters:)``.
///
/// Combined search does not report a total count, and pagination works through
/// the ``more`` link rather than page numbers. Fetch further results with
/// ``FreesoundClient/moreResults(of:)``.
public struct CombinedSearchResponse: Decodable, Sendable {
    public let results: [Sound]
    /// A link to the next batch of results, or `nil` when there are no more.
    public let more: String?
}

public struct APIStatusResponse: Decodable, Sendable {
    public let detail: String?
    public let status: String?
}

public struct OAuthTokenResponse: Decodable, Sendable {
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
}

public struct Sound: Decodable, Sendable {
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
}

public struct SoundPreviews: Decodable, Sendable {
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
}

/// A preview encoding offered by ``SoundPreviews``, used with
/// ``FreesoundClient/downloadPreview(for:format:)``.
public enum SoundPreviewFormat: Sendable {
    /// High-quality MP3 (~128 kbps).
    case hqMP3
    /// Low-quality MP3 (~64 kbps).
    case lqMP3
    /// High-quality Ogg Vorbis (~192 kbps).
    case hqOGG
    /// Low-quality Ogg Vorbis (~80 kbps).
    case lqOGG
}

public struct SoundImages: Decodable, Sendable {
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
}

public struct SoundAnalysis: Decodable, Sendable {
    public let descriptors: SoundDescriptors

    public init(from decoder: Decoder) throws {
        descriptors = try SoundDescriptors(from: decoder)
    }
}

public struct SoundDescriptors: Decodable, Sendable {
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
}

public struct Comment: Decodable, Sendable {
    public let id: Int?
    public let url: URL?
    public let username: String?
    public let comment: String?
    public let created: String?
}

public struct User: Decodable, Sendable {
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
}

public struct Pack: Decodable, Sendable {
    public let id: Int
    public let url: URL?
    public let name: String?
    public let description: String?
    public let username: String?
    public let created: String?
    public let numSounds: Int?
    public let sounds: URL?
    public let download: URL?

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
}

public struct Me: Decodable, Sendable {
    public let username: String
    public let url: URL?
    public let about: String?
    public let homepage: URL?
    public let avatar: URL?

    enum CodingKeys: String, CodingKey {
        case username
        case url
        case about
        case homepage
        case avatar
    }
}

public struct BookmarkCategory: Decodable, Sendable {
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
}

public struct PendingUploads: Decodable, Sendable {
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
}

public struct PendingUpload: Decodable, Sendable {
    public let id: Int?
    public let filename: String?
    public let originalFilename: String?
    public let uploadDate: String?
    public let status: String?
    public let detail: String?
    public let sound: URL?

    enum CodingKeys: String, CodingKey {
        case id
        case filename
        case originalFilename = "original_filename"
        case uploadDate = "upload_date"
        case status
        case detail
        case sound
    }
}

public struct UploadSoundResponse: Decodable, Sendable {
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
}
