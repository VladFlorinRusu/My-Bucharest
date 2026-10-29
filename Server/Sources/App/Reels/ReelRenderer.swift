import Foundation

/// Asamblează cu ffmpeg un reel vertical 1080x1920: fiecare fotografie apare pe un fundal
/// estompat, cu zoom lent (efect Ken Burns) și tranziții fade, peste vocea generată.
enum ReelRenderer {
    static let width = 1080
    static let height = 1920
    static let fps = 30
    static let fade = 0.6
    static let tail = 0.8
    static let minSecondsPerPhoto = 3.5

    /// Câte fotografii încap, ca fiecare să stea pe ecran cel puțin `minSecondsPerPhoto`.
    static func photoCount(available: Int, duration: Double) -> Int {
        max(1, min(available, Int(duration / minSecondsPerPhoto)))
    }

    /// Durata fiecărui segment, astfel încât segmentele suprapuse prin fade să acopere `total`.
    static func segmentDuration(total: Double, count: Int) -> Double {
        (total + Double(count - 1) * fade) / Double(count)
    }

    /// Momentul de start al fiecărei tranziții `xfade` din lanț.
    static func transitionOffsets(segment: Double, count: Int) -> [Double] {
        (1..<max(count, 1)).map { Double($0) * (segment - fade) }
    }

    static func audioDuration(_ file: URL) throws -> Double {
        let output = try ProcessRunner.run("ffprobe", [
            "-v", "error", "-show_entries", "format=duration", "-of", "csv=p=0", file.path,
        ])
        guard let duration = Double(output.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            throw ProcessRunner.Failure(tool: "ffprobe", status: 0, output: "durată invalidă: \(output)")
        }
        return duration
    }

    /// Un cadru din reel, ca miniatură verticală pentru lista de povești salvate.
    static func extractThumbnail(from video: URL, to output: URL) throws {
        try ProcessRunner.run("ffmpeg", [
            "-y", "-loglevel", "error", "-nostats",
            "-ss", "1.5", "-i", video.path,
            "-frames:v", "1", "-vf", "scale=540:-2", "-q:v", "4",
            output.path,
        ])
    }

    /// Convertește vocea în AAC mono, cu volum normalizat pentru telefon.
    static func normalizeAudio(_ input: URL, to output: URL) throws {
        try ProcessRunner.run("ffmpeg", [
            "-y", "-loglevel", "error", "-nostats",
            "-i", input.path,
            "-af", "loudnorm=I=-16:TP=-1.5:LRA=11",
            "-ac", "1", "-c:a", "aac", "-b:a", "128k",
            output.path,
        ])
    }

    static func render(photos: [URL], audio: URL, output: URL) throws {
        precondition(!photos.isEmpty)
        let total = try audioDuration(audio) + tail
        let count = photoCount(available: photos.count, duration: total)
        let images = Array(photos.prefix(count))
        let segment = segmentDuration(total: total, count: count)
        let frames = Int((segment * Double(fps)).rounded(.up))

        var arguments = ["-y", "-loglevel", "error", "-nostats"]
        for image in images {
            arguments += ["-i", image.path]
        }
        arguments += ["-i", audio.path]

        var filters: [String] = []
        for index in images.indices {
            let zoom = index.isMultiple(of: 2)
                ? "min(zoom+0.0007,1.15)"
                : "if(lte(zoom,1.0),1.15,max(1.001,zoom-0.0007))"
            filters += [
                "[\(index):v]split=2[bgsrc\(index)][fgsrc\(index)]",
                "[bgsrc\(index)]scale=\(width):\(height):force_original_aspect_ratio=increase,crop=\(width):\(height),gblur=sigma=40,eq=brightness=-0.08[bg\(index)]",
                "[fgsrc\(index)]scale=\(width):\(height):force_original_aspect_ratio=decrease[fg\(index)]",
                "[bg\(index)][fg\(index)]overlay=(W-w)/2:(H-h)/2,scale=\(width * 2):\(height * 2),"
                    + "zoompan=z='\(zoom)':d=\(frames):x='iw/2-(iw/zoom/2)':y='ih/2-(ih/zoom/2)':s=\(width)x\(height):fps=\(fps),"
                    + "setsar=1,format=yuv420p[v\(index)]",
            ]
        }

        var last = "v0"
        for (step, offset) in transitionOffsets(segment: segment, count: count).enumerated() {
            let next = "x\(step + 1)"
            filters.append("[\(last)][v\(step + 1)]xfade=transition=fade:duration=\(fade):offset=\(String(format: "%.3f", offset))[\(next)]")
            last = next
        }
        filters.append("[\(images.count):a]apad[aout]")

        arguments += [
            "-filter_complex", filters.joined(separator: ";"),
            "-map", "[\(last)]", "-map", "[aout]",
            "-t", String(format: "%.3f", total),
            "-c:v", "libx264", "-preset", "medium", "-crf", "22", "-pix_fmt", "yuv420p", "-r", "\(fps)",
            "-c:a", "aac", "-b:a", "128k",
            "-movflags", "+faststart",
            output.path,
        ]
        try ProcessRunner.run("ffmpeg", arguments)
    }
}
