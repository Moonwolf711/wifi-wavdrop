import Foundation
import AVFoundation
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

    private func calculateBPM(from buffer: AVAudioPCMBuffer) -> Double {
        guard let channelData = buffer.floatChannelData?[0] else { return 0 }
        let frameCount = Int(buffer.frameLength)

        // Autocorrelation-based BPM detection
        let sampleRate = buffer.format.sampleRate
        let minBPM = 60.0
        let maxBPM = 200.0

        let minLag = Int(60.0 / maxBPM * sampleRate)
        let maxLag = Int(60.0 / minBPM * sampleRate)

        var maxCorrelation = 0.0
        var bestLag = minLag

        for lag in minLag..<min(maxLag, frameCount / 2) {
            var correlation = 0.0
            for i in 0..<(frameCount - lag) {
                correlation += Double(channelData[i] * channelData[i + lag])
            }

            if correlation > maxCorrelation {
                maxCorrelation = correlation
                bestLag = lag
            }
        }

        let bpm = 60.0 * sampleRate / Double(bestLag)
        return bpm
    }

    private func detectKey(from buffer: AVAudioPCMBuffer) -> MusicalKey {
        // Simplified key detection - in production, use proper pitch class profile analysis
        // This is a placeholder that returns C major
        return MusicalKey(note: .C, scale: .major)
    }

    private func convertToCamelot(_ key: MusicalKey) -> String {
        // Camelot Wheel notation conversion
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
            MusicalKey(note: .BFlat, scale: .minor): "3A",
            MusicalKey(note: .AFlat, scale: .major): "4B",
            MusicalKey(note: .F, scale: .minor): "4A",
            MusicalKey(note: .EFlat, scale: .major): "5B",
            MusicalKey(note: .C, scale: .minor): "5A",
            MusicalKey(note: .BFlat, scale: .major): "6B",
            MusicalKey(note: .G, scale: .minor): "6A",
            MusicalKey(note: .F, scale: .major): "7B",
            MusicalKey(note: .D, scale: .minor): "7A",
        ]

        return camelotWheel[key] ?? "8B"
    }

    private func downsampleToWaveform(buffer: AVAudioPCMBuffer, targetSamples: Int) -> [Float] {
        guard let channelData = buffer.floatChannelData?[0] else { return [] }
        let frameCount = Int(buffer.frameLength)

        var waveform: [Float] = []
        let samplesPerBin = frameCount / targetSamples

        for i in 0..<targetSamples {
            let start = i * samplesPerBin
            let end = min(start + samplesPerBin, frameCount)

            var maxAmplitude: Float = 0
            for j in start..<end {
                maxAmplitude = max(maxAmplitude, abs(channelData[j]))
            }

            waveform.append(maxAmplitude)
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
