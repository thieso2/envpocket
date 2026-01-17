//
//  EnvPocketMockTests.swift
//  EnvPocketTests
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

import Testing
import Foundation
@testable import EnvPocket

final class TestEnvironment {
    let mockKeychain: MockKeychain
    let envPocket: EnvPocket
    let testContent = "TEST_VAR=value\nANOTHER_VAR=secret123\n"
    let testFilePath: String

    init() {
        // Create mock keychain and EnvPocket instance
        mockKeychain = MockKeychain()
        envPocket = EnvPocket(keychain: mockKeychain)

        // Create test file
        let tempDir = FileManager.default.temporaryDirectory
        testFilePath = tempDir.appendingPathComponent("test-\(UUID().uuidString).env").path
        try? testContent.write(toFile: testFilePath, atomically: true, encoding: .utf8)
    }

    deinit {
        // Clean up test file
        try? FileManager.default.removeItem(atPath: testFilePath)

        // Clear mock keychain
        mockKeychain.clear()
    }
}

// MARK: - Save Tests

@Test("Save file to keychain")
func testSaveFile() {
    let env = TestEnvironment()

    let result = env.envPocket.saveFile(key: "test-key", filePath: env.testFilePath)
    #expect(result == true)

    // Verify the file was saved to mock keychain
    let (data, _, status) = env.mockKeychain.load(account: "envpocket:test-key")
    #expect(status == errSecSuccess)
    #expect(data != nil)
    #expect(String(data: data!, encoding: .utf8) == env.testContent)
}

@Test("Save overwrite creates history")
func testSaveOverwriteCreatesHistory() {
    let env = TestEnvironment()

    // First save
    _ = env.envPocket.saveFile(key: "test-key", filePath: env.testFilePath)

    // Modify file
    let newContent = "UPDATED=true\n"
    try? newContent.write(toFile: env.testFilePath, atomically: true, encoding: .utf8)

    // Second save (should create history)
    Thread.sleep(forTimeInterval: 0.1) // Ensure different timestamp
    let result = env.envPocket.saveFile(key: "test-key", filePath: env.testFilePath)
    #expect(result == true)

    // Check that history was created
    let (items, _) = env.mockKeychain.list()
    let historyItems = items.filter { item in
        if let account = item[kSecAttrAccount as String] as? String {
            return account.hasPrefix("envpocket-history:test-key:")
        }
        return false
    }
    #expect(historyItems.count == 1)
}

@Test("Set value to keychain")
func testSetValue() {
    let env = TestEnvironment()

    let result = env.envPocket.setValue(key: "test-key", value: "secret-value-123")
    #expect(result == true)

    // Verify the value was saved to mock keychain
    let (data, attributes, status) = env.mockKeychain.load(account: "envpocket:test-key")
    #expect(status == errSecSuccess)
    #expect(data != nil)
    #expect(String(data: data!, encoding: .utf8) == "secret-value-123")

    // Verify it has the direct value label
    #expect(attributes?[kSecAttrLabel as String] as? String == "(direct value)")
}

@Test("Set value overwrite creates history")
func testSetValueOverwriteCreatesHistory() {
    let env = TestEnvironment()

    // First set
    _ = env.envPocket.setValue(key: "api-key", value: "original-value")

    // Second set (should create history)
    Thread.sleep(forTimeInterval: 0.1) // Ensure different timestamp
    let result = env.envPocket.setValue(key: "api-key", value: "updated-value")
    #expect(result == true)

    // Check that history was created
    let (items, _) = env.mockKeychain.list()
    let historyItems = items.filter { item in
        if let account = item[kSecAttrAccount as String] as? String {
            return account.hasPrefix("envpocket-history:api-key:")
        }
        return false
    }
    #expect(historyItems.count == 1)
}

// MARK: - Get Tests

@Test("Get file from keychain")
func testGetFile() {
    let env = TestEnvironment()

    // Save file first
    _ = env.envPocket.saveFile(key: "test-key", filePath: env.testFilePath)

    // Get file to new location
    let outputPath = FileManager.default.temporaryDirectory
        .appendingPathComponent("output-\(UUID().uuidString).env").path
    defer { try? FileManager.default.removeItem(atPath: outputPath) }

    let result = env.envPocket.getFile(key: "test-key", outputPath: outputPath)
    #expect(result == true)

    // Verify content
    let retrievedContent = try? String(contentsOfFile: outputPath)
    #expect(retrievedContent == env.testContent)
}

@Test("Get non-existent key fails")
func testGetNonExistentKey() {
    let env = TestEnvironment()

    let result = env.envPocket.getFile(key: "nonexistent", outputPath: "-")
    #expect(result == false)
}

// MARK: - Delete Tests

@Test("Delete single key")
func testDeleteSingleKey() {
    let env = TestEnvironment()

    // Save file first
    _ = env.envPocket.saveFile(key: "test-key", filePath: env.testFilePath)

    // Delete with force (to skip confirmation)
    let result = env.envPocket.deleteFile(key: "test-key", force: true)
    #expect(result == true)

    // Verify deletion
    let (_, _, status) = env.mockKeychain.load(account: "envpocket:test-key")
    #expect(status == errSecItemNotFound)
}

@Test("Delete with wildcard pattern")
func testDeleteWithWildcard() {
    let env = TestEnvironment()

    // Save multiple files
    _ = env.envPocket.saveFile(key: "test-1", filePath: env.testFilePath)
    _ = env.envPocket.saveFile(key: "test-2", filePath: env.testFilePath)
    _ = env.envPocket.saveFile(key: "prod-1", filePath: env.testFilePath)

    // Delete all test-* keys
    let result = env.envPocket.deleteFile(key: "test-*", force: true)
    #expect(result == true)

    // Verify test keys are deleted
    let (_, _, status1) = env.mockKeychain.load(account: "envpocket:test-1")
    #expect(status1 == errSecItemNotFound)

    let (_, _, status2) = env.mockKeychain.load(account: "envpocket:test-2")
    #expect(status2 == errSecItemNotFound)

    // Verify prod key still exists
    let (_, _, status3) = env.mockKeychain.load(account: "envpocket:prod-1")
    #expect(status3 == errSecSuccess)
}

@Test("Delete with question mark wildcard")
func testDeleteWithQuestionMark() {
    let env = TestEnvironment()

    // Save multiple files
    _ = env.envPocket.saveFile(key: "test-1", filePath: env.testFilePath)
    _ = env.envPocket.saveFile(key: "test-2", filePath: env.testFilePath)
    _ = env.envPocket.saveFile(key: "test-10", filePath: env.testFilePath)

    // Delete test-? (single character wildcard)
    let result = env.envPocket.deleteFile(key: "test-?", force: true)
    #expect(result == true)

    // Verify single digit keys are deleted
    let (_, _, status1) = env.mockKeychain.load(account: "envpocket:test-1")
    #expect(status1 == errSecItemNotFound)

    let (_, _, status2) = env.mockKeychain.load(account: "envpocket:test-2")
    #expect(status2 == errSecItemNotFound)

    // Verify double digit key still exists
    let (_, _, status3) = env.mockKeychain.load(account: "envpocket:test-10")
    #expect(status3 == errSecSuccess)
}

// MARK: - List Tests

@Test("List keys")
func testListKeys() {
    let env = TestEnvironment()

    // Save multiple files
    _ = env.envPocket.saveFile(key: "key-1", filePath: env.testFilePath)
    _ = env.envPocket.saveFile(key: "key-2", filePath: env.testFilePath)

    // Verify the keychain contains the expected items
    let (items, _) = env.mockKeychain.list()
    let currentKeys = items.filter { item in
        if let account = item[kSecAttrAccount as String] as? String {
            return account.hasPrefix("envpocket:") && !account.hasPrefix("envpocket-history:")
        }
        return false
    }
    #expect(currentKeys.count == 2)
}

// MARK: - Pattern Matching Tests

@Test("Match keys with asterisk wildcard")
func testMatchKeysWithAsterisk() {
    let env = TestEnvironment()

    _ = env.envPocket.saveFile(key: "dev-api", filePath: env.testFilePath)
    _ = env.envPocket.saveFile(key: "dev-web", filePath: env.testFilePath)
    _ = env.envPocket.saveFile(key: "prod-api", filePath: env.testFilePath)

    let matches = env.envPocket.matchKeys(pattern: "dev-*")
    #expect(matches.count == 2)
    #expect(matches.contains("dev-api"))
    #expect(matches.contains("dev-web"))
    #expect(!matches.contains("prod-api"))
}

@Test("Match keys with question mark wildcard")
func testMatchKeysWithQuestionMark() {
    let env = TestEnvironment()

    _ = env.envPocket.saveFile(key: "v1", filePath: env.testFilePath)
    _ = env.envPocket.saveFile(key: "v2", filePath: env.testFilePath)
    _ = env.envPocket.saveFile(key: "v10", filePath: env.testFilePath)

    let matches = env.envPocket.matchKeys(pattern: "v?")
    #expect(matches.count == 2)
    #expect(matches.contains("v1"))
    #expect(matches.contains("v2"))
    #expect(!matches.contains("v10"))
}

@Test("Match keys with complex pattern")
func testMatchKeysWithComplexPattern() {
    let env = TestEnvironment()

    _ = env.envPocket.saveFile(key: "app-dev-1", filePath: env.testFilePath)
    _ = env.envPocket.saveFile(key: "app-dev-2", filePath: env.testFilePath)
    _ = env.envPocket.saveFile(key: "app-prod-1", filePath: env.testFilePath)
    _ = env.envPocket.saveFile(key: "db-dev-1", filePath: env.testFilePath)

    let matches = env.envPocket.matchKeys(pattern: "app-*-?")
    #expect(matches.count == 3)
    #expect(matches.contains("app-dev-1"))
    #expect(matches.contains("app-dev-2"))
    #expect(matches.contains("app-prod-1"))
    #expect(!matches.contains("db-dev-1"))
}

// MARK: - Vault Tests

@Test("Save and get with nested vault")
func testNestedVault() {
    let env = TestEnvironment()
    let vaultedEnvPocket = EnvPocket(keychain: env.mockKeychain, vault: "prod/sql/onprem")

    let success = vaultedEnvPocket.saveFile(key: "test-key", filePath: env.testFilePath)
    #expect(success == true)

    // Verify key is in vault namespace
    let (data, _, status) = env.mockKeychain.load(account: "envpocket:prod/sql/onprem::test-key")
    #expect(status == errSecSuccess)
    #expect(data != nil)

    // Verify get works with vault
    let outputPath = FileManager.default.temporaryDirectory
        .appendingPathComponent("output-\(UUID().uuidString).env").path
    defer { try? FileManager.default.removeItem(atPath: outputPath) }

    let getSuccess = vaultedEnvPocket.getFile(key: "test-key", outputPath: outputPath)
    #expect(getSuccess == true)

    let retrievedContent = try? String(contentsOfFile: outputPath)
    #expect(retrievedContent == env.testContent)
}

@Test("Vault isolation")
func testVaultIsolation() {
    let env = TestEnvironment()

    // Save to prod vault
    let prodEnvPocket = EnvPocket(keychain: env.mockKeychain, vault: "prod")
    _ = prodEnvPocket.saveFile(key: "api-key", filePath: env.testFilePath)

    // Save to staging vault
    let stagingEnvPocket = EnvPocket(keychain: env.mockKeychain, vault: "staging")
    _ = stagingEnvPocket.saveFile(key: "api-key", filePath: env.testFilePath)

    // Verify isolation - both vaults have the same key but different namespaces
    let (prodData, _, prodStatus) = env.mockKeychain.load(account: "envpocket:prod::api-key")
    #expect(prodStatus == errSecSuccess)

    let (stagingData, _, stagingStatus) = env.mockKeychain.load(account: "envpocket:staging::api-key")
    #expect(stagingStatus == errSecSuccess)

    // Verify matchKeys respects vault context
    let prodMatches = prodEnvPocket.matchKeys(pattern: "*")
    let stagingMatches = stagingEnvPocket.matchKeys(pattern: "*")

    #expect(prodMatches == ["api-key"])
    #expect(stagingMatches == ["api-key"])
}

@Test("Backwards compatibility - no vault")
func testBackwardsCompatibility() {
    let env = TestEnvironment()

    // Save without vault
    env.envPocket.saveFile(key: "legacy-key", filePath: env.testFilePath)

    // Should be saved without vault separator
    let (data, _, status) = env.mockKeychain.load(account: "envpocket:legacy-key")
    #expect(status == errSecSuccess)
    #expect(data != nil)

    // Non-vaulted envPocket should only see non-vaulted keys
    let matches = env.envPocket.matchKeys(pattern: "*")
    #expect(matches.contains("legacy-key"))

    // Vaulted envPocket should not see non-vaulted keys
    let vaultedEnvPocket = EnvPocket(keychain: env.mockKeychain, vault: "prod")
    let vaultedMatches = vaultedEnvPocket.matchKeys(pattern: "*")
    #expect(!vaultedMatches.contains("legacy-key"))
}

@Test("Vault filtering with matchKeys")
func testVaultFilteringWithMatchKeys() {
    let env = TestEnvironment()

    // Save to different vaults
    let prodEnvPocket = EnvPocket(keychain: env.mockKeychain, vault: "prod")
    _ = prodEnvPocket.saveFile(key: "db-url", filePath: env.testFilePath)
    _ = prodEnvPocket.saveFile(key: "api-key", filePath: env.testFilePath)

    let stagingEnvPocket = EnvPocket(keychain: env.mockKeychain, vault: "staging")
    _ = stagingEnvPocket.saveFile(key: "db-url", filePath: env.testFilePath)

    // Save non-vaulted
    _ = env.envPocket.saveFile(key: "local-key", filePath: env.testFilePath)

    // Verify prod vault only shows prod keys
    let prodMatches = prodEnvPocket.matchKeys(pattern: "*")
    #expect(prodMatches.count == 2)
    #expect(prodMatches.contains("db-url"))
    #expect(prodMatches.contains("api-key"))

    // Verify staging vault only shows staging keys
    let stagingMatches = stagingEnvPocket.matchKeys(pattern: "*")
    #expect(stagingMatches.count == 1)
    #expect(stagingMatches.contains("db-url"))

    // Verify non-vaulted only shows non-vaulted keys
    let nonVaultedMatches = env.envPocket.matchKeys(pattern: "*")
    #expect(nonVaultedMatches.count == 1)
    #expect(nonVaultedMatches.contains("local-key"))
}

@Test("List vaults")
func testListVaults() {
    let env = TestEnvironment()

    // Create entries in different vaults
    let prodEnvPocket = EnvPocket(keychain: env.mockKeychain, vault: "prod")
    _ = prodEnvPocket.saveFile(key: "db-url", filePath: env.testFilePath)

    let stagingEnvPocket = EnvPocket(keychain: env.mockKeychain, vault: "staging/api")
    _ = stagingEnvPocket.saveFile(key: "api-key", filePath: env.testFilePath)

    // Save non-vaulted
    _ = env.envPocket.saveFile(key: "local-key", filePath: env.testFilePath)

    // Verify vaults are listed
    // Note: listVaults() prints to stdout, so we can't easily verify the output
    // But we can verify the keychain contains the expected vault namespaces
    let (items, _) = env.mockKeychain.list()
    let vaultedKeys = items.filter { item in
        if let account = item[kSecAttrAccount as String] as? String,
           account.hasPrefix("envpocket:") && !account.hasPrefix("envpocket-history:") {
            return account.contains("::")
        }
        return false
    }
    #expect(vaultedKeys.count == 2)
}

@Test("History with vaults")
func testHistoryWithVaults() {
    let env = TestEnvironment()
    let vaultedEnvPocket = EnvPocket(keychain: env.mockKeychain, vault: "prod")

    // Save initial version
    _ = vaultedEnvPocket.saveFile(key: "db-url", filePath: env.testFilePath)

    // Update to create history
    let newContent = "UPDATED=true\n"
    try? newContent.write(toFile: env.testFilePath, atomically: true, encoding: .utf8)

    Thread.sleep(forTimeInterval: 0.1) // Ensure different timestamp
    _ = vaultedEnvPocket.saveFile(key: "db-url", filePath: env.testFilePath)

    // Verify history exists in vault namespace
    let (items, _) = env.mockKeychain.list()
    let historyItems = items.filter { item in
        if let account = item[kSecAttrAccount as String] as? String {
            return account.hasPrefix("envpocket-history:prod::db-url:")
        }
        return false
    }
    #expect(historyItems.count == 1)
}

@Test("Delete with vaults")
func testDeleteWithVaults() {
    let env = TestEnvironment()

    // Save to vault
    let vaultedEnvPocket = EnvPocket(keychain: env.mockKeychain, vault: "prod")
    _ = vaultedEnvPocket.saveFile(key: "db-url", filePath: env.testFilePath)

    // Create history
    let newContent = "UPDATED=true\n"
    try? newContent.write(toFile: env.testFilePath, atomically: true, encoding: .utf8)
    Thread.sleep(forTimeInterval: 0.1)
    _ = vaultedEnvPocket.saveFile(key: "db-url", filePath: env.testFilePath)

    // Delete
    let deleteSuccess = vaultedEnvPocket.deleteFile(key: "db-url", force: true)
    #expect(deleteSuccess == true)

    // Verify current and history are deleted
    let (data, _, status) = env.mockKeychain.load(account: "envpocket:prod::db-url")
    #expect(status == errSecItemNotFound)

    let (items, _) = env.mockKeychain.list()
    let historyItems = items.filter { item in
        if let account = item[kSecAttrAccount as String] as? String {
            return account.hasPrefix("envpocket-history:prod::db-url:")
        }
        return false
    }
    #expect(historyItems.count == 0)
}

@Test("Set value with vault")
func testSetValueWithVault() {
    let env = TestEnvironment()
    let vaultedEnvPocket = EnvPocket(keychain: env.mockKeychain, vault: "prod/secrets")

    let success = vaultedEnvPocket.setValue(key: "api-token", value: "secret-123")
    #expect(success == true)

    // Verify value is in vault namespace
    let (data, attributes, status) = env.mockKeychain.load(account: "envpocket:prod/secrets::api-token")
    #expect(status == errSecSuccess)
    #expect(String(data: data!, encoding: .utf8) == "secret-123")
    #expect(attributes?[kSecAttrLabel as String] as? String == "(direct value)")
}

@Test("Export and import with vault")
func testExportImportWithVault() {
    let env = TestEnvironment()
    let prodEnvPocket = EnvPocket(keychain: env.mockKeychain, vault: "prod")

    // Save to prod vault
    _ = prodEnvPocket.saveFile(key: "db-url", filePath: env.testFilePath)

    // Export from prod vault
    guard let exportedData = prodEnvPocket.exportEncrypted(key: "db-url", password: "test123") else {
        Issue.record("Export failed")
        return
    }

    // Clear keychain
    env.mockKeychain.clear()

    // Import to staging vault (different vault)
    let stagingEnvPocket = EnvPocket(keychain: env.mockKeychain, vault: "staging")
    let importSuccess = stagingEnvPocket.importEncrypted(key: "db-url", encryptedData: exportedData, password: "test123")
    #expect(importSuccess == true)

    // Verify it's in staging vault namespace
    let (data, _, status) = env.mockKeychain.load(account: "envpocket:staging::db-url")
    #expect(status == errSecSuccess)
    #expect(data != nil)

    // Verify it's not in prod vault
    let (_, _, prodStatus) = env.mockKeychain.load(account: "envpocket:prod::db-url")
    #expect(prodStatus == errSecItemNotFound)
}
