import Foundation

/// Looks up a string in the app bundle (Localization/<lang>.lproj, copied by Scripts/build.sh).
func L(_ key: String) -> String {
    NSLocalizedString(key, comment: "")
}

func L(_ key: String, _ args: CVarArg...) -> String {
    String(format: NSLocalizedString(key, comment: ""), arguments: args)
}
