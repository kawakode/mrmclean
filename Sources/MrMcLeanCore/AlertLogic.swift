import Foundation

public enum AlertLogic {
    public struct Evaluation: Sendable {
        public var shouldNotify: Bool
        public var fraction: Double
    }

    /// Decide whether a category currently warrants a notification.
    public static func evaluate(
        sizeBytes: Int64,
        diskBytes: Int64,
        category: CategoryConfig,
        global: AppConfig,
        now: Date = Date()
    ) -> Evaluation {
        guard diskBytes > 0 else { return Evaluation(shouldNotify: false, fraction: 0) }
        let fraction = Double(sizeBytes) / Double(diskBytes)

        guard global.alertsEnabled, category.alertEnabled else {
            return Evaluation(shouldNotify: false, fraction: fraction)
        }
        guard fraction * 100 >= category.thresholdPercent else {
            return Evaluation(shouldNotify: false, fraction: fraction)
        }

        guard let last = category.lastAlertDate else {
            return Evaluation(shouldNotify: true, fraction: fraction)
        }

        let hoursSince = now.timeIntervalSince(last) / 3600
        if hoursSince >= global.cooldownHours {
            return Evaluation(shouldNotify: true, fraction: fraction)
        }

        guard category.lastAlertBytes > 0 else {
            return Evaluation(shouldNotify: false, fraction: fraction)
        }
        let growthPercent = Double(sizeBytes - category.lastAlertBytes)
            / Double(category.lastAlertBytes) * 100
        return Evaluation(shouldNotify: growthPercent >= global.reAlertGrowthPercent,
                          fraction: fraction)
    }
}
