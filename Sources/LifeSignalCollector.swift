import CoreLocation
import Foundation
import HealthKit
import UIKit

/// Collects factual phone/health signals. Missing permissions produce explicit
/// availability fields; the model never receives invented zero values.
final class LifeSignalCollector: NSObject, CLLocationManagerDelegate {
    static let shared = LifeSignalCollector()

    private let locationManager = CLLocationManager()
    private let healthStore = HKHealthStore()
    private var lastLocation: CLLocation?
    private var foregroundStarted = Date()
    private var lastBackgroundAt: Date?

    private override init() {
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyKilometer
        NotificationCenter.default.addObserver(
            self, selector: #selector(didBecomeActive),
            name: UIApplication.didBecomeActiveNotification, object: nil)
        NotificationCenter.default.addObserver(
            self, selector: #selector(willResignActive),
            name: UIApplication.willResignActiveNotification, object: nil)
    }

    @objc private func didBecomeActive() {
        foregroundStarted = Date()
    }

    @objc private func willResignActive() {
        lastBackgroundAt = Date()
    }

    func collect(completion: @escaping ([String: Any]) -> Void) {
        var result: [String: Any] = [
            "screenState": UIApplication.shared.applicationState == .active ? "foreground" : "background",
            "ownAppForegroundSeconds": Int(Date().timeIntervalSince(foregroundStarted)),
            // iOS does not expose system-wide Screen Time to an ordinary app.
            "screenTimeAvailability": "requires_family_controls_entitlement"
        ]
        if let lastBackgroundAt {
            result["secondsSinceLastBackground"] = Int(Date().timeIntervalSince(lastBackgroundAt))
        }
        if CLLocationManager.locationServicesEnabled() {
            switch locationManager.authorizationStatus {
            case .notDetermined:
                locationManager.requestWhenInUseAuthorization()
            case .authorizedAlways, .authorizedWhenInUse:
                locationManager.requestLocation()
            default:
                result["locationAvailability"] = "denied"
            }
        } else {
            result["locationAvailability"] = "disabled"
        }
        if let location = lastLocation, Date().timeIntervalSince(location.timestamp) < 1800 {
            result["location"] = [
                "latitude": location.coordinate.latitude,
                "longitude": location.coordinate.longitude,
                "accuracyMeters": Int(location.horizontalAccuracy)
            ]
        }

        collectHealth { health in
            result["health"] = health
            completion(result)
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        lastLocation = locations.last
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {}

    private func collectHealth(completion: @escaping ([String: Any]) -> Void) {
        guard HKHealthStore.isHealthDataAvailable() else {
            completion(["availability": "unsupported"])
            return
        }
        let step = HKObjectType.quantityType(forIdentifier: .stepCount)!
        let hrv = HKObjectType.quantityType(forIdentifier: .heartRateVariabilitySDNN)!
        let sleep = HKObjectType.categoryType(forIdentifier: .sleepAnalysis)!
        let menstrual = HKObjectType.categoryType(forIdentifier: .menstrualFlow)!
        let readTypes: Set<HKObjectType> = [step, hrv, sleep, menstrual]
        healthStore.requestAuthorization(toShare: [], read: readTypes) { [weak self] granted, error in
            guard let self else { return }
            guard granted else {
                DispatchQueue.main.async {
                    completion(["availability": "authorization_failed",
                                "error": error?.localizedDescription ?? "HealthKit entitlement or permission unavailable"])
                }
                return
            }
            let group = DispatchGroup()
            let lock = NSLock()
            var values: [String: Any] = ["availability": "requested"]

            group.enter()
            self.querySteps(step) { value in
                lock.lock(); if let value { values["stepsToday"] = value }; lock.unlock()
                group.leave()
            }
            group.enter()
            self.queryLatestHRV(hrv) { value, date in
                lock.lock()
                if let value { values["hrvMs"] = value }
                if let date { values["hrvAt"] = ISO8601DateFormatter().string(from: date) }
                lock.unlock(); group.leave()
            }
            group.enter()
            self.querySleep(sleep) { sleepValue in
                lock.lock(); values.merge(sleepValue) { _, new in new }; lock.unlock()
                group.leave()
            }
            group.enter()
            self.queryMenstrual(menstrual) { flow, date in
                lock.lock()
                if let flow { values["latestMenstrualFlow"] = flow }
                if let date { values["latestMenstrualAt"] = ISO8601DateFormatter().string(from: date) }
                lock.unlock(); group.leave()
            }
            group.notify(queue: .main) { completion(values) }
        }
    }

    private func querySteps(_ type: HKQuantityType, completion: @escaping (Int?) -> Void) {
        let start = Calendar.current.startOfDay(for: Date())
        let predicate = HKQuery.predicateForSamples(withStart: start, end: Date())
        let query = HKStatisticsQuery(quantityType: type,
                                      quantitySamplePredicate: predicate,
                                      options: .cumulativeSum) { _, stats, _ in
            let value = stats?.sumQuantity()?.doubleValue(for: .count())
            completion(value.map(Int.init))
        }
        healthStore.execute(query)
    }

    private func queryLatestHRV(_ type: HKQuantityType,
                                completion: @escaping (Double?, Date?) -> Void) {
        let query = HKSampleQuery(sampleType: type, predicate: nil, limit: 1,
                                  sortDescriptors: [NSSortDescriptor(
                                    key: HKSampleSortIdentifierEndDate, ascending: false)]) {
            _, samples, _ in
            let sample = samples?.first as? HKQuantitySample
            completion(sample?.quantity.doubleValue(for: HKUnit.secondUnit(with: .milli)),
                       sample?.endDate)
        }
        healthStore.execute(query)
    }

    private func querySleep(_ type: HKCategoryType,
                            completion: @escaping ([String: Any]) -> Void) {
        let start = Date().addingTimeInterval(-36 * 3600)
        let predicate = HKQuery.predicateForSamples(withStart: start, end: Date())
        let query = HKSampleQuery(sampleType: type, predicate: predicate, limit: 100,
                                  sortDescriptors: [NSSortDescriptor(
                                    key: HKSampleSortIdentifierStartDate, ascending: true)]) {
            _, samples, _ in
            let asleep = (samples as? [HKCategorySample] ?? []).filter {
                if #available(iOS 16.0, *) {
                    return [HKCategoryValueSleepAnalysis.asleepCore.rawValue,
                            HKCategoryValueSleepAnalysis.asleepDeep.rawValue,
                            HKCategoryValueSleepAnalysis.asleepREM.rawValue,
                            HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue].contains($0.value)
                }
                return $0.value == HKCategoryValueSleepAnalysis.asleep.rawValue
            }
            guard let first = asleep.first, let last = asleep.last else {
                completion([:]); return
            }
            let seconds = asleep.reduce(0.0) { $0 + $1.endDate.timeIntervalSince($1.startDate) }
            completion([
                "sleepStart": ISO8601DateFormatter().string(from: first.startDate),
                "wakeTime": ISO8601DateFormatter().string(from: last.endDate),
                "sleepMinutes": Int(seconds / 60)
            ])
        }
        healthStore.execute(query)
    }

    private func queryMenstrual(_ type: HKCategoryType,
                                completion: @escaping (Int?, Date?) -> Void) {
        let start = Date().addingTimeInterval(-60 * 86400)
        let predicate = HKQuery.predicateForSamples(withStart: start, end: Date())
        let query = HKSampleQuery(sampleType: type, predicate: predicate, limit: 1,
                                  sortDescriptors: [NSSortDescriptor(
                                    key: HKSampleSortIdentifierEndDate, ascending: false)]) {
            _, samples, _ in
            let sample = samples?.first as? HKCategorySample
            completion(sample?.value, sample?.startDate)
        }
        healthStore.execute(query)
    }
}
