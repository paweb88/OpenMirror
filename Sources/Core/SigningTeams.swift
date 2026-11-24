import Foundation
import Security

/// Apple Developer team that can sign WebDriverAgent, found from "Apple Development" certificates.
struct SigningTeam: Equatable, Hashable {
    let teamID: String
    let certificateName: String
}

enum SigningTeams {
    /// Reads code-signing certificates from the login keychain and returns their team IDs (subject OU).
    static func discover() -> [SigningTeam] {
        let query: [String: Any] = [
            kSecClass as String: kSecClassCertificate,
            kSecMatchLimit as String: kSecMatchLimitAll,
            kSecReturnRef as String: true,
        ]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let certificates = result as? [SecCertificate] else { return [] }

        let teams = certificates.compactMap { certificate -> SigningTeam? in
            let name = SecCertificateCopySubjectSummary(certificate) as String? ?? ""
            guard isDevelopmentCertificate(name), let teamID = organizationalUnit(of: certificate) else { return nil }
            return SigningTeam(teamID: teamID, certificateName: name)
        }
        return Array(Set(teams)).sorted { $0.certificateName < $1.certificateName }
    }

    static func isDevelopmentCertificate(_ name: String) -> Bool {
        name.hasPrefix("Apple Development:") || name.hasPrefix("iPhone Developer:")
    }

    static func isValidTeamID(_ value: String) -> Bool {
        value.count == 10 && value.allSatisfy { $0.isASCII && ($0.isUppercase || $0.isNumber) }
    }

    private static func organizationalUnit(of certificate: SecCertificate) -> String? {
        let keys = [kSecOIDX509V1SubjectName] as CFArray
        guard let values = SecCertificateCopyValues(certificate, keys, nil) as? [String: Any],
              let subject = values[kSecOIDX509V1SubjectName as String] as? [String: Any],
              let entries = subject[kSecPropertyKeyValue as String] as? [[String: Any]] else { return nil }
        let unit = entries.first { ($0[kSecPropertyKeyLabel as String] as? String) == (kSecOIDOrganizationalUnitName as String) }
        return unit?[kSecPropertyKeyValue as String] as? String
    }
}
