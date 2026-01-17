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
