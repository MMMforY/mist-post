import AVFoundation
import Foundation

/// The game owns one instance. Synthesis, graph changes and playback stay off the UI thread.
final class HarborAudio: @unchecked Sendable {
    private let queue = DispatchQueue(label: "mistpost.harbor.audio", qos: .userInitiated)
    private var enabled = true
    private var active = false
    private var graph: Graph?
    private var deviceObserver: NSObjectProtocol?
    private var fadeTimer: DispatchSourceTimer?
    private var distanceTimer: DispatchSourceTimer?
    private var distanceIndex = 0
    private var retryTimer: DispatchSourceTimer?
    private var retryDelay = 2.0
    private var takeCursor: [HarborCue: Int] = [:]
    private var lastCue: [HarborCue: Double] = [:]
    private var lastBuoy = [Double](repeating: -1_000, count: 3)
    private var wave: AVAudioPCMBuffer?
    private var takes: [HarborCue: [Int: AVAudioPCMBuffer]] = [:]
    private var distant: [Int: AVAudioPCMBuffer] = [:]
    private let format = AVAudioFormat(standardFormatWithSampleRate: Double(HarborSamples.rate), channels: 2)

    init() {}

    func setEnabled(_ value: Bool) {
        queue.async { [weak self] in
            guard let self else { return }
            if self.enabled == value, self.graph?.engine.isRunning == true { return }
            self.enabled = value
            self.reconcile()
        }
    }

    func setActive(_ value: Bool) {
        queue.async { [weak self] in
            guard let self else { return }
            if self.active == value, self.graph?.engine.isRunning == true { return }
            self.active = value
            self.reconcile()
        }
    }

    func play(_ cue: HarborCue) { submit(cue, buoy: nil) }

    /// Distinct low, middle and high clappers identify the chart's three buoy channels.
    func ringBuoy(_ channel: Int) { submit(.bell, buoy: max(0, channel) % 3) }

    private func submit(_ cue: HarborCue, buoy: Int?) {
        let requestedAt = ProcessInfo.processInfo.systemUptime
        queue.async { [weak self] in self?.perform(cue, buoy: buoy, requestedAt: requestedAt) }
    }

    deinit {
        fadeTimer?.cancel()
        distanceTimer?.cancel()
        retryTimer?.cancel()
        if let deviceObserver { NotificationCenter.default.removeObserver(deviceObserver) }
        graph?.stop()
    }

    private final class Voice {
        let node = AVAudioPlayerNode()
        var freeAt = 0.0
        var priority = 0
    }

    private final class Graph {
        let engine = AVAudioEngine()
        let tide = AVAudioPlayerNode()
        let horizon = AVAudioPlayerNode()
        let voices = (0..<8).map { _ in Voice() }

        init?(format: AVAudioFormat) {
            #if !MISTPOST_AUDIO_OFFLINE_TEST
            let hardware = engine.outputNode.outputFormat(forBus: 0)
            guard hardware.channelCount > 0, hardware.sampleRate.isFinite, hardware.sampleRate > 0 else { return nil }
            #endif
            let mixer = engine.mainMixerNode
            mixer.outputVolume = 0
            for player in [tide, horizon] + voices.map(\.node) {
                engine.attach(player)
                engine.connect(player, to: mixer, format: format)
            }
            #if MISTPOST_AUDIO_OFFLINE_TEST
            guard let output = AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 2) else { return nil }
            do {
                try engine.enableManualRenderingMode(.offline, format: output, maximumFrameCount: 2_048)
            } catch { return nil }
            #endif
        }

        func stop() {
            tide.stop()
            horizon.stop()
            for voice in voices {
                voice.node.stop()
                voice.freeAt = 0
                voice.priority = 0
            }
            engine.stop()
        }
    }

    private func makeBuffer(_ samples: HarborSamples) -> AVAudioPCMBuffer? {
        guard let format, !samples.left.isEmpty, samples.left.count == samples.right.count,
              let pcm = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(samples.left.count)),
              let channels = pcm.floatChannelData else { return nil }
        pcm.frameLength = pcm.frameCapacity
        for (channel, values) in [samples.left, samples.right].enumerated() {
            values.withUnsafeBufferPointer { source in
                if let base = source.baseAddress { channels[channel].update(from: base, count: source.count) }
            }
        }
        return pcm
    }

    private func reconcile() {
        guard enabled, active else {
            retryTimer?.cancel()
            retryTimer = nil
            retryDelay = 2
            distanceTimer?.cancel()
            distanceTimer = nil
            if let graph, graph.engine.isRunning { fade(to: 0, seconds: 0.18) }
            return
        }
        if let graph, graph.engine.isRunning {
            fade(to: 0.90, seconds: 0.23)
            scheduleDistance()
            return
        }
        guard let format, retryTimer == nil else { return }
        if graph == nil {
            guard let fresh = Graph(format: format) else {
                scheduleRetry()
                return
            }
            graph = fresh
            deviceObserver = NotificationCenter.default.addObserver(
                forName: .AVAudioEngineConfigurationChange, object: fresh.engine, queue: nil
            ) { [weak self] note in
                let identity = note.object.map { ObjectIdentifier($0 as AnyObject) }
                self?.queue.async { [weak self] in self?.deviceChanged(identity) }
            }
        }
        guard let graph else { return }
        if wave == nil { wave = makeBuffer(HarborScore.tide()) }
        guard let wave else { return }
        graph.engine.mainMixerNode.outputVolume = 0
        do {
            graph.engine.prepare()
            try graph.engine.start()
        } catch {
            discardGraph()
            scheduleRetry()
            return
        }
        retryDelay = 2
        graph.tide.scheduleBuffer(wave, at: nil, options: .loops, completionHandler: nil)
        graph.tide.play()
        fade(to: 0.90, seconds: 0.48)
        scheduleDistance()
    }

    /// Core Audio can stop the graph when the current headphones or output device changes.
    private func deviceChanged(_ identity: ObjectIdentifier?) {
        guard let graph, ObjectIdentifier(graph.engine) == identity, !graph.engine.isRunning else { return }
        discardGraph()
        queue.asyncAfter(deadline: .now() + 0.2) { [weak self] in
            guard let self, self.graph == nil else { return }
            self.reconcile()
        }
    }

    /// Retry an unavailable output even while the player is reading a letter in silence.
    private func scheduleRetry() {
        guard enabled, active, retryTimer == nil else { return }
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + retryDelay, leeway: .milliseconds(100))
        retryDelay = min(30, retryDelay * 2)
        timer.setEventHandler { [weak self] in
            guard let self else { return }
            self.retryTimer?.cancel()
            self.retryTimer = nil
            self.reconcile()
        }
        retryTimer = timer
        timer.activate()
    }

    private func discardGraph() {
        if let deviceObserver { NotificationCenter.default.removeObserver(deviceObserver) }
        deviceObserver = nil
        fadeTimer?.cancel()
        fadeTimer = nil
        distanceTimer?.cancel()
        distanceTimer = nil
        graph?.stop()
        graph = nil
    }

    /// A short gain ramp avoids a hard edge when the player mutes or leaves the app.
    private func fade(to target: Float, seconds: Double) {
        fadeTimer?.cancel()
        fadeTimer = nil
        guard let graph else { return }
        let mixer = graph.engine.mainMixerNode
        let start = mixer.outputVolume
        if abs(start - target) < 0.001 {
            mixer.outputVolume = target
            if target == 0 { graph.stop() }
            return
        }
        let begin = ProcessInfo.processInfo.systemUptime
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now(), repeating: .milliseconds(10), leeway: .milliseconds(2))
        timer.setEventHandler { [weak self] in
            guard let self, let graph = self.graph else { return }
            let fraction = Float(min(1, (ProcessInfo.processInfo.systemUptime - begin) / seconds))
            let smooth = fraction * fraction * (3 - 2 * fraction)
            graph.engine.mainMixerNode.outputVolume = start + (target - start) * smooth
            if fraction >= 1 {
                self.fadeTimer?.cancel()
                self.fadeTimer = nil
                if target == 0 { graph.stop() }
            }
        }
        fadeTimer = timer
        timer.activate()
    }

    private func scheduleDistance() {
        guard distanceTimer == nil, enabled, active, graph?.engine.isRunning == true else { return }
        let intervals = [17.6, 34.7, 24.2, 43.9, 27.4, 36.3, 47.1]
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + intervals[distanceIndex % intervals.count], leeway: .milliseconds(240))
        timer.setEventHandler { [weak self] in
            guard let self else { return }
            self.distanceTimer?.cancel()
            self.distanceTimer = nil
            guard self.enabled, self.active, let graph = self.graph, graph.engine.isRunning else { return }
            let order = [0, 1, 2, 0, 2, 1]
            let signal = order[self.distanceIndex % order.count]
            self.distanceIndex = (self.distanceIndex + 1) % 42
            let now = ProcessInfo.processInfo.systemUptime
            if !graph.voices.contains(where: { $0.priority >= 3 && $0.freeAt > now }) {
                if self.distant[signal] == nil { self.distant[signal] = self.makeBuffer(HarborScore.distant(signal)) }
                if let pcm = self.distant[signal] {
                    graph.horizon.scheduleBuffer(pcm, at: nil, options: .interrupts, completionHandler: nil)
                    graph.horizon.play()
                }
            }
            self.scheduleDistance()
        }
        distanceTimer = timer
        timer.activate()
    }

    private func perform(_ cue: HarborCue, buoy: Int?, requestedAt: Double) {
        guard enabled, active else { return }
        if graph?.engine.isRunning != true { reconcile() }
        guard let graph, graph.engine.isRunning else { return }
        let now = ProcessInfo.processInfo.systemUptime
        let priority: Int
        switch cue {
        case .move, .wait, .blocked, .select: priority = 1
        case .stamp, .undo, .bell: priority = 2
        case .rewind: priority = 3
        case .delivered, .ending: priority = 4
        }
        guard now - requestedAt < (priority > 2 ? 2.5 : 0.55) else { return }
        // A held key at a wall should sound like one impact, not a rattling speaker.
        let gap = cue == .blocked ? 0.20 : (cue == .bell ? 0.13 : 0.043)
        let variant = cue == .bell ? (buoy ?? 0) : (takeCursor[cue] ?? 0)
        let last = cue == .bell ? lastBuoy[variant] : (lastCue[cue] ?? -1_000)
        guard now - last > gap else { return }
        let idle = graph.voices.first { $0.freeAt <= now }
        let quietest = graph.voices.filter { $0.priority < priority }.min { $0.freeAt < $1.freeAt }
        guard let voice = idle ?? quietest else { return }
        if takes[cue]?[variant] == nil {
            guard let pcm = makeBuffer(HarborScore.take(cue, variation: variant)) else { return }
            takes[cue, default: [:]][variant] = pcm
        }
        guard let pcm = takes[cue]?[variant] else { return }
        let started = ProcessInfo.processInfo.systemUptime
        voice.node.scheduleBuffer(pcm, at: nil, options: .interrupts, completionHandler: nil)
        voice.node.play()
        voice.priority = priority
        voice.freeAt = started + Double(pcm.frameLength) / pcm.format.sampleRate
        if cue == .bell {
            lastBuoy[variant] = started
        } else {
            lastCue[cue] = started
            takeCursor[cue] = (variant + 1) % HarborScore.variations(for: cue)
        }
    }
}

#if MISTPOST_AUDIO_OFFLINE_TEST
extension HarborAudio {
    func offlineState() -> (running: Bool, fading: Bool, distance: Bool, voices: Int, gain: Float) {
        queue.sync {
            (graph?.engine.isRunning == true, fadeTimer != nil, distanceTimer != nil,
             graph?.voices.filter { $0.freeAt > ProcessInfo.processInfo.systemUptime }.count ?? 0,
             graph?.engine.mainMixerNode.outputVolume ?? 0)
        }
    }

    func offlineFrames(_ frames: Int) throws -> [Float] {
        try queue.sync {
            guard let graph, graph.engine.isRunning else { return [] }
            let engine = graph.engine
            guard let pcm = AVAudioPCMBuffer(pcmFormat: engine.manualRenderingFormat, frameCapacity: 2_048) else { return [] }
            var results = [Float]()
            var remaining = frames, retries = 0
            while remaining > 0, retries < 10 {
                let count = AVAudioFrameCount(min(remaining, 2_048))
                switch try engine.renderOffline(count, to: pcm) {
                case .success:
                    guard let channels = pcm.floatChannelData, pcm.frameLength > 0 else { return [] }
                    results += UnsafeBufferPointer(start: channels[0], count: Int(pcm.frameLength))
                    remaining -= Int(pcm.frameLength)
                    retries = 0
                case .cannotDoInCurrentContext:
                    retries += 1
                default:
                    return []
                }
            }
            return remaining == 0 ? results : []
        }
    }

    func simulateDeviceChange() {
        queue.sync {
            guard let graph else { return }
            graph.engine.stop()
            deviceChanged(ObjectIdentifier(graph.engine))
        }
    }
}
#endif
