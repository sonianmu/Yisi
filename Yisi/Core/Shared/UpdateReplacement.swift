import Foundation

/// Arguments are positional so app names containing quotes or spaces remain literal.
enum UpdateReplacement {
    static let script = """
    sleep "$5"
    app="$1"
    staged="$2"
    dmg="$3"
    backup="${app}.update-backup"
    [ -d "$staged" ] && [ -d "$app" ] && [ ! -e "$backup" ] || exit 1
    mv "$app" "$backup" || exit 1
    if ! mv "$staged" "$app"; then
        mv "$backup" "$app"
        exit 1
    fi
    if "$4" -n "$app"; then
        rm -rf "$backup"
        rm -f "$dmg"
    else
        mv "$app" "$staged"
        mv "$backup" "$app"
        "$4" -n "$app"
        exit 1
    fi
    """

    static func arguments(appPath: String, stagingPath: String, dmgPath: String,
                          launcher: String = "/usr/bin/open", delay: String = "1") -> [String] {
        ["-c", script, "yisi-update", appPath, stagingPath, dmgPath, launcher, delay]
    }
}
