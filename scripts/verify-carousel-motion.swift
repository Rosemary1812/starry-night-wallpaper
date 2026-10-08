import Foundation

@main
struct VerifyCarouselMotion {
    static func main() {
        var checks = 0
        func require(_ condition: Bool, _ message: String) {
            guard condition else { fputs("FAIL: \(message)\n", stderr); exit(1) }
            checks += 1
        }
        func finish(_ motion: inout CarouselMotion, rate: Double = 120) {
            for _ in 0..<240 { motion.advance(by: 1 / rate) }
        }

        var motion = CarouselMotion(index: 3, count: 12)
        motion.beginDrag()
        motion.drag(by: 0.2, elapsed: 0.05)
        motion.release(projectVelocity: true, reduceMotion: false)
        require(motion.target == 4, "A short fast flick should advance")
        require(abs(motion.position - 3.2) < 0.00001, "Release must preserve the current position")
        motion.advance(by: 0.08)
        let beforeReversal = motion.position
        let velocityBeforeReversal = motion.velocity
        motion.step(by: -1, reduceMotion: false)
        require(motion.position == beforeReversal && motion.velocity == velocityBeforeReversal,
            "Retargeting must preserve position and velocity")
        finish(&motion)
        require(motion.phase == .idle && motion.position == 3, "Reversal must settle at the new target")

        motion.step(by: 1, reduceMotion: false)
        motion.advance(by: 0.1)
        let grabbedPosition = motion.position
        motion.beginDrag()
        require(motion.position == grabbedPosition, "Grabbing a moving card must not jump")
        motion.drag(by: -0.12, elapsed: 0.02)
        motion.release(projectVelocity: true, reduceMotion: false)
        finish(&motion)
        require(motion.phase == .idle, "An interrupted drag must settle")

        motion.reset(to: 0)
        for _ in 0..<40 {
            motion.step(by: 1, reduceMotion: false)
            motion.advance(by: 0.01)
        }
        require(motion.target == 40 && motion.selectedIndex == 4 && motion.position.isFinite, "Repeated input must continue through multiple loops")
        finish(&motion)
        for _ in 0..<40 {
            motion.step(by: -1, reduceMotion: false)
            motion.advance(by: 0.01)
        }
        finish(&motion)
        require(motion.position == 0, "Repeated reverse input must reach the first card")

        motion.beginDrag()
        motion.drag(by: -2, elapsed: 0.05)
        motion.release(projectVelocity: true, reduceMotion: false)
        finish(&motion)
        require(motion.target == -3 && motion.selectedIndex == 9, "Dragging backwards must wrap into the previous cycle")
        motion.step(by: 1, reduceMotion: true)
        require(motion.phase == .idle && motion.selectedIndex == 10 && motion.velocity == 0,
            "Reduced motion must select without residual sliding")

        motion.reset(to: 5)
        motion.beginDrag()
        motion.drag(by: 0.16, elapsed: 0.01)
        motion.release(projectVelocity: false, reduceMotion: false)
        require(motion.target == 5, "Holding before release must discard stale flick velocity")

        motion.reset(to: 11)
        motion.step(by: 1, reduceMotion: false)
        require(motion.target == 12 && motion.selectedIndex == 0, "Last-to-first must travel one slot")
        finish(&motion)
        require(motion.position == 12, "The seam must settle without travelling backwards through the catalog")
        motion.select(index: 11, reduceMotion: false)
        require(motion.target == 11, "Thumbnail selection must use the nearest cyclic copy")
        finish(&motion)
        motion.reset(to: 0)
        motion.step(by: -1, reduceMotion: false)
        require(motion.target == -1 && motion.selectedIndex == 11, "First-to-last must travel one slot backwards")
        finish(&motion)
        require(motion.artworkIndex(at: -25) == 11, "Negative cycle indices must resolve to valid artworks")

        var results: [Double] = []
        for rate in [30.0, 60.0, 120.0] {
            var sample = CarouselMotion(index: 2, count: 12)
            sample.step(by: 1, reduceMotion: false)
            var previous = sample.position
            for _ in 0..<Int(rate * 0.3) {
                sample.advance(by: 1 / rate)
                require(sample.position >= previous && sample.position <= 3, "Resting spring must not visibly bounce")
                previous = sample.position
            }
            results.append(sample.position)
        }
        require(results.max()! - results.min()! < 1e-10, "Motion must be frame-rate independent")
        print("PASS: \(checks) motion assertions; flick, retarget, interruption, infinite wrapping, reduced motion, 30/60/120 Hz")
    }
}
