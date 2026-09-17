public struct ZoomLevel: Equatable, Sendable {
    public private(set) var percent: Int
    public init(percent: Int = 100) { self.percent = min(175, max(75, percent)) }
    public var scale: Double { Double(percent) / 100 }
    public var canIncrease: Bool { percent < 175 }
    public var canDecrease: Bool { percent > 75 }
    public mutating func increase() { percent = min(175, percent + 25) }
    public mutating func decrease() { percent = max(75, percent - 25) }
    public mutating func reset() { percent = 100 }
}
