import Foundation
import AVFoundation
import Accelerate
import AudioKit
import ID3TagEditor

/// Extracts DJ-relevant metadata from audio files (BPM, key, waveform, etc.)
public class AudioMetadataExtractor {

    // MARK: - Public Methods

    /// Extract complete DJ metadata from audio file
    public func extractMetadata(from url: URL) async throws -> DJTrack {
        let asset = AVAsset(url: url)

        async let bpm = detectBPM(from: url)
        async let key = detectMusicalKey(from: url)
        async let waveform = generateWaveform(from: url)
        async let duration = extractDuration(from: asset)
        async let id3Tags = extractID3Tags(from: url)

        return try await DJTrack(
            id: UUID(),
            url: url,
            title: id3Tags.title ?? url.deletingPathExtension().lastPathComponent,
            artist: id3Tags.artist,
            album: id3Tags.album,
            genre: id3Tags.genre,
            bpm: bpm,
            musicalKey: key,
            duration: duration,
            waveform: waveform,
            cuePoints: [],
            dateAdded: Date()
        )
    }

    /// Detect BPM using beat tracking algorithm
    public func detectBPM(from url: URL) async throws -> Double {
        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    let file = try AVAudioFile(forReading: url)
                    let format = file.processingFormat
                    let frameCount = AVAudioFrameCount(file.length)

                    guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else {
                        throw AudioError.bufferCreationFailed
                    }

                    try file.read(into: buffer)

                    // Use autocorrelation-based BPM detection
                    let bpm = self.calculateBPM(from: buffer)
                    continuation.resume(returning: bpm)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    /// Detect musical key using Krumhansl-Schmuckler algorithm
    public func detectMusicalKey(from url: URL) async throws -> String {
        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    let file = try AVAudioFile(forReading: url)
                    let format = file.processingFormat
                    let frameCount = AVAudioFrameCount(file.length)

                    guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else {
                        throw AudioError.bufferCreationFailed
                    }

                    try file.read(into: buffer)

                    // Detect key and convert to Camelot notation
                    let key = self.detectKey(from: buffer)
                    let camelotKey = self.convertToCamelot(key)
                    continuation.resume(returning: camelotKey)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    /// Generate waveform data for visualization
    public func generateWaveform(from url: URL, samples: Int = 1000) async throws -> [Float] {
        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    let file = try AVAudioFile(forReading: url)
                    let format = file.processingFormat
                    let frameCount = AVAudioFrameCount(file.length)

                    guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else {
                        throw AudioError.bufferCreationFailed
                    }

                    try file.read(into: buffer)

                    let waveform = self.downsampleToWaveform(buffer: buffer, targetSamples: samples)
                    continuation.resume(returning: waveform)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    // MARK: - Private Methods

    private func extractDuration(from asset: AVAsset) async throws -> TimeInterval {
        let duration = try await asset.load(.duration)
        return CMTimeGetSeconds(duration)
    }

    private func extractID3Tags(from url: URL) async throws -> ID3Tags {
        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    let id3TagEditor = ID3TagEditor()

                    guard let id3Tag = try? id3TagEditor.read(from: url.path) else {
                        continuation.resume(returning: ID3Tags())
                        return
                    }

                    let tags = ID3Tags(
                        title: (id3Tag.frames[.title] as? ID3FrameWithStringContent)?.content,
                        artist: (id3Tag.frames[.artist] as? ID3FrameWithStringContent)?.content,
                        album: (id3Tag.frames[.album] as? ID3FrameWithStringContent)?.content,
                        genre: (id3Tag.frames[.genre] as? ID3FrameWithStringContent)?.content
                    )

                    continuation.resume(returning: tags)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    // MARK: - DSP Constants

    private static let fftSize = 4096
    private static let hopSize = 512

    // MARK: - BPM Detection (Onset-based beat tracking)

    /// Detect BPM using spectral flux onset envelope + autocorrelation.
    /// This mirrors librosa's beat_track approach: STFT -> onset strength -> autocorrelation.
    private func calculateBPM(from buffer: AVAudioPCMBuffer) -> Double {
        guard let channelData = buffer.floatChannelData?[0] else { return 0 }
        let frameCount = Int(buffer.frameLength)
        let sampleRate = buffer.format.sampleRate

        let onsetEnvelope = computeOnsetStrength(
            channelData: channelData,
            frameCount: frameCount,
            sampleRate: sampleRate
        )
        guard onsetEnvelope.count > 1 else { return 0 }

        // Autocorrelate the onset envelope to find tempo periodicity
        let minBPM = 60.0
        let maxBPM = 200.0
        let onsetRate = sampleRate / Double(Self.hopSize)

        let minLag = max(1, Int(60.0 / maxBPM * onsetRate))
        let maxLag = min(Int(60.0 / minBPM * onsetRate), onsetEnvelope.count / 2)

        guard minLag < maxLag else { return 0 }

        var maxCorrelation: Float = -.greatestFiniteMagnitude
        var bestLag = minLag

        onsetEnvelope.withUnsafeBufferPointer { bufPtr in
            guard let base = bufPtr.baseAddress else { return }
            for lag in minLag..<maxLag {
                var correlation: Float = 0
                let n = vDSP_Length(onsetEnvelope.count - lag)
                vDSP_dotpr(base, 1, base.advanced(by: lag), 1, &correlation, n)
                if correlation > maxCorrelation {
                    maxCorrelation = correlation
                    bestLag = lag
                }
            }
        }

        return 60.0 * onsetRate / Double(bestLag)
    }

    /// Compute spectral flux onset strength envelope via STFT.
    /// Each value represents the half-wave rectified increase in spectral energy.
    private func computeOnsetStrength(
        channelData: UnsafePointer<Float>,
        frameCount: Int,
        sampleRate: Double
    ) -> [Float] {
        let fftSize = Self.fftSize
        let hopSize = Self.hopSize
        let halfN = fftSize / 2
        let numFrames = (frameCount - fftSize) / hopSize + 1
        guard numFrames > 1 else { return [] }

        var window = [Float](repeating: 0, count: fftSize)
        vDSP_hann_window(&window, vDSP_Length(fftSize), Int32(vDSP_HANN_NORM))

        let log2n = vDSP_Length(log2(Float(fftSize)))
        guard let fftSetup = vDSP_create_fftsetup(log2n, FFTRadix(kFFTRadix2)) else { return [] }
        defer { vDSP_destroy_fftsetup(fftSetup) }

        var prevMagnitudes = [Float](repeating: 0, count: halfN)
        var onsetEnvelope = [Float]()
        onsetEnvelope.reserveCapacity(numFrames)

        var windowedFrame = [Float](repeating: 0, count: fftSize)
        var realp = [Float](repeating: 0, count: halfN)
        var imagp = [Float](repeating: 0, count: halfN)

        for i in 0..<numFrames {
            let offset = i * hopSize

            vDSP_vmul(channelData.advanced(by: offset), 1, window, 1,
                       &windowedFrame, 1, vDSP_Length(fftSize))

            windowedFrame.withUnsafeMutableBufferPointer { ptr in
                ptr.baseAddress!.withMemoryRebound(to: DSPComplex.self, capacity: halfN) { complexPtr in
                    var split = DSPSplitComplex(realp: &realp, imagp: &imagp)
                    vDSP_ctoz(complexPtr, 2, &split, 1, vDSP_Length(halfN))
                }
            }

            var split = DSPSplitComplex(realp: &realp, imagp: &imagp)
            vDSP_fft_zrip(fftSetup, &split, 1, log2n, FFTDirection(FFT_FORWARD))

            var magnitudes = [Float](repeating: 0, count: halfN)
            vDSP_zvmags(&split, 1, &magnitudes, 1, vDSP_Length(halfN))

            // Spectral flux: sum of positive magnitude increases
            var flux: Float = 0
            for j in 0..<halfN {
                let diff = magnitudes[j] - prevMagnitudes[j]
                if diff > 0 { flux += diff }
            }

            onsetEnvelope.append(flux)
            prevMagnitudes = magnitudes
        }

        return onsetEnvelope
    }

    // MARK: - Key Detection (Krumhansl-Schmuckler)

    /// Krumhansl-Schmuckler key profiles for major and minor keys.
    /// Correlation of a chromagram against these profiles determines the key.
    private static let majorProfile: [Float] = [
        6.35, 2.23, 3.48, 2.33, 4.38, 4.09, 2.52, 5.19, 2.39, 3.66, 2.29, 2.88
    ]
    private static let minorProfile: [Float] = [
        6.33, 2.68, 3.52, 5.38, 2.60, 3.53, 2.54, 4.75, 3.98, 2.69, 3.34, 3.17
    ]

    /// Chromatic note order matching chroma bin indices 0-11.
    private static let noteOrder: [MusicalKey.Note] = [
        .C, .CSharp, .D, .DSharp, .E, .F, .FSharp, .G, .GSharp, .A, .ASharp, .B
    ]

    /// Detect musical key using chromagram + Krumhansl-Schmuckler profile correlation.
    /// This mirrors librosa's chroma_cqt + K-S correlation approach.
    private func detectKey(from buffer: AVAudioPCMBuffer) -> MusicalKey {
        guard let channelData = buffer.floatChannelData?[0] else {
            return MusicalKey(note: .C, scale: .major)
        }
        let frameCount = Int(buffer.frameLength)
        let sampleRate = buffer.format.sampleRate

        let chroma = computeChromagram(
            channelData: channelData,
            frameCount: frameCount,
            sampleRate: sampleRate
        )
        guard chroma.count == 12 else {
            return MusicalKey(note: .C, scale: .major)
        }

        // Normalize chroma distribution
        let chromaSum = chroma.reduce(0, +)
        guard chromaSum > 0 else { return MusicalKey(note: .C, scale: .major) }
        let normalizedChroma = chroma.map { $0 / chromaSum }

        // Test all 12 major and 12 minor key profiles via Pearson correlation
        var bestCorrelation: Float = -.greatestFiniteMagnitude
        var bestNote = 0
        var bestScale: MusicalKey.Scale = .major

        for i in 0..<12 {
            let majorRotated = normalizeProfile(rotateProfile(Self.majorProfile, by: i))
            let minorRotated = normalizeProfile(rotateProfile(Self.minorProfile, by: i))

            let majorCorr = pearsonCorrelation(normalizedChroma, majorRotated)
            let minorCorr = pearsonCorrelation(normalizedChroma, minorRotated)

            if majorCorr > bestCorrelation {
                bestCorrelation = majorCorr
                bestNote = i
                bestScale = .major
            }
            if minorCorr > bestCorrelation {
                bestCorrelation = minorCorr
                bestNote = i
                bestScale = .minor
            }
        }

        return MusicalKey(note: Self.noteOrder[bestNote], scale: bestScale)
    }

    /// Compute a 12-bin chromagram by mapping FFT magnitude bins to pitch classes.
    private func computeChromagram(
        channelData: UnsafePointer<Float>,
        frameCount: Int,
        sampleRate: Double
    ) -> [Float] {
        let fftSize = Self.fftSize
        let hopSize = Self.hopSize
        let halfN = fftSize / 2
        let numFrames = (frameCount - fftSize) / hopSize + 1
        guard numFrames > 0 else { return [] }

        var window = [Float](repeating: 0, count: fftSize)
        vDSP_hann_window(&window, vDSP_Length(fftSize), Int32(vDSP_HANN_NORM))

        let log2n = vDSP_Length(log2(Float(fftSize)))
        guard let fftSetup = vDSP_create_fftsetup(log2n, FFTRadix(kFFTRadix2)) else { return [] }
        defer { vDSP_destroy_fftsetup(fftSetup) }

        // Pre-compute mapping from FFT bin index to pitch class (0-11)
        let freqPerBin = sampleRate / Double(fftSize)
        var binToChroma = [Int](repeating: -1, count: halfN)
        for bin in 1..<halfN {
            let freq = Double(bin) * freqPerBin
            guard freq >= 27.5, freq <= 4186.0 else { continue } // A0 to C8
            let midiNote = 12.0 * log2(freq / 440.0) + 69.0
            binToChroma[bin] = ((Int(round(midiNote)) % 12) + 12) % 12
        }

        var chromaAccum = [Float](repeating: 0, count: 12)
        var windowedFrame = [Float](repeating: 0, count: fftSize)
        var realp = [Float](repeating: 0, count: halfN)
        var imagp = [Float](repeating: 0, count: halfN)

        for i in 0..<numFrames {
            let offset = i * hopSize

            vDSP_vmul(channelData.advanced(by: offset), 1, window, 1,
                       &windowedFrame, 1, vDSP_Length(fftSize))

            windowedFrame.withUnsafeMutableBufferPointer { ptr in
                ptr.baseAddress!.withMemoryRebound(to: DSPComplex.self, capacity: halfN) { complexPtr in
                    var split = DSPSplitComplex(realp: &realp, imagp: &imagp)
                    vDSP_ctoz(complexPtr, 2, &split, 1, vDSP_Length(halfN))
                }
            }

            var split = DSPSplitComplex(realp: &realp, imagp: &imagp)
            vDSP_fft_zrip(fftSetup, &split, 1, log2n, FFTDirection(FFT_FORWARD))

            var magnitudes = [Float](repeating: 0, count: halfN)
            vDSP_zvmags(&split, 1, &magnitudes, 1, vDSP_Length(halfN))

            for bin in 0..<halfN {
                let pitchClass = binToChroma[bin]
                if pitchClass >= 0 {
                    chromaAccum[pitchClass] += magnitudes[bin]
                }
            }
        }

        let divisor = Float(numFrames)
        return chromaAccum.map { $0 / divisor }
    }

    /// Rotate a 12-element profile array right by `amount` positions (matching numpy.roll).
    private func rotateProfile(_ profile: [Float], by amount: Int) -> [Float] {
        let n = profile.count
        return (0..<n).map { profile[($0 - amount + n) % n] }
    }

    /// Normalize a profile so its elements sum to 1.
    private func normalizeProfile(_ profile: [Float]) -> [Float] {
        let sum = profile.reduce(0, +)
        guard sum > 0 else { return profile }
        return profile.map { $0 / sum }
    }

    /// Pearson correlation coefficient between two equal-length arrays.
    private func pearsonCorrelation(_ x: [Float], _ y: [Float]) -> Float {
        let n = Float(x.count)
        let meanX = x.reduce(0, +) / n
        let meanY = y.reduce(0, +) / n

        var numerator: Float = 0
        var denomX: Float = 0
        var denomY: Float = 0

        for i in 0..<x.count {
            let dx = x[i] - meanX
            let dy = y[i] - meanY
            numerator += dx * dy
            denomX += dx * dx
            denomY += dy * dy
        }

        let denom = sqrt(denomX * denomY)
        guard denom > 0 else { return 0 }
        return numerator / denom
    }

    private func convertToCamelot(_ key: MusicalKey) -> String {
        // Camelot Wheel notation conversion.
        // Includes both sharp and flat enharmonic equivalents so that
        // noteOrder (which uses sharps) always finds a match.
        let camelotWheel: [MusicalKey: String] = [
            MusicalKey(note: .C, scale: .major): "8B",
            MusicalKey(note: .A, scale: .minor): "8A",
            MusicalKey(note: .G, scale: .major): "9B",
            MusicalKey(note: .E, scale: .minor): "9A",
            MusicalKey(note: .D, scale: .major): "10B",
            MusicalKey(note: .B, scale: .minor): "10A",
            MusicalKey(note: .A, scale: .major): "11B",
            MusicalKey(note: .FSharp, scale: .minor): "11A",
            MusicalKey(note: .E, scale: .major): "12B",
            MusicalKey(note: .CSharp, scale: .minor): "12A",
            MusicalKey(note: .B, scale: .major): "1B",
            MusicalKey(note: .GSharp, scale: .minor): "1A",
            MusicalKey(note: .FSharp, scale: .major): "2B",
            MusicalKey(note: .DSharp, scale: .minor): "2A",
            MusicalKey(note: .DFlat, scale: .major): "3B",
            MusicalKey(note: .CSharp, scale: .major): "3B",  // enharmonic
            MusicalKey(note: .BFlat, scale: .minor): "3A",
            MusicalKey(note: .ASharp, scale: .minor): "3A",  // enharmonic
            MusicalKey(note: .AFlat, scale: .major): "4B",
            MusicalKey(note: .GSharp, scale: .major): "4B",  // enharmonic
            MusicalKey(note: .F, scale: .minor): "4A",
            MusicalKey(note: .EFlat, scale: .major): "5B",
            MusicalKey(note: .DSharp, scale: .major): "5B",  // enharmonic
            MusicalKey(note: .C, scale: .minor): "5A",
            MusicalKey(note: .BFlat, scale: .major): "6B",
            MusicalKey(note: .ASharp, scale: .major): "6B",  // enharmonic
            MusicalKey(note: .G, scale: .minor): "6A",
            MusicalKey(note: .F, scale: .major): "7B",
            MusicalKey(note: .D, scale: .minor): "7A",
        ]

        return camelotWheel[key] ?? "8B"
    }

    /// Generate waveform using RMS (root mean square) per bin for smoother,
    /// more perceptually accurate visualization than peak amplitude.
    private func downsampleToWaveform(buffer: AVAudioPCMBuffer, targetSamples: Int) -> [Float] {
        guard let channelData = buffer.floatChannelData?[0] else { return [] }
        let frameCount = Int(buffer.frameLength)
        let samplesPerBin = frameCount / targetSamples

        var waveform = [Float]()
        waveform.reserveCapacity(targetSamples)

        for i in 0..<targetSamples {
            let start = i * samplesPerBin
            let end = min(start + samplesPerBin, frameCount)
            let count = end - start
            guard count > 0 else {
                waveform.append(0)
                continue
            }

            var sumOfSquares: Float = 0
            vDSP_svesq(channelData.advanced(by: start), 1, &sumOfSquares, vDSP_Length(count))
            waveform.append(sqrt(sumOfSquares / Float(count)))
        }

        return waveform
    }
}

// MARK: - Models

/// Complete DJ track information
public struct DJTrack: Identifiable, Codable {
    public let id: UUID
    public let url: URL
    public let title: String
    public let artist: String?
    public let album: String?
    public let genre: String?
    public let bpm: Double
    public let musicalKey: String
    public let duration: TimeInterval
    public let waveform: [Float]
    public var cuePoints: [CuePoint]
    public let dateAdded: Date

    public init(
        id: UUID,
        url: URL,
        title: String,
        artist: String?,
        album: String?,
        genre: String?,
        bpm: Double,
        musicalKey: String,
        duration: TimeInterval,
        waveform: [Float],
        cuePoints: [CuePoint],
        dateAdded: Date
    ) {
        self.id = id
        self.url = url
        self.title = title
        self.artist = artist
        self.album = album
        self.genre = genre
        self.bpm = bpm
        self.musicalKey = musicalKey
        self.duration = duration
        self.waveform = waveform
        self.cuePoints = cuePoints
        self.dateAdded = dateAdded
    }
}

/// Cue point for DJ mixing
public struct CuePoint: Identifiable, Codable {
    public let id: UUID
    public let name: String
    public let timeInSeconds: Double
    public let color: CuePointColor

    public init(id: UUID = UUID(), name: String, timeInSeconds: Double, color: CuePointColor) {
        self.id = id
        self.name = name
        self.timeInSeconds = timeInSeconds
        self.color = color
    }
}

public enum CuePointColor: String, Codable {
    case red, orange, yellow, green, blue, purple, pink
}

/// Musical key representation
public struct MusicalKey: Hashable {
    public let note: Note
    public let scale: Scale

    public enum Note: String {
        case C, CSharp = "C#", DFlat = "Db", D, DSharp = "D#", EFlat = "Eb"
        case E, F, FSharp = "F#", GFlat = "Gb", G, GSharp = "G#", AFlat = "Ab"
        case A, ASharp = "A#", BFlat = "Bb", B
    }

    public enum Scale: String {
        case major, minor
    }
}

/// ID3 tag information
public struct ID3Tags {
    public let title: String?
    public let artist: String?
    public let album: String?
    public let genre: String?

    public init(title: String? = nil, artist: String? = nil, album: String? = nil, genre: String? = nil) {
        self.title = title
        self.artist = artist
        self.album = album
        self.genre = genre
    }
}

/// Audio processing errors
public enum AudioError: LocalizedError {
    case fileNotFound
    case bufferCreationFailed
    case processingFailed(String)

    public var errorDescription: String? {
        switch self {
        case .fileNotFound:
            return "Audio file not found"
        case .bufferCreationFailed:
            return "Failed to create audio buffer"
        case .processingFailed(let message):
            return "Audio processing failed: \(message)"
        }
    }
}
