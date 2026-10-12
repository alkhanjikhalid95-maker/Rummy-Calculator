// Trims the Kling Joker clip, scales it to 1080 px wide and re-encodes it as
// HEVC for the app, then writes its first and last frames as JPEG stills.
//
//   swift encode_reveal.swift <source.mp4> <out-folder> [start=0.75] [end=4.52]
//
// For kling_20261012_VIDEO_Animate_th_5981_0.mp4: the first 0.75 s barely
// moves; the sign holds still from 4.0 s; the jester starts to blink at
// 4.58 s. The cut ends on the 4.5 s frame, which the app holds.
import AVFoundation
import AppKit

let args = CommandLine.arguments
guard args.count >= 3 else {
    print("usage: swift encode_reveal.swift <source.mp4> <out-folder> [start] [end]")
    exit(1)
}
let source = URL(fileURLWithPath: args[1])
let folder = URL(fileURLWithPath: args[2])
let start = args.count > 3 ? Double(args[3])! : 0.75
let end = args.count > 4 ? Double(args[4])! : 4.52
let width = 1080.0

let output = folder.appendingPathComponent("JokerReveal.mp4")
try? FileManager.default.removeItem(at: output)

let done = DispatchSemaphore(value: 0)
Task {
    do {
        let asset = AVURLAsset(url: source)
        let track = try await asset.loadTracks(withMediaType: .video)[0]
        let natural = try await track.load(.naturalSize)
        let fps = try await track.load(.nominalFrameRate)
        let height = (natural.height * width / natural.width / 2).rounded() * 2
        let renderSize = CGSize(width: width, height: height)

        let reader = try AVAssetReader(asset: asset)
        let startTime = CMTime(seconds: start, preferredTimescale: 600)
        reader.timeRange = CMTimeRange(start: startTime, end: CMTime(seconds: end, preferredTimescale: 600))
        let readerOutput = AVAssetReaderTrackOutput(
            track: track,
            outputSettings: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
        )
        reader.add(readerOutput)

        let writer = try AVAssetWriter(outputURL: output, fileType: .mp4)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.hevc,
            AVVideoWidthKey: renderSize.width,
            AVVideoHeightKey: renderSize.height,
            // The encoder scales each frame down to the output size.
            AVVideoScalingModeKey: AVVideoScalingModeResizeAspectFill,
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: 4_500_000,
                AVVideoExpectedSourceFrameRateKey: fps,
            ],
        ])
        input.expectsMediaDataInRealTime = false
        writer.add(input)
        writer.startWriting()
        writer.startSession(atSourceTime: .zero)
        reader.startReading()

        var frames = 0
        while let sample = readerOutput.copyNextSampleBuffer() {
            // Shift every frame so the cut starts at zero.
            var timing = CMSampleTimingInfo()
            CMSampleBufferGetSampleTimingInfo(sample, at: 0, timingInfoOut: &timing)
            timing.presentationTimeStamp = CMTimeSubtract(timing.presentationTimeStamp, startTime)
            timing.decodeTimeStamp = .invalid
            var shifted: CMSampleBuffer?
            CMSampleBufferCreateCopyWithNewTiming(allocator: nil, sampleBuffer: sample, sampleTimingEntryCount: 1, sampleTimingArray: &timing, sampleBufferOut: &shifted)
            while !input.isReadyForMoreMediaData { usleep(2000) }
            input.append(shifted!)
            frames += 1
        }
        input.markAsFinished()
        await writer.finishWriting()
        guard writer.status == .completed else { throw writer.error ?? CocoaError(.fileWriteUnknown) }

        let encoded = AVURLAsset(url: output)
        let duration = try await encoded.load(.duration)
        let generator = AVAssetImageGenerator(asset: encoded)
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero
        let lastFrame = CMTimeSubtract(duration, CMTime(value: 1, timescale: CMTimeScale(fps.rounded())))
        for (name, time) in [("joker-reveal-start", CMTime.zero), ("joker-reveal-end", lastFrame)] {
            let (image, _) = try await generator.image(at: time)
            let jpeg = NSBitmapImageRep(cgImage: image).representation(using: .jpeg, properties: [.compressionFactor: 0.88])!
            try jpeg.write(to: folder.appendingPathComponent("\(name).jpg"))
        }
        let bytes = (try FileManager.default.attributesOfItem(atPath: output.path)[.size] as? Int) ?? 0
        print("frames \(frames), \(Int(renderSize.width))x\(Int(renderSize.height)), \(String(format: "%.3f", duration.seconds)) s, \(bytes / 1024) KB")
    } catch {
        print("failed: \(error)")
    }
    done.signal()
}
done.wait()
