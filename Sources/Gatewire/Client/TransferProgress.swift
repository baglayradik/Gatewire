internal import Foundation

/// Прогресс отправки или получения данных.
public struct TransferProgress: Sendable, Equatable {
    /// Количество переданных байтов.
    public let completedBytes: Int64

    /// Общий размер в байтах или `nil`, если он неизвестен.
    public let totalBytes: Int64?

    /// Доля выполнения от 0 до 1. Если общий размер неизвестен — 0.
    public var fractionCompleted: Double {
        guard let totalBytes, totalBytes > 0 else { return 0 }

        return min(Double(completedBytes) / Double(totalBytes), 1)
    }

    /// Создаёт прогресс.
    public init(completedBytes: Int64, totalBytes: Int64?) {
        self.completedBytes = completedBytes
        self.totalBytes = totalBytes
    }

    init(_ progress: Progress) {
        self.init(
            completedBytes: progress.completedUnitCount,
            totalBytes: progress.totalUnitCount > 0 ? progress.totalUnitCount : nil
        )
    }
}

/// Обработчик прогресса передачи. Вызывается на главном потоке.
public typealias TransferProgressHandler = @MainActor @Sendable (TransferProgress) -> Void
