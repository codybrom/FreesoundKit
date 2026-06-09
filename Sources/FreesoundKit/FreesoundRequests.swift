//
//  FreesoundRequests.swift
//  FreesoundKit
//
//  Created by Cody Bromley on 6/9/26.
//

import Foundation

public struct SoundUploadRequest: Sendable {
    public var tags: [String]
    public var description: String
    public var license: String
    public var name: String?
    public var bstCategory: String?
    public var pack: String?
    public var geotag: String?

    public init(
        tags: [String],
        description: String,
        license: String,
        name: String? = nil,
        bstCategory: String? = nil,
        pack: String? = nil,
        geotag: String? = nil
    ) {
        self.tags = tags
        self.description = description
        self.license = license
        self.name = name
        self.bstCategory = bstCategory
        self.pack = pack
        self.geotag = geotag
    }

    var asFormFields: [String: String] {
        var fields: [String: String] = [
            "tags": tags.joined(separator: " "),
            "description": description,
            "license": license,
        ]
        if let name {
            fields["name"] = name
        }
        if let bstCategory {
            fields["bst_category"] = bstCategory
        }
        if let pack {
            fields["pack"] = pack
        }
        if let geotag {
            fields["geotag"] = geotag
        }
        return fields
    }
}

public struct SoundDescribeRequest: Sendable {
    /// Filename of a previously uploaded sound, as returned by `pendingUploads()`.
    public var uploadFilename: String
    /// Broad Sound Taxonomy category id (required by the describe endpoint).
    public var bstCategory: String
    public var tags: [String]
    public var description: String
    public var license: String
    public var name: String?
    public var pack: String?
    public var geotag: String?

    public init(
        uploadFilename: String,
        bstCategory: String,
        tags: [String],
        description: String,
        license: String,
        name: String? = nil,
        pack: String? = nil,
        geotag: String? = nil
    ) {
        self.uploadFilename = uploadFilename
        self.bstCategory = bstCategory
        self.tags = tags
        self.description = description
        self.license = license
        self.name = name
        self.pack = pack
        self.geotag = geotag
    }

    var asFormFields: [String: String] {
        var fields: [String: String] = [
            "upload_filename": uploadFilename,
            "bst_category": bstCategory,
            "tags": tags.joined(separator: " "),
            "description": description,
            "license": license,
        ]
        if let name {
            fields["name"] = name
        }
        if let pack {
            fields["pack"] = pack
        }
        if let geotag {
            fields["geotag"] = geotag
        }
        return fields
    }
}
