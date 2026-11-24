import Foundation

/// Events the post-boat can make. All of its instruments are synthesized locally.
enum HarborCue: CaseIterable, Sendable {
    case move, wait, blocked, stamp, rewind, undo, delivered, select, bell, ending
}

struct HarborSamples {
    static let rate = 24_000
    var left: [Float]
    var right: [Float]

    init(seconds: Double) {
        let count = Int((seconds * Double(Self.rate)).rounded())
        left = [Float](repeating: 0, count: count)
        right = [Float](repeating: 0, count: count)
    }
}

private struct HarborNoise {
    var state: UInt64

    mutating func next() -> Double {
        state ^= state << 13
        state ^= state >> 7
        state ^= state << 17
        return Double(state >> 40) / 8_388_608 - 1
    }
}

/// An instrument bench for a small quay: damped wood, rolled bronze, wind and reeds.
private struct QuayInstruments {
    static let rate = Double(HarborSamples.rate)
    static let turn = 2 * Double.pi
    var samples: HarborSamples
    var noise: HarborNoise

    init(_ length: Double, seed: UInt64) {
        samples = HarborSamples(seconds: length)
        noise = HarborNoise(state: max(1, seed))
    }

    /// Equal-power panning keeps the instrument's perceived strength stable at the edges.
    static func pan(_ position: Double) -> (Float, Float) {
        let angle = (max(-1, min(1, position)) + 1) * Double.pi * 0.25
        return (Float(cos(angle)), Float(sin(angle)))
    }

    mutating func ring(at time: Double, hz: Double, gain: Double, attack: Double,
                       decay: Double, length: Double, pan: Double, bend: Double = 0) {
        let first = Int(time * Self.rate)
        let last = min(samples.left.count, first + Int(length * Self.rate))
        guard last > first else { return }
        let stereo = Self.pan(pan)
        let step = Self.turn * hz / Self.rate
        let release = exp(-1 / (decay * Self.rate))
        let settle = exp(-1 / (0.045 * Self.rate))
        let attackFrames = max(1, attack * Self.rate)
        let tailFrames = max(1, min(0.055 * Self.rate, Double(last - first) / 8))
        var pitchOffset = Self.turn * bend / Self.rate
        var phase = 0.0
        var level = gain
        for i in first..<last {
            let a = min(1, Double(i - first) / attackFrames)
            let tail = min(1, Double(last - 1 - i) / tailFrames)
            let value = Float(sin(phase) * level * a * (2 - a) * tail)
            samples.left[i] += value * stereo.0
            samples.right[i] += value * stereo.1
            phase += step + pitchOffset
            pitchOffset *= settle
            level *= release
        }
    }

    /// Two lowpasses form a broad, soft band of air or water around the resonances.
    mutating func brush(at time: Double, length: Double, gain: Double, attack: Double,
                        decay: Double, lower: Double, upper: Double, pan: Double) {
        let first = Int(time * Self.rate)
        let last = min(samples.left.count, first + Int(length * Self.rate))
        guard last > first else { return }
        let stereo = Self.pan(pan)
        let lowStep = 1 - exp(-Self.turn * lower / Self.rate)
        let highStep = 1 - exp(-Self.turn * upper / Self.rate)
        let release = exp(-1 / (decay * Self.rate))
        let attackFrames = max(1, attack * Self.rate)
        let tailFrames = max(1, min(0.045 * Self.rate, Double(last - first) / 6))
        var body = 0.0, edge = 0.0, level = gain
        for i in first..<last {
            let raw = noise.next()
            body += lowStep * (raw - body)
            edge += highStep * (raw - edge)
            let a = min(1, Double(i - first) / attackFrames)
            let tail = min(1, Double(last - 1 - i) / tailFrames)
            let value = Float((edge - body) * level * a * (2 - a) * tail)
            samples.left[i] += value * stereo.0
            samples.right[i] += value * stereo.1
            level *= release
        }
    }

    mutating func timber(_ at: Double, _ hz: Double, _ gain: Double, _ pan: Double) {
        ring(at: at, hz: hz, gain: gain, attack: 0.0028, decay: 0.041,
             length: 0.22, pan: pan, bend: hz * 0.18)
        ring(at: at, hz: hz * 2.71, gain: gain * 0.25, attack: 0.0019,
             decay: 0.021, length: 0.1, pan: pan - 0.08)
        brush(at: at, length: 0.095, gain: gain * 0.56, attack: 0.002,
              decay: 0.018, lower: 520, upper: 2_900, pan: pan)
    }

    mutating func bronze(_ at: Double, _ hz: Double, _ gain: Double,
                          _ decay: Double, _ pan: Double) {
        // Hum, prime, tierce, quint, nominal and rim. The rim decays first.
        let modes: [(ratio: Double, amplitude: Double, decay: Double, pan: Double)] = [
            (0.505, 0.33, 0.93, -0.09), (1, 1, 1, 0), (1.203, 0.17, 0.46, 0.10),
            (1.507, 0.23, 0.56, -0.11), (2.014, 0.33, 0.41, 0.07), (3.79, 0.07, 0.15, 0.12)
        ]
        for mode in modes {
            ring(at: at, hz: hz * mode.ratio, gain: gain * mode.amplitude,
                 attack: 0.007, decay: decay * mode.decay, length: decay * 6,
                 pan: pan + mode.pan, bend: hz * 0.002)
        }
        brush(at: at, length: 0.09, gain: gain * 0.28, attack: 0.0018,
              decay: 0.014, lower: 680, upper: 3_400, pan: pan)
    }

    /// A hand-pumped reed. Both sides of the breath are rounded and the pitch settles slowly.
    mutating func reed(_ at: Double, _ hz: Double, _ length: Double,
                        _ gain: Double, _ pan: Double) {
        let first = Int(at * Self.rate)
        let last = min(samples.left.count, first + Int(length * Self.rate))
        guard last > first else { return }
        let stereo = Self.pan(pan)
        let attack = min(0.48, length * 0.31)
        let release = min(0.9, length * 0.46)
        let step = Self.turn * hz / Self.rate
        var phase = 0.0
        for i in first..<last {
            let t = Double(i - first) / Self.rate
            let inRamp = min(1, t / attack)
            let outRamp = min(1, (length - t) / release)
            let breath = inRamp * inRamp * (3 - 2 * inRamp) * outRamp * outRamp * (3 - 2 * outRamp)
            let color = sin(phase) + 0.24 * sin(2 * phase + 0.11) + 0.11 * sin(3 * phase + 0.17)
            let value = Float(gain * breath * color * (0.93 + 0.07 * sin(Self.turn * t * 1.7)))
            samples.left[i] += value * stereo.0
            samples.right[i] += value * stereo.1
            phase += step * (1 - 0.008 * (1 - inRamp) + 0.0018 * sin(Self.turn * t * 3.1))
        }
        brush(at: at + 0.01, length: length * 0.83, gain: gain * 0.16, attack: attack,
              decay: length * 0.55, lower: 120, upper: 1_900, pan: pan)
    }

    /// A reflection off the quay and one darker return from the water.
    mutating func finish(peak: Float, reflections: Float = 0) -> HarborSamples {
        let count = samples.left.count
        if reflections > 0 {
            let first = Int(Self.rate * 0.071)
            let second = Int(Self.rate * 0.173)
            var leftWall: Float = 0, rightWall: Float = 0
            if count > second {
                for i in first..<count {
                    leftWall += 0.23 * (samples.right[i - first] - leftWall)
                    rightWall += 0.19 * (samples.left[i - first] - rightWall)
                    var l = leftWall, r = rightWall
                    if i >= second {
                        l += 0.43 * samples.left[i - second]
                        r += 0.39 * samples.right[i - second]
                    }
                    samples.left[i] += reflections * l
                    samples.right[i] += reflections * r
                }
            }
        }
        var maximum: Float = 0
        let fade = max(1, min(count / 6, Int(Self.rate * 0.1)))
        for i in 0..<count {
            let tail = min(1, Float(count - i - 1) / Float(fade))
            samples.left[i] *= tail
            samples.right[i] *= tail
            maximum = max(maximum, abs(samples.left[i]), abs(samples.right[i]))
        }
        let scale = peak / max(maximum, 0.0001)
        for i in 0..<count {
            samples.left[i] *= scale
            samples.right[i] *= scale
        }
        return samples
    }
}

enum HarborScore {
    private static let d = 293.6648, e = 329.6276, f = 349.2282, g = 391.9954, a = 440.0

    static func variations(for cue: HarborCue) -> Int {
        switch cue {
        case .move: return 4
        case .bell: return 3
        case .wait, .blocked, .stamp, .select: return 2
        default: return 1
        }
    }

    static func take(_ cue: HarborCue, variation: Int = 0) -> HarborSamples {
        let index = max(0, variation) % variations(for: cue)
        let side = index.isMultiple(of: 2) ? -0.14 : 0.14
        let pitch = [1.0, 0.974, 1.032, 0.987][index]
        let seed = UInt64(0x95B1_7E32) &* UInt64(13 + index + 11 * (HarborCue.allCases.firstIndex(of: cue) ?? 0))
        switch cue {
        case .move:
            var s = QuayInstruments(0.49, seed: seed)
            s.brush(at: 0, length: 0.34, gain: 1.1, attack: 0.034, decay: 0.087,
                    lower: 97, upper: 1_490, pan: side)
            s.brush(at: 0.095, length: 0.34, gain: 0.68, attack: 0.049, decay: 0.105,
                    lower: 270, upper: 2_310, pan: -side)
            s.ring(at: 0.013, hz: 166 * pitch, gain: 0.16, attack: 0.017, decay: 0.054,
                   length: 0.28, pan: side, bend: -22)
            s.timber(0.112, 326 * pitch, 0.055, -side)
            return s.finish(peak: 0.145, reflections: 0.05)
        case .wait:
            var s = QuayInstruments(0.46, seed: seed)
            s.timber(0, 292 * pitch, 0.62, -0.21)
            s.timber(0.166, 351 * pitch, 0.42, 0.22)
            s.ring(at: 0.167, hz: g, gain: 0.12, attack: 0.004, decay: 0.067,
                   length: 0.27, pan: 0.14)
            return s.finish(peak: 0.106, reflections: 0.07)
        case .blocked:
            var s = QuayInstruments(0.34, seed: seed)
            s.timber(0, 113 * pitch, 1, -0.09)
            s.timber(0.094, 96 * pitch, 0.48, 0.10)
            s.brush(at: 0.025, length: 0.24, gain: 0.29, attack: 0.027,
                    decay: 0.051, lower: 150, upper: 1_230, pan: side)
            return s.finish(peak: 0.155)
        case .select:
            var s = QuayInstruments(0.15, seed: seed)
            s.timber(0, 471 * pitch, 1, side * 0.5)
            return s.finish(peak: 0.087)
        case .stamp:
            var s = QuayInstruments(1.07, seed: seed)
            s.brush(at: 0, length: 0.17, gain: 0.78, attack: 0.018,
                    decay: 0.051, lower: 790, upper: 3_100, pan: -0.19)
            s.timber(0.071, 131 * pitch, 1.2, -0.10)
            s.timber(0.113, 254 * pitch, 0.28, 0.14)
            s.bronze(0.153, a, 0.31, 0.16, 0.19)
            return s.finish(peak: 0.22, reflections: 0.11)
        case .undo:
            var s = QuayInstruments(0.65, seed: seed)
            s.reed(0, g * 0.5, 0.34, 0.31, 0.13)
            s.brush(at: 0, length: 0.30, gain: 0.8, attack: 0.18,
                    decay: 0.21, lower: 160, upper: 1_700, pan: -0.18)
            s.timber(0.28, 207, 0.38, -0.12)
            return s.finish(peak: 0.136, reflections: 0.08)
        case .rewind:
            var s = QuayInstruments(2.4, seed: seed)
            s.reed(0, a * 0.5, 0.62, 0.23, -0.26)
            s.reed(0.21, g * 0.5, 0.65, 0.29, 0.12)
            s.brush(at: 0.04, length: 0.78, gain: 0.46, attack: 0.34,
                    decay: 0.39, lower: 120, upper: 2_080, pan: -0.27)
            s.bronze(0.68, d, 0.52, 0.43, 0.06)
            s.bronze(0.86, a, 0.22, 0.33, 0.29)
            return s.finish(peak: 0.210, reflections: 0.18)
        case .bell:
            // Each buoy has its own pitch and clapper pattern, even in a mono downmix.
            let note = [d, a, d * 2][index]
            let decay = [0.55, 0.36, 0.245][index]
            let location = [-0.31, 0.0, 0.31][index]
            let spacing = [0.0, 0.22, 0.153][index]
            var s = QuayInstruments(2.45, seed: seed)
            for strike in 0...index {
                s.bronze(Double(strike) * spacing, note, [1, 0.73, 0.57][strike], decay, location)
            }
            return s.finish(peak: 0.177, reflections: 0.19)
        case .delivered:
            var s = QuayInstruments(4.0, seed: seed)
            s.timber(0, 179, 0.27, 0)
            s.reed(0.02, d * 0.5, 2.15, 0.16, -0.25)
            s.reed(0.49, a * 0.5, 1.88, 0.11, 0.27)
            for (at, note, gain, pan) in [(0.10, d, 0.46, -0.24), (0.39, g, 0.38, 0.18),
                                        (0.66, a, 0.41, -0.07), (1.17, f, 0.39, 0.21),
                                        (1.48, e, 0.27, -0.14), (1.81, d, 0.47, 0.05)] {
                s.bronze(at, note, gain, 0.43, pan)
            }
            return s.finish(peak: 0.224, reflections: 0.20)
        case .ending:
            var s = QuayInstruments(9.6, seed: seed)
            let chords = [(0.1, d / 2, a / 2), (2.35, 130.8128, g / 2),
                          (4.15, 116.5409, f / 2), (6.12, d / 2, a / 2)]
            for (at, bass, fifth) in chords {
                s.reed(at, bass, 2.65, 0.20, -0.21)
                s.reed(at + 0.13, fifth, 2.55, 0.105, 0.25)
            }
            for (at, note, gain, pan) in [(0.20, d, 0.48, -0.22), (0.62, g, 0.42, 0.15),
                                        (1.06, a, 0.45, 0.03), (1.92, f, 0.38, -0.15),
                                        (2.55, e, 0.30, 0.23), (3.01, d, 0.35, -0.04),
                                        (4.30, f, 0.37, 0.19), (4.90, a, 0.33, -0.20),
                                        (5.36, g, 0.33, 0.05), (6.11, e, 0.32, 0.17),
                                        (6.76, d, 0.47, -0.10), (7.19, d * 2, 0.16, 0.27)] {
                s.bronze(at, note, gain, 0.52, pan)
            }
            return s.finish(peak: 0.235, reflections: 0.22)
        }
    }

    /// The waves and the higher wash have different periods and stereo positions.
    /// Overlap their actual running filters across the seam, including the low shore rumble.
    static func tide() -> HarborSamples {
        let seconds = 43.0
        let rate = Double(HarborSamples.rate)
        let frames = Int(seconds * rate), overlap = Int(1.8 * rate)
        var bed = HarborSamples(seconds: seconds)
        var tailL = [Float](repeating: 0, count: overlap), tailR = tailL
        var noise = HarborNoise(state: 0xF30B_29C7_B51A_00E3)
        var bass = 0.0, bodyL = 0.0, bodyR = 0.0, midL = 0.0, midR = 0.0
        var foamL = 0.0, foamR = 0.0
        let unit = 2 * Double.pi / Double(frames)
        for i in 0..<(frames + overlap) {
            let l = noise.next(), r = noise.next(), mono = (l + r) * 0.5
            bass += 0.007 * (mono - bass)
            bodyL += 0.022 * (l - bodyL)
            bodyR += 0.025 * (r - bodyR)
            midL += 0.119 * (l - midL)
            midR += 0.112 * (r - midR)
            foamL += 0.39 * (l - foamL)
            foamR += 0.37 * (r - foamR)
            let p = Double(i) * unit
            let swell = 0.59 + 0.19 * sin(5 * p + 0.7) + 0.11 * sin(8 * p - 1.2) + 0.09 * sin(2 * p)
            let ripple = 0.49 + 0.26 * sin(9 * p - 0.5) + 0.15 * sin(13 * p + 1.1)
            let lOut = Float(0.16 * bass + 0.068 * bodyL + 0.078 * swell * (midL - bodyL) + 0.016 * ripple * (foamL - midL))
            let rOut = Float(0.16 * bass + 0.066 * bodyR + 0.076 * swell * (midR - bodyR) + 0.016 * ripple * (foamR - midR))
            if i < frames {
                bed.left[i] = lOut
                bed.right[i] = rOut
            } else {
                tailL[i - frames] = lOut
                tailR[i - frames] = rOut
            }
        }
        for i in 0..<overlap {
            let angle = Double(i) / Double(overlap - 1) * Double.pi * 0.5
            let outGain = Float(cos(angle)), inGain = Float(sin(angle))
            bed.left[i] = tailL[i] * outGain + bed.left[i] * inGain
            bed.right[i] = tailR[i] * outGain + bed.right[i] * inGain
        }
        return bed
    }

    /// Short signals across the water are separated by irregular spans of quiet.
    static func distant(_ index: Int) -> HarborSamples {
        var s = QuayInstruments(5.8, seed: UInt64(0x1792_EA37) &* UInt64(max(1, index + 1)))
        switch index % 3 {
        case 0:
            s.reed(0, d / 2, 2.85, 0.68, -0.56)
            s.reed(0.55, a / 2, 2.25, 0.18, -0.31)
        case 1:
            s.bronze(0, g, 0.50, 0.57, 0.58)
            s.bronze(1.55, d, 0.30, 0.48, 0.42)
        default:
            s.reed(0, g / 2, 1.45, 0.47, 0.47)
            s.reed(2.04, d / 2, 2.36, 0.63, 0.30)
        }
        return s.finish(peak: index % 3 == 1 ? 0.027 : 0.035, reflections: 0.29)
    }
}
