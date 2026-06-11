//
//  main.swift
//  FreesoundKitTester
//
//  Created by Cody Bromley on 6/9/26.
//

import Foundation
import FreesoundKit

@main
enum FreesoundKitTester {
    static func main() async {
        let arguments = Array(CommandLine.arguments.dropFirst())
        let parser = CLIParser(arguments: arguments)

        guard let command = parser.command else {
            printUsage()
            return
        }

        do {
            switch command {
            case "help", "--help", "-h":
                printUsage()
            case "search":
                try await runSearch(parser: parser)
            case "oauth-url":
                try runOAuthURL(parser: parser)
            case "oauth-exchange":
                try await runOAuthExchange(parser: parser)
            case "oauth-refresh":
                try await runOAuthRefresh(parser: parser)
            case "me":
                try await runMe(parser: parser)
            default:
                throw CLIError.unknownCommand(command)
            }
        } catch {
            try? FileHandle.standardError.write(contentsOf: Data("Error: \(error)\n\n".utf8))
            printUsage()
            Foundation.exit(1)
        }
    }

    private static func runSearch(parser: CLIParser) async throws {
        let apiKey = try parser.requiredValue(flags: ["--api-key"], env: "FREESOUND_API_KEY")
        let query = try parser.requiredValue(flags: ["--query"])
        let fields = parser.value(flags: ["--fields"])
        let pageSize = parser.value(flags: ["--page-size"])

        let client = FreesoundClient(authentication: .apiKey(apiKey))
        var parameters: [String: String?] = [:]
        parameters["fields"] = fields
        parameters["page_size"] = pageSize
        let result = try await client.textSearch(query: query, parameters: parameters)

        print("count: \(result.count ?? result.results.count)")
        for sound in result.results.prefix(10) {
            print("- \(sound.id): \(sound.name ?? "<unnamed>")")
        }
    }

    private static func runOAuthURL(parser: CLIParser) throws {
        let clientID = try parser.requiredValue(flags: ["--client-id"], env: "FREESOUND_CLIENT_ID")
        let state = parser.value(flags: ["--state"])
        let redirectURI = parser.value(flags: ["--redirect-uri", "--redirect"])
        let forceLogin = parser.hasFlag("--force-login")

        let client = FreesoundClient()
        let url = try client.oauthAuthorizationURL(
            clientID: clientID,
            responseState: state,
            redirectURI: redirectURI,
            forceLogin: forceLogin
        )
        print(url.absoluteString)
    }

    private static func runOAuthExchange(parser: CLIParser) async throws {
        let clientID = try parser.requiredValue(flags: ["--client-id"], env: "FREESOUND_CLIENT_ID")
        let clientSecret = try parser.requiredValue(
            flags: ["--client-secret"], env: "FREESOUND_CLIENT_SECRET")
        let code = try parser.requiredValue(flags: ["--code"])

        let client = FreesoundClient()
        let token = try await client.exchangeAuthorizationCode(
            clientID: clientID,
            clientSecret: clientSecret,
            code: code
        )

        print("access_token: \(token.accessToken)")
        print("expires_in: \(token.expiresIn)")
        print("refresh_token: \(token.refreshToken)")
        if let scope = token.scope {
            print("scope: \(scope)")
        }
    }

    private static func runOAuthRefresh(parser: CLIParser) async throws {
        let clientID = try parser.requiredValue(flags: ["--client-id"], env: "FREESOUND_CLIENT_ID")
        let clientSecret = try parser.requiredValue(
            flags: ["--client-secret"], env: "FREESOUND_CLIENT_SECRET")
        let refreshToken = try parser.requiredValue(
            flags: ["--refresh-token"], env: "FREESOUND_REFRESH_TOKEN")

        let client = FreesoundClient()
        let token = try await client.refreshAccessToken(
            clientID: clientID,
            clientSecret: clientSecret,
            refreshToken: refreshToken
        )

        print("access_token: \(token.accessToken)")
        print("expires_in: \(token.expiresIn)")
        print("refresh_token: \(token.refreshToken)")
        if let scope = token.scope {
            print("scope: \(scope)")
        }
    }

    private static func runMe(parser: CLIParser) async throws {
        let accessToken = try parser.requiredValue(
            flags: ["--access-token"], env: "FREESOUND_ACCESS_TOKEN")
        let client = FreesoundClient(authentication: .oauthToken(accessToken))
        let me = try await client.me()
        print("username: \(me.username)")
        if let url = me.url {
            print("url: \(url.absoluteString)")
        }
    }

    private static func printUsage() {
        let usage = """
            FreesoundKit local tester

            Usage:
              swift run freesound-tester <command> [options]

            Commands:
              search          Text search using API key auth
              oauth-url       Build OAuth2 authorization URL
              oauth-exchange  Exchange authorization code for tokens
              oauth-refresh   Refresh access token
              me              Call /me endpoint using OAuth access token

            Options:
              search --api-key <key> --query <text> [--fields <csv>] [--page-size <n>]
              oauth-url --client-id <id> [--state <state>] [--redirect-uri <uri>] [--force-login]
              oauth-exchange --client-id <id> --client-secret <secret> --code <code>
              oauth-refresh --client-id <id> --client-secret <secret> --refresh-token <token>
              me --access-token <token>

            Environment variable fallbacks:
              FREESOUND_API_KEY
              FREESOUND_CLIENT_ID
              FREESOUND_CLIENT_SECRET
              FREESOUND_REFRESH_TOKEN
              FREESOUND_ACCESS_TOKEN
            """
        print(usage)
    }
}

private struct CLIParser {
    let arguments: [String]
    var command: String? { arguments.first }

    func hasFlag(_ flag: String) -> Bool {
        arguments.contains(flag)
    }

    func value(flags: [String]) -> String? {
        for (index, arg) in arguments.enumerated() where flags.contains(arg) {
            let nextIndex = arguments.index(after: index)
            guard nextIndex < arguments.count else { return nil }
            let next = arguments[nextIndex]
            if next.hasPrefix("--") { return nil }
            return next
        }
        return nil
    }

    func requiredValue(flags: [String], env: String? = nil) throws -> String {
        if let value = value(flags: flags) {
            return value
        }
        if let env, let envValue = ProcessInfo.processInfo.environment[env], !envValue.isEmpty {
            return envValue
        }
        throw CLIError.missingRequired(flags.first ?? "value")
    }
}

private enum CLIError: Error, CustomStringConvertible {
    case unknownCommand(String)
    case missingRequired(String)

    var description: String {
        switch self {
        case .unknownCommand(let command):
            return "Unknown command: \(command)"
        case .missingRequired(let value):
            return "Missing required option: \(value)"
        }
    }
}
