//
//  ErrorTypes.swift
//  EnvPocket
//
//  Created by Claude Code
//  Copyright © 2025 thieso2. All rights reserved.
//
//  MIT License
//

import Foundation

// MARK: - Keychain Error Handling

enum KeychainError: Error {
    case accessDenied
    case itemNotFound
    case duplicateItem
    case invalidParameters
    case interactionNotAllowed
    case operationNotPermitted
    case unknown(OSStatus)

    init(status: OSStatus) {
        switch status {
        case errSecSuccess:
            fatalError("errSecSuccess should not create an error")
        case errSecItemNotFound, -25300:  // -25300 is also item not found
            self = .itemNotFound
        case errSecDuplicateItem, -25299:
            self = .duplicateItem
        case errSecParam, -50:
            self = .invalidParameters
        case errSecAuthFailed, -25293:
            self = .accessDenied
        case errSecInteractionNotAllowed, -25308:
            self = .interactionNotAllowed
        case -34018:  // Operation not permitted (sandbox/entitlements)
            self = .operationNotPermitted
        default:
            self = .unknown(status)
        }
    }

    var userMessage: String {
        switch self {
        case .accessDenied:
            return "Keychain access denied. Please allow access in System Preferences > Security & Privacy."
        case .itemNotFound:
            return "Item not found in keychain."
        case .duplicateItem:
            return "Item already exists in keychain."
        case .invalidParameters:
            return "Invalid parameters provided to keychain operation."
        case .interactionNotAllowed:
            return "Keychain interaction not allowed. Please unlock your keychain."
        case .operationNotPermitted:
            return "Operation not permitted. This may be due to sandboxing or missing entitlements."
        case .unknown(let status):
            return "Keychain error: \(status)"
        }
    }
}

// MARK: - User Message Types

enum UserMessage {
    case success(String)
    case error(String)
    case warning(String)
    case info(String)

    func display() {
        switch self {
        case .success(let message):
            print("✓ \(message)")
        case .error(let message):
            fputs("Error: \(message)\n", stderr)
        case .warning(let message):
            fputs("Warning: \(message)\n", stderr)
        case .info(let message):
            print(message)
        }
    }

    // Static methods for common messages
    static func keychainError(_ status: OSStatus) -> UserMessage {
        if status == errSecSuccess {
            fatalError("errSecSuccess should not be an error")
        }
        let error = KeychainError(status: status)
        return .error(error.userMessage)
    }

    static func fileReadError(_ path: String) -> UserMessage {
        .error("Could not read file at \(path). Check that the file exists and you have permission to read it.")
    }

    static func fileWriteError(_ path: String, _ error: Error) -> UserMessage {
        .error("Could not write file to \(path): \(error.localizedDescription)")
    }

    static func fileSaved(_ key: String, _ path: String) -> UserMessage {
        .success("File saved to Keychain under key '\(key)' from \(path)")
    }

    static func valueSaved(_ key: String) -> UserMessage {
        .success("Value saved to Keychain under key '\(key)'")
    }

    static func previousVersionBackedUp() -> UserMessage {
        .info("Previous version backed up to history")
    }

    static func fileRetrieved(_ path: String) -> UserMessage {
        .success("File retrieved and saved to \(path)")
    }

    static func historicalVersion() -> UserMessage {
        .info("(Retrieved historical version)")
    }

    static func keyDeleted(_ key: String, historyCount: Int = 0) -> UserMessage {
        var message = "Deleted key '\(key)' from Keychain"
        if historyCount > 0 {
            message += "\nAlso deleted \(historyCount) history entr\(historyCount == 1 ? "y" : "ies")"
        }
        return .success(message)
    }

    static func keyNotFound(_ key: String) -> UserMessage {
        .error("Key '\(key)' not found")
    }

    static func invalidVersionIndex(_ key: String) -> UserMessage {
        .error("Invalid version index. Use 'envpocket history \(key)' to see available versions.")
    }

    static func noOriginalFilename(_ key: String) -> UserMessage {
        .error("No original filename stored for key '\(key)'. Please specify an output file.")
    }

    static func encryptionError(_ message: String) -> UserMessage {
        .error("Encryption failed: \(message)")
    }

    static func decryptionError() -> UserMessage {
        .error("Decryption failed - incorrect password or corrupted file")
    }

    static func exportSuccess(_ path: String) -> UserMessage {
        .success("Encrypted file exported to '\(path)'\nShare this file and password with your team to grant access")
    }

    static func importSuccess(_ key: String, historyCount: Int = 0) -> UserMessage {
        if historyCount > 0 {
            return .success("Successfully imported '\(key)' with \(historyCount) history version\(historyCount == 1 ? "" : "s")")
        }
        return .success("Successfully imported '\(key)'")
    }

    static func fileExists(_ path: String) -> UserMessage {
        .warning("File '\(path)' already exists.")
    }

    static func operationCancelled() -> UserMessage {
        .info("Operation cancelled.")
    }

    static func noKeysMatching(_ pattern: String) -> UserMessage {
        .error("No keys found matching pattern '\(pattern)'")
    }

    static func deletionCancelled() -> UserMessage {
        .info("Deletion cancelled.")
    }

    static func keysDeleted(_ count: Int) -> UserMessage {
        .success("Deleted \(count) key\(count == 1 ? "" : "s").")
    }

    static func listError(_ status: OSStatus) -> UserMessage {
        .error("Error listing Keychain items: \(status)")
    }

    static func noEntriesFound() -> UserMessage {
        .info("No envpocket entries found.")
    }

    static func noHistoryFound(_ key: String) -> UserMessage {
        .info("No history found for key '\(key)'")
    }

    static func invalidFileFormat() -> UserMessage {
        .error("Invalid encrypted file format")
    }

    static func invalidFileHeader() -> UserMessage {
        .error("Invalid file header. This doesn't appear to be an envpocket export file.")
    }

    static func corruptedFile() -> UserMessage {
        .error("Corrupted encrypted file")
    }

    static func derivationError() -> UserMessage {
        .error("Failed to derive encryption key")
    }

    static func parseError() -> UserMessage {
        .error("Failed to parse decrypted data")
    }

    static func saveError(_ status: OSStatus) -> UserMessage {
        .error("Failed to save to keychain - \(status)")
    }

    static func serializationError() -> UserMessage {
        .error("Failed to serialize export data")
    }
}
