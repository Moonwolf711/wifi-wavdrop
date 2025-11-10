import Foundation

/// Manages exporting track metadata to various DJ software formats
public class DJExportManager {

    public enum DJSoftware {
        case rekordbox
        case serato
        case traktor
        case virtualDJ
        case enginePrime
    }

    // MARK: - Public Methods

    /// Export track to specified DJ software format
    public func exportTrack(
        _ track: DJTrack,
        to software: DJSoftware,
        outputDirectory: URL
    ) async throws -> URL {
        switch software {
        case .rekordbox:
            return try await exportToRekordbox(track, outputDirectory: outputDirectory)
        case .serato:
            return try await exportToSerato(track, outputDirectory: outputDirectory)
        case .traktor:
            return try await exportToTraktor(track, outputDirectory: outputDirectory)
        case .virtualDJ:
            return try await exportToVirtualDJ(track, outputDirectory: outputDirectory)
        case .enginePrime:
            return try await exportToEnginePrime(track, outputDirectory: outputDirectory)
        }
    }

    /// Export multiple tracks in batch
    public func exportTracks(
        _ tracks: [DJTrack],
        to software: DJSoftware,
        outputDirectory: URL,
        progress: @escaping (Int, Int) -> Void
    ) async throws -> [URL] {
        var exportedURLs: [URL] = []

        for (index, track) in tracks.enumerated() {
            let url = try await exportTrack(track, to: software, outputDirectory: outputDirectory)
            exportedURLs.append(url)
            progress(index + 1, tracks.count)
        }

        return exportedURLs
    }

    // MARK: - Rekordbox Export

    private func exportToRekordbox(_ track: DJTrack, outputDirectory: URL) async throws -> URL {
        // Rekordbox uses XML format
        let xml = generateRekordboxXML(for: track)
        let filename = "\(track.title.sanitizedFilename)_rekordbox.xml"
        let outputURL = outputDirectory.appendingPathComponent(filename)

        try xml.write(to: outputURL, atomically: true, encoding: .utf8)
        return outputURL
    }

    private func generateRekordboxXML(for track: DJTrack) -> String {
        var xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <DJ_PLAYLISTS Version="1.0.0">
          <COLLECTION Entries="1">
            <TRACK TrackID="1" Name="\(track.title.xmlEscaped)"
        """

        if let artist = track.artist {
            xml += " Artist=\"\(artist.xmlEscaped)\""
        }
        if let album = track.album {
            xml += " Album=\"\(album.xmlEscaped)\""
        }
        if let genre = track.genre {
            xml += " Genre=\"\(genre.xmlEscaped)\""
        }

        xml += """

                   Location="file://localhost\(track.url.path.xmlEscaped)"
                   TotalTime="\(Int(track.duration))"
                   AverageBpm="\(String(format: "%.2f", track.bpm))"
                   Tonality="\(track.musicalKey)">
        """

        // Add cue points
        for (index, cue) in track.cuePoints.enumerated() {
            xml += """

                  <POSITION_MARK Name="\(cue.name.xmlEscaped)" Type="0"
                                 Start="\(String(format: "%.3f", cue.timeInSeconds))"
                                 Num="\(index)" />
            """
        }

        // Add beat grid
        xml += """

              <TEMPO Inizio="\(String(format: "%.2f", track.bpm))"
                     Bpm="\(String(format: "%.2f", track.bpm))"
                     Metro="4/4" Battito="1"/>
            </TRACK>
          </COLLECTION>
        </DJ_PLAYLISTS>
        """

        return xml
    }

    // MARK: - Serato Export

    private func exportToSerato(_ track: DJTrack, outputDirectory: URL) async throws -> URL {
        // Serato uses proprietary binary markers in ID3 tags
        // For simplicity, export as Serato CSV format
        let csv = generateSeratoCSV(for: track)
        let filename = "\(track.title.sanitizedFilename)_serato.csv"
        let outputURL = outputDirectory.appendingPathComponent(filename)

        try csv.write(to: outputURL, atomically: true, encoding: .utf8)
        return outputURL
    }

    private func generateSeratoCSV(for track: DJTrack) -> String {
        var csv = "name,artist,album,genre,bpm,key,location,cues\n"

        let cuePoints = track.cuePoints.map { "\($0.name):\(String(format: "%.2f", $0.timeInSeconds))" }.joined(separator: ";")

        csv += """
        "\(track.title.csvEscaped)","\(track.artist?.csvEscaped ?? "")","\(track.album?.csvEscaped ?? "")","\(track.genre?.csvEscaped ?? "")",\(String(format: "%.2f", track.bpm)),"\(track.musicalKey)","\(track.url.path.csvEscaped)","\(cuePoints)"
        """

        return csv
    }

    // MARK: - Traktor Export

    private func exportToTraktor(_ track: DJTrack, outputDirectory: URL) async throws -> URL {
        // Traktor uses NML (Native Instruments Music List) format
        let nml = generateTraktorNML(for: track)
        let filename = "\(track.title.sanitizedFilename)_traktor.nml"
        let outputURL = outputDirectory.appendingPathComponent(filename)

        try nml.write(to: outputURL, atomically: true, encoding: .utf8)
        return outputURL
    }

    private func generateTraktorNML(for track: DJTrack) -> String {
        var nml = """
        <?xml version="1.0" encoding="UTF-8" standalone="no"?>
        <NML VERSION="19">
          <COLLECTION ENTRIES="1">
            <ENTRY TITLE="\(track.title.xmlEscaped)"
        """

        if let artist = track.artist {
            nml += " ARTIST=\"\(artist.xmlEscaped)\""
        }

        nml += """

                   AUDIO_ID="\(track.id.uuidString)"
                   GENRE="\(track.genre?.xmlEscaped ?? "")"
                   BPM="\(String(format: "%.2f", track.bpm))"
                   KEY="\(track.musicalKey)">
              <LOCATION DIR="/:/" FILE="\(track.url.path.xmlEscaped)" VOLUME="" VOLUMEID=""/>
              <MUSICAL_KEY VALUE="\(track.musicalKey)"/>
              <INFO BITRATE="320000" PLAYTIME="\(Int(track.duration))"/>
              <TEMPO BPM="\(String(format: "%.2f", track.bpm))"/>
              <CUE_V2>
        """

        // Add cue points
        for (index, cue) in track.cuePoints.enumerated() {
            nml += """

                    <CUE NAME="\(cue.name.xmlEscaped)"
                         TYPE="0"
                         START="\(String(format: "%.3f", cue.timeInSeconds))"
                         HOTCUE="\(index)"/>
            """
        }

        nml += """

              </CUE_V2>
            </ENTRY>
          </COLLECTION>
        </NML>
        """

        return nml
    }

    // MARK: - Virtual DJ Export

    private func exportToVirtualDJ(_ track: DJTrack, outputDirectory: URL) async throws -> URL {
        // Virtual DJ uses XML database format
        let xml = generateVirtualDJXML(for: track)
        let filename = "\(track.title.sanitizedFilename)_virtualdj.xml"
        let outputURL = outputDirectory.appendingPathComponent(filename)

        try xml.write(to: outputURL, atomically: true, encoding: .utf8)
        return outputURL
    }

    private func generateVirtualDJXML(for track: DJTrack) -> String {
        var xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <VirtualDJ_Database Version="2021">
          <Song FilePath="\(track.url.path.xmlEscaped)"
        """

        xml += """

                Title="\(track.title.xmlEscaped)"
                Artist="\(track.artist?.xmlEscaped ?? "")"
                Genre="\(track.genre?.xmlEscaped ?? "")"
                Bpm="\(String(format: "%.2f", track.bpm))"
                Key="\(track.musicalKey)"
                SongLength="\(String(format: "%.3f", track.duration))">
            <Poi>
        """

        // Add POIs (Points of Interest - VDJ's cue points)
        for (index, cue) in track.cuePoints.enumerated() {
            xml += """

                  <Point Type="cue" Pos="\(String(format: "%.3f", cue.timeInSeconds))"
                         Name="\(cue.name.xmlEscaped)" Num="\(index)"/>
            """
        }

        xml += """

            </Poi>
          </Song>
        </VirtualDJ_Database>
        """

        return xml
    }

    // MARK: - Engine Prime Export

    private func exportToEnginePrime(_ track: DJTrack, outputDirectory: URL) async throws -> URL {
        // Engine Prime uses SQLite database, but we'll export as JSON for simplicity
        let json = try generateEnginePrimeJSON(for: track)
        let filename = "\(track.title.sanitizedFilename)_engineprime.json"
        let outputURL = outputDirectory.appendingPathComponent(filename)

        try json.write(to: outputURL, atomically: true, encoding: .utf8)
        return outputURL
    }

    private func generateEnginePrimeJSON(for track: DJTrack) throws -> String {
        let trackDict: [String: Any] = [
            "id": track.id.uuidString,
            "title": track.title,
            "artist": track.artist ?? "",
            "album": track.album ?? "",
            "genre": track.genre ?? "",
            "bpm": track.bpm,
            "key": track.musicalKey,
            "duration": track.duration,
            "path": track.url.path,
            "cuePoints": track.cuePoints.map { cue in
                [
                    "name": cue.name,
                    "time": cue.timeInSeconds,
                    "color": cue.color.rawValue
                ]
            }
        ]

        let jsonData = try JSONSerialization.data(withJSONObject: trackDict, options: .prettyPrinted)
        return String(data: jsonData, encoding: .utf8) ?? "{}"
    }
}

// MARK: - String Extensions

extension String {
    var xmlEscaped: String {
        return self
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&apos;")
    }

    var csvEscaped: String {
        if self.contains(",") || self.contains("\"") || self.contains("\n") {
            return "\"\(self.replacingOccurrences(of: "\"", with: "\"\""))\""
        }
        return self
    }

    var sanitizedFilename: String {
        let invalidCharacters = CharacterSet(charactersIn: ":/\\?%*|\"<>")
        return self.components(separatedBy: invalidCharacters).joined(separator: "_")
    }
}
