import Foundation

/// The keys of the user's preferences (UserDefaults), written once. A typo in a string literal used to silently
/// create a second setting; now the compiler catches it. Used by @AppStorage and by UserDefaults alike.
enum Pref {
    static let recordMicrophone = "recordMicrophone"
    static let recordSystemAudio = "recordSystemAudio"
    static let recordCountdown = "recordCountdown"
    static let watchedFolder = "watchedFolder"
    static let showClicks = "showClicks"
    static let clickColor = "clickColor"
    static let clickSize = "clickSize"
    static let openEditorAfterRecording = "openEditorAfterRecording"
    static let closeAfterAction = "closeAfterAction"
    static let alwaysOnTop = "alwaysOnTop"
    static let toolPanelCollapsed = "toolPanelCollapsed"
    static let exportFormat = "exportFormat"
    static let exportMaxMB = "exportMaxMB"
    static let exportMaxWidth = "exportMaxWidth"
    static let mcpEnabled = "mcpEnabled"
    static let mcpPort = "mcpPort"
    static let autoZoomStrength = "autoZoomStrength"
}
