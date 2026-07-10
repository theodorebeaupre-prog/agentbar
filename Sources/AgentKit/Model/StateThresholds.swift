import Foundation

public struct StateThresholds: Sendable {
    public var active: TimeInterval = 30
    public var settle: TimeInterval = 5
    public var idle: TimeInterval = 1800
    public var ended: TimeInterval = 86400
    public init() {}
}
