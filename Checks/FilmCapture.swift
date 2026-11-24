import AppKit
import AVFoundation

/// Captures the actual game renderer and score into a short local gameplay film.
@MainActor
enum FilmCapture {
    struct FilmError: LocalizedError {
        let description: String
        var errorDescription: String? { description }
    }
    static func make(view: StationView, file: URL) async throws {
        let parent = file.deletingLastPathComponent()
        try FileManager.default.createDirectory(at:parent,withIntermediateDirectories:true)
        let scratch = parent.appendingPathComponent(".film-"+UUID().uuidString,isDirectory:true)
        try FileManager.default.createDirectory(at:scratch,withIntermediateDirectories:true)
        defer { try? FileManager.default.removeItem(at:scratch) }
        let silent = scratch.appendingPathComponent("harbor.mov"), audio = scratch.appendingPathComponent("score.caf")
        let joined = scratch.appendingPathComponent("preview.mp4")
        let w = 1200, h = 750, fps = 24, frames = 552
        let writer = try AVAssetWriter(outputURL:silent,fileType:.mov)
        let input = AVAssetWriterInput(mediaType:.video,outputSettings:[
            AVVideoCodecKey:AVVideoCodecType.h264,
            AVVideoWidthKey:w, AVVideoHeightKey:h,
            AVVideoCompressionPropertiesKey:[AVVideoAverageBitRateKey:6_500_000,AVVideoMaxKeyFrameIntervalKey:48]
        ])
        input.expectsMediaDataInRealTime = false
        let adapter = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput:input,sourcePixelBufferAttributes:[
            kCVPixelBufferPixelFormatTypeKey as String:kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String:w,kCVPixelBufferHeightKey as String:h
        ])
        guard writer.canAdd(input) else { throw FilmError(description:"Video input unavailable") }
        writer.add(input)
        guard writer.startWriting() else { throw writer.error ?? FilmError(description:"Cannot start video") }
        writer.startSession(atSourceTime:.zero)
        view.frame = R(0,0,CGFloat(w),CGFloat(h))
        view.audio.setActive(false)
        var cues: [(Int,HarborCue)] = []
        let stage2 = MistCampaign.levels[1]
        let steps = [104,122,140,181,212,232,252,272,292,314]
        let stepAt = Dictionary(uniqueKeysWithValues:zip(steps,stage2.guide))
        func dispatch(_ cmd: MistCommand, at i: Int) {
            let old = view.voyage
            view.operate(cmd)
            let cue: HarborCue
            if view.voyage.delivered { cue = .delivered }
            else if cmd == .record { cue = .rewind }
            else if (0..<3).contains(where:{ !old.gateOpen($0,at:old.beat) && view.voyage.gateOpen($0,at:view.voyage.beat) }) { cue = .bell }
            else { cue = cmd == .move(.wait) ? .wait : .move }
            cues.append((i,cue))
        }
        for index in 0..<frames {
            try autoreleasepool {
                view.frozenTime = 10+Double(index)/Double(fps)
                if index == 48 {
                    var first = MistVoyage(level:MistCampaign.levels[0])
                    for command in first.level.guide { first.perform(command) }
                    view.store.save(first)
                    view.act(.routes)
                    view.act(.port(2))
                    cues.append((index,.select))
                }
                if index == 84 { view.start(2) }
                if let cmd = stepAt[index] { dispatch(cmd,at:index) }
                if index == 388 {
                    for lvl in MistCampaign.levels.prefix(7) {
                        var trip = MistVoyage(level:lvl)
                        for command in lvl.guide { trip.perform(command) }
                        view.store.save(trip)
                    }
                    let lvl = MistCampaign.levels[7]
                    view.start(lvl.id)
                    for cmd in lvl.guide.dropLast(6) { view.operate(cmd) }
                    view.motionAt = nil
                }
                if [412,432,452].contains(index) {
                    let cmd = view.voyage.level.guide[view.voyage.history.count]
                    dispatch(cmd,at:index)
                }
                if index == 477 { view.act(.album); view.act(.chapter(0)); cues.append((index,.select)) }
                if index == 526 { view.act(.home) }
                let deadline = ProcessInfo.processInfo.systemUptime+12
                while !input.isReadyForMoreMediaData {
                    guard writer.status == .writing, ProcessInfo.processInfo.systemUptime < deadline else {
                        throw writer.error ?? FilmError(description:"Video stream stalled")
                    }
                    Thread.sleep(forTimeInterval:0.003)
                }
                var ref: CVPixelBuffer?
                guard let pool = adapter.pixelBufferPool,
                      CVPixelBufferPoolCreatePixelBuffer(nil,pool,&ref) == kCVReturnSuccess, let buf = ref else {
                    throw FilmError(description:"No video frame")
                }
                CVPixelBufferLockBaseAddress(buf,[])
                guard let ctx = CGContext(data:CVPixelBufferGetBaseAddress(buf),width:w,height:h,bitsPerComponent:8,
                                          bytesPerRow:CVPixelBufferGetBytesPerRow(buf),
                                          space:CGColorSpace(name:CGColorSpace.sRGB)!,
                                          bitmapInfo:CGBitmapInfo.byteOrder32Little.rawValue | CGImageAlphaInfo.premultipliedFirst.rawValue)
                else { CVPixelBufferUnlockBaseAddress(buf,[]); throw FilmError(description:"Invalid pixel buffer") }
                ctx.translateBy(x:0,y:CGFloat(h)); ctx.scaleBy(x:1,y:-1)
                NSGraphicsContext.saveGraphicsState()
                NSGraphicsContext.current = NSGraphicsContext(cgContext:ctx,flipped:true)
                view.draw(view.bounds)
                NSGraphicsContext.restoreGraphicsState()
                ctx.flush()
                CVPixelBufferUnlockBaseAddress(buf,[])
                guard adapter.append(buf,withPresentationTime:CMTime(value:Int64(index),timescale:Int32(fps))) else {
                    throw writer.error ?? FilmError(description:"Video frame rejected")
                }
            }
        }
        input.markAsFinished()
        writer.endSession(atSourceTime:CMTime(value:Int64(frames),timescale:Int32(fps)))
        await writer.finishWriting()
        guard writer.status == .completed else {
            throw writer.error ?? FilmError(description:"Incomplete video stream")
        }
        let duration = Double(frames)/Double(fps)
        var track = HarborScore.tide()
        let count = Int(duration*Double(HarborSamples.rate))
        for (frame,cue) in cues {
            let hit = HarborScore.take(cue)
            let start = frame*HarborSamples.rate/fps
            for i in 0..<min(hit.left.count,count-start) {
                track.left[start+i] += hit.left[i]
                track.right[start+i] += hit.right[i]
            }
        }
        let format = AVAudioFormat(standardFormatWithSampleRate:Double(HarborSamples.rate),channels:2)!
        let pcm = AVAudioPCMBuffer(pcmFormat:format,frameCapacity:AVAudioFrameCount(count))!
        pcm.frameLength = AVAudioFrameCount(count)
        for i in 0..<count {
            let fade = Float(max(0,min(1,Double(i)/5500,Double(count-i-1)/12000)))
            pcm.floatChannelData![0][i] = track.left[i]*fade
            pcm.floatChannelData![1][i] = track.right[i]*fade
        }
        do {
            var diskFormat = format.settings
            diskFormat[AVLinearPCMIsNonInterleaved] = false
            let pcmFile = try AVAudioFile(forWriting:audio,settings:diskFormat,commonFormat:.pcmFormatFloat32,interleaved:false)
            try pcmFile.write(from:pcm)
        }
        let videoAsset = AVURLAsset(url:silent), soundAsset = AVURLAsset(url:audio)
        let comp = AVMutableComposition()
        let full = CMTimeRange(start:.zero,duration:CMTime(value:Int64(frames),timescale:Int32(fps)))
        let videoTracks = try await videoAsset.loadTracks(withMediaType:.video)
        let soundTracks = try await soundAsset.loadTracks(withMediaType:.audio)
        guard let vt = videoTracks.first, let at = soundTracks.first,
              let cv = comp.addMutableTrack(withMediaType:.video,preferredTrackID:kCMPersistentTrackID_Invalid),
              let ca = comp.addMutableTrack(withMediaType:.audio,preferredTrackID:kCMPersistentTrackID_Invalid)
        else { throw FilmError(description:"Missing film tracks") }
        try cv.insertTimeRange(full,of:vt,at:.zero)
        try ca.insertTimeRange(full,of:at,at:.zero)
        guard let export = AVAssetExportSession(asset:comp,presetName:AVAssetExportPresetHighestQuality) else {
            throw FilmError(description:"Movie export unavailable")
        }
        export.shouldOptimizeForNetworkUse = true
        if #available(macOS 15.0, *) {
            try await export.export(to:joined,as:.mp4)
        } else {
            export.outputURL = joined
            export.outputFileType = .mp4
            await export.export()
            guard export.status == .completed else {
                throw export.error ?? FilmError(description:"Movie export did not complete")
            }
        }
        try Data(contentsOf:joined).write(to:file,options:.atomic)
        print("PASS native gameplay film: \(w)×\(h), \(fps) fps, \(Int(duration)) s, stereo score")
    }
}
