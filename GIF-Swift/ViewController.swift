// SIMDetectionModule.swift
import Foundation
import CoreTelephony

@objc(SIMDetectionModule)
class SIMDetectionModule: NSObject {

  private let networkInfo = CTTelephonyNetworkInfo()

  // MARK: - Required by React Native
  @objc static func requiresMainQueueSetup() -> Bool { return false }

  // MARK: - Main SIM check (Promise-based)
  @objc func checkSIM(
    _ resolve: @escaping RCTPromiseResolveBlock,
    rejecter reject: @escaping RCTPromiseRejectBlock
  ) {
    let result = buildSIMReport()
    resolve(result)
  }

  // MARK: - Build full SIM report
  private func buildSIMReport() -> [String: Any] {
    var report: [String: Any] = [
      "isSimulator":      isSimulator,
      "iosVersion":       UIDevice.current.systemVersion,
      "detectionStrategy": detectionStrategy,
      "slots":            detectSlots(),
      "fingerprint":      buildFingerprint(),
    ]
    return report
  }

  // MARK: - Detect all SIM slots (iOS version branching)
  private func detectSlots() -> [[String: Any]] {
    if isSimulator {
      return [simulatorSlot()]
    }
    if #available(iOS 18.0, *) {
      return detectSlotsIOS18()
    }
    if #available(iOS 12.0, *) {
      return detectSlotsIOS12()
    }
    return detectSlotsLegacy()
  }

  // iOS 18+: isSIMInserted (requires entitlements + CarrierDescriptors)
  @available(iOS 18.0, *)
  private func detectSlotsIOS18() -> [[String: Any]] {
    let subscribers = CTSubscriberInfo().subscribers
    guard !subscribers.isEmpty else {
      return [makeSlot(id: 1, key: "slot_1", inserted: false,
                       api: "CTSubscriberInfo.isSIMInserted", rat: nil)]
    }
    let rat = networkInfo.serviceCurrentRadioAccessTechnology
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

  // iOS 12–17: serviceCurrentRadioAccessTechnology
  @available(iOS 12.0, *)
  private func detectSlotsIOS12() -> [[String: Any]] {
    guard let rat = networkInfo.serviceCurrentRadioAccessTechnology,
          !rat.isEmpty else {
      return [makeSlot(id: 1, key: "slot_1", inserted: false,
                       api: "serviceCurrentRadioAccessTechnology", rat: nil)]
    }
    return rat.enumerated().map { index, pair in
      makeSlot(id: index + 1, key: pair.key,
               inserted: !pair.value.isEmpty,
               api: "serviceCurrentRadioAccessTechnology",
               rat: pair.value)
    }
  }

  // Legacy
  private func detectSlotsLegacy() -> [[String: Any]] {
    let carrier = networkInfo.subscriberCellularProvider
    let hasSIM  = carrier?.mobileCountryCode != nil
    return [makeSlot(id: 1, key: "slot_1", inserted: hasSIM,
                     api: "subscriberCellularProvider (deprecated)", rat: nil)]
  }

  // MARK: - Slot builder
  private func makeSlot(id: Int, key: String, inserted: Bool,
                         api: String, rat: String?) -> [String: Any] {
    [
      "slotId":           id,
      "slotKey":          key,
      "isSIMInserted":    inserted,
      "detectionAPI":     api,
      "radioAccessTech":  rat ?? NSNull(),
      "networkGeneration": networkGeneration(from: rat),
    ]
  }

  // MARK: - SIM fingerprint for change detection
  private func buildFingerprint() -> [String: Any] {
    let rat       = networkInfo.serviceCurrentRadioAccessTechnology
    let slotKeys  = Array(rat?.keys.sorted() ?? [])
    var simInserted = false
    if #available(iOS 18.0, *) {
      simInserted = CTSubscriberInfo().subscribers.contains { $0.isSIMInserted }
    }
    return [
      "slotCount":    rat?.count ?? 0,
      "slotKeys":     slotKeys,
      "simInserted":  simInserted,
      "idfv":         UIDevice.current.identifierForVendor?.uuidString ?? "",
    ]
  }

  // MARK: - RAT → network generation
  private func networkGeneration(from rat: String?) -> String {
    guard let rat = rat else { return "unknown" }
    switch rat {
    case CTRadioAccessTechnologyGPRS,
         CTRadioAccessTechnologyEdge,
         CTRadioAccessTechnologyCDMA1x:
      return "2G"
    case CTRadioAccessTechnologyWCDMA,
         CTRadioAccessTechnologyHSDPA,
         CTRadioAccessTechnologyHSUPA,
         CTRadioAccessTechnologyCDMAEVDORev0,
         CTRadioAccessTechnologyCDMAEVDORevA,
         CTRadioAccessTechnologyCDMAEVDORevB,
         CTRadioAccessTechnologyeHRPD:
      return "3G"
    case CTRadioAccessTechnologyLTE:
      return "4G"
    default:
      if #available(iOS 14.1, *) {
        if rat == CTRadioAccessTechnologyNRNSA ||
           rat == CTRadioAccessTechnologyNR { return "5G" }
      }
      return "unknown"
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
    if #available(iOS 18.0, *) { return "CTSubscriberInfo.isSIMInserted (iOS 18+)" }
    if #available(iOS 12.0, *)  { return "serviceCurrentRadioAccessTechnology (iOS 12–17)" }
    return "subscriberCellularProvider (Legacy)"
  }
}
