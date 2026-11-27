import AppKit

enum MusicScripts {
    // Streaming/radio tracks may omit library fields. Preserve playback state regardless.
    private static let fields = """
    on fieldsForTrack(t)
        tell application id "com.apple.Music"
            set tid to ""
            set tn to ""
            set ta to ""
            set tal to ""
            try
                set tid to persistent ID of t as string
            end try
            try
                set tn to name of t as string
            end try
            try
                set ta to artist of t as string
            end try
            try
                set tal to album of t as string
            end try
            return {tid & "|" & tn & "|" & ta & "|" & tal, tn, ta, tal}
        end tell
    end fieldsForTrack

    """

    static let metadata = fields + """
    with timeout of 5 seconds
        tell application id "com.apple.Music"
            set ps to player state as string
            if ps is "stopped" then return {ps, "", "", "", ""}
            try
                set t to current track
            on error
                return {ps, "", "", "", ""}
            end try
            set trackFields to my fieldsForTrack(t)
            return {ps} & trackFields
        end tell
    end timeout
    """

    static let artwork = fields + """
    with timeout of 3 seconds
        tell application id "com.apple.Music"
            set t to current track
            set trackFields to my fieldsForTrack(t)
            set trackKey to item 1 of trackFields
            if (count of artworks of t) > 0 then return {trackKey, raw data of artwork 1 of t}
            return {trackKey, ""}
        end tell
    end timeout
    """

    static func validate() throws {
        for source in [metadata, artwork] {
            var error: NSDictionary?
            guard NSAppleScript(source: source)?.compileAndReturnError(&error) == true else {
                throw NSError(domain: "MusicGlow.AppleScript", code: 1, userInfo: [NSLocalizedDescriptionKey: error?.description ?? "Invalid script"])
            }
        }
    }
}
