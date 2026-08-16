// SPDX-License-Identifier: Apache-2.0

import Combine
import Foundation

public struct BodyTemperatureSnapshot: Equatable, Sendable {
    public let sampleID: UUID
    public let wristTemperatureCelsius: Double
    public let baselineCelsius: Double?
    public let baselineSampleCount: Int
    public let measuredAt: Date
    public let sourceName: String

    public init(
        sampleID: UUID,
        wristTemperatureCelsius: Double,
        baselineCelsius: Double?,
        baselineSampleCount: Int,
        measuredAt: Date,
        sourceName: String
    ) {
        self.sampleID = sampleID
        self.wristTemperatureCelsius = wristTemperatureCelsius
        self.baselineCelsius = baselineCelsius
        self.baselineSampleCount = baselineSampleCount
        self.measuredAt = measuredAt
        self.sourceName = sourceName
    }

    public var deviationCelsius: Double? {
        baselineCelsius.map { wristTemperatureCelsius - $0 }
    }

    public func isFresh(at date: Date = Date(), maximumAge: TimeInterval = 18 * 60 * 60) -> Bool {
        let age = date.timeIntervalSince(measuredAt)
        return age >= 0 && age <= maximumAge
    }

    public func shouldActivateCooling(
        threshold: Double,
        at date: Date = Date(),
        minimumBaselineSamples: Int = 3
    ) -> Bool {
        guard baselineSampleCount >= minimumBaselineSamples,
              isFresh(at: date),
              let deviationCelsius else { return false }
        return deviationCelsius >= threshold
    }
}

#if canImport(HealthKit)
import HealthKit

@MainActor
public final class BodyTemperatureManager: ObservableObject {
    public static let shared = BodyTemperatureManager()

    @Published public private(set) var snapshot: BodyTemperatureSnapshot?
    @Published public private(set) var isLoading = false
    @Published public private(set) var errorMessage: String?
    @Published public private(set) var hasRequestedAuthorization: Bool

    public let isAvailable = HKHealthStore.isHealthDataAvailable()

    private let store = HKHealthStore()
    private var observerQuery: HKObserverQuery?
    private static let authorizationKey = "betterBCool.bodyTemperature.authorizationRequested"

    public init() {
        hasRequestedAuthorization = UserDefaults.standard.bool(forKey: Self.authorizationKey)
    }

    public func requestAuthorization() async {
        guard isAvailable, let type = wristTemperatureType else {
            errorMessage = "Health data is unavailable on this device."
            return
        }

        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            try await store.requestAuthorization(toShare: [], read: [type])
            hasRequestedAuthorization = true
            UserDefaults.standard.set(true, forKey: Self.authorizationKey)
            startMonitoring()
            await refresh()
        } catch {
            errorMessage = "Apple Health access could not be requested."
        }
    }

    public func startMonitoring() {
        guard isAvailable, let type = wristTemperatureType else { return }
        if observerQuery == nil {
            let query = HKObserverQuery(sampleType: type, predicate: nil) { [weak self] _, completion, error in
                Task { @MainActor in
                    defer { completion() }
                    guard let self else { return }
                    if error != nil {
                        self.errorMessage = "Apple Health could not monitor wrist temperature updates."
                    } else {
                        await self.refresh()
                    }
                }
            }
            observerQuery = query
            store.execute(query)
        }

        store.enableBackgroundDelivery(for: type, frequency: .immediate) { [weak self] success, _ in
            guard !success else { return }
            Task { @MainActor in
                self?.errorMessage = "Background wrist-temperature updates are unavailable."
            }
        }
    }

    public func refresh() async {
        guard isAvailable, let type = wristTemperatureType else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            let samples = try await recentSamples(for: type)
            snapshot = Self.snapshot(from: samples)
        } catch {
            errorMessage = "Wrist temperature could not be read from Apple Health."
        }
    }

    public func loadPreviewSnapshot() {
        snapshot = BodyTemperatureSnapshot(
            sampleID: UUID(uuidString: "A7700000-0000-4000-8000-000000000001")!,
            wristTemperatureCelsius: 36.2,
            baselineCelsius: 35.5,
            baselineSampleCount: 7,
            measuredAt: Date(),
            sourceName: "Apple Watch preview"
        )
    }

    private var wristTemperatureType: HKQuantityType? {
        HKObjectType.quantityType(forIdentifier: .appleSleepingWristTemperature)
    }

    private func recentSamples(for type: HKQuantityType) async throws -> [HKQuantitySample] {
        try await withCheckedThrowingContinuation { continuation in
            let sort = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)
            let query = HKSampleQuery(
                sampleType: type,
                predicate: nil,
                limit: 8,
                sortDescriptors: [sort]
            ) { _, samples, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: samples as? [HKQuantitySample] ?? [])
                }
            }
            store.execute(query)
        }
    }

    private static func snapshot(from samples: [HKQuantitySample]) -> BodyTemperatureSnapshot? {
        guard let latest = samples.first else { return nil }
        let unit = HKUnit.degreeCelsius()
        let priorValues = samples.dropFirst().map { $0.quantity.doubleValue(for: unit) }
        let baseline = priorValues.isEmpty
            ? nil
            : priorValues.reduce(0, +) / Double(priorValues.count)
        return BodyTemperatureSnapshot(
            sampleID: latest.uuid,
            wristTemperatureCelsius: latest.quantity.doubleValue(for: unit),
            baselineCelsius: baseline,
            baselineSampleCount: priorValues.count,
            measuredAt: latest.endDate,
            sourceName: latest.sourceRevision.source.name
        )
    }
}
#else
@MainActor
public final class BodyTemperatureManager: ObservableObject {
    public static let shared = BodyTemperatureManager()
    @Published public private(set) var snapshot: BodyTemperatureSnapshot?
    @Published public private(set) var isLoading = false
    @Published public private(set) var errorMessage: String?
    @Published public private(set) var hasRequestedAuthorization = false
    public let isAvailable = false
    public init() {}
    public func requestAuthorization() async {}
    public func startMonitoring() {}
    public func refresh() async {}
    public func loadPreviewSnapshot() {
        snapshot = BodyTemperatureSnapshot(
            sampleID: UUID(uuidString: "A7700000-0000-4000-8000-000000000001")!,
            wristTemperatureCelsius: 36.2,
            baselineCelsius: 35.5,
            baselineSampleCount: 7,
            measuredAt: Date(),
            sourceName: "Apple Watch preview"
        )
    }
}
#endif
