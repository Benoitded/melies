import CoreGraphics
import CoreImage
import Foundation

/// How strong the motion blur is during zoom and pan transitions (export only).
enum MotionBlurLevel: String, CaseIterable {
    case off, light, strong

    static let `default` = MotionBlurLevel.light

    /// Virtual shutter time in seconds: the camera travel during this interval is smeared.
    var shutter: Double {
        switch self {
        case .off: return 0
        case .light: return 1.0 / 60
        case .strong: return 1.0 / 30
        }
    }

    /// Largest blur radius at 1920 px wide output, in pixels.
    var maxRadius1080: Double {
        switch self {
        case .off: return 0
        case .light: return 12
        case .strong: return 24
        }
    }

    var labelKey: String { "exp.motionblur.\(rawValue)" }

    static var current: MotionBlurLevel {
        MotionBlurLevel(rawValue: UserDefaults.standard.string(forKey: Pref.motionBlur) ?? "") ?? .default
    }
}

/// Camera speed: log-scale change per second, and normalized center displacement per second.
struct CameraVelocity: Equatable {
    var logScale: Double
    var center: CGVector

    static let zero = CameraVelocity(logScale: 0, center: .zero)
}

/// What to draw for one frame (all lengths in output pixels).
struct MotionBlurParams: Equatable {
    var zoomAmount: Double
    var panRadius: Double
    /// Radians, Core Image convention (y up).
    var panAngle: Double
}

enum MotionBlur {
    /// Smears shorter than this many pixels are skipped (no extra pass).
    static let minimumPixels = 0.75

    /// Central difference of the camera around `t`. Exactly zero when the camera does not move.
    static func velocity(at t: Double, points: [ZoomPoint], dt: Double = 1.0 / 120) -> CameraVelocity {
        guard dt > 0, !points.isEmpty else { return .zero }
        let a = ZoomCamera.state(at: t - dt, points: points)
        let b = ZoomCamera.state(at: t + dt, points: points)
        return CameraVelocity(
            logScale: (log(b.scale) - log(a.scale)) / (2 * dt),
            center: CGVector(dx: (b.center.x - a.center.x) / (2 * dt), dy: (b.center.y - a.center.y) / (2 * dt))
        )
    }

    /// Largest radius allowed for an output `canvas` (scales with the output width).
    static func maxRadius(level: MotionBlurLevel, canvas: CGSize) -> Double {
        level.maxRadius1080 * Double(canvas.width) / 1920
    }

    /// nil when nothing should be drawn (blur off or camera still).
    static func params(velocity v: CameraVelocity, scale: Double, content: CGSize, canvas: CGSize, level: MotionBlurLevel) -> MotionBlurParams? {
        guard level != .off else { return nil }
        let cap = maxRadius(level: level, canvas: canvas)
        // Pan: the picture moves by (center speed x zoom) of the content per second.
        let px = v.center.dx * scale * Double(content.width)
        let py = v.center.dy * scale * Double(content.height)
        let pan = min(hypot(px, py) * level.shutter, cap)
        // Zoom: points at the corner travel (log-scale speed x half diagonal) per second.
        let halfDiagonal = 0.5 * hypot(Double(content.width), Double(content.height))
        let zoom = min(abs(v.logScale) * halfDiagonal * level.shutter, cap)
        let panOn = pan >= minimumPixels
        let zoomOn = zoom >= minimumPixels
        guard panOn || zoomOn else { return nil }
        return MotionBlurParams(zoomAmount: zoomOn ? zoom : 0, panRadius: panOn ? pan : 0, panAngle: atan2(-py, px))
    }

    /// CIZoomBlur's amount is not in pixels: measured, an amount of 1 smears roughly 6 px at the edge.
    static let zoomBlurGain = 1.0 / 6

    /// Smears `image` (the picture, canvas coordinates, bottom-left origin) and keeps its extent.
    static func apply(_ params: MotionBlurParams, to image: CIImage, center: CGPoint) -> CIImage {
        let extent = image.extent
        var result = image.clampedToExtent()
        if params.zoomAmount > 0 {
            result = result.applyingFilter("CIZoomBlur", parameters: [
                kCIInputCenterKey: CIVector(x: center.x, y: center.y), kCIInputAmountKey: params.zoomAmount * zoomBlurGain,
            ])
        }
        if params.panRadius > 0 {
            result = result.clampedToExtent().applyingFilter("CIMotionBlur", parameters: [
                kCIInputRadiusKey: params.panRadius, kCIInputAngleKey: params.panAngle,
            ])
        }
        return result.cropped(to: extent)
    }
}
