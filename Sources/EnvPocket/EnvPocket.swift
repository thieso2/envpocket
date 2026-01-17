//
//  EnvPocket.swift
//  EnvPocket
//
//  Created by thieso2 on 2024.
//  Copyright © 2025 thieso2. All rights reserved.
//
//  MIT License
//
//  Permission is hereby granted, free of charge, to any person obtaining a copy
//  of this software and associated documentation files (the "Software"), to deal
//  in the Software without restriction, including without limitation the rights
//  to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
//  copies of the Software, and to permit persons to whom the Software is
//  furnished to do so, subject to the following conditions:
//
//  The above copyright notice and this permission notice shall be included in all
//  copies or substantial portions of the Software.
//
//  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
//  IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
//  FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
//  AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
//  LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
//  OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
//  SOFTWARE.
//

import Foundation
import CryptoKit
import CommonCrypto

class EnvPocket {
    private let keychain: KeychainProtocol
    private let vault: String?
    private let prefix = "envpocket:"
    private let historyPrefix = "envpocket-history:"

    init(keychain: KeychainProtocol = RealKeychain(), vault: String? = nil) {
        self.keychain = keychain
        self.vault = vault
    }

    private func validateVaultName(_ vault: String?) -> Bool {
        guard let vault = vault else { return true }
        guard vault.count >= 1 && vault.count <= 100 else { return false }
        // Allow: letters, numbers, /, _, -
        let validPattern = "^[a-zA-Z0-9/_-]+$"
        return vault.range(of: validPattern, options: .regularExpression) != nil
    }
    
    private func getDateFormatter() -> ISO8601DateFormatter {
        return ISO8601DateFormatter()
    }
    
    private func prefixedKey(_ key: String) -> String {
        if let vault = vault {
            return prefix + vault + "::" + key
        }
        return prefix + key
    }

    private func historyKey(_ key: String, timestamp: Date) -> String {
        if let vault = vault {
            return historyPrefix + vault + "::" + key + ":" + getDateFormatter().string(from: timestamp)
        }
        return historyPrefix + key + ":" + getDateFormatter().string(from: timestamp)
    }

    private func parseVaultAndKey(_ accountWithoutPrefix: String) -> (vault: String?, key: String) {
        let components = accountWithoutPrefix.components(separatedBy: "::")
        if components.count == 2 {
            return (components[0], components[1])
        }
        return (nil, accountWithoutPrefix)
    }

    func saveFile(key: String, filePath: String) -> Bool {
        let account = prefixedKey(key)
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: filePath)) else {
            UserMessage.fileReadError(filePath).display()
            return false
        }

        // Get absolute path for storage
        let fileURL = URL(fileURLWithPath: filePath)
        let absolutePath = fileURL.path

        // Get current version if it exists and save to history
        let (currentData, currentAttributes, currentStatus) = keychain.load(account: account)

        // If there's an existing version, save it to history with current timestamp
        if currentStatus == errSecSuccess,
           let currentData = currentData {
            let timestamp = Date()
            let historyAccount = historyKey(key, timestamp: timestamp)

            // Preserve the original path from the current version if it exists
            let originalPath = currentAttributes?[kSecAttrLabel as String] as? String ?? absolutePath

            let historyStatus = keychain.save(
                account: historyAccount,
                data: currentData,
                label: originalPath,
                comment: nil
            )

            if historyStatus != errSecSuccess {
                UserMessage.warning("Failed to save history: \(KeychainError(status: historyStatus).userMessage)").display()
            }
        }

        // Now save the new version as current with file path
        let newTimestamp = Date()
        let status = keychain.save(
            account: account,
            data: data,
            label: absolutePath,
            comment: "Last modified: \(getDateFormatter().string(from: newTimestamp))"
        )

        if status == errSecSuccess {
            UserMessage.fileSaved(key, absolutePath).display()
            if currentStatus == errSecSuccess {
                UserMessage.previousVersionBackedUp().display()
            }
            return true
        } else {
            UserMessage.keychainError(status).display()
            return false
        }
    }
    
    func setValue(key: String, value: String) -> Bool {
        let account = prefixedKey(key)
        guard let data = value.data(using: .utf8) else {
            UserMessage.error("Could not encode value").display()
            return false
        }

        // Get current version if it exists and save to history
        let (currentData, currentAttributes, currentStatus) = keychain.load(account: account)

        // If there's an existing version, save it to history with current timestamp
        if currentStatus == errSecSuccess,
           let currentData = currentData {
            let timestamp = Date()
            let historyAccount = historyKey(key, timestamp: timestamp)

            // Preserve the original label from the current version if it exists
            let originalLabel = currentAttributes?[kSecAttrLabel as String] as? String ?? "(direct value)"

            let historyStatus = keychain.save(
                account: historyAccount,
                data: currentData,
                label: originalLabel,
                comment: nil
            )

            if historyStatus != errSecSuccess {
                UserMessage.warning("Failed to save history: \(KeychainError(status: historyStatus).userMessage)").display()
            }
        }

        // Now save the new version as current
        let newTimestamp = Date()
        let status = keychain.save(
            account: account,
            data: data,
            label: "(direct value)",
            comment: "Last modified: \(getDateFormatter().string(from: newTimestamp))"
        )

        if status == errSecSuccess {
            UserMessage.valueSaved(key).display()
            if currentStatus == errSecSuccess {
                UserMessage.previousVersionBackedUp().display()
            }
            return true
        } else {
            UserMessage.keychainError(status).display()
            return false
        }
    }

    func getFile(key: String, outputPath: String? = nil, versionIndex: Int? = nil, force: Bool = false) -> Bool {
        var account = prefixedKey(key)

        // If version specified, get from history
        if let version = versionIndex {
            let historyItems = getHistoryForKey(key)
            if version >= 0 && version < historyItems.count {
                account = historyItems[version]
            } else {
                UserMessage.invalidVersionIndex(key).display()
                return false
            }
        }

        let (data, attributes, status) = keychain.load(account: account)

        if status == errSecSuccess,
           let data = data {

            // Determine output destination
            let finalOutputPath: String
            if let specifiedPath = outputPath {
                if specifiedPath == "-" {
                    // Write to stdout
                    FileHandle.standardOutput.write(data)
                    if versionIndex != nil {
                        FileHandle.standardError.write("(Retrieved historical version)\n".data(using: .utf8)!)
                    }
                    return true
                } else {
                    finalOutputPath = specifiedPath
                }
            } else {
                // Use original filename from keychain
                if let originalPath = attributes?[kSecAttrLabel as String] as? String {
                    // Extract just the filename from the full path
                    let url = URL(fileURLWithPath: originalPath)
                    finalOutputPath = url.lastPathComponent
                } else {
                    UserMessage.noOriginalFilename(key).display()
                    return false
                }
            }

            // Check if file exists and prompt for overwrite if not forced
            if FileManager.default.fileExists(atPath: finalOutputPath) && !force {
                UserMessage.fileExists(finalOutputPath).display()
                print("Overwrite? (y/n): ", terminator: "")
                fflush(stdout)
                guard let response = readLine()?.lowercased(),
                      response == "y" || response == "yes" else {
                    UserMessage.operationCancelled().display()
                    return false
                }
            }

            do {
                try data.write(to: URL(fileURLWithPath: finalOutputPath))
                UserMessage.fileRetrieved(finalOutputPath).display()
                if versionIndex != nil {
                    UserMessage.historicalVersion().display()
                }
                return true
            } catch {
                UserMessage.fileWriteError(finalOutputPath, error).display()
                return false
            }
        } else {
            UserMessage.keychainError(status).display()
            return false
        }
    }
    
    func matchKeys(pattern: String) -> [String] {
        let (items, status) = keychain.list()
        guard status == errSecSuccess else {
            return []
        }

        var matchedKeys: [String] = []

        for item in items {
            if let account = item[kSecAttrAccount as String] as? String,
               account.hasPrefix(prefix) && !account.hasPrefix(historyPrefix) {

                let withoutPrefix = String(account.dropFirst(prefix.count))
                let (parsedVault, parsedKey) = parseVaultAndKey(withoutPrefix)

                // Filter by vault context
                if let vault = vault {
                    guard parsedVault == vault else { continue }
                } else {
                    guard parsedVault == nil else { continue }  // Only non-vaulted
                }

                // Check if key matches pattern
                if matchesPattern(parsedKey, pattern: pattern) {
                    matchedKeys.append(parsedKey)
                }
            }
        }

        return matchedKeys.sorted()
    }
    
    private func matchesPattern(_ text: String, pattern: String) -> Bool {
        // Convert wildcard pattern to regex
        var regexPattern = "^"
        for char in pattern {
            switch char {
            case "*":
                regexPattern += ".*"
            case "?":
                regexPattern += "."
            case ".", "+", "(", ")", "[", "]", "{", "}", "^", "$", "|", "\\":
                regexPattern += "\\\(char)"
            default:
                regexPattern += String(char)
            }
        }
        regexPattern += "$"
        
        return text.range(of: regexPattern, options: .regularExpression) != nil
    }
    
    func deleteFile(key: String, force: Bool = false) -> Bool {
        // Check if key contains wildcards
        if key.contains("*") || key.contains("?") {
            let matchedKeys = matchKeys(pattern: key)

            if matchedKeys.isEmpty {
                UserMessage.noKeysMatching(key).display()
                return false
            }

            // Show matched keys and ask for confirmation
            if !force {
                UserMessage.info("The following keys will be deleted:").display()
                for matchedKey in matchedKeys {
                    let historyCount = getHistoryForKey(matchedKey).count
                    if historyCount > 0 {
                        UserMessage.info("  • \(matchedKey) (plus \(historyCount) history version\(historyCount == 1 ? "" : "s"))").display()
                    } else {
                        UserMessage.info("  • \(matchedKey)").display()
                    }
                }

                print("\nAre you sure you want to delete \(matchedKeys.count) key\(matchedKeys.count == 1 ? "" : "s")? (yes/no): ", terminator: "")

                if let response = readLine()?.lowercased(),
                   response != "yes" && response != "y" {
                    UserMessage.deletionCancelled().display()
                    return false
                }
            }

            // Delete all matched keys
            var successCount = 0
            for matchedKey in matchedKeys {
                if deleteSingleKey(matchedKey) {
                    successCount += 1
                }
            }

            UserMessage.keysDeleted(successCount).display()
            return successCount == matchedKeys.count
        } else {
            // Single key deletion
            return deleteSingleKey(key)
        }
    }
    
    private func deleteSingleKey(_ key: String) -> Bool {
        // Delete current version
        let account = prefixedKey(key)
        let status = keychain.delete(account: account)

        // Delete all history entries for this key
        let (items, historyStatus) = keychain.list()

        // Construct the history prefix pattern based on vault
        let historyPattern: String
        if let vault = vault {
            historyPattern = historyPrefix + vault + "::" + key + ":"
        } else {
            historyPattern = historyPrefix + key + ":"
        }

        var historyDeleted = 0
        if historyStatus == errSecSuccess {
            for item in items {
                if let account = item[kSecAttrAccount as String] as? String,
                   account.hasPrefix(historyPattern) {
                    if keychain.delete(account: account) == errSecSuccess {
                        historyDeleted += 1
                    }
                }
            }
        }

        if status == errSecSuccess {
            UserMessage.keyDeleted(key, historyCount: historyDeleted).display()
            return true
        } else if status == errSecItemNotFound {
            UserMessage.keyNotFound(key).display()
            return false
        } else {
            UserMessage.keychainError(status).display()
            return false
        }
    }
    
    func listKeys() {
        let (items, status) = keychain.list()

        guard status == errSecSuccess else {
            UserMessage.listError(status).display()
            return
        }

        var keyInfo: [String: (current: Date?, historyCount: Int, filePath: String?, vault: String?)] = [:]

        for item in items {
            if let account = item[kSecAttrAccount as String] as? String {
                if account.hasPrefix(prefix) && !account.hasPrefix(historyPrefix) {
                    let withoutPrefix = String(account.dropFirst(prefix.count))
                    let (parsedVault, parsedKey) = parseVaultAndKey(withoutPrefix)

                    // Filter by vault context
                    if let vault = vault {
                        guard parsedVault == vault else { continue }
                    } else {
                        guard parsedVault == nil else { continue }  // Only non-vaulted
                    }

                    // Try to extract date from comment
                    var modDate: Date? = nil
                    if let comment = item[kSecAttrComment as String] as? String,
                       comment.hasPrefix("Last modified: ") {
                        let dateStr = String(comment.dropFirst("Last modified: ".count))
                        modDate = getDateFormatter().date(from: dateStr)
                    }

                    // Extract file path from label
                    let filePath = item[kSecAttrLabel as String] as? String

                    if keyInfo[parsedKey] == nil {
                        keyInfo[parsedKey] = (current: modDate, historyCount: 0, filePath: filePath, vault: parsedVault)
                    } else {
                        keyInfo[parsedKey]?.current = modDate
                        keyInfo[parsedKey]?.filePath = filePath
                    }
                } else if account.hasPrefix(historyPrefix) {
                    // Extract key from history entry: envpocket-history:[vault::]key:timestamp
                    let withoutPrefix = String(account.dropFirst(historyPrefix.count))

                    // Check for vault separator first
                    if withoutPrefix.contains("::") {
                        let parts = withoutPrefix.components(separatedBy: "::")
                        if parts.count == 2 {
                            let parsedVault = parts[0]
                            let keyAndTimestamp = parts[1]

                            // Filter by vault context
                            if let vault = vault {
                                guard parsedVault == vault else { continue }
                            } else {
                                continue  // Skip vaulted history when not in vault mode
                            }

                            // Extract key from keyAndTimestamp
                            if let colonIndex = keyAndTimestamp.firstIndex(of: ":") {
                                let key = String(keyAndTimestamp[..<colonIndex])
                                if keyInfo[key] == nil {
                                    keyInfo[key] = (current: nil, historyCount: 1, filePath: nil, vault: parsedVault)
                                } else {
                                    keyInfo[key]?.historyCount += 1
                                }
                            }
                        }
                    } else {
                        // No vault separator, this is a non-vaulted history entry
                        if vault != nil {
                            continue  // Skip non-vaulted history when in vault mode
                        }

                        if let colonIndex = withoutPrefix.firstIndex(of: ":") {
                            let key = String(withoutPrefix[..<colonIndex])
                            if keyInfo[key] == nil {
                                keyInfo[key] = (current: nil, historyCount: 1, filePath: nil, vault: nil)
                            } else {
                                keyInfo[key]?.historyCount += 1
                            }
                        }
                    }
                }
            }
        }

        if keyInfo.isEmpty {
            UserMessage.noEntriesFound().display()
        } else {
            UserMessage.info("envpocket entries:").display()
            let formatter = DateFormatter()
            formatter.dateStyle = .short
            formatter.timeStyle = .short

            for (key, info) in keyInfo.sorted(by: { $0.key < $1.key }) {
                var line = "  • \(key)"

                // Add file path if available
                if let filePath = info.filePath {
                    // Decode URL encoding and show a more readable path
                    let decodedPath = filePath.removingPercentEncoding ?? filePath
                    line += " (\(decodedPath))"
                }

                if let modDate = info.current {
                    line += " [modified: \(formatter.string(from: modDate))]"
                }

                if info.historyCount > 0 {
                    line += " [\(info.historyCount) version\(info.historyCount == 1 ? "" : "s") in history]"
                }

                UserMessage.info(line).display()
            }
            UserMessage.info("\nUse 'envpocket history <key>' to see version history").display()
        }
    }

    func listVaults() {
        let (items, status) = keychain.list()
        guard status == errSecSuccess else {
            UserMessage.listError(status).display()
            return
        }

        var vaults: Set<String> = []
        var unvaultedCount = 0

        for item in items {
            if let account = item[kSecAttrAccount as String] as? String,
               account.hasPrefix(prefix) && !account.hasPrefix(historyPrefix) {
                let withoutPrefix = String(account.dropFirst(prefix.count))
                let (parsedVault, _) = parseVaultAndKey(withoutPrefix)

                if let vault = parsedVault {
                    vaults.insert(vault)
                } else {
                    unvaultedCount += 1
                }
            }
        }

        if vaults.isEmpty && unvaultedCount == 0 {
            print("No vaults or entries found")
        } else {
            print("Available vaults:")
            for vault in vaults.sorted() {
                print("  • \(vault)")
            }
            if unvaultedCount > 0 {
                print("  • (default) - \(unvaultedCount) unvaulted entr\(unvaultedCount == 1 ? "y" : "ies")")
            }
        }
    }

    private func getHistoryForKey(_ key: String) -> [String] {
        let (items, status) = keychain.list()

        guard status == errSecSuccess else {
            return []
        }

        var historyAccounts: [(account: String, date: Date)] = []

        // Construct the history prefix pattern based on vault
        let historyPattern: String
        if let vault = vault {
            historyPattern = historyPrefix + vault + "::" + key + ":"
        } else {
            historyPattern = historyPrefix + key + ":"
        }

        for item in items {
            if let account = item[kSecAttrAccount as String] as? String,
               account.hasPrefix(historyPattern) {
                // Extract timestamp from account string
                let timestampStr = String(account.dropFirst(historyPattern.count))
                if let date = getDateFormatter().date(from: timestampStr) {
                    historyAccounts.append((account: account, date: date))
                }
            }
        }

        // Sort by date descending (newest first)
        historyAccounts.sort { $0.date > $1.date }

        return historyAccounts.map { $0.account }
    }
    
    func showHistory(key: String) {
        let historyItems = getHistoryForKey(key)

        if historyItems.isEmpty {
            UserMessage.noHistoryFound(key).display()
        } else {
            UserMessage.info("History for '\(key)':").display()
            for (index, account) in historyItems.enumerated() {
                let timestampStr = String(account.dropFirst((historyPrefix + key + ":").count))
                if let date = getDateFormatter().date(from: timestampStr) {
                    let formatter = DateFormatter()
                    formatter.dateStyle = .medium
                    formatter.timeStyle = .medium
                    UserMessage.info("  \(index): \(formatter.string(from: date))").display()
                }
            }
            UserMessage.info("\nUse 'envpocket get \(key) --version <index> <output_file>' to retrieve a specific version").display()
        }
    }
    
    // MARK: - Encryption/Decryption for Team Sharing
    
    private func deriveKey(from password: String, salt: Data) -> SymmetricKey? {
        guard let passwordData = password.data(using: .utf8) else { return nil }
        
        // Use PBKDF2 to derive a key from the password
        let keyData = pbkdf2(password: passwordData, salt: salt, iterations: 100_000, keyLength: 32)
        return SymmetricKey(data: keyData)
    }
    
    private func pbkdf2(password: Data, salt: Data, iterations: Int, keyLength: Int) -> Data {
        var derivedKey = Data(count: keyLength)
        let result = derivedKey.withUnsafeMutableBytes { derivedKeyBytes in
            password.withUnsafeBytes { passwordBytes in
                salt.withUnsafeBytes { saltBytes in
                    CCKeyDerivationPBKDF(
                        CCPBKDFAlgorithm(kCCPBKDF2),
                        passwordBytes.bindMemory(to: Int8.self).baseAddress!,
                        password.count,
                        saltBytes.bindMemory(to: UInt8.self).baseAddress!,
                        salt.count,
                        CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256),
                        UInt32(iterations),
                        derivedKeyBytes.bindMemory(to: UInt8.self).baseAddress!,
                        keyLength
                    )
                }
            }
        }
        guard result == kCCSuccess else {
            return Data()
        }
        return derivedKey
    }
    
    func exportEncrypted(key: String, password: String) -> Data? {
        let account = prefixedKey(key)
        let (data, attributes, status) = keychain.load(account: account)

        guard status == errSecSuccess, let data = data else {
            UserMessage.keyNotFound(key).display()
            return nil
        }

        // Generate a random salt
        let salt = Data((0..<32).map { _ in UInt8.random(in: 0...255) })

        // Derive encryption key from password
        guard let symmetricKey = deriveKey(from: password, salt: salt) else {
            UserMessage.derivationError().display()
            return nil
        }

        // Create metadata dictionary
        var metadata: [String: Any] = ["key": key]
        if let vault = vault {
            metadata["vault"] = vault
        }
        if let filePath = attributes?[kSecAttrLabel as String] as? String {
            metadata["originalPath"] = filePath
        }
        if let comment = attributes?[kSecAttrComment as String] as? String {
            metadata["lastModified"] = comment
        }

        // Include history versions
        let historyItems = getHistoryForKey(key)
        if !historyItems.isEmpty {
            var historyData: [[String: Any]] = []
            for historyAccount in historyItems {
                let (histData, histAttrs, histStatus) = keychain.load(account: historyAccount)
                if histStatus == errSecSuccess, let histData = histData {
                    var histEntry: [String: Any] = ["data": histData.base64EncodedString()]
                    if let histPath = histAttrs?[kSecAttrLabel as String] as? String {
                        histEntry["originalPath"] = histPath
                    }
                    // Extract timestamp from account name
                    let timestampStr = String(historyAccount.dropFirst((historyPrefix + key + ":").count))
                    histEntry["timestamp"] = timestampStr
                    historyData.append(histEntry)
                }
            }
            metadata["history"] = historyData
        }

        // Combine file data and metadata
        let exportData: [String: Any] = [
            "data": data.base64EncodedString(),
            "metadata": metadata
        ]

        guard let jsonData = try? JSONSerialization.data(withJSONObject: exportData, options: .prettyPrinted) else {
            UserMessage.serializationError().display()
            return nil
        }

        // Encrypt the JSON data
        do {
            let sealedBox = try AES.GCM.seal(jsonData, using: symmetricKey)

            // Combine salt + nonce + ciphertext + tag for export
            var exportedData = Data()
            exportedData.append(salt)
            exportedData.append(contentsOf: sealedBox.nonce)
            exportedData.append(contentsOf: sealedBox.ciphertext)
            exportedData.append(contentsOf: sealedBox.tag)

            // Add a magic header to identify the file format
            let header = "ENVPOCKET_V1".data(using: .utf8)!
            var finalData = Data()
            finalData.append(header)
            finalData.append(exportedData)

            return finalData
        } catch {
            UserMessage.encryptionError(error.localizedDescription).display()
            return nil
        }
    }
    
    func importEncrypted(key: String, encryptedData: Data, password: String) -> Bool {
        // Check for magic header
        let headerLength = "ENVPOCKET_V1".count
        guard encryptedData.count > headerLength else {
            UserMessage.invalidFileFormat().display()
            return false
        }

        let header = String(data: encryptedData.prefix(headerLength), encoding: .utf8)
        guard header == "ENVPOCKET_V1" else {
            UserMessage.invalidFileHeader().display()
            return false
        }

        // Remove header
        let dataWithoutHeader = encryptedData.dropFirst(headerLength)

        // Extract components
        guard dataWithoutHeader.count > 32 + 12 else { // salt + nonce minimum
            UserMessage.corruptedFile().display()
            return false
        }

        let salt = dataWithoutHeader.prefix(32)
        let nonceData = dataWithoutHeader.dropFirst(32).prefix(12)
        let remainder = dataWithoutHeader.dropFirst(32 + 12)

        guard remainder.count > 16 else { // Need at least tag size
            UserMessage.corruptedFile().display()
            return false
        }

        let ciphertext = remainder.dropLast(16)
        let tag = remainder.suffix(16)

        // Derive decryption key
        guard let symmetricKey = deriveKey(from: password, salt: salt) else {
            UserMessage.derivationError().display()
            return false
        }

        // Decrypt
        do {
            let nonce = try AES.GCM.Nonce(data: nonceData)
            let sealedBox = try AES.GCM.SealedBox(nonce: nonce, ciphertext: ciphertext, tag: tag)
            let decryptedData = try AES.GCM.open(sealedBox, using: symmetricKey)

            // Parse JSON
            guard let exportData = try? JSONSerialization.jsonObject(with: decryptedData) as? [String: Any],
                  let dataString = exportData["data"] as? String,
                  let fileData = Data(base64Encoded: dataString),
                  let metadata = exportData["metadata"] as? [String: Any] else {
                UserMessage.parseError().display()
                return false
            }

            // Extract metadata
            let originalPath = metadata["originalPath"] as? String
            let lastModified = metadata["lastModified"] as? String

            // Save current version to keychain
            let account = prefixedKey(key)
            let status = keychain.save(
                account: account,
                data: fileData,
                label: originalPath,
                comment: lastModified
            )

            guard status == errSecSuccess else {
                UserMessage.saveError(status).display()
                return false
            }

            // Import history if present
            if let history = metadata["history"] as? [[String: Any]] {
                var importedHistory = 0
                for histEntry in history {
                    if let histDataString = histEntry["data"] as? String,
                       let histData = Data(base64Encoded: histDataString),
                       let timestamp = histEntry["timestamp"] as? String {

                        // Construct history account with vault if present
                        let historyAccount: String
                        if let vault = vault {
                            historyAccount = historyPrefix + vault + "::" + key + ":" + timestamp
                        } else {
                            historyAccount = historyPrefix + key + ":" + timestamp
                        }
                        let histPath = histEntry["originalPath"] as? String

                        let histStatus = keychain.save(
                            account: historyAccount,
                            data: histData,
                            label: histPath,
                            comment: nil
                        )

                        if histStatus == errSecSuccess {
                            importedHistory += 1
                        }
                    }
                }

                UserMessage.importSuccess(key, historyCount: importedHistory).display()
            } else {
                UserMessage.importSuccess(key).display()
            }

            return true

        } catch {
            UserMessage.decryptionError().display()
            return false
        }
    }
}