import Foundation
import HealthKit

enum HealthManagerError: LocalizedError {
    case healthDataUnavailable
    case invalidDataType(String)
    case invalidDate(String)
    case dataTypeUnavailable(String)
    case invalidDateRange
    case operationFailed(String)

    var errorDescription: String? {
        switch self {
        case .healthDataUnavailable:
            return "Health data is not available on this device."
        case let .invalidDataType(identifier):
            return "Unsupported health data type: \(identifier)."
        case let .invalidDate(dateString):
            return "Invalid ISO 8601 date value: \(dateString)."
        case let .dataTypeUnavailable(identifier):
            return "The health data type \(identifier) is not available on this device."
        case .invalidDateRange:
            return "endDate must be greater than or equal to startDate."
        case let .operationFailed(message):
            return message
        }
    }
}

enum HealthDataType: String, CaseIterable {
    case steps
    case distance
    case calories
    case heartRate
    case weight
    case sleep
    case mobility
    case activity
    case heart
    case body
    case workout

    func sampleType() throws -> HKSampleType {
        if self == .sleep {
            guard let type = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) else {
                throw HealthManagerError.dataTypeUnavailable(rawValue)
            }
            return type
        }
        
        if self == .mobility {
            // Mobility uses multiple types, return walkingSpeed as representative
            guard let type = HKObjectType.quantityType(forIdentifier: .walkingSpeed) else {
                throw HealthManagerError.dataTypeUnavailable(rawValue)
            }
            return type
        }
        
        if self == .activity {
            // Activity uses multiple types, return stepCount as representative
            guard let type = HKObjectType.quantityType(forIdentifier: .stepCount) else {
                throw HealthManagerError.dataTypeUnavailable(rawValue)
            }
            return type
        }
        
        if self == .heart {
            // Heart uses multiple types, return heartRate as representative
            guard let type = HKObjectType.quantityType(forIdentifier: .heartRate) else {
                throw HealthManagerError.dataTypeUnavailable(rawValue)
            }
            return type
        }
        
        if self == .body {
            // Body uses multiple types, return bodyMass as representative
            guard let type = HKObjectType.quantityType(forIdentifier: .bodyMass) else {
                throw HealthManagerError.dataTypeUnavailable(rawValue)
            }
            return type
        }
        
        if self == .workout {
            // Workout uses HKWorkoutType
            return HKObjectType.workoutType()
        }
        
        let identifier: HKQuantityTypeIdentifier
        switch self {
        case .steps:
            identifier = .stepCount
        case .distance:
            identifier = .distanceWalkingRunning
        case .calories:
            identifier = .activeEnergyBurned
        case .heartRate:
            identifier = .heartRate
        case .weight:
            identifier = .bodyMass
        case .sleep:
            fatalError("Sleep should have been handled above")
        case .mobility:
            fatalError("Mobility should have been handled above")
        case .activity:
            fatalError("Activity should have been handled above")
        case .heart:
            fatalError("Heart should have been handled above")
        case .body:
            fatalError("Body should have been handled above")
        case .workout:
            fatalError("Workout should have been handled above")
        }

        guard let type = HKObjectType.quantityType(forIdentifier: identifier) else {
            throw HealthManagerError.dataTypeUnavailable(rawValue)
        }
        return type
    }

    var defaultUnit: HKUnit {
        switch self {
        case .steps:
            return HKUnit.count()
        case .distance:
            return HKUnit.meter()
        case .calories:
            return HKUnit.kilocalorie()
        case .heartRate:
            return HKUnit.count().unitDivided(by: HKUnit.minute())
        case .weight:
            return HKUnit.gramUnit(with: .kilo)
        case .sleep:
            return HKUnit.minute() // Sleep duration in minutes
        case .mobility:
            return HKUnit.meter() // Placeholder, mobility has multiple units
        case .activity:
            return HKUnit.count() // Placeholder, activity has multiple units
        case .heart:
            return HKUnit.count().unitDivided(by: HKUnit.minute()) // Placeholder, heart has multiple units
        case .body:
            return HKUnit.gramUnit(with: .kilo) // Placeholder, body has multiple units
        case .workout:
            return HKUnit.minute() // Workout duration in minutes
        }
    }

    var unitIdentifier: String {
        switch self {
        case .steps:
            return "count"
        case .distance:
            return "meter"
        case .calories:
            return "kilocalorie"
        case .heartRate:
            return "bpm"
        case .weight:
            return "kilogram"
        case .sleep:
            return "minute"
        case .mobility:
            return "mixed" // Mobility has multiple units
        case .activity:
            return "mixed" // Activity has multiple units
        case .heart:
            return "mixed" // Heart has multiple units
        case .body:
            return "mixed" // Body has multiple units
        case .workout:
            return "minute" // Workout duration in minutes
        }
    }

    static func parseMany(_ identifiers: [String]) throws -> [HealthDataType] {
        try identifiers.map { identifier in
            guard let type = HealthDataType(rawValue: identifier) else {
                throw HealthManagerError.invalidDataType(identifier)
            }
            return type
        }
    }
}

struct AuthorizationStatusPayload {
    let readAuthorized: [HealthDataType]
    let readDenied: [HealthDataType]
    let writeAuthorized: [HealthDataType]
    let writeDenied: [HealthDataType]

    func toDictionary() -> [String: Any] {
        return [
            "readAuthorized": readAuthorized.map { $0.rawValue },
            "readDenied": readDenied.map { $0.rawValue },
            "writeAuthorized": writeAuthorized.map { $0.rawValue },
            "writeDenied": writeDenied.map { $0.rawValue }
        ]
    }
}

final class Health {
    private let healthStore = HKHealthStore()
    private let isoFormatter: ISO8601DateFormatter

    init() {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        isoFormatter = formatter
    }

    func availabilityPayload() -> [String: Any] {
        let available = HKHealthStore.isHealthDataAvailable()
        if available {
            return [
                "available": true,
                "platform": "ios"
            ]
        }

        return [
            "available": false,
            "platform": "ios",
            "reason": "Health data is not available on this device."
        ]
    }

    func requestAuthorization(readIdentifiers: [String], writeIdentifiers: [String], completion: @escaping (Result<AuthorizationStatusPayload, Error>) -> Void) {
        guard HKHealthStore.isHealthDataAvailable() else {
            completion(.failure(HealthManagerError.healthDataUnavailable))
            return
        }

        do {
            let readTypes = try HealthDataType.parseMany(readIdentifiers)
            let writeTypes = try HealthDataType.parseMany(writeIdentifiers)

            let readObjectTypes = try objectTypes(for: readTypes)
            let writeSampleTypes = try sampleTypes(for: writeTypes)

            healthStore.requestAuthorization(toShare: writeSampleTypes, read: readObjectTypes) { [weak self] success, error in
                guard let self = self else { return }

                if let error = error {
                    completion(.failure(error))
                    return
                }

                if success {
                    self.evaluateAuthorizationStatus(readTypes: readTypes, writeTypes: writeTypes) { result in
                        completion(.success(result))
                    }
                } else {
                    completion(.failure(HealthManagerError.operationFailed("Authorization request was not granted.")))
                }
            }
        } catch {
            completion(.failure(error))
        }
    }

    func checkAuthorization(readIdentifiers: [String], writeIdentifiers: [String], completion: @escaping (Result<AuthorizationStatusPayload, Error>) -> Void) {
        do {
            let readTypes = try HealthDataType.parseMany(readIdentifiers)
            let writeTypes = try HealthDataType.parseMany(writeIdentifiers)

            evaluateAuthorizationStatus(readTypes: readTypes, writeTypes: writeTypes) { payload in
                completion(.success(payload))
            }
        } catch {
            completion(.failure(error))
        }
    }

    func readSamples(dataTypeIdentifier: String, startDateString: String?, endDateString: String?, limit: Int?, ascending: Bool, completion: @escaping (Result<[[String: Any]], Error>) -> Void) throws {
        let dataType = try parseDataType(identifier: dataTypeIdentifier)
        
        let startDate = try parseDate(startDateString, defaultValue: Date().addingTimeInterval(-86400))
        let endDate = try parseDate(endDateString, defaultValue: Date())

        guard endDate >= startDate else {
            throw HealthManagerError.invalidDateRange
        }

        // Handle body data (multiple quantity types)
        // Skip the initial query and go directly to processing to avoid authorization issues
        if dataType == .body {
            processBodyData(startDate: startDate, endDate: endDate) { result in
                switch result {
                case .success(let bodyData):
                    completion(.success(bodyData))
                case .failure(let error):
                    completion(.failure(error))
                }
            }
            return
        }

        // Handle heart data (multiple quantity types)
        // Skip the initial query and go directly to processing to avoid authorization issues
        if dataType == .heart {
            processHeartData(startDate: startDate, endDate: endDate) { result in
                switch result {
                case .success(let heartData):
                    completion(.success(heartData))
                case .failure(let error):
                    completion(.failure(error))
                }
            }
            return
        }

        // Handle activity data (multiple quantity and category types)
        // Skip the initial query and go directly to processing to avoid authorization issues
        if dataType == .activity {
            processActivityData(startDate: startDate, endDate: endDate) { result in
                switch result {
                case .success(let activityData):
                    completion(.success(activityData))
                case .failure(let error):
                    completion(.failure(error))
                }
            }
            return
        }
        
        // Handle mobility data (multiple quantity types)
        // Skip the initial query and go directly to processing to avoid authorization issues
        if dataType == .mobility {
            processMobilityData(startDate: startDate, endDate: endDate) { result in
                switch result {
                case .success(let mobilityData):
                    completion(.success(mobilityData))
                case .failure(let error):
                    completion(.failure(error))
                }
            }
            return
        }
        
        // Handle workout data
        if dataType == .workout {
            processWorkoutData(startDate: startDate, endDate: endDate, limit: limit, ascending: ascending) { result in
                switch result {
                case .success(let workoutData):
                    completion(.success(workoutData))
                case .failure(let error):
                    completion(.failure(error))
                }
            }
            return
        }
        
        // For all other data types, use the standard query approach
        let sampleType = try dataType.sampleType()
        let predicate = HKQuery.predicateForSamples(withStart: startDate, end: endDate, options: [])
        let sortDescriptor = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: ascending)
        let queryLimit = limit ?? 100

        let query = HKSampleQuery(sampleType: sampleType, predicate: predicate, limit: queryLimit, sortDescriptors: [sortDescriptor]) { [weak self] _, samples, error in
            guard let self = self else { return }

            if let error = error {
                completion(.failure(error))
                return
            }

            guard let samples = samples else {
                completion(.success([]))
                return
            }
            
            // Handle sleep data (category samples)
            if dataType == .sleep {
                guard let categorySamples = samples as? [HKCategorySample] else {
                    completion(.success([]))
                    return
                }

                // Process sleep data similar to client-side parser
                let processedSleepData = self.processSleepSamples(categorySamples)
                completion(.success(processedSleepData))
                return
            }

            // Handle quantity samples (existing logic)
            guard let quantitySamples = samples as? [HKQuantitySample] else {
                completion(.success([]))
                return
            }

            let results = quantitySamples.map { sample -> [String: Any] in
                let value = sample.quantity.doubleValue(for: dataType.defaultUnit)
                var payload: [String: Any] = [
                    "dataType": dataType.rawValue,
                    "value": value,
                    "unit": dataType.unitIdentifier,
                    "startDate": self.isoFormatter.string(from: sample.startDate),
                    "endDate": self.isoFormatter.string(from: sample.endDate)
                ]

                let source = sample.sourceRevision.source
                payload["sourceName"] = source.name
                payload["sourceId"] = source.bundleIdentifier

                return payload
            }

            completion(.success(results))
        }

        healthStore.execute(query)
    }

    func saveSample(dataTypeIdentifier: String, value: Double, unitIdentifier: String?, startDateString: String?, endDateString: String?, metadata: [String: String]?, completion: @escaping (Result<Void, Error>) -> Void) throws {
        guard HKHealthStore.isHealthDataAvailable() else {
            throw HealthManagerError.healthDataUnavailable
        }

        let dataType = try parseDataType(identifier: dataTypeIdentifier)
        let sampleType = try dataType.sampleType()

        let startDate = try parseDate(startDateString, defaultValue: Date())
        let endDate = try parseDate(endDateString, defaultValue: startDate)

        guard endDate >= startDate else {
            throw HealthManagerError.invalidDateRange
        }

        var metadataDictionary: [String: Any]?
        if let metadata = metadata, !metadata.isEmpty {
            metadataDictionary = metadata.reduce(into: [String: Any]()) { result, entry in
                result[entry.key] = entry.value
            }
        }

        let sample: HKSample
        
        // Handle sleep data (category samples)
        if dataType == .sleep {
            guard let categoryType = sampleType as? HKCategoryType else {
                throw HealthManagerError.operationFailed("Invalid category type for sleep")
            }
            
            // Value represents sleep state (0 = inBed, 1 = asleep, 2 = awake, etc.)
            let sleepValue = Int(value)
            sample = HKCategorySample(type: categoryType, value: sleepValue, start: startDate, end: endDate, metadata: metadataDictionary)
        } else {
            // Handle quantity samples (existing logic)
            guard let quantityType = sampleType as? HKQuantityType else {
                throw HealthManagerError.operationFailed("Invalid quantity type")
            }
            
            let unit = unit(for: unitIdentifier, dataType: dataType)
            let quantity = HKQuantity(unit: unit, doubleValue: value)
            sample = HKQuantitySample(type: quantityType, quantity: quantity, start: startDate, end: endDate, metadata: metadataDictionary)
        }

        healthStore.save(sample) { success, error in
            if let error = error {
                completion(.failure(error))
                return
            }

            if success {
                completion(.success(()))
            } else {
                completion(.failure(HealthManagerError.operationFailed("Failed to save the sample.")))
            }
        }
    }

    private func evaluateAuthorizationStatus(readTypes: [HealthDataType], writeTypes: [HealthDataType], completion: @escaping (AuthorizationStatusPayload) -> Void) {
        let writeStatus = writeAuthorizationStatus(for: writeTypes)

        readAuthorizationStatus(for: readTypes) { readAuthorized, readDenied in
            let payload = AuthorizationStatusPayload(
                readAuthorized: readAuthorized,
                readDenied: readDenied,
                writeAuthorized: writeStatus.authorized,
                writeDenied: writeStatus.denied
            )
            completion(payload)
        }
    }

    private func writeAuthorizationStatus(for types: [HealthDataType]) -> (authorized: [HealthDataType], denied: [HealthDataType]) {
        var authorized: [HealthDataType] = []
        var denied: [HealthDataType] = []

        for type in types {
            // Special handling for activity - check all activity types
            // Consider authorized if at least one activity type is authorized
            if type == .activity {
                let activityIdentifiers: [HKQuantityTypeIdentifier] = [
                    .stepCount,
                    .distanceWalkingRunning,
                    .flightsClimbed,
                    .activeEnergyBurned,
                    .appleExerciseTime
                ]
                
                var hasAnyAuthorized = false
                for identifier in activityIdentifiers {
                    if let quantityType = HKObjectType.quantityType(forIdentifier: identifier) {
                        let status = healthStore.authorizationStatus(for: quantityType)
                        if status == .sharingAuthorized {
                            hasAnyAuthorized = true
                            break
                        }
                    }
                }
                
                // Also check stand hour (category type)
                if !hasAnyAuthorized {
                    if let standHourType = HKObjectType.categoryType(forIdentifier: .appleStandHour) {
                        let status = healthStore.authorizationStatus(for: standHourType)
                        if status == .sharingAuthorized {
                            hasAnyAuthorized = true
                        }
                    }
                }
                
                if hasAnyAuthorized {
                    authorized.append(type)
                } else {
                    denied.append(type)
                }
            }
            // Special handling for body - check body composition types
            // Consider authorized if at least one body type is authorized
            else if type == .body {
                let bodyIdentifiers: [HKQuantityTypeIdentifier] = [
                    .bodyMass,
                    .bodyFatPercentage
                ]
                
                var hasAnyAuthorized = false
                for identifier in bodyIdentifiers {
                    if let quantityType = HKObjectType.quantityType(forIdentifier: identifier) {
                        let status = healthStore.authorizationStatus(for: quantityType)
                        if status == .sharingAuthorized {
                            hasAnyAuthorized = true
                            break
                        }
                    }
                }
                
                if hasAnyAuthorized {
                    authorized.append(type)
                } else {
                    denied.append(type)
                }
            }
            // Special handling for mobility - check all 6 types
            else if type == .mobility {
                let mobilityIdentifiers: [HKQuantityTypeIdentifier] = [
                    .walkingSpeed,
                    .walkingStepLength,
                    .walkingAsymmetryPercentage,
                    .walkingDoubleSupportPercentage,
                    .stairAscentSpeed,
                    .sixMinuteWalkTestDistance
                ]
                
                var allAuthorized = true
                for identifier in mobilityIdentifiers {
                    if let quantityType = HKObjectType.quantityType(forIdentifier: identifier) {
                        let status = healthStore.authorizationStatus(for: quantityType)
                        if status != .sharingAuthorized {
                            allAuthorized = false
                            break
                        }
                    }
                }
                
                if allAuthorized {
                    authorized.append(type)
                } else {
                    denied.append(type)
                }
            } else {
                guard let sampleType = try? type.sampleType() else {
                    denied.append(type)
                    continue
                }

                switch healthStore.authorizationStatus(for: sampleType) {
                case .sharingAuthorized:
                    authorized.append(type)
                case .sharingDenied, .notDetermined:
                    denied.append(type)
                @unknown default:
                    denied.append(type)
                }
            }
        }

        return (authorized, denied)
    }

    private func readAuthorizationStatus(for types: [HealthDataType], completion: @escaping ([HealthDataType], [HealthDataType]) -> Void) {
        guard !types.isEmpty else {
            completion([], [])
            return
        }

        if #available(iOS 12.0, *) {
            let group = DispatchGroup()
            let lock = NSLock()
            var authorized: [HealthDataType] = []
            var denied: [HealthDataType] = []

            for type in types {
                // Special handling for activity - check all activity types
                if type == .activity {
                    let activityIdentifiers: [HKQuantityTypeIdentifier] = [
                        .stepCount,
                        .distanceWalkingRunning,
                        .flightsClimbed,
                        .activeEnergyBurned,
                        .appleExerciseTime
                    ]
                    
                    // Check all 5 quantity types + 1 category type
                    var activityAuthorizedCount = 0
                    let totalActivityTypes = activityIdentifiers.count + 1 // +1 for stand hour
                    
                    // Create a nested group for activity checks
                    let activityGroup = DispatchGroup()
                    
                    for identifier in activityIdentifiers {
                        if let quantityType = HKObjectType.quantityType(forIdentifier: identifier) {
                            activityGroup.enter()
                            let readSet = Set<HKObjectType>([quantityType])
                            healthStore.getRequestStatusForAuthorization(toShare: Set<HKSampleType>(), read: readSet) { status, error in
                                defer { activityGroup.leave() }
                                
                                if error == nil && status == .unnecessary {
                                    lock.lock()
                                    activityAuthorizedCount += 1
                                    lock.unlock()
                                }
                            }
                        }
                    }
                    
                    // Check stand hour (category type)
                    if let standHourType = HKObjectType.categoryType(forIdentifier: .appleStandHour) {
                        activityGroup.enter()
                        let readSet = Set<HKObjectType>([standHourType])
                        healthStore.getRequestStatusForAuthorization(toShare: Set<HKSampleType>(), read: readSet) { status, error in
                            defer { activityGroup.leave() }
                            
                            if error == nil && status == .unnecessary {
                                lock.lock()
                                activityAuthorizedCount += 1
                                lock.unlock()
                            }
                        }
                    }
                    
                    // Wait for all activity checks, then determine if activity is authorized
                    // Consider authorized if at least one activity type is authorized
                    activityGroup.notify(queue: .main) {
                        lock.lock()
                        if activityAuthorizedCount > 0 {
                            authorized.append(type)
                        } else {
                            denied.append(type)
                        }
                        lock.unlock()
                    }
                }
                // Special handling for body - check body composition types
                else if type == .body {
                    let bodyIdentifiers: [HKQuantityTypeIdentifier] = [
                        .bodyMass,
                        .bodyFatPercentage
                    ]
                    
                    // Check all body types
                    var bodyAuthorizedCount = 0
                    
                    // Create a nested group for body checks
                    let bodyGroup = DispatchGroup()
                    
                    for identifier in bodyIdentifiers {
                        if let quantityType = HKObjectType.quantityType(forIdentifier: identifier) {
                            bodyGroup.enter()
                            let readSet = Set<HKObjectType>([quantityType])
                            healthStore.getRequestStatusForAuthorization(toShare: Set<HKSampleType>(), read: readSet) { status, error in
                                defer { bodyGroup.leave() }
                                
                                if error == nil && status == .unnecessary {
                                    lock.lock()
                                    bodyAuthorizedCount += 1
                                    lock.unlock()
                                }
                            }
                        }
                    }
                    
                    // Wait for all body checks, then determine if body is authorized
                    // Consider authorized if at least one body type is authorized
                    bodyGroup.notify(queue: .main) {
                        lock.lock()
                        if bodyAuthorizedCount > 0 {
                            authorized.append(type)
                        } else {
                            denied.append(type)
                        }
                        lock.unlock()
                    }
                }
                // Special handling for mobility - check all 6 types
                else if type == .mobility {
                    let mobilityIdentifiers: [HKQuantityTypeIdentifier] = [
                        .walkingSpeed,
                        .walkingStepLength,
                        .walkingAsymmetryPercentage,
                        .walkingDoubleSupportPercentage,
                        .stairAscentSpeed,
                        .sixMinuteWalkTestDistance
                    ]
                    
                    // Check all 6 mobility types
                    var mobilityAuthorizedCount = 0
                    
                    // Create a nested group for mobility checks
                    let mobilityGroup = DispatchGroup()
                    
                    for identifier in mobilityIdentifiers {
                        if let quantityType = HKObjectType.quantityType(forIdentifier: identifier) {
                            mobilityGroup.enter()
                            let readSet = Set<HKObjectType>([quantityType])
                            healthStore.getRequestStatusForAuthorization(toShare: Set<HKSampleType>(), read: readSet) { status, error in
                                defer { mobilityGroup.leave() }
                                
                                if error == nil && status == .unnecessary {
                                    lock.lock()
                                    mobilityAuthorizedCount += 1
                                    lock.unlock()
                                }
                            }
                        }
                    }
                    
                    // Wait for all mobility checks, then determine if mobility is authorized
                    mobilityGroup.notify(queue: .main) {
                        lock.lock()
                        if mobilityAuthorizedCount == mobilityIdentifiers.count {
                            authorized.append(type)
                        } else {
                            denied.append(type)
                        }
                        lock.unlock()
                    }
                } else {
                    guard let objectType = try? type.sampleType() else {
                        denied.append(type)
                        continue
                    }

                    group.enter()
                    let readSet = Set<HKObjectType>([objectType])
                    healthStore.getRequestStatusForAuthorization(toShare: Set<HKSampleType>(), read: readSet) { status, error in
                        defer { group.leave() }

                        if error != nil {
                            lock.lock(); denied.append(type); lock.unlock()
                            return
                        }

                        switch status {
                        case .unnecessary:
                            lock.lock(); authorized.append(type); lock.unlock()
                        case .shouldRequest, .unknown:
                            lock.lock(); denied.append(type); lock.unlock()
                        @unknown default:
                            lock.lock(); denied.append(type); lock.unlock()
                        }
                    }
                }
            }

            group.notify(queue: .main) {
                completion(authorized, denied)
            }
        } else {
            completion(types, [])
        }
    }

    private func parseDataType(identifier: String) throws -> HealthDataType {
        guard let type = HealthDataType(rawValue: identifier) else {
            throw HealthManagerError.invalidDataType(identifier)
        }
        return type
    }

    private func parseDate(_ string: String?, defaultValue: Date) throws -> Date {
        guard let value = string else {
            return defaultValue
        }

        if let date = isoFormatter.date(from: value) {
            return date
        }

        throw HealthManagerError.invalidDate(value)
    }

    private func sleepValueString(for value: Int) -> String {
        if #available(iOS 16.0, *) {
            switch value {
            case HKCategoryValueSleepAnalysis.inBed.rawValue:
                return "inBed"
            case HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue:
                return "asleep"
            case HKCategoryValueSleepAnalysis.awake.rawValue:
                return "awake"
            case HKCategoryValueSleepAnalysis.asleepCore.rawValue:
                return "asleepCore"
            case HKCategoryValueSleepAnalysis.asleepDeep.rawValue:
                return "asleepDeep"
            case HKCategoryValueSleepAnalysis.asleepREM.rawValue:
                return "asleepREM"
            default:
                return "unknown"
            }
        } else {
            switch value {
            case HKCategoryValueSleepAnalysis.inBed.rawValue:
                return "inBed"
            case HKCategoryValueSleepAnalysis.asleep.rawValue:
                return "asleep"
            case HKCategoryValueSleepAnalysis.awake.rawValue:
                return "awake"
            default:
                return "unknown"
            }
        }
    }
    
    private func processSleepSamples(_ samples: [HKCategorySample]) -> [[String: Any]] {
        // Filter for detailed stage data only (Deep, REM, Core, Awake)
        let detailedSamples = samples.filter { sample in
            if #available(iOS 16.0, *) {
                return sample.value == HKCategoryValueSleepAnalysis.asleepDeep.rawValue ||
                       sample.value == HKCategoryValueSleepAnalysis.asleepREM.rawValue ||
                       sample.value == HKCategoryValueSleepAnalysis.asleepCore.rawValue ||
                       sample.value == HKCategoryValueSleepAnalysis.awake.rawValue
            } else {
                // For older iOS, just process what's available
                return true
            }
        }
        
        // Sort by start date
        let sortedSamples = detailedSamples.sorted { $0.startDate < $1.startDate }
        
        // Collect ALL stage segments (raw data) - matching TypeScript structure
        struct SleepSegment {
            let start: Date
            let end: Date
            let stage: String
        }
        
        var allSegments: [SleepSegment] = []
        
        for sample in sortedSamples {
            let stageValue = getHealthKitStageConstantName(for: sample.value)
            allSegments.append(SleepSegment(
                start: sample.startDate,
                end: sample.endDate,
                stage: stageValue
            ))
        }
        
        // Group segments by SLEEP SESSION (not by day!)
        // Sessions are separated by 30+ minute gaps
        struct SleepSession {
            let start: Date
            let end: Date
            let segments: [SleepSegment]
        }
        
        var sessions: [SleepSession] = []
        var currentSession: [SleepSegment] = []
        
        for segment in allSegments {
            if currentSession.isEmpty {
                currentSession.append(segment)
            } else {
                let lastSegment = currentSession.last!
                let gapMinutes = segment.start.timeIntervalSince(lastSegment.end) / 60.0
                
                if gapMinutes < 30 {
                    // Same session
                    currentSession.append(segment)
                } else {
                    // New session (gap > 30 min)
                    if !currentSession.isEmpty {
                        sessions.append(SleepSession(
                            start: currentSession.first!.start,
                            end: currentSession.last!.end,
                            segments: currentSession
                        ))
                    }
                    currentSession = [segment]
                }
            }
        }
        
        // Don't forget last session
        if !currentSession.isEmpty {
            sessions.append(SleepSession(
                start: currentSession.first!.start,
                end: currentSession.last!.end,
                segments: currentSession
            ))
        }
        
        // Now attribute each session to the day you WOKE UP (end date)
        struct DayData {
            var sessions: [SleepSession]
            var deepMinutes: Double
            var remMinutes: Double
            var coreMinutes: Double
            var awakeMinutes: Double
        }
        
        var sleepByDate: [String: DayData] = [:]
        
        for session in sessions {
            // Wake-up date (local)
            let calendar = Calendar.current
            let wakeDate = calendar.dateComponents([.year, .month, .day], from: session.end)
            let dateString = String(format: "%04d-%02d-%02d", wakeDate.year!, wakeDate.month!, wakeDate.day!)
            
            // Initialize day data if needed
            if sleepByDate[dateString] == nil {
                sleepByDate[dateString] = DayData(
                    sessions: [],
                    deepMinutes: 0,
                    remMinutes: 0,
                    coreMinutes: 0,
                    awakeMinutes: 0
                )
            }
            
            sleepByDate[dateString]!.sessions.append(session)
            
            // Calculate minutes per stage for THIS session
            for segment in session.segments {
                let minutes = segment.end.timeIntervalSince(segment.start) / 60.0
                
                if segment.stage == "HKCategoryValueSleepAnalysisAsleepDeep" {
                    sleepByDate[dateString]!.deepMinutes += minutes
                } else if segment.stage == "HKCategoryValueSleepAnalysisAsleepREM" {
                    sleepByDate[dateString]!.remMinutes += minutes
                } else if segment.stage == "HKCategoryValueSleepAnalysisAsleepCore" {
                    sleepByDate[dateString]!.coreMinutes += minutes
                } else if segment.stage == "HKCategoryValueSleepAnalysisAwake" {
                    sleepByDate[dateString]!.awakeMinutes += minutes
                }
            }
        }
        
        // Convert to final format
        var sleepData: [[String: Any]] = []
        
        for (date, data) in sleepByDate {
            let deepHours = data.deepMinutes / 60.0
            let remHours = data.remMinutes / 60.0
            let coreHours = data.coreMinutes / 60.0
            let awakeHours = data.awakeMinutes / 60.0
            let totalSleepHours = deepHours + remHours + coreHours
            
            // Calculate time in bed from merged sessions (first start to last end)
            var timeInBed = 0.0
            if !data.sessions.isEmpty {
                let bedtime = data.sessions.first!.start
                let wakeTime = data.sessions.last!.end
                timeInBed = wakeTime.timeIntervalSince(bedtime) / 3600.0
            }
            
            // Calculate efficiency
            let efficiency = timeInBed > 0 ? Int(round((totalSleepHours / timeInBed) * 100)) : 0
            
            // Map sessions to output format with segments matching TypeScript structure
            let mergedSessions: [[String: Any]] = data.sessions.map { session in
                let segments: [[String: Any]] = session.segments.map { segment in
                    return [
                        "start": isoFormatter.string(from: segment.start),
                        "end": isoFormatter.string(from: segment.end),
                        "stage": segment.stage
                    ]
                }
                
                return [
                    "start": isoFormatter.string(from: session.start),
                    "end": isoFormatter.string(from: session.end),
                    "segments": segments
                ]
            }
            
            sleepData.append([
                "date": date,
                "totalSleepHours": round(totalSleepHours * 10) / 10,
                "sleepSessions": data.sessions.count,
                "deepSleep": round(deepHours * 10) / 10,
                "remSleep": round(remHours * 10) / 10,
                "coreSleep": round(coreHours * 10) / 10,
                "awakeTime": round(awakeHours * 10) / 10,
                "timeInBed": round(timeInBed * 10) / 10,
                "efficiency": efficiency,
                "mergedSessions": mergedSessions
            ])
        }
        
        // Sort by date
        sleepData.sort { (a, b) -> Bool in
            let dateA = a["date"] as! String
            let dateB = b["date"] as! String
            return dateA < dateB
        }
        
        return sleepData
    }
    
    private func getHealthKitStageConstantName(for value: Int) -> String {
        if #available(iOS 16.0, *) {
            switch value {
            case HKCategoryValueSleepAnalysis.asleepDeep.rawValue:
                return "HKCategoryValueSleepAnalysisAsleepDeep"
            case HKCategoryValueSleepAnalysis.asleepREM.rawValue:
                return "HKCategoryValueSleepAnalysisAsleepREM"
            case HKCategoryValueSleepAnalysis.asleepCore.rawValue:
                return "HKCategoryValueSleepAnalysisAsleepCore"
            case HKCategoryValueSleepAnalysis.awake.rawValue:
                return "HKCategoryValueSleepAnalysisAwake"
            case HKCategoryValueSleepAnalysis.inBed.rawValue:
                return "HKCategoryValueSleepAnalysisInBed"
            case HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue:
                return "HKCategoryValueSleepAnalysisAsleepUnspecified"
            default:
                return "HKCategoryValueSleepAnalysisUnknown"
            }
        } else {
            switch value {
            case HKCategoryValueSleepAnalysis.inBed.rawValue:
                return "HKCategoryValueSleepAnalysisInBed"
            case HKCategoryValueSleepAnalysis.asleep.rawValue:
                return "HKCategoryValueSleepAnalysisAsleep"
            case HKCategoryValueSleepAnalysis.awake.rawValue:
                return "HKCategoryValueSleepAnalysisAwake"
            default:
                return "HKCategoryValueSleepAnalysisUnknown"
            }
        }
    }

    private func unit(for identifier: String?, dataType: HealthDataType) -> HKUnit {
        guard let identifier = identifier else {
            return dataType.defaultUnit
        }

        switch identifier {
        case "count":
            return HKUnit.count()
        case "meter":
            return HKUnit.meter()
        case "kilocalorie":
            return HKUnit.kilocalorie()
        case "bpm":
            return HKUnit.count().unitDivided(by: HKUnit.minute())
        case "kilogram":
            return HKUnit.gramUnit(with: .kilo)
        case "minute":
            return HKUnit.minute()
        default:
            return dataType.defaultUnit
        }
    }

    private func objectTypes(for dataTypes: [HealthDataType]) throws -> Set<HKObjectType> {
        var set = Set<HKObjectType>()
        for dataType in dataTypes {
            // Special handling for activity - expand into all activity-related HealthKit types
            if dataType == .activity {
                let activityIdentifiers: [HKQuantityTypeIdentifier] = [
                    .stepCount,
                    .distanceWalkingRunning,
                    .flightsClimbed,
                    .activeEnergyBurned,
                    .appleExerciseTime
                ]
                
                for identifier in activityIdentifiers {
                    if let quantityType = HKObjectType.quantityType(forIdentifier: identifier) {
                        set.insert(quantityType)
                    }
                }
                
                // Add category type for stand hours
                if let standHourType = HKObjectType.categoryType(forIdentifier: .appleStandHour) {
                    set.insert(standHourType)
                }
            }
            // Special handling for heart - expand into all 6 HealthKit types
            else if dataType == .heart {
                let heartIdentifiers: [HKQuantityTypeIdentifier] = [
                    .heartRate,
                    .restingHeartRate,
                    .vo2Max,
                    .heartRateVariabilitySDNN,
                    .oxygenSaturation,
                    .respiratoryRate
                ]
                
                for identifier in heartIdentifiers {
                    if let quantityType = HKObjectType.quantityType(forIdentifier: identifier) {
                        set.insert(quantityType)
                    }
                }
            }
            // Special handling for body - expand into body composition types
            else if dataType == .body {
                let bodyIdentifiers: [HKQuantityTypeIdentifier] = [
                    .bodyMass,
                    .bodyFatPercentage
                ]
                
                for identifier in bodyIdentifiers {
                    if let quantityType = HKObjectType.quantityType(forIdentifier: identifier) {
                        set.insert(quantityType)
                    }
                }
            }
            // Special handling for mobility - expand into all 6 HealthKit types
            else if dataType == .mobility {
                let mobilityIdentifiers: [HKQuantityTypeIdentifier] = [
                    .walkingSpeed,
                    .walkingStepLength,
                    .walkingAsymmetryPercentage,
                    .walkingDoubleSupportPercentage,
                    .stairAscentSpeed,
                    .sixMinuteWalkTestDistance
                ]
                
                for identifier in mobilityIdentifiers {
                    if let quantityType = HKObjectType.quantityType(forIdentifier: identifier) {
                        set.insert(quantityType)
                    }
                }
            } else {
                let type = try dataType.sampleType()
                set.insert(type)
            }
        }
        return set
    }

    private func sampleTypes(for dataTypes: [HealthDataType]) throws -> Set<HKSampleType> {
        var set = Set<HKSampleType>()
        for dataType in dataTypes {
            // Special handling for activity - expand into all activity-related HealthKit types
            if dataType == .activity {
                let activityIdentifiers: [HKQuantityTypeIdentifier] = [
                    .stepCount,
                    .distanceWalkingRunning,
                    .flightsClimbed,
                    .activeEnergyBurned,
                    .appleExerciseTime
                ]
                
                for identifier in activityIdentifiers {
                    if let quantityType = HKObjectType.quantityType(forIdentifier: identifier) {
                        set.insert(quantityType)
                    }
                }
                
                // Add category type for stand hours
                if let standHourType = HKObjectType.categoryType(forIdentifier: .appleStandHour) {
                    set.insert(standHourType)
                }
            }
            // Special handling for heart - expand into all 6 HealthKit types
            else if dataType == .heart {
                let heartIdentifiers: [HKQuantityTypeIdentifier] = [
                    .heartRate,
                    .restingHeartRate,
                    .vo2Max,
                    .heartRateVariabilitySDNN,
                    .oxygenSaturation,
                    .respiratoryRate
                ]
                
                for identifier in heartIdentifiers {
                    if let quantityType = HKObjectType.quantityType(forIdentifier: identifier) {
                        set.insert(quantityType)
                    }
                }
            }
            // Special handling for body - expand into body composition types
            else if dataType == .body {
                let bodyIdentifiers: [HKQuantityTypeIdentifier] = [
                    .bodyMass,
                    .bodyFatPercentage
                ]
                
                for identifier in bodyIdentifiers {
                    if let quantityType = HKObjectType.quantityType(forIdentifier: identifier) {
                        set.insert(quantityType)
                    }
                }
            }
            // Special handling for mobility - expand into all 6 HealthKit types
            else if dataType == .mobility {
                let mobilityIdentifiers: [HKQuantityTypeIdentifier] = [
                    .walkingSpeed,
                    .walkingStepLength,
                    .walkingAsymmetryPercentage,
                    .walkingDoubleSupportPercentage,
                    .stairAscentSpeed,
                    .sixMinuteWalkTestDistance
                ]
                
                for identifier in mobilityIdentifiers {
                    if let quantityType = HKObjectType.quantityType(forIdentifier: identifier) {
                        set.insert(quantityType)
                    }
                }
            } else {
                let type = try dataType.sampleType() as HKSampleType
                set.insert(type)
            }
        }
        return set
    }
    
    // MARK: - Body Data Processing
    
    private func processBodyData(startDate: Date, endDate: Date, completion: @escaping (Result<[[String: Any]], Error>) -> Void) {
        let calendar = Calendar.current
        
        // Define body composition quantity types
        let bodyTypes: [(HKQuantityTypeIdentifier, String)] = [
            (.bodyMass, "bodyMass"),
            (.bodyFatPercentage, "bodyFatPercentage")
        ]
        
        // Get all dates in the range
        var dates: [Date] = []
        var currentDate = calendar.startOfDay(for: startDate)
        let endOfDay = calendar.startOfDay(for: endDate)
        
        while currentDate <= endOfDay {
            dates.append(currentDate)
            currentDate = calendar.date(byAdding: .day, value: 1, to: currentDate)!
        }
        
        // Dictionary to store body data by date
        var bodyDataByDate: [String: [String: Any]] = [:]
        
        // Initialize dates with empty dictionaries
        let dateFormatter = ISO8601DateFormatter()
        dateFormatter.formatOptions = [.withFullDate]
        
        for date in dates {
            let dateStr = dateFormatter.string(from: date)
            bodyDataByDate[dateStr] = ["date": dateStr]
        }
        
        let group = DispatchGroup()
        
        // Query each body type
        for (identifier, _) in bodyTypes {
            guard let quantityType = HKObjectType.quantityType(forIdentifier: identifier) else {
                continue
            }
            
            group.enter()
            
            let predicate = HKQuery.predicateForSamples(withStart: startDate, end: endDate, options: .strictStartDate)
            let sortDescriptor = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)
            
            let query = HKSampleQuery(sampleType: quantityType, predicate: predicate, limit: HKObjectQueryNoLimit, sortDescriptors: [sortDescriptor]) { _, samples, error in
                defer { group.leave() }
                
                // Don't fail the entire request if one body type fails
                // Just skip this type and continue with others
                if error != nil {
                    return
                }
                
                guard let samples = samples as? [HKQuantitySample] else {
                    return
                }
                
                // Group samples by date and take the last measurement of each day
                var samplesByDate: [String: HKQuantitySample] = [:]
                
                for sample in samples {
                    let sampleDate = calendar.startOfDay(for: sample.startDate)
                    let dateStr = dateFormatter.string(from: sampleDate)
                    
                    // Keep the last (most recent) sample for each date
                    if let existingSample = samplesByDate[dateStr] {
                        if sample.startDate > existingSample.startDate {
                            samplesByDate[dateStr] = sample
                        }
                    } else {
                        samplesByDate[dateStr] = sample
                    }
                }
                
                // Process the last measurement for each date
                for (dateStr, sample) in samplesByDate {
                    var dayData = bodyDataByDate[dateStr] ?? ["date": dateStr]
                    
                    switch identifier {
                    case .bodyMass:
                        // Convert kg to lbs: kg * 2.20462
                        let valueInKg = sample.quantity.doubleValue(for: HKUnit.gramUnit(with: .kilo))
                        let valueInLbs = valueInKg * 2.20462
                        dayData["weight"] = round(valueInLbs * 10) / 10  // 1 decimal place
                        
                    case .bodyFatPercentage:
                        // Convert decimal to percentage: 0.25 -> 25%
                        let valueInDecimal = sample.quantity.doubleValue(for: HKUnit.percent())
                        dayData["bodyFat"] = round(valueInDecimal * 10) / 10  // 1 decimal place
                        
                    default:
                        break
                    }
                    
                    bodyDataByDate[dateStr] = dayData
                }
            }
            
            healthStore.execute(query)
        }
        
        group.notify(queue: .main) {
            // Convert to array and sort by date
            let sortedData = bodyDataByDate.values
                .sorted { dict1, dict2 in
                    guard let date1Str = dict1["date"] as? String,
                          let date2Str = dict2["date"] as? String else {
                        return false
                    }
                    return date1Str < date2Str
                }
                .filter { dict in
                    // Only include dates that have at least one body measurement
                    return dict.count > 1  // More than just the "date" field
                }
            
            completion(.success(sortedData))
        }
    }
    
    // MARK: - Mobility Data Processing
    
    private func processMobilityData(startDate: Date, endDate: Date, completion: @escaping (Result<[[String: Any]], Error>) -> Void) {
        let calendar = Calendar.current
        
        // Calculate the local date range that corresponds to the input UTC date range
        let startDateComponents = calendar.dateComponents([.year, .month, .day], from: startDate)
        let endDateComponents = calendar.dateComponents([.year, .month, .day], from: endDate)
        let localStartDateString = String(format: "%04d-%02d-%02d", startDateComponents.year!, startDateComponents.month!, startDateComponents.day!)
        let localEndDateString = String(format: "%04d-%02d-%02d", endDateComponents.year!, endDateComponents.month!, endDateComponents.day!)
        
        // Define all mobility quantity types
        let mobilityTypes: [(HKQuantityTypeIdentifier, String)] = [
            (.walkingSpeed, "walkingSpeed"),
            (.walkingStepLength, "walkingStepLength"),
            (.walkingAsymmetryPercentage, "walkingAsymmetry"),
            (.walkingDoubleSupportPercentage, "walkingDoubleSupportTime"),
            (.stairAscentSpeed, "stairSpeed"),
            (.sixMinuteWalkTestDistance, "sixMinuteWalkDistance")
        ]
        
        let group = DispatchGroup()
        let lock = NSLock()
        
        // Maps to store values by date for each metric
        var walkingSpeedMap: [String: [Double]] = [:]
        var stepLengthMap: [String: [Double]] = [:]
        var asymmetryMap: [String: [Double]] = [:]
        var doubleSupportMap: [String: [Double]] = [:]
        var stairSpeedMap: [String: [Double]] = [:]
        var sixMinWalkMap: [String: [Double]] = [:]
        
        var errors: [Error] = []
        
        // Query each mobility metric
        for (typeIdentifier, key) in mobilityTypes {
            guard let quantityType = HKObjectType.quantityType(forIdentifier: typeIdentifier) else {
                continue
            }
            
            group.enter()
            
            let predicate = HKQuery.predicateForSamples(withStart: startDate, end: endDate, options: [])
            let query = HKSampleQuery(sampleType: quantityType, predicate: predicate, limit: HKObjectQueryNoLimit, sortDescriptors: nil) { _, samples, error in
                defer { group.leave() }
                
                if let error = error {
                    lock.lock()
                    errors.append(error)
                    lock.unlock()
                    return
                }
                
                guard let quantitySamples = samples as? [HKQuantitySample] else {
                    return
                }
                
                // Process samples and group by date
                for sample in quantitySamples {
                    let dateComponents = calendar.dateComponents([.year, .month, .day], from: sample.startDate)
                    let dateString = String(format: "%04d-%02d-%02d", dateComponents.year!, dateComponents.month!, dateComponents.day!)
                    
                    var value: Double = 0.0
                    
                    // Convert values to match XML parser units
                    switch typeIdentifier {
                    case .walkingSpeed:
                        // Convert to mph (HealthKit stores in m/s)
                        value = sample.quantity.doubleValue(for: HKUnit.meter().unitDivided(by: HKUnit.second())) * 2.23694
                        lock.lock()
                        if walkingSpeedMap[dateString] == nil {
                            walkingSpeedMap[dateString] = []
                        }
                        walkingSpeedMap[dateString]?.append(value)
                        lock.unlock()
                        
                    case .walkingStepLength:
                        // Convert to inches (HealthKit stores in meters)
                        value = sample.quantity.doubleValue(for: HKUnit.meter()) * 39.3701
                        lock.lock()
                        if stepLengthMap[dateString] == nil {
                            stepLengthMap[dateString] = []
                        }
                        stepLengthMap[dateString]?.append(value)
                        lock.unlock()
                        
                    case .walkingAsymmetryPercentage:
                        // Convert to percentage (HealthKit stores as decimal)
                        value = sample.quantity.doubleValue(for: HKUnit.percent()) * 100
                        lock.lock()
                        if asymmetryMap[dateString] == nil {
                            asymmetryMap[dateString] = []
                        }
                        asymmetryMap[dateString]?.append(value)
                        lock.unlock()
                        
                    case .walkingDoubleSupportPercentage:
                        // Convert to percentage (HealthKit stores as decimal)
                        value = sample.quantity.doubleValue(for: HKUnit.percent()) * 100
                        lock.lock()
                        if doubleSupportMap[dateString] == nil {
                            doubleSupportMap[dateString] = []
                        }
                        doubleSupportMap[dateString]?.append(value)
                        lock.unlock()
                        
                    case .stairAscentSpeed:
                        // Convert to ft/s (HealthKit stores in m/s)
                        value = sample.quantity.doubleValue(for: HKUnit.meter().unitDivided(by: HKUnit.second())) * 3.28084
                        lock.lock()
                        if stairSpeedMap[dateString] == nil {
                            stairSpeedMap[dateString] = []
                        }
                        stairSpeedMap[dateString]?.append(value)
                        lock.unlock()
                        
                    case .sixMinuteWalkTestDistance:
                        // Convert to yards (HealthKit stores in meters)
                        value = sample.quantity.doubleValue(for: HKUnit.meter()) * 1.09361
                        lock.lock()
                        if sixMinWalkMap[dateString] == nil {
                            sixMinWalkMap[dateString] = []
                        }
                        sixMinWalkMap[dateString]?.append(value)
                        lock.unlock()
                        
                    default:
                        break
                    }
                }
            }
            
            healthStore.execute(query)
        }
        
        group.notify(queue: .main) {
            if !errors.isEmpty {
                completion(.failure(errors.first!))
                return
            }
            
            // Collect all unique dates
            var allDates = Set<String>()
            allDates.formUnion(walkingSpeedMap.keys)
            allDates.formUnion(stepLengthMap.keys)
            allDates.formUnion(asymmetryMap.keys)
            allDates.formUnion(doubleSupportMap.keys)
            allDates.formUnion(stairSpeedMap.keys)
            allDates.formUnion(sixMinWalkMap.keys)
            
            // Filter dates to only include those within the requested local date range
            let filteredDates = allDates.filter { date in
                return date >= localStartDateString && date <= localEndDateString
            }
            
            // Create mobility data array with aggregated daily averages
            var mobilityData: [[String: Any]] = []
            
            for date in filteredDates.sorted() {
                var result: [String: Any] = ["date": date]
                
                // Average all measurements for the day
                if let values = walkingSpeedMap[date], !values.isEmpty {
                    let average = values.reduce(0.0, +) / Double(values.count)
                    result["walkingSpeed"] = round(average * 100) / 100
                }
                
                if let values = stepLengthMap[date], !values.isEmpty {
                    let average = values.reduce(0.0, +) / Double(values.count)
                    result["walkingStepLength"] = round(average * 10) / 10
                }
                
                if let values = asymmetryMap[date], !values.isEmpty {
                    let average = values.reduce(0.0, +) / Double(values.count)
                    result["walkingAsymmetry"] = round(average * 10) / 10
                }
                
                if let values = doubleSupportMap[date], !values.isEmpty {
                    let average = values.reduce(0.0, +) / Double(values.count)
                    result["walkingDoubleSupportTime"] = round(average * 10) / 10
                }
                
                if let values = stairSpeedMap[date], !values.isEmpty {
                    let average = values.reduce(0.0, +) / Double(values.count)
                    result["stairSpeed"] = round(average * 100) / 100
                }
                
                if let values = sixMinWalkMap[date], !values.isEmpty {
                    let average = values.reduce(0.0, +) / Double(values.count)
                    result["sixMinuteWalkDistance"] = round(average * 10) / 10
                }
                
                mobilityData.append(result)
            }
            
            completion(.success(mobilityData))
        }
    }
    
    // MARK: - Activity Data Processing
    
    private func processActivityData(startDate: Date, endDate: Date, completion: @escaping (Result<[[String: Any]], Error>) -> Void) {
        let calendar = Calendar.current
        let group = DispatchGroup()
        let lock = NSLock()
        
        // Calculate the local date range that corresponds to the input UTC date range
        // This ensures we only return data for dates that fall within the requested range
        let startDateComponents = calendar.dateComponents([.year, .month, .day], from: startDate)
        let endDateComponents = calendar.dateComponents([.year, .month, .day], from: endDate)
        let localStartDateString = String(format: "%04d-%02d-%02d", startDateComponents.year!, startDateComponents.month!, startDateComponents.day!)
        let localEndDateString = String(format: "%04d-%02d-%02d", endDateComponents.year!, endDateComponents.month!, endDateComponents.day!)
        
        // Maps to store values by date for each metric
        var stepsMap: [String: Double] = [:]
        var distanceMap: [String: Double] = [:]
        var flightsMap: [String: Double] = [:]
        var activeEnergyMap: [String: Double] = [:]
        var exerciseMinutesMap: [String: Double] = [:]
        var standHoursMap: [String: Int] = [:]
        
        var errors: [Error] = []
        
        // === STEPS ===
        if let stepsType = HKObjectType.quantityType(forIdentifier: .stepCount) {
            group.enter()
            let predicate = HKQuery.predicateForSamples(withStart: startDate, end: endDate, options: [])
            let query = HKSampleQuery(sampleType: stepsType, predicate: predicate, limit: HKObjectQueryNoLimit, sortDescriptors: nil) { _, samples, error in
                defer { group.leave() }
                
                if let error = error {
                    lock.lock()
                    errors.append(error)
                    lock.unlock()
                    return
                }
                
                guard let quantitySamples = samples as? [HKQuantitySample] else { return }
                
                for sample in quantitySamples {
                    let dateComponents = calendar.dateComponents([.year, .month, .day], from: sample.startDate)
                    let dateString = String(format: "%04d-%02d-%02d", dateComponents.year!, dateComponents.month!, dateComponents.day!)
                    
                    let steps = sample.quantity.doubleValue(for: HKUnit.count())
                    lock.lock()
                    stepsMap[dateString] = (stepsMap[dateString] ?? 0) + steps
                    lock.unlock()
                }
            }
            healthStore.execute(query)
        }
        
        // === DISTANCE (Walking + Running) ===
        if let distanceType = HKObjectType.quantityType(forIdentifier: .distanceWalkingRunning) {
            group.enter()
            let predicate = HKQuery.predicateForSamples(withStart: startDate, end: endDate, options: [])
            let query = HKSampleQuery(sampleType: distanceType, predicate: predicate, limit: HKObjectQueryNoLimit, sortDescriptors: nil) { _, samples, error in
                defer { group.leave() }
                
                if let error = error {
                    lock.lock()
                    errors.append(error)
                    lock.unlock()
                    return
                }
                
                guard let quantitySamples = samples as? [HKQuantitySample] else { return }
                
                for sample in quantitySamples {
                    let dateComponents = calendar.dateComponents([.year, .month, .day], from: sample.startDate)
                    let dateString = String(format: "%04d-%02d-%02d", dateComponents.year!, dateComponents.month!, dateComponents.day!)
                    
                    // Convert to miles (HealthKit stores in meters)
                    let distanceMeters = sample.quantity.doubleValue(for: HKUnit.meter())
                    let distanceMiles = distanceMeters * 0.000621371
                    lock.lock()
                    distanceMap[dateString] = (distanceMap[dateString] ?? 0) + distanceMiles
                    lock.unlock()
                }
            }
            healthStore.execute(query)
        }
        
        // === FLIGHTS CLIMBED ===
        if let flightsType = HKObjectType.quantityType(forIdentifier: .flightsClimbed) {
            group.enter()
            let predicate = HKQuery.predicateForSamples(withStart: startDate, end: endDate, options: [])
            let query = HKSampleQuery(sampleType: flightsType, predicate: predicate, limit: HKObjectQueryNoLimit, sortDescriptors: nil) { _, samples, error in
                defer { group.leave() }
                
                if let error = error {
                    lock.lock()
                    errors.append(error)
                    lock.unlock()
                    return
                }
                
                guard let quantitySamples = samples as? [HKQuantitySample] else { return }
                
                for sample in quantitySamples {
                    let dateComponents = calendar.dateComponents([.year, .month, .day], from: sample.startDate)
                    let dateString = String(format: "%04d-%02d-%02d", dateComponents.year!, dateComponents.month!, dateComponents.day!)
                    
                    let flights = sample.quantity.doubleValue(for: HKUnit.count())
                    lock.lock()
                    flightsMap[dateString] = (flightsMap[dateString] ?? 0) + flights
                    lock.unlock()
                }
            }
            healthStore.execute(query)
        }
        
        // === ACTIVE ENERGY ===
        if let activeEnergyType = HKObjectType.quantityType(forIdentifier: .activeEnergyBurned) {
            group.enter()
            let predicate = HKQuery.predicateForSamples(withStart: startDate, end: endDate, options: [])
            let query = HKSampleQuery(sampleType: activeEnergyType, predicate: predicate, limit: HKObjectQueryNoLimit, sortDescriptors: nil) { _, samples, error in
                defer { group.leave() }
                
                if let error = error {
                    lock.lock()
                    errors.append(error)
                    lock.unlock()
                    return
                }
                
                guard let quantitySamples = samples as? [HKQuantitySample] else { return }
                
                for sample in quantitySamples {
                    let dateComponents = calendar.dateComponents([.year, .month, .day], from: sample.startDate)
                    let dateString = String(format: "%04d-%02d-%02d", dateComponents.year!, dateComponents.month!, dateComponents.day!)
                    
                    let calories = sample.quantity.doubleValue(for: HKUnit.kilocalorie())
                    lock.lock()
                    activeEnergyMap[dateString] = (activeEnergyMap[dateString] ?? 0) + calories
                    lock.unlock()
                }
            }
            healthStore.execute(query)
        }
        
        // === EXERCISE MINUTES ===
        if let exerciseType = HKObjectType.quantityType(forIdentifier: .appleExerciseTime) {
            group.enter()
            let predicate = HKQuery.predicateForSamples(withStart: startDate, end: endDate, options: [])
            let query = HKSampleQuery(sampleType: exerciseType, predicate: predicate, limit: HKObjectQueryNoLimit, sortDescriptors: nil) { _, samples, error in
                defer { group.leave() }
                
                if let error = error {
                    lock.lock()
                    errors.append(error)
                    lock.unlock()
                    return
                }
                
                guard let quantitySamples = samples as? [HKQuantitySample] else { return }
                
                for sample in quantitySamples {
                    let dateComponents = calendar.dateComponents([.year, .month, .day], from: sample.startDate)
                    let dateString = String(format: "%04d-%02d-%02d", dateComponents.year!, dateComponents.month!, dateComponents.day!)
                    
                    let minutes = sample.quantity.doubleValue(for: HKUnit.minute())
                    lock.lock()
                    exerciseMinutesMap[dateString] = (exerciseMinutesMap[dateString] ?? 0) + minutes
                    lock.unlock()
                }
            }
            healthStore.execute(query)
        }
        
        // === STAND HOURS ===
        if let standHourType = HKObjectType.categoryType(forIdentifier: .appleStandHour) {
            group.enter()
            let predicate = HKQuery.predicateForSamples(withStart: startDate, end: endDate, options: [])
            let query = HKSampleQuery(sampleType: standHourType, predicate: predicate, limit: HKObjectQueryNoLimit, sortDescriptors: nil) { _, samples, error in
                defer { group.leave() }
                
                if let error = error {
                    lock.lock()
                    errors.append(error)
                    lock.unlock()
                    return
                }
                
                guard let categorySamples = samples as? [HKCategorySample] else { return }
                
                for sample in categorySamples {
                    let dateComponents = calendar.dateComponents([.year, .month, .day], from: sample.startDate)
                    let dateString = String(format: "%04d-%02d-%02d", dateComponents.year!, dateComponents.month!, dateComponents.day!)
                    
                    // Value is HKCategoryValueAppleStandHour.stood (1) or .idle (0)
                    if sample.value == HKCategoryValueAppleStandHour.stood.rawValue {
                        lock.lock()
                        standHoursMap[dateString] = (standHoursMap[dateString] ?? 0) + 1
                        lock.unlock()
                    }
                }
            }
            healthStore.execute(query)
        }
        
        group.notify(queue: .main) {
            // Only fail if there are errors AND no data was collected
            // This allows partial data to be returned if some permissions are denied
            if !errors.isEmpty {
                // Check if any data was actually collected
                let hasData = !stepsMap.isEmpty || !distanceMap.isEmpty || !flightsMap.isEmpty || 
                              !activeEnergyMap.isEmpty || !exerciseMinutesMap.isEmpty || !standHoursMap.isEmpty
                
                if !hasData {
                    // No data at all, return the error
                    completion(.failure(errors.first!))
                    return
                }
                // If we have some data, continue and return what we have
            }
            
            // Collect all unique dates that have any activity data
            var allDates = Set<String>()
            allDates.formUnion(stepsMap.keys)
            allDates.formUnion(distanceMap.keys)
            allDates.formUnion(flightsMap.keys)
            allDates.formUnion(activeEnergyMap.keys)
            allDates.formUnion(exerciseMinutesMap.keys)
            allDates.formUnion(standHoursMap.keys)
            
            // Filter dates to only include those within the requested local date range
            // This prevents returning data from dates outside the user's intended range
            let filteredDates = allDates.filter { date in
                return date >= localStartDateString && date <= localEndDateString
            }
            
            // Create activity data array matching the reference format
            let activityData: [[String: Any]] = filteredDates.sorted().compactMap { date in
                var result: [String: Any] = ["date": date]
                
                // Add each metric if available, with proper rounding
                if let steps = stepsMap[date] {
                    result["steps"] = Int(round(steps))
                }
                
                if let distance = distanceMap[date] {
                    result["distance"] = round(distance * 100) / 100
                }
                
                if let flights = flightsMap[date] {
                    result["flightsClimbed"] = Int(round(flights))
                }
                
                if let activeEnergy = activeEnergyMap[date] {
                    result["activeEnergy"] = Int(round(activeEnergy))
                }
                
                if let exerciseMinutes = exerciseMinutesMap[date] {
                    result["exerciseMinutes"] = Int(round(exerciseMinutes))
                }
                
                if let standHours = standHoursMap[date] {
                    result["standHours"] = standHours
                }
                
                return result
            }
            
            completion(.success(activityData))
        }
    }
    
    // MARK: - Heart Data Processing
    
    private func processHeartData(startDate: Date, endDate: Date, completion: @escaping (Result<[[String: Any]], Error>) -> Void) {
        let calendar = Calendar.current
        let group = DispatchGroup()
        let lock = NSLock()
        
        // Calculate the local date range that corresponds to the input UTC date range
        let startDateComponents = calendar.dateComponents([.year, .month, .day], from: startDate)
        let endDateComponents = calendar.dateComponents([.year, .month, .day], from: endDate)
        let localStartDateString = String(format: "%04d-%02d-%02d", startDateComponents.year!, startDateComponents.month!, startDateComponents.day!)
        let localEndDateString = String(format: "%04d-%02d-%02d", endDateComponents.year!, endDateComponents.month!, endDateComponents.day!)
        
        // Maps to store values by date for each metric
        struct HeartRateStats {
            var sum: Double = 0
            var count: Int = 0
            var min: Double = 999
            var max: Double = 0
        }
        
        var heartRateMap: [String: HeartRateStats] = [:]
        var restingHRMap: [String: Double] = [:]
        var vo2MaxMap: [String: Double] = [:]
        var hrvMap: [String: Double] = [:]
        var spo2Map: [String: [Double]] = [:]
        var respirationRateMap: [String: [Double]] = [:]
        
        var errors: [Error] = []
        
        // === HEART RATE ===
        if let heartRateType = HKObjectType.quantityType(forIdentifier: .heartRate) {
            group.enter()
            let predicate = HKQuery.predicateForSamples(withStart: startDate, end: endDate, options: [])
            let query = HKSampleQuery(sampleType: heartRateType, predicate: predicate, limit: HKObjectQueryNoLimit, sortDescriptors: nil) { _, samples, error in
                defer { group.leave() }
                
                if let error = error {
                    lock.lock()
                    errors.append(error)
                    lock.unlock()
                    return
                }
                
                guard let quantitySamples = samples as? [HKQuantitySample] else { return }
                
                for sample in quantitySamples {
                    let dateComponents = calendar.dateComponents([.year, .month, .day], from: sample.startDate)
                    let dateString = String(format: "%04d-%02d-%02d", dateComponents.year!, dateComponents.month!, dateComponents.day!)
                    
                    let bpm = sample.quantity.doubleValue(for: HKUnit.count().unitDivided(by: HKUnit.minute()))
                    lock.lock()
                    var stats = heartRateMap[dateString] ?? HeartRateStats()
                    stats.sum += bpm
                    stats.count += 1
                    stats.min = min(stats.min, bpm)
                    stats.max = max(stats.max, bpm)
                    heartRateMap[dateString] = stats
                    lock.unlock()
                }
            }
            healthStore.execute(query)
        }
        
        // === RESTING HEART RATE ===
        if let restingHRType = HKObjectType.quantityType(forIdentifier: .restingHeartRate) {
            group.enter()
            let predicate = HKQuery.predicateForSamples(withStart: startDate, end: endDate, options: [])
            let query = HKSampleQuery(sampleType: restingHRType, predicate: predicate, limit: HKObjectQueryNoLimit, sortDescriptors: nil) { _, samples, error in
                defer { group.leave() }
                
                if let error = error {
                    lock.lock()
                    errors.append(error)
                    lock.unlock()
                    return
                }
                
                guard let quantitySamples = samples as? [HKQuantitySample] else { return }
                
                for sample in quantitySamples {
                    let dateComponents = calendar.dateComponents([.year, .month, .day], from: sample.startDate)
                    let dateString = String(format: "%04d-%02d-%02d", dateComponents.year!, dateComponents.month!, dateComponents.day!)
                    
                    let bpm = sample.quantity.doubleValue(for: HKUnit.count().unitDivided(by: HKUnit.minute()))
                    lock.lock()
                    restingHRMap[dateString] = bpm // Take last measurement
                    lock.unlock()
                }
            }
            healthStore.execute(query)
        }
        
        // === VO2 MAX ===
        if let vo2MaxType = HKObjectType.quantityType(forIdentifier: .vo2Max) {
            group.enter()
            let predicate = HKQuery.predicateForSamples(withStart: startDate, end: endDate, options: [])
            let query = HKSampleQuery(sampleType: vo2MaxType, predicate: predicate, limit: HKObjectQueryNoLimit, sortDescriptors: nil) { _, samples, error in
                defer { group.leave() }
                
                if let error = error {
                    lock.lock()
                    errors.append(error)
                    lock.unlock()
                    return
                }
                
                guard let quantitySamples = samples as? [HKQuantitySample] else { return }
                
                for sample in quantitySamples {
                    let dateComponents = calendar.dateComponents([.year, .month, .day], from: sample.startDate)
                    let dateString = String(format: "%04d-%02d-%02d", dateComponents.year!, dateComponents.month!, dateComponents.day!)
                    
                    let vo2 = sample.quantity.doubleValue(for: HKUnit.literUnit(with: .milli).unitDivided(by: HKUnit.gramUnit(with: .kilo).unitMultiplied(by: HKUnit.minute())))
                    lock.lock()
                    vo2MaxMap[dateString] = vo2 // Take last measurement
                    lock.unlock()
                }
            }
            healthStore.execute(query)
        }
        
        // === HRV (Heart Rate Variability SDNN) ===
        if let hrvType = HKObjectType.quantityType(forIdentifier: .heartRateVariabilitySDNN) {
            group.enter()
            let predicate = HKQuery.predicateForSamples(withStart: startDate, end: endDate, options: [])
            let query = HKSampleQuery(sampleType: hrvType, predicate: predicate, limit: HKObjectQueryNoLimit, sortDescriptors: nil) { _, samples, error in
                defer { group.leave() }
                
                if let error = error {
                    lock.lock()
                    errors.append(error)
                    lock.unlock()
                    return
                }
                
                guard let quantitySamples = samples as? [HKQuantitySample] else { return }
                
                for sample in quantitySamples {
                    let dateComponents = calendar.dateComponents([.year, .month, .day], from: sample.startDate)
                    let dateString = String(format: "%04d-%02d-%02d", dateComponents.year!, dateComponents.month!, dateComponents.day!)
                    
                    let hrv = sample.quantity.doubleValue(for: HKUnit.secondUnit(with: .milli))
                    lock.lock()
                    hrvMap[dateString] = hrv // Take last measurement
                    lock.unlock()
                }
            }
            healthStore.execute(query)
        }
        
        // === SPO2 (Blood Oxygen Saturation) ===
        if let spo2Type = HKObjectType.quantityType(forIdentifier: .oxygenSaturation) {
            group.enter()
            let predicate = HKQuery.predicateForSamples(withStart: startDate, end: endDate, options: [])
            let query = HKSampleQuery(sampleType: spo2Type, predicate: predicate, limit: HKObjectQueryNoLimit, sortDescriptors: nil) { _, samples, error in
                defer { group.leave() }
                
                if let error = error {
                    lock.lock()
                    errors.append(error)
                    lock.unlock()
                    return
                }
                
                guard let quantitySamples = samples as? [HKQuantitySample] else { return }
                
                for sample in quantitySamples {
                    let dateComponents = calendar.dateComponents([.year, .month, .day], from: sample.startDate)
                    let dateString = String(format: "%04d-%02d-%02d", dateComponents.year!, dateComponents.month!, dateComponents.day!)
                    
                    // HealthKit stores as decimal (0.96), convert to percentage (96)
                    let value = sample.quantity.doubleValue(for: HKUnit.percent()) * 100
                    lock.lock()
                    if spo2Map[dateString] == nil {
                        spo2Map[dateString] = []
                    }
                    spo2Map[dateString]?.append(value)
                    lock.unlock()
                }
            }
            healthStore.execute(query)
        }
        
        // === RESPIRATION RATE ===
        if let respirationRateType = HKObjectType.quantityType(forIdentifier: .respiratoryRate) {
            group.enter()
            let predicate = HKQuery.predicateForSamples(withStart: startDate, end: endDate, options: [])
            let query = HKSampleQuery(sampleType: respirationRateType, predicate: predicate, limit: HKObjectQueryNoLimit, sortDescriptors: nil) { _, samples, error in
                defer { group.leave() }
                
                if let error = error {
                    lock.lock()
                    errors.append(error)
                    lock.unlock()
                    return
                }
                
                guard let quantitySamples = samples as? [HKQuantitySample] else { return }
                
                for sample in quantitySamples {
                    let dateComponents = calendar.dateComponents([.year, .month, .day], from: sample.startDate)
                    let dateString = String(format: "%04d-%02d-%02d", dateComponents.year!, dateComponents.month!, dateComponents.day!)
                    
                    let breathsPerMin = sample.quantity.doubleValue(for: HKUnit.count().unitDivided(by: HKUnit.minute()))
                    lock.lock()
                    if respirationRateMap[dateString] == nil {
                        respirationRateMap[dateString] = []
                    }
                    respirationRateMap[dateString]?.append(breathsPerMin)
                    lock.unlock()
                }
            }
            healthStore.execute(query)
        }
        
        group.notify(queue: .main) {
            // Only fail if there are errors AND no data was collected
            // This allows partial data to be returned if some permissions are denied
            if !errors.isEmpty {
                // Check if any data was actually collected
                let hasData = !heartRateMap.isEmpty || !restingHRMap.isEmpty || !vo2MaxMap.isEmpty || 
                              !hrvMap.isEmpty || !spo2Map.isEmpty || !respirationRateMap.isEmpty
                
                if !hasData {
                    // No data at all, return the error
                    completion(.failure(errors.first!))
                    return
                }
                // If we have some data, continue and return what we have
            }
            
            // Collect all unique dates that have any heart data
            var allDates = Set<String>()
            allDates.formUnion(heartRateMap.keys)
            allDates.formUnion(restingHRMap.keys)
            allDates.formUnion(vo2MaxMap.keys)
            allDates.formUnion(hrvMap.keys)
            allDates.formUnion(spo2Map.keys)
            allDates.formUnion(respirationRateMap.keys)
            
            // Filter dates to only include those within the requested local date range
            let filteredDates = allDates.filter { date in
                return date >= localStartDateString && date <= localEndDateString
            }
            
            // Create heart data array matching the TypeScript format
            let heartData: [[String: Any]] = filteredDates.sorted().compactMap { date in
                var result: [String: Any] = ["date": date]
                
                // Heart Rate (avg, min, max, count)
                if let stats = heartRateMap[date] {
                    result["avgBpm"] = Int(round(stats.sum / Double(stats.count)))
                    result["minBpm"] = Int(round(stats.min))
                    result["maxBpm"] = Int(round(stats.max))
                    result["heartRateMeasurements"] = stats.count
                }
                
                // Resting Heart Rate
                if let restingBpm = restingHRMap[date] {
                    result["restingBpm"] = Int(round(restingBpm))
                }
                
                // VO2 Max (rounded to 1 decimal)
                if let vo2 = vo2MaxMap[date] {
                    result["vo2Max"] = round(vo2 * 10) / 10
                }
                
                // HRV (rounded to 3 decimals)
                if let hrv = hrvMap[date] {
                    result["hrv"] = round(hrv * 1000) / 1000
                }
                
                // SpO2 (average)
                if let readings = spo2Map[date], !readings.isEmpty {
                    let average = readings.reduce(0.0, +) / Double(readings.count)
                    result["spo2"] = Int(round(average))
                }
                
                // Respiration Rate (average, rounded to 1 decimal)
                if let readings = respirationRateMap[date], !readings.isEmpty {
                    let average = readings.reduce(0.0, +) / Double(readings.count)
                    result["respirationRate"] = round(average * 10) / 10
                }
                
                return result
            }
            
            completion(.success(heartData))
        }
    }
    
    // MARK: - Workout Data Processing
    
    private func processWorkoutData(startDate: Date, endDate: Date, limit: Int?, ascending: Bool, completion: @escaping (Result<[[String: Any]], Error>) -> Void) {
        let workoutType = HKObjectType.workoutType()
        let predicate = HKQuery.predicateForSamples(withStart: startDate, end: endDate, options: [])
        let sortDescriptor = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: ascending)
        let queryLimit = limit ?? HKObjectQueryNoLimit
        
        let query = HKSampleQuery(sampleType: workoutType, predicate: predicate, limit: queryLimit, sortDescriptors: [sortDescriptor]) { [weak self] _, samples, error in
            guard let self = self else { return }
            
            if let error = error {
                completion(.failure(error))
                return
            }
            
            guard let workouts = samples as? [HKWorkout], !workouts.isEmpty else {
                completion(.success([]))
                return
            }
            
            var workoutData: [[String: Any]] = []
            let group = DispatchGroup()
            let lock = NSLock()
            
            for workout in workouts {
                group.enter()
                
                // Extract basic workout info
                let dateFormatter = ISO8601DateFormatter()
                dateFormatter.formatOptions = [.withFullDate]
                let date = dateFormatter.string(from: workout.startDate)
                
                // Get workout type (remove "HKWorkoutActivityType" prefix to match XML format)
                let activityTypeString = self.workoutActivityTypeString(for: workout.workoutActivityType)
                
                // Duration in minutes (matching XML parser logic)
                let durationInMinutes = Int(round(workout.duration / 60.0))
                
                // Distance in miles (if available)
                var distance: Double?
                if let totalDistance = workout.totalDistance {
                    let distanceInMeters = totalDistance.doubleValue(for: HKUnit.meter())
                    distance = distanceInMeters * 0.000621371 // meters to miles
                }
                
                // Calories (if available)
                var calories: Int?
                if let totalEnergy = workout.totalEnergyBurned {
                    let caloriesValue = totalEnergy.doubleValue(for: HKUnit.kilocalorie())
                    calories = Int(round(caloriesValue))
                }
                
                // Source name
                let source = workout.sourceRevision.source.name
                
                // Query for heart rate statistics during this workout
                self.queryWorkoutHeartRateStatistics(for: workout) { avgHR, maxHR in
                    // Query for heart rate zones
                    self.queryWorkoutHeartRateZones(for: workout) { zones in
                        lock.lock()
                        
                        var workoutDict: [String: Any] = [
                            "date": date,
                            "type": activityTypeString,
                            "duration": durationInMinutes,
                            "source": source
                        ]
                        
                        if let distance = distance {
                            workoutDict["distance"] = round(distance * 100) / 100 // 2 decimal places
                        }
                        
                        if let calories = calories {
                            workoutDict["calories"] = calories
                        }
                        
                        if let avgHR = avgHR {
                            workoutDict["avgHeartRate"] = avgHR
                        }
                        
                        if let maxHR = maxHR {
                            workoutDict["maxHeartRate"] = maxHR
                        }
                        
                        if !zones.isEmpty {
                            workoutDict["zones"] = zones
                        }
                        
                        workoutData.append(workoutDict)
                        lock.unlock()
                        
                        group.leave()
                    }
                }
            }
            
            group.notify(queue: .main) {
                // Sort by date if needed
                let sortedData = workoutData.sorted { dict1, dict2 in
                    guard let date1 = dict1["date"] as? String,
                          let date2 = dict2["date"] as? String else {
                        return false
                    }
                    return ascending ? date1 < date2 : date1 > date2
                }
                
                completion(.success(sortedData))
            }
        }
        
        healthStore.execute(query)
    }
    
    private func workoutActivityTypeString(for type: HKWorkoutActivityType) -> String {
        // Return the activity type name without the "HKWorkoutActivityType" prefix
        // to match the XML export format
        switch type {
        case .running: return "Running"
        case .cycling: return "Cycling"
        case .walking: return "Walking"
        case .swimming: return "Swimming"
        case .yoga: return "Yoga"
        case .functionalStrengthTraining: return "FunctionalStrengthTraining"
        case .traditionalStrengthTraining: return "TraditionalStrengthTraining"
        case .elliptical: return "Elliptical"
        case .rowing: return "Rowing"
        case .hiking: return "Hiking"
        case .highIntensityIntervalTraining: return "HighIntensityIntervalTraining"
        case .dance: return "Dance"
        case .basketball: return "Basketball"
        case .soccer: return "Soccer"
        case .tennis: return "Tennis"
        case .golf: return "Golf"
        case .stairClimbing: return "StairClimbing"
        case .stepTraining: return "StepTraining"
        case .kickboxing: return "Kickboxing"
        case .pilates: return "Pilates"
        case .boxing: return "Boxing"
        case .taiChi: return "TaiChi"
        case .crossTraining: return "CrossTraining"
        case .mindAndBody: return "MindAndBody"
        case .coreTraining: return "CoreTraining"
        case .flexibility: return "Flexibility"
        case .cooldown: return "Cooldown"
        case .wheelchairWalkPace: return "WheelchairWalkPace"
        case .wheelchairRunPace: return "WheelchairRunPace"
        case .other: return "Other"
        default:
            // For any unknown or new types
            return "Other"
        }
    }
    
    private func queryWorkoutHeartRateStatistics(for workout: HKWorkout, completion: @escaping (Int?, Int?) -> Void) {
        guard let heartRateType = HKObjectType.quantityType(forIdentifier: .heartRate) else {
            completion(nil, nil)
            return
        }
        
        let predicate = HKQuery.predicateForSamples(withStart: workout.startDate, end: workout.endDate, options: .strictStartDate)
        
        let query = HKStatisticsQuery(quantityType: heartRateType, quantitySamplePredicate: predicate, options: [.discreteAverage, .discreteMax]) { _, statistics, error in
            if error != nil {
                completion(nil, nil)
                return
            }
            
            var avgHR: Int?
            var maxHR: Int?
            
            if let avgQuantity = statistics?.averageQuantity() {
                let bpm = avgQuantity.doubleValue(for: HKUnit.count().unitDivided(by: HKUnit.minute()))
                avgHR = Int(round(bpm))
            }
            
            if let maxQuantity = statistics?.maximumQuantity() {
                let bpm = maxQuantity.doubleValue(for: HKUnit.count().unitDivided(by: HKUnit.minute()))
                maxHR = Int(round(bpm))
            }
            
            completion(avgHR, maxHR)
        }
        
        healthStore.execute(query)
    }
    
    private func queryWorkoutHeartRateZones(for workout: HKWorkout, completion: @escaping ([String: Int]) -> Void) {
        // Check if heart rate zone data is available in workout metadata
        var zones: [String: Int] = [:]
        
        if let metadata = workout.metadata {
            // Look for heart rate zone keys in metadata
            // Apple Health stores zones as HKMetadataKeyHeartRateEventThreshold or custom keys
            for (key, value) in metadata {
                if key.contains("Zone") || key.contains("zone") {
                    // Try to extract zone number
                    if let zoneMatch = key.range(of: #"\d+"#, options: .regularExpression),
                       let zoneNum = Int(key[zoneMatch]) {
                        // Value might be in seconds, convert to minutes
                        if let seconds = value as? Double {
                            let minutes = Int(round(seconds / 60.0))
                            zones["zone\(zoneNum)"] = minutes
                        } else if let minutes = value as? Int {
                            zones["zone\(zoneNum)"] = minutes
                        }
                    }
                }
            }
        }
        
        // If no zones found in metadata, try querying heart rate samples to calculate zones
        if zones.isEmpty {
            calculateHeartRateZones(for: workout) { calculatedZones in
                completion(calculatedZones)
            }
        } else {
            completion(zones)
        }
    }
    
    private func calculateHeartRateZones(for workout: HKWorkout, completion: @escaping ([String: Int]) -> Void) {
        guard let heartRateType = HKObjectType.quantityType(forIdentifier: .heartRate) else {
            completion([:])
            return
        }
        
        let predicate = HKQuery.predicateForSamples(withStart: workout.startDate, end: workout.endDate, options: .strictStartDate)
        let sortDescriptor = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)
        
        let query = HKSampleQuery(sampleType: heartRateType, predicate: predicate, limit: HKObjectQueryNoLimit, sortDescriptors: [sortDescriptor]) { _, samples, error in
            if error != nil || samples == nil {
                completion([:])
                return
            }
            
            guard let heartRateSamples = samples as? [HKQuantitySample], !heartRateSamples.isEmpty else {
                completion([:])
                return
            }
            
            // Calculate zones based on standard heart rate zone definitions
            // Zone 1: 50-60% max HR
            // Zone 2: 60-70% max HR
            // Zone 3: 70-80% max HR
            // Zone 4: 80-90% max HR
            // Zone 5: 90-100% max HR
            
            // Estimate max HR (220 - age), or use 180 as a reasonable default
            let estimatedMaxHR = 180.0
            
            var zoneMinutes: [Int: TimeInterval] = [1: 0, 2: 0, 3: 0, 4: 0, 5: 0]
            
            for i in 0..<heartRateSamples.count {
                let sample = heartRateSamples[i]
                let bpm = sample.quantity.doubleValue(for: HKUnit.count().unitDivided(by: HKUnit.minute()))
                let percentMax = (bpm / estimatedMaxHR) * 100
                
                // Determine zone
                let zone: Int
                if percentMax < 60 {
                    zone = 1
                } else if percentMax < 70 {
                    zone = 2
                } else if percentMax < 80 {
                    zone = 3
                } else if percentMax < 90 {
                    zone = 4
                } else {
                    zone = 5
                }
                
                // Calculate time in this zone (use interval to next sample or default to 5 seconds)
                let duration: TimeInterval
                if i < heartRateSamples.count - 1 {
                    duration = heartRateSamples[i + 1].startDate.timeIntervalSince(sample.startDate)
                } else {
                    duration = 5.0 // Default 5 seconds for last sample
                }
                
                zoneMinutes[zone, default: 0] += duration
            }
            
            // Convert seconds to minutes and filter out zones with 0 minutes
            var zones: [String: Int] = [:]
            for (zone, seconds) in zoneMinutes {
                let minutes = Int(round(seconds / 60.0))
                if minutes > 0 {
                    zones["zone\(zone)"] = minutes
                }
            }
            
            completion(zones)
        }
        
        healthStore.execute(query)
    }
}
