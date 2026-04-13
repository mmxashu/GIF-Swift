// SIMDetectionModule.swift
import Foundation
import CoreTelephony

@objc(SIMDetectionModule)
class SIMDetectionModule: NSObject {

    private let networkInfo = CTTelephonyNetworkInfo()

    @objc static func requiresMainQueueSetup() -> Bool { return false }

    // MARK: - Main entry point (no @escaping — RCT types are already escaping)
    @objc func checkSIM(
        _ resolve: RCTPromiseResolveBlock,
        rejecter reject: RCTPromiseRejectBlock
    ) {
        resolve(buildSIMReport())
    }

    // MARK: - Build full report
    private func buildSIMReport() -> [String: Any] {
        return [
            "isSimulator":       isSimulator,
            "iosVersion":        UIDevice.current.systemVersion,
            "detectionStrategy": detectionStrategy,
            "slots":             detectSlots(),
            "fingerprint":       buildFingerprint(),
        ]
    }

    // MARK: - Slot detection (min iOS 15.5 — no legacy path needed)
    private func detectSlots() -> [[String: Any]] {
        if isSimulator { return [simulatorSlot()] }

        if #available(iOS 18.0, *) {
            return detectSlotsIOS18()
        }
        // iOS 15.5–17: serviceCurrentRadioAccessTechnology
        // always available at this deployment target, no @available guard needed
        return detectSlotsIOS15()
    }

    // MARK: - iOS 18+ (isSIMInserted)
    @available(iOS 18.0, *)
    private func detectSlotsIOS18() -> [[String: Any]] {
        let subscribers = CTSubscriberInfo().subscribers
        let rat = networkInfo.serviceCurrentRadioAccessTechnology

        guard !subscribers.isEmpty else {
            return [makeSlot(
                id: 1, key: "slot_1", inserted: false,
                api: "CTSubscriberInfo.isSIMInserted", rat: nil
            )]
        }

        return subscribers.enumerated().map { index, sub in
            let key = sub.identifier ?? "slot_\(index + 1)"
            return makeSlot(
                id:       index + 1,
                key:      key,
                inserted: sub.isSIMInserted,
                api:      "CTSubscriberInfo.isSIMInserted",
                rat:      rat?[key]
            )
        }
    }

    // MARK: - iOS 15.5–17 (signal-dependent fallback)
    private func detectSlotsIOS15() -> [[String: Any]] {
        // serviceCurrentRadioAccessTechnology available since iOS 12
        // Always present at min deployment target 15.5 — no guard needed
        let rat = networkInfo.serviceCurrentRadioAccessTechnology

        guard let rat = rat, !rat.isEmpty else {
            return [makeSlot(
                id: 1, key: "slot_1", inserted: false,
                api: "serviceCurrentRadioAccessTechnology", rat: nil
            )]
        }

        return rat.enumerated().map { index, pair in
            makeSlot(
                id:       index + 1,
                key:      pair.key,
                inserted: !pair.value.isEmpty,
                api:      "serviceCurrentRadioAccessTechnology",
                rat:      pair.value
            )
        }
    }

    // MARK: - Simulator placeholder
    private func simulatorSlot() -> [String: Any] {
        return makeSlot(
            id: 1, key: "simulator", inserted: false,
            api: "N/A — Simulator", rat: nil
        )
    }

    // MARK: - Slot builder
    private func makeSlot(
        id: Int, key: String, inserted: Bool,
        api: String, rat: String?
    ) -> [String: Any] {
        return [
            "slotId":            id,
            "slotKey":           key,
            "isSIMInserted":     inserted,
            "detectionAPI":      api,
            "radioAccessTech":   rat ?? NSNull(),
            "networkGeneration": networkGeneration(from: rat),
        ]
    }

    // MARK: - Network generation
    // No @available checks needed — min iOS 15.5 means NR/NRNSA always present
    private func networkGeneration(from rat: String?) -> String {
        guard let rat = rat else { return "unknown" }
        switch rat {
        // 5G — CTRadioAccessTechnologyNR / NRNSA available since iOS 14.1
        // Always safe at min iOS 15.5 — include directly in switch
        case CTRadioAccessTechnologyNRNSA,
             CTRadioAccessTechnologyNR:
            return "5G"

        // 4G
        case CTRadioAccessTechnologyLTE:
            return "4G"

        // 3G
        case CTRadioAccessTechnologyWCDMA,
             CTRadioAccessTechnologyHSDPA,
             CTRadioAccessTechnologyHSUPA,
             CTRadioAccessTechnologyCDMAEVDORev0,
             CTRadioAccessTechnologyCDMAEVDORevA,
             CTRadioAccessTechnologyCDMAEVDORevB,
             CTRadioAccessTechnologyeHRPD:
            return "3G"

        // 2G
        case CTRadioAccessTechnologyGPRS,
             CTRadioAccessTechnologyEdge,
             CTRadioAccessTechnologyCDMA1x:
            return "2G"

        default:
            return "unknown"
        }
    }

    // MARK: - SIM fingerprint for change detection
    private func buildFingerprint() -> [String: Any] {
        let rat      = networkInfo.serviceCurrentRadioAccessTechnology
        let slotKeys = Array(rat?.keys.sorted() ?? [])

        var simInserted = false
        if #available(iOS 18.0, *) {
            simInserted = CTSubscriberInfo().subscribers
                .contains { $0.isSIMInserted }
        } else {
            // iOS 15.5–17: infer from RAT presence
            simInserted = !(rat?.isEmpty ?? true)
        }

        return [
            "slotCount":   rat?.count ?? 0,
            "slotKeys":    slotKeys,
            "simInserted": simInserted,
            "idfv":        UIDevice.current.identifierForVendor?.uuidString ?? "",
        ]
    }

    // MARK: - UPI capability check (use in payment flows)
    @objc func isUPICapable(
        _ resolve: RCTPromiseResolveBlock,
        rejecter reject: RCTPromiseRejectBlock
    ) {
        if isSimulator {
            resolve(true) // allow in simulator for development
            return
        }
        if #available(iOS 18.0, *) {
            let capable = CTSubscriberInfo().subscribers
                .contains { $0.isSIMInserted }
            resolve(capable)
        } else {
            let rat = networkInfo.serviceCurrentRadioAccessTechnology
            resolve(!(rat?.isEmpty ?? true))
        }
    }

    // MARK: - Helpers
    private var isSimulator: Bool {
        #if targetEnvironment(simulator)
        return true
        #else
        return false
        #endif
    }

    private var detectionStrategy: String {
        if #available(iOS 18.0, *) {
            return "CTSubscriberInfo.isSIMInserted (iOS 18+)"
        }
        return "serviceCurrentRadioAccessTechnology (iOS 15.5–17)"
    }
}
