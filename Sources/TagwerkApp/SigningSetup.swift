import Foundation
import Security

/// Feste Signatur, damit macOS Freigaben (Kalender, Schlüsselbund, Musik) über Updates hinweg behält.
/// Erzeugt ein selbst signiertes Zertifikat „Tagwerk Lokal“; bei GitHub als Secret hinterlegt,
/// signiert der Build damit jede neue Fassung gleich.
enum SigningSetup {
    static let certificateName = "Tagwerk Lokal"
    static let secretsURL = URL(string: "https://github.com/boberbeck/todo/settings/secrets/actions/new")!
    static let actionsURL = URL(string: "https://github.com/boberbeck/todo/actions")!

    struct Secrets {
        /// .p12 (Zertifikat und Schlüssel), Base64 für das Secret TAGWERK_SIGNING_P12
        let p12Base64: String
        /// Passwort der .p12 für das Secret TAGWERK_SIGNING_PASSWORD
        let password: String
    }

    enum SetupError: Error, CustomStringConvertible {
        case failed(String)
        var description: String {
            switch self {
            case .failed(let message): return message
            }
        }
    }

    /// Wie die laufende App signiert ist.
    static var currentSignature: String {
        var code: SecCode?
        guard SecCodeCopySelf([], &code) == errSecSuccess, let code else { return "unbekannt" }
        var staticCode: SecStaticCode?
        guard SecCodeCopyStaticCode(code, [], &staticCode) == errSecSuccess, let staticCode else { return "unbekannt" }
        var info: CFDictionary?
        guard SecCodeCopySigningInformation(staticCode, SecCSFlags(rawValue: UInt32(kSecCSSigningInformation)), &info) == errSecSuccess,
              let dictionary = info as? [String: Any] else { return "unbekannt" }
        if let certificates = dictionary[kSecCodeInfoCertificates as String] as? [SecCertificate],
           let leaf = certificates.first,
           let name = SecCertificateCopySubjectSummary(leaf) as String? {
            return "fest signiert mit „\(name)“"
        }
        return "ad hoc signiert"
    }

    static var isFixed: Bool { currentSignature.hasPrefix("fest") }

    /// Erzeugt Zertifikat und Schlüssel mit dem openssl von macOS (dessen .p12 liest der Schlüsselbund).
    static func generate() throws -> Secrets {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("tagwerk-signatur-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let config = folder.appendingPathComponent("zertifikat.cnf")
        try """
        [req]
        distinguished_name = dn
        x509_extensions = ext
        prompt = no
        [dn]
        CN = \(certificateName)
        [ext]
        basicConstraints = critical, CA:false
        keyUsage = critical, digitalSignature
        extendedKeyUsage = critical, codeSigning
        """.write(to: config, atomically: true, encoding: .utf8)
        let key = folder.appendingPathComponent("schluessel.pem")
        let certificate = folder.appendingPathComponent("zertifikat.pem")
        let p12 = folder.appendingPathComponent("tagwerk.p12")
        let password = randomPassword()
        try run(["req", "-x509", "-newkey", "rsa:2048", "-nodes", "-days", "3650", "-sha256",
                 "-keyout", key.path, "-out", certificate.path, "-config", config.path])
        try run(["pkcs12", "-export", "-name", certificateName, "-inkey", key.path, "-in", certificate.path,
                 "-out", p12.path, "-passout", "pass:\(password)"])
        let data = try Data(contentsOf: p12)
        return Secrets(p12Base64: data.base64EncodedString(), password: password)
    }

    private static func randomPassword() -> String {
        let letters = Array("ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz23456789")
        return String((0..<24).map { _ in letters.randomElement()! })
    }

    private static func run(_ arguments: [String]) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/openssl")
        process.arguments = arguments
        let errors = Pipe()
        process.standardError = errors
        process.standardOutput = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            let message = String(decoding: errors.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
            throw SetupError.failed("openssl: \(message.trimmingCharacters(in: .whitespacesAndNewlines))")
        }
    }
}
