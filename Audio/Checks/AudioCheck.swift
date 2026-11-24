#if MISTPOST_AUDIO_OFFLINE_TEST
import AVFoundation
import Foundation

/// Run with Audio/Checks/check.sh. The test build routes the entire game mixer to memory.
@main
struct AudioCheck {
    static func require(_ condition: @autoclosure () -> Bool, _ message: @autoclosure () -> String) {
        if !condition() {
            FileHandle.standardError.write(Data("FAIL \(message())\n".utf8))
            exit(1)
        }
    }

    static func statistics(_ name: String, _ samples: HarborSamples) -> (peak: Double, rms: Double) {
        require(samples.left.count == samples.right.count && !samples.left.isEmpty, "\(name) channel dimensions")
        let n = Double(samples.left.count)
        var energy = 0.0, monoEnergy = 0.0, peak = 0.0, mean = 0.0
        for i in samples.left.indices {
            let l = Double(samples.left[i]), r = Double(samples.right[i])
            require(l.isFinite && r.isFinite, "\(name) contains non-finite audio")
            let mono = (l + r) * 0.5
            monoEnergy += mono * mono
            energy += (l * l + r * r) * 0.5
            mean += mono
            peak = max(peak, abs(l), abs(r))
        }
        let rms = sqrt(energy / n)
        require(peak < 0.26 && peak > 0.013, "\(name) has no headroom or no signal")
        require(abs(mean / n) < max(0.0007, rms * 0.035), "\(name) has DC bias")
        require(monoEnergy / energy > 0.55, "\(name) has poor mono compatibility")
        print(String(format: "%@  %.2f s  peak %.1f dBFS  RMS %.1f dBFS", name,
                     n / Double(HarborSamples.rate), 20 * log10(peak), 20 * log10(rms)))
        return (peak, rms)
    }

    static func main() throws {
        let start = ProcessInfo.processInfo.systemUptime
        for cue in HarborCue.allCases {
            var first: HarborSamples?
            for i in 0..<HarborScore.variations(for: cue) {
                let s = HarborScore.take(cue, variation: i)
                _ = statistics("\(cue).\(i)", s)
                require(s.left.first == 0 && s.right.first == 0 && s.left.last == 0 && s.right.last == 0,
                        "\(cue) does not start/end at silence")
                if let first {
                    require(s.left != first.left && s.right != first.right, "\(cue) variation identical")
                } else { first = s }
            }
        }
        for i in 0..<3 { _ = statistics("horizon.\(i)", HarborScore.distant(i)) }
        let tide = HarborScore.tide()
        let bed = statistics("waves", tide)
        require(bed.rms > 0.006 && bed.rms < 0.022, "tide RMS outside design range")
        for channel in [tide.left, tide.right] {
            var changes = [Float]()
            for i in stride(from: 1, to: channel.count, by: 43) { changes.append(abs(channel[i] - channel[i - 1])) }
            changes.sort()
            let seam = abs(channel[0] - channel[channel.count - 1])
            let p99 = changes[Int(Double(changes.count) * 0.99)]
            print(String(format: "loop seam %.5f vs ordinary p99 %.5f", seam, p99))
            require(seam <= p99, "audible loop seam")
        }
        print(String(format: "synthesis + signal checks %.2f s", ProcessInfo.processInfo.systemUptime - start))

        var audio: HarborAudio? = HarborAudio()
        let wasReleased = { [weak audio] in audio == nil }
        require(audio?.offlineState().running == false, "mixer plays before activation")
        audio?.setEnabled(false)
        audio?.setActive(true)
        audio?.play(.ending)
        require(audio?.offlineState().running == false, "disabled mixer started")
        audio?.setEnabled(true)
        require(audio?.offlineState().running == true, "offline engine failed to start")
        Thread.sleep(forTimeInterval: 0.55)
        let tideOutput = try audio?.offlineFrames(48_000) ?? []
        require(tideOutput.count == 48_000 && tideOutput.contains { abs($0) > 0.008 }, "no resampled tide on mixer")
        for channel in 0..<3 { audio?.ringBuoy(channel) }
        audio?.ringBuoy(1)
        require(audio?.offlineState().voices == 3, "independent, debounced gate sounds")
        for cue in HarborCue.allCases {
            audio?.play(cue)
            let result = try audio?.offlineFrames(12_288) ?? []
            require(result.count == 12_288 && result.allSatisfy { $0.isFinite && abs($0) < 1 }, "\(cue) render clipped or failed")
            Thread.sleep(forTimeInterval: 0.051)
        }
        audio?.setEnabled(false)
        Thread.sleep(forTimeInterval: 0.24)
        guard let muted = audio?.offlineState() else { fatalError() }
        require(!muted.running && !muted.fading && !muted.distance && muted.voices == 0 && muted.gain == 0,
                "mute left a running voice or timer")
        audio?.setActive(false)
        audio?.setEnabled(true)
        require(audio?.offlineState().running == false, "background app played")
        for _ in 0..<40 {
            audio?.setActive(true)
            audio?.play(.move)
            audio?.setActive(false)
        }
        audio?.setActive(true)
        Thread.sleep(forTimeInterval: 0.60)
        guard let resumed = audio?.offlineState() else { fatalError() }
        require(resumed.running && !resumed.fading && resumed.distance && resumed.gain > 0.89, "focus transition race")
        audio?.simulateDeviceChange()
        Thread.sleep(forTimeInterval: 0.85)
        let recovered = try audio?.offlineFrames(16_384) ?? []
        require(recovered.count == 16_384 && recovered.contains { abs($0) > 0.006 }, "route change recovery")
        audio = nil
        require(wasReleased(), "live mixer retained after its owner released it")
        print("PASS  all cues, waves, mono downmix, 48 kHz output, mute, focus, device recovery, teardown")
        if CommandLine.arguments.count == 3, CommandLine.arguments[1] == "--soak",
           let seconds = Double(CommandLine.arguments[2]), seconds.isFinite, seconds > 0 {
            try AudioSoak.run(seconds: seconds)
        }
    }
}
#endif
