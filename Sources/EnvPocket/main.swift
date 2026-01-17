//
//  main.swift
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

enum Command: String {
    case save, get, set, delete, list, history, export, `import`
}

func readPassword(prompt: String) -> String? {
    print(prompt, terminator: "")
    
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

func usage() {
    print("""
    Usage:
      envpocket save <key> <file>
      envpocket set <key> [<value>]
      envpocket get <key> [<output_file>]
      envpocket get <key> --version <version_index> [<output_file>]
      envpocket delete <key> [-f]
      envpocket delete <pattern> [-f]
      envpocket list
      envpocket history <key>
      envpocket export <key> [--password <password>] [<output_file>]
      envpocket import <key> <encrypted_file> [--password <password>]

    Notes:
      - For 'set': stores a value directly (not from a file). If value is omitted, you'll be prompted
      - For 'delete': supports wildcards (* and ?). Use -f to skip confirmation
      - For 'get': if output_file is omitted, uses the original filename
      - Use '-' as output_file to write to stdout
      - For 'export': creates an encrypted file that can be shared with team members
                      If password is omitted, you'll be prompted (with confirmation)
      - For 'import': decrypts and imports a file previously exported with 'export'
                      If password is omitted, you'll be prompted
    """)
}

func main() {
    let args = CommandLine.arguments
    guard args.count >= 2, let command = Command(rawValue: args[1]) else {
        usage()
        exit(1)
    }
    
    let envPocket = EnvPocket()
    
    switch command {
    case .save:
        guard args.count == 4 else { usage(); exit(1) }
        if !envPocket.saveFile(key: args[2], filePath: args[3]) {
            exit(1)
        }

    case .set:
        let key: String
        let value: String

        if args.count == 3 {
            // Prompt for value
            key = args[2]
            print("Enter value for '\(key)': ", terminator: "")
            guard let inputValue = readLine() else {
                print("Error: No value provided")
                exit(1)
            }
            value = inputValue
        } else if args.count == 4 {
            // Value provided as argument
            key = args[2]
            value = args[3]
        } else {
            usage()
            exit(1)
        }

        if !envPocket.setValue(key: key, value: value) {
            exit(1)
        }

    case .get:
        if args.count == 3 {
            // Get with default output: envpocket get <key>
            if !envPocket.getFile(key: args[2]) {
                exit(1)
            }
        } else if args.count == 4 {
            // Get with specified output: envpocket get <key> <output_file>
            if !envPocket.getFile(key: args[2], outputPath: args[3]) {
                exit(1)
            }
        } else if args.count == 5 && args[3] == "--version" {
            // Get version with default output: envpocket get <key> --version <index>
            if let versionIndex = Int(args[4]) {
                if !envPocket.getFile(key: args[2], versionIndex: versionIndex) {
                    exit(1)
                }
            } else {
                print("Error: Invalid version index")
                exit(1)
            }
        } else if args.count == 6 && args[3] == "--version" {
            // Get version with specified output: envpocket get <key> --version <index> <output_file>
            if let versionIndex = Int(args[4]) {
                if !envPocket.getFile(key: args[2], outputPath: args[5], versionIndex: versionIndex) {
                    exit(1)
                }
            } else {
                print("Error: Invalid version index")
                exit(1)
            }
        } else {
            usage()
            exit(1)
        }
        
    case .delete:
        if args.count == 3 {
            // Delete without force: envpocket delete <key>
            if !envPocket.deleteFile(key: args[2], force: false) {
                exit(1)
            }
        } else if args.count == 4 && args[3] == "-f" {
            // Delete with force: envpocket delete <key> -f
            if !envPocket.deleteFile(key: args[2], force: true) {
                exit(1)
            }
        } else if args.count == 4 && args[2] == "-f" {
            // Alternative syntax: envpocket delete -f <key>
            if !envPocket.deleteFile(key: args[3], force: true) {
                exit(1)
            }
        } else {
            usage()
            exit(1)
        }
        
    case .list:
        envPocket.listKeys()
        
    case .history:
        guard args.count == 3 else { usage(); exit(1) }
        envPocket.showHistory(key: args[2])
        
    case .export:
        guard args.count >= 3 else { usage(); exit(1) }
        
        let key = args[2]
        var password: String? = nil
        var outputFile: String? = nil
        
        // Parse arguments
        if args.count == 3 {
            // envpocket export <key>
            outputFile = "\(key).envpocket"
        } else if args.count == 4 {
            // envpocket export <key> <output_file>
            outputFile = args[3]
        } else if args.count == 5 && args[3] == "--password" {
            // envpocket export <key> --password <password>
            password = args[4]
            outputFile = "\(key).envpocket"
        } else if args.count == 6 && args[3] == "--password" {
            // envpocket export <key> --password <password> <output_file>
            password = args[4]
            outputFile = args[5]
        } else {
            usage()
            exit(1)
        }
        
        // Get password if not provided
        if password == nil {
            guard let firstPassword = readPassword(prompt: "Enter password for encryption: ") else {
                print("Error: Password is required")
                exit(1)
            }
            
            guard let confirmPassword = readPassword(prompt: "Confirm password: ") else {
                print("Error: Password confirmation is required")
                exit(1)
            }
            
            if firstPassword != confirmPassword {
                print("Error: Passwords do not match")
                exit(1)
            }
            
            password = firstPassword
        }
        
        // Export with the password
        guard let finalPassword = password,
              let encryptedData = envPocket.exportEncrypted(key: key, password: finalPassword) else {
            exit(1)
        }
        
        // Write to output
        if outputFile == "-" {
            // Write to stdout
            FileHandle.standardOutput.write(encryptedData)
        } else if let outputFile = outputFile {
            do {
                try encryptedData.write(to: URL(fileURLWithPath: outputFile))
                print("Encrypted file exported to '\(outputFile)'")
                print("Share this file and password with your team to grant access")
            } catch {
                print("Error writing encrypted file: \(error)")
                exit(1)
            }
        }
        
    case .import:
        guard args.count >= 4 else {
            usage()
            exit(1)
        }
        
        let key = args[2]
        let filePath = args[3]
        var password: String? = nil
        
        // Parse password argument if provided
        if args.count == 6 && args[4] == "--password" {
            password = args[5]
        } else if args.count != 4 {
            usage()
            exit(1)
        }
        
        // Get password if not provided
        if password == nil {
            guard let inputPassword = readPassword(prompt: "Enter password for decryption: ") else {
                print("Error: Password is required")
                exit(1)
            }
            password = inputPassword
        }
        
        guard let encryptedData = try? Data(contentsOf: URL(fileURLWithPath: filePath)) else {
            print("Error: Could not read encrypted file at \(filePath)")
            exit(1)
        }
        
        guard let finalPassword = password else {
            print("Error: Password is required")
            exit(1)
        }
        
        if !envPocket.importEncrypted(key: key, encryptedData: encryptedData, password: finalPassword) {
            exit(1)
        }
    }
}

main()