import Foundation

struct CarouselMotion {
    enum Phase { case idle, dragging, settling }
    private(set) var position: Double
    private(set) var velocity = 0.0
    private(set) var target: Int
    private(set) var phase: Phase = .idle
    let count: Int

    init(index: Int, count: Int) {
        self.count = count
        position = Double(index)
        target = index
    }

    mutating func reset(to index: Int) {
        target = index
        position = Double(target)
        velocity = 0
        phase = .idle
    }

    mutating func beginDrag() {
        phase = .dragging
        velocity = 0
    }

    mutating func drag(by delta: Double, elapsed: Double) {
        guard phase == .dragging else { return }
        position += delta
        let measured = delta / max(1.0 / 240, elapsed)
        let sameDirection = measured * velocity > 0 && elapsed < 0.1
        velocity = min(7, max(-7, sameDirection ? velocity * 0.25 + measured * 0.75 : measured))
    }

    mutating func release(projectVelocity: Bool, reduceMotion: Bool) {
        if !projectVelocity { velocity = 0 }
        let projection = reduceMotion ? 0 : min(0.65, max(-0.65, velocity * 0.16))
        settle(to: Int((position + projection).rounded()), reduceMotion: reduceMotion)
    }

    mutating func settle(to index: Int, reduceMotion: Bool) {
        target = index
        if reduceMotion { reset(to: target) }
        else { phase = .settling }
    }

    mutating func step(by delta: Int, reduceMotion: Bool) {
        let base = phase == .settling ? target : Int(position.rounded())
        settle(to: base + delta, reduceMotion: reduceMotion)
    }

    mutating func advance(by elapsed: Double) {
        guard phase == .settling, elapsed > 0 else { return }
        // Exact critically damped spring, so a retarget preserves position and velocity.
        let frequency = 18.0
        let displacement = position - Double(target)
        let coefficient = velocity + frequency * displacement
        let decay = exp(-frequency * elapsed)
        position = Double(target) + (displacement + coefficient * elapsed) * decay
        velocity = (velocity - frequency * coefficient * elapsed) * decay
        if abs(position - Double(target)) < 0.0008 && abs(velocity) < 0.012 {
            reset(to: target)
        }
    }

    func artworkIndex(at slot: Int) -> Int { ((slot % count) + count) % count }

    var selectedIndex: Int { artworkIndex(at: target) }

    func nearestSlot(for index: Int) -> Int {
        index + Int(((position - Double(index)) / Double(count)).rounded()) * count
    }

    mutating func select(index: Int, reduceMotion: Bool) {
        settle(to: nearestSlot(for: index), reduceMotion: reduceMotion)
    }
}
