// Builds an .mp4 (H.264 video + AAC audio) from the frames and the soundtrack of a movie run, with AVFoundation and nothing else (no ffmpeg on the machine): docs/audio-capture.md.
//
//   swiftc -O tools/make_mp4.swift -o /tmp/make_mp4
//   /tmp/make_mp4 FRAMES_DIR AUDIO.wav OUT.mp4 FIRST LAST [WIDTH] [BITRATE_KBPS]
//
// FRAMES_DIR holds f000000.jpg... (tools/avi_extract.py --range=FIRST,LAST); the video is frames FIRST..LAST at 30 fps, the audio is the file from FIRST/30 seconds to LAST/30,
// so that picture and sound start together (the first seconds of a run are the loading card: FIRST is where the clip begins). WIDTH defaults to 1280 (the height follows, 16:9).
import AVFoundation
import CoreGraphics
import CoreVideo
import Foundation
import ImageIO

func fail(_ message: String) -> Never {
    FileHandle.standardError.write((message + "\n").data(using: .utf8)!)
    exit(1)
}

let args = CommandLine.arguments
if args.count < 6 { fail("usage: make_mp4 FRAMES_DIR AUDIO.wav OUT.mp4 FIRST LAST [WIDTH] [BITRATE_KBPS]") }
let framesDir = args[1]
let audioPath = args[2]
let outPath = args[3]
guard let first = Int(args[4]), let last = Int(args[5]) else { fail("FIRST and LAST are frame numbers") }
let width = args.count > 6 ? (Int(args[6]) ?? 1280) : 1280
let height = width * 9 / 16
let kbps = args.count > 7 ? (Int(args[7]) ?? 3500) : 3500
let fps: Int32 = 30

try? FileManager.default.removeItem(atPath: outPath)
guard let writer = try? AVAssetWriter(outputURL: URL(fileURLWithPath: outPath), fileType: .mp4) else { fail("cannot open the output") }

let videoSettings: [String: Any] = [
    AVVideoCodecKey: AVVideoCodecType.h264,
    AVVideoWidthKey: width,
    AVVideoHeightKey: height,
    AVVideoCompressionPropertiesKey: [AVVideoAverageBitRateKey: kbps * 1000, AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel, AVVideoMaxKeyFrameIntervalKey: 60],
]
let videoIn = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
videoIn.expectsMediaDataInRealTime = false
let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: videoIn, sourcePixelBufferAttributes: [
    kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA, kCVPixelBufferWidthKey as String: width, kCVPixelBufferHeightKey as String: height,
])
writer.add(videoIn)

let audioSettings: [String: Any] = [AVFormatIDKey: kAudioFormatMPEG4AAC, AVNumberOfChannelsKey: 2, AVSampleRateKey: 48000, AVEncoderBitRateKey: 160_000]
let audioIn = AVAssetWriterInput(mediaType: .audio, outputSettings: audioSettings)
audioIn.expectsMediaDataInRealTime = false
writer.add(audioIn)

// the soundtrack, from FIRST/30 s
let audioAsset = AVURLAsset(url: URL(fileURLWithPath: audioPath))
guard let audioTrack = audioAsset.tracks(withMediaType: .audio).first else { fail("no audio track in the wav") }
guard let reader = try? AVAssetReader(asset: audioAsset) else { fail("cannot read the wav") }
let start = CMTime(value: CMTimeValue(first), timescale: CMTimeScale(fps))
let length = CMTime(value: CMTimeValue(last - first + 1), timescale: CMTimeScale(fps))
reader.timeRange = CMTimeRange(start: start, duration: length)
let readerOut = AVAssetReaderTrackOutput(track: audioTrack, outputSettings: [
    AVFormatIDKey: kAudioFormatLinearPCM, AVLinearPCMBitDepthKey: 16, AVLinearPCMIsFloatKey: false, AVLinearPCMIsBigEndianKey: false, AVLinearPCMIsNonInterleaved: false,
    AVNumberOfChannelsKey: 2, AVSampleRateKey: 48000,
])
reader.add(readerOut)
reader.startReading()

writer.startWriting()
writer.startSession(atSourceTime: .zero)

func pixelBuffer(for path: String) -> CVPixelBuffer? {
    guard let src = CGImageSourceCreateWithURL(URL(fileURLWithPath: path) as CFURL, nil), let image = CGImageSourceCreateImageAtIndex(src, 0, nil) else { return nil }
    var pb: CVPixelBuffer?
    guard let pool = adaptor.pixelBufferPool, CVPixelBufferPoolCreatePixelBuffer(nil, pool, &pb) == kCVReturnSuccess, let buffer = pb else { return nil }
    CVPixelBufferLockBaseAddress(buffer, [])
    defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
    guard let ctx = CGContext(data: CVPixelBufferGetBaseAddress(buffer), width: width, height: height, bitsPerComponent: 8, bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
                              space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue) else { return nil }
    ctx.interpolationQuality = .high
    ctx.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
    return buffer
}

let group = DispatchGroup()
let videoQueue = DispatchQueue(label: "video")
let audioQueue = DispatchQueue(label: "audio")
var frame = first

group.enter()
videoIn.requestMediaDataWhenReady(on: videoQueue) {
    while videoIn.isReadyForMoreMediaData {
        if frame > last {
            videoIn.markAsFinished()
            group.leave()
            return
        }
        let path = String(format: "%@/f%06d.jpg", framesDir, frame)
        guard let buffer = pixelBuffer(for: path) else { fail("cannot read " + path) }
        let time = CMTime(value: CMTimeValue(frame - first), timescale: CMTimeScale(fps))
        if !adaptor.append(buffer, withPresentationTime: time) { fail("cannot append frame \(frame): \(String(describing: writer.error))") }
        frame += 1
    }
}

group.enter()
audioIn.requestMediaDataWhenReady(on: audioQueue) {
    while audioIn.isReadyForMoreMediaData {
        if let sample = readerOut.copyNextSampleBuffer() {
            // (the reader's times begin at FIRST/30 s: moved back to zero, so that the sound starts with the picture)
            var timing = CMSampleTimingInfo()
            CMSampleBufferGetSampleTimingInfo(sample, at: 0, timingInfoOut: &timing)
            var shifted = timing
            shifted.presentationTimeStamp = CMTimeSubtract(timing.presentationTimeStamp, start)
            shifted.decodeTimeStamp = .invalid
            var copy: CMSampleBuffer?
            CMSampleBufferCreateCopyWithNewTiming(allocator: nil, sampleBuffer: sample, sampleTimingEntryCount: 1, sampleTimingArray: &shifted, sampleBufferOut: &copy)
            if let copy = copy { audioIn.append(copy) }
        } else {
            audioIn.markAsFinished()
            group.leave()
            return
        }
    }
}

group.notify(queue: .main) {
    writer.finishWriting {
        if writer.status == .completed {
            print("wrote \(outPath)")
            exit(0)
        }
        fail("failed: \(String(describing: writer.error))")
    }
}
dispatchMain()
