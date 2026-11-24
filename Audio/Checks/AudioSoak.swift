#if MISTPOST_AUDIO_OFFLINE_TEST
import Foundation

/// Wall-clock playback under the same serial queue, timers and graph lifecycle as the game.
/// Every sample goes to AVAudioEngine's offline renderer. The speaker is never opened.
enum AudioSoak {
    static func log(_ message: String) { FileHandle.standardOutput.write(Data((message + "\n").utf8)) }

    static func run(seconds: Double) throws {
        let audio = HarborAudio()
        let clock = ProcessInfo.processInfo
        let start = clock.systemUptime
        var last = start, lastTransition = -10.0, nextSignal = 0.0, nextRouteChange = 149.0
        var nextReport = min(60, seconds), enabled = false, active = false
        var events = 0, routes = 0, transitions = 0, rendered: Int64 = 0
        var peak: Float = 0
        let actions: [HarborCue] = [.select, .move, .move, .wait, .bell, .move, .stamp, .move, .blocked,
                                    .undo, .move, .rewind, .move, .wait, .move, .bell, .move, .stamp,
                                    .move, .move, .delivered, .select, .wait]
        fflush(nil)
        log("Starting hardware-free, wall-clock mixer run for \(Int(seconds)) seconds")
        while clock.systemUptime - start < seconds {
            try autoreleasepool {
                let now = clock.systemUptime, elapsed = now - start
                let cycle = Int(elapsed) % 227
                let shouldBeActive = !(84..<90).contains(cycle)
                let shouldBeEnabled = !(165..<170).contains(cycle)
                if active != shouldBeActive {
                    active = shouldBeActive
                    audio.setActive(active)
                    lastTransition = elapsed
                    transitions += 1
                }
                if enabled != shouldBeEnabled {
                    enabled = shouldBeEnabled
                    audio.setEnabled(enabled)
                    lastTransition = elapsed
                    transitions += 1
                }
                if elapsed >= nextRouteChange, enabled, active {
                    audio.simulateDeviceChange()
                    lastTransition = elapsed
                    nextRouteChange += 311
                    routes += 1
                }
                if elapsed >= nextSignal {
                    let cue = events > 0 && events.isMultiple(of: 407) ? HarborCue.ending : actions[events % actions.count]
                    if cue == .bell {
                        audio.ringBuoy(events % 3)
                        if events.isMultiple(of: 11) { audio.ringBuoy((events + 1) % 3) }
                    } else { audio.play(cue) }
                    events += 1
                    nextSignal = elapsed + [0.62, 1.06, 0.71, 0.45, 1.41][events % 5]
                }
                let state = audio.offlineState()
                if elapsed - lastTransition > 1.35 {
                    AudioCheck.require(state.running == (enabled && active), "mixer disagrees with focus/mute at \(elapsed)")
                    if !enabled || !active { AudioCheck.require(!state.fading && !state.distance && state.voices == 0, "idle work in silence") }
                }
                let count = Int(min(0.5, max(0, now - last)) * 48_000)
                if state.running, count > 0 {
                    let samples = try audio.offlineFrames(count)
                    AudioCheck.require(samples.count == count, "offline graph dropped a render at \(elapsed)")
                    for sample in samples {
                        AudioCheck.require(sample.isFinite && abs(sample) < 0.995, "clipping or non-finite mix at \(elapsed)")
                        peak = max(peak, abs(sample))
                    }
                    rendered += Int64(samples.count)
                }
                last = now
                if elapsed >= nextReport {
                    var usage = rusage()
                    getrusage(RUSAGE_SELF, &usage)
                    let memoryMB = Double(usage.ru_maxrss) / 1_048_576
                    log(String(format: "%.0f s   %lld frames   %d actions   %d focus/mute changes   %d device changes   peak %.3f   high-water RSS %.1f MiB", elapsed, rendered, events, transitions, routes, peak, memoryMB))
                    AudioCheck.require(memoryMB < 320, "audio process exceeded its bounded memory budget")
                    nextReport += 300
                }
            }
            Thread.sleep(forTimeInterval: 0.12)
        }
        audio.setActive(false)
        Thread.sleep(forTimeInterval: 0.25)
        let end = audio.offlineState()
        AudioCheck.require(!end.running && !end.fading && !end.distance && end.voices == 0, "soak teardown left active work")
        log(String(format: "PASS  %.1f wall-clock seconds, %lld rendered frames, %d actions, %d focus/mute changes, %d recovered routes, peak %.3f", clock.systemUptime - start, rendered, events, transitions, routes, peak))
    }
}
#endif
