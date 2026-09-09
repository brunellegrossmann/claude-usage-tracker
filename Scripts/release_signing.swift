#!/usr/bin/env swift
// Ed25519 signing for release downloads. This is NOT Apple code signing: it
// proves a download came from whoever holds this repo's release key, so the
// app can refuse an update that a compromised server or network handed it.
//
//   swift Scripts/release_signing.swift generate
//   RELEASE_SIGNING_PRIVATE_KEY=<base64> swift Scripts/release_signing.swift sign <file>
//   RELEASE_SIGNING_PUBLIC_KEY=<base64>  swift Scripts/release_signing.swift verify <file> <signature-base64>
//
// The private key never leaves the maintainer's machine and the GitHub secret.
// The public key is embedded in the app, so forging an update needs the key
// itself, not merely control of the download server.
import CryptoKit
import Foundation

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("error: \(message)\n".utf8))
    exit(1)
}

func environmentKey(_ name: String) -> Data {
    guard let raw = ProcessInfo.processInfo.environment[name]?
        .trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else {
        fail("\(name) is not set")
    }
    guard let data = Data(base64Encoded: raw) else { fail("\(name) is not valid base64") }
    return data
}

func fileContents(_ path: String) -> Data {
    guard let data = FileManager.default.contents(atPath: path) else {
        fail("cannot read \(path)")
    }
    return data
}

let arguments = Array(CommandLine.arguments.dropFirst())
guard let command = arguments.first else {
    fail("usage: release_signing.swift generate | sign <file> | verify <file> <signature>")
}

switch command {
case "generate":
    let privateKey = Curve25519.Signing.PrivateKey()
    let privateKeyFile = "release-signing-private-key.txt"
    let base64PrivateKey = privateKey.rawRepresentation.base64EncodedString()
    guard FileManager.default.createFile(
        atPath: privateKeyFile,
        contents: Data((base64PrivateKey + "\n").utf8),
        attributes: [.posixPermissions: 0o600]
    ) else {
        fail("could not write \(privateKeyFile)")
    }
    // Only the public half is printed: a private key echoed to a terminal ends
    // up in scrollback, shell history, and CI logs.
    print("Public key (embed in Resources/Info.plist as ReleaseSigningPublicKey):")
    print(privateKey.publicKey.rawRepresentation.base64EncodedString())
    print("")
    print("Private key written to ./\(privateKeyFile) (mode 600).")
    print("Store it as the repo secret RELEASE_SIGNING_PRIVATE_KEY, then delete the file:")
    print("  gh secret set RELEASE_SIGNING_PRIVATE_KEY < \(privateKeyFile)")
    print("  rm \(privateKeyFile)")
    print("Losing it means future updates cannot be signed; leaking it means")
    print("anyone can sign an update this app will accept.")

case "sign":
    guard arguments.count == 2 else { fail("usage: sign <file>") }
    let privateKey = try Curve25519.Signing.PrivateKey(
        rawRepresentation: environmentKey("RELEASE_SIGNING_PRIVATE_KEY"))
    let payload = fileContents(arguments[1])
    let signature = try privateKey.signature(for: payload)
    // Verified before it is published: an unverifiable signature would ship a
    // release no app could install.
    guard privateKey.publicKey.isValidSignature(signature, for: payload) else {
        fail("signature failed its own verification")
    }
    print(signature.base64EncodedString())

case "verify":
    guard arguments.count == 3 else { fail("usage: verify <file> <signature-base64>") }
    let publicKey = try Curve25519.Signing.PublicKey(
        rawRepresentation: environmentKey("RELEASE_SIGNING_PUBLIC_KEY"))
    guard let signature = Data(base64Encoded: arguments[2].trimmingCharacters(in: .whitespacesAndNewlines)) else {
        fail("signature is not valid base64")
    }
    guard publicKey.isValidSignature(signature, for: fileContents(arguments[1])) else {
        fail("signature does not match \(arguments[1])")
    }
    print("ok: signature matches \(arguments[1])")

default:
    fail("unknown command '\(command)'")
}
