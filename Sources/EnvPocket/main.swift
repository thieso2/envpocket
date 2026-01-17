//
//  main.swift
//  EnvPocket
//
//  Created by thieso2 on 2024.
//  Copyright © 2025 thieso2. All rights reserved.
//
//  MIT License
//

import Foundation
import ArgumentParser

// MARK: - Main Command

@main
struct EnvPocketCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "envpocket",
        abstract: "Secure environment file storage for macOS using the system keychain",
        version: "0.5.0",
        subcommands: [
            Save.self,
            Set.self,
            Get.self,
            Delete.self,
            List.self,
            History.self,
            Export.self,
            Import.self
        ]
    )

    // MARK: - Helper Functions

    static func readPassword(prompt: String) -> String? {
        print(prompt, terminator: "")
        fflush(stdout)

        // Disable echo for password input
        var oldTermios = termios()
        tcgetattr(STDIN_FILENO, &oldTermios)
        var newTermios = oldTermios
        newTermios.c_lflag &= ~UInt(ECHO)
        tcsetattr(STDIN_FILENO, TCSANOW, &newTermios)

        defer {
            // Restore terminal settings
            tcsetattr(STDIN_FILENO, TCSANOW, &oldTermios)
            print() // New line after password input
        }

        guard let password = readLine() else {
            return nil
        }

        return password.isEmpty ? nil : password
    }
}

// MARK: - Save Command

extension EnvPocketCommand {
    struct Save: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Save a file to the keychain"
        )

        @Argument(help: "Key name to store the file under")
        var key: String

        @Argument(help: "Path to the file to save",
                  completion: .file())
        var filePath: String

        func run() throws {
            let envPocket = EnvPocket()
            let success = envPocket.saveFile(key: key, filePath: filePath)
            if !success {
                throw ExitCode.failure
            }
        }
    }
}

// MARK: - Set Command

extension EnvPocketCommand {
    struct Set: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Set a value directly (without a file)"
        )

        @Argument(help: "Key name to store the value under")
        var key: String

        @Argument(help: "Value to store (omit to be prompted securely)")
        var value: String?

        func run() throws {
            let envPocket = EnvPocket()

            let finalValue: String
            if let providedValue = value {
                finalValue = providedValue
            } else {
                // Prompt for value
                print("Enter value for '\(key)': ", terminator: "")
                fflush(stdout)
                guard let inputValue = readLine() else {
                    UserMessage.error("No value provided").display()
                    throw ExitCode.failure
                }
                finalValue = inputValue
            }

            let success = envPocket.setValue(key: key, value: finalValue)
            if !success {
                throw ExitCode.failure
            }
        }
    }
}

// MARK: - Get Command

extension EnvPocketCommand {
    struct Get: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Retrieve a file or value from the keychain"
        )

        @Argument(help: "Key name to retrieve")
        var key: String

        @Argument(help: "Output path (use '-' for stdout, omit to use original filename)",
                  completion: .file())
        var outputPath: String?

        @Option(name: .long, help: "Retrieve a specific version by index (0 = most recent)")
        var version: Int?

        @Flag(name: .shortAndLong, help: "Force overwrite without confirmation")
        var force: Bool = false

        func run() throws {
            let envPocket = EnvPocket()
            let success = envPocket.getFile(
                key: key,
                outputPath: outputPath,
                versionIndex: version,
                force: force
            )
            if !success {
                throw ExitCode.failure
            }
        }
    }
}

// MARK: - Delete Command

extension EnvPocketCommand {
    struct Delete: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Delete a key from the keychain (supports wildcards)"
        )

        @Argument(help: "Key name or pattern to delete (supports * and ? wildcards)")
        var key: String

        @Flag(name: .shortAndLong, help: "Force deletion without confirmation")
        var force: Bool = false

        func run() throws {
            let envPocket = EnvPocket()
            let success = envPocket.deleteFile(key: key, force: force)
            if !success {
                throw ExitCode.failure
            }
        }
    }
}

// MARK: - List Command

extension EnvPocketCommand {
    struct List: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "List all stored keys with metadata"
        )

        func run() throws {
            let envPocket = EnvPocket()
            envPocket.listKeys()
        }
    }
}

// MARK: - History Command

extension EnvPocketCommand {
    struct History: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Show version history for a key"
        )

        @Argument(help: "Key name to show history for")
        var key: String

        func run() throws {
            let envPocket = EnvPocket()
            envPocket.showHistory(key: key)
        }
    }
}

// MARK: - Export Command

extension EnvPocketCommand {
    struct Export: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Export encrypted file for team sharing"
        )

        @Argument(help: "Key name to export")
        var key: String

        @Argument(help: "Output file path (default: <key>.envpocket)",
                  completion: .file())
        var outputPath: String?

        @Option(name: .long, help: "Password for encryption (omit to be prompted)")
        var password: String?

        func run() throws {
            let envPocket = EnvPocket()

            // Get password if not provided
            let finalPassword: String
            if let providedPassword = password {
                finalPassword = providedPassword
            } else {
                guard let firstPassword = EnvPocketCommand.readPassword(prompt: "Enter password for encryption: ") else {
                    UserMessage.error("Password is required").display()
                    throw ExitCode.failure
                }

                guard let confirmPassword = EnvPocketCommand.readPassword(prompt: "Confirm password: ") else {
                    UserMessage.error("Password confirmation is required").display()
                    throw ExitCode.failure
                }

                if firstPassword != confirmPassword {
                    UserMessage.error("Passwords do not match").display()
                    throw ExitCode.failure
                }

                finalPassword = firstPassword
            }

            // Export with the password
            guard let encryptedData = envPocket.exportEncrypted(key: key, password: finalPassword) else {
                throw ExitCode.failure
            }

            // Determine output path
            let finalOutputPath = outputPath ?? "\(key).envpocket"

            // Write to output
            if finalOutputPath == "-" {
                // Write to stdout
                FileHandle.standardOutput.write(encryptedData)
            } else {
                do {
                    try encryptedData.write(to: URL(fileURLWithPath: finalOutputPath))
                    UserMessage.exportSuccess(finalOutputPath).display()
                } catch {
                    UserMessage.fileWriteError(finalOutputPath, error).display()
                    throw ExitCode.failure
                }
            }
        }
    }
}

// MARK: - Import Command

extension EnvPocketCommand {
    struct Import: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Import encrypted file from team member"
        )

        @Argument(help: "Key name to import as")
        var key: String

        @Argument(help: "Path to encrypted file",
                  completion: .file())
        var filePath: String

        @Option(name: .long, help: "Password for decryption (omit to be prompted)")
        var password: String?

        func run() throws {
            let envPocket = EnvPocket()

            // Get password if not provided
            let finalPassword: String
            if let providedPassword = password {
                finalPassword = providedPassword
            } else {
                guard let inputPassword = EnvPocketCommand.readPassword(prompt: "Enter password for decryption: ") else {
                    UserMessage.error("Password is required").display()
                    throw ExitCode.failure
                }
                finalPassword = inputPassword
            }

            // Read encrypted file
            guard let encryptedData = try? Data(contentsOf: URL(fileURLWithPath: filePath)) else {
                UserMessage.fileReadError(filePath).display()
                throw ExitCode.failure
            }

            // Import
            let success = envPocket.importEncrypted(key: key, encryptedData: encryptedData, password: finalPassword)
            if !success {
                throw ExitCode.failure
            }
        }
    }
}
