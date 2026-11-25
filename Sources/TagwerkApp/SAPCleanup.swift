import Foundation
import WebKit

/// SAP ByDesign ist aus Tagwerk ausgebaut. Einmalig aufräumen, was davon auf dem Mac liegt:
/// das gespeicherte Passwort im Schlüsselbund, die Anmeldung im früheren ByDesign-Fenster und die Einstellungen.
/// Die Daten in der Datenbank (alte PSP-Elemente, SAP-Spalten) bleiben unangetastet, werden aber nicht mehr gelesen.
@MainActor
enum SAPCleanup {
    private static let doneKey = "sapRemovedCleanup"
    private static let passwordAccount = "bydesign"
    private static let settingsKeys = [
        "bydesignURL", "bydesignUser", "bydesignTaskListURL", "bydesignAutoFetch", "bydesignLastAutoFetch",
        "serviceProduct.wartung", "serviceProduct.stoerung", "serviceProduct.projekt", "serviceProduct.beratung",
    ]

    static func runOnce() {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: doneKey) else { return }
        defaults.set(true, forKey: doneKey)

        let host = defaults.string(forKey: "bydesignURL").flatMap { URL(string: $0)?.host?.lowercased() }
        for key in settingsKeys {
            defaults.removeObject(forKey: key)
        }
        if Keychain.exists(account: passwordAccount) {
            Keychain.delete(account: passwordAccount)
        }

        // Anmeldung (Cookies) aus dem früheren ByDesign-Fenster
        Task { @MainActor in
            let store = WKWebsiteDataStore.default()
            let types = WKWebsiteDataStore.allWebsiteDataTypes()
            let records = await store.dataRecords(ofTypes: types)
            let byDesign = records.filter { record in
                let name = record.displayName.lowercased()
                if name.contains("bydesign") { return true }
                guard let host, !name.isEmpty else { return false }
                return host == name || host.hasSuffix("." + name)
            }
            guard !byDesign.isEmpty else { return }
            await store.removeData(ofTypes: types, for: byDesign)
            AppLog.info("SAP", "Anmeldedaten des früheren ByDesign-Fensters entfernt")
        }
        AppLog.info("SAP", "SAP ByDesign ausgebaut: Einstellungen und gespeichertes Passwort entfernt")
    }
}
