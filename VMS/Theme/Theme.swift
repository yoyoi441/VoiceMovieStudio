import SwiftUI

/// Shared design tokens for the editor chrome (toolbar, ruler, timeline, inspector).
/// Not a full design system — just the handful of colors/metrics that were previously
/// hand-rolled per-file (`Color(nsColor: .controlBackgroundColor)`, literal `4`/`36`/`140`
/// everywhere) so new high-density panels stay visually consistent with each other.
enum Theme {
    // MARK: Colors — light-gray desktop editor look, thin borders, pale blue selection.
    static let panelBackground = Color(nsColor: .controlBackgroundColor)
    static let canvasBackground = Color(nsColor: .underPageBackgroundColor)
    static let border = Color.black.opacity(0.12)
    static let borderStrong = Color.black.opacity(0.25)
    static let selectionFill = Color.accentColor.opacity(0.22)
    static let selectionBorder = Color.accentColor
    static let disabledForeground = Color.secondary.opacity(0.5)
    static let disabledFill = Color.gray.opacity(0.12)

    /// Timeline item fill by content kind — distinct, readable at small sizes, matches
    /// the color used for the same kind elsewhere (e.g. add-item toolbar icons).
    static let textItemColor = Color.blue
    static let characterItemColor = Color.green
    static let audioItemColor = Color.orange
    static let imageItemColor = Color.purple
    static let videoItemColor = Color.cyan
    static let unimplementedItemColor = Color.gray

    // MARK: Metrics
    static let toolbarHeight: CGFloat = 32
    static let toolbarSpacing: CGFloat = 4
    static let toolbarGroupSpacing: CGFloat = 10
    static let controlCornerRadius: CGFloat = 4
    static let sectionSpacing: CGFloat = 10
    static let rowHeight: CGFloat = 36
    static let trackHeaderWidth: CGFloat = 140
    static let rulerHeight: CGFloat = 24
    static let sceneTabHeight: CGFloat = 28

    // MARK: Fonts
    static let toolbarFont = Font.system(size: 11)
    static let labelFont = Font.system(size: 11)
    static let valueFont = Font.system(size: 11).monospacedDigit()
}
