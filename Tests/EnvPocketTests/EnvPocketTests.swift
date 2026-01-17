//
//  EnvPocketTests.swift
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
import Security

// NOTE: These integration tests use the real macOS keychain and run the actual binary.
// For most testing, see EnvPocketMockTests which uses an in-memory mock keychain.

/// Integration test that verifies the binary can be executed
@Test("Binary executable exists and shows usage")
func testBinaryExecutable() throws {
    let binaryPath = ".build/debug/envpocket"
    let fileManager = FileManager.default

    // Check if binary exists
    let binaryExists = fileManager.fileExists(atPath: binaryPath)
    #expect(binaryExists, "Binary should exist at \(binaryPath). Run 'swift build' first.")

    // Try to run it (should show usage and exit with code 1)
    let process = Process()
    process.executableURL = URL(fileURLWithPath: binaryPath)
    process.arguments = []

    let pipe = Pipe()
    process.standardOutput = pipe
    process.standardError = pipe

    try process.run()
    process.waitUntilExit()

    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    let output = String(data: data, encoding: .utf8) ?? ""

    #expect(process.terminationStatus == 1)
    #expect(output.contains("Usage:"))
}
