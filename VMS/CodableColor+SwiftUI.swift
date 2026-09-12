import SwiftUI
import VMSCore

extension CodableColor {
    var color: Color { Color(red: red, green: green, blue: blue, opacity: alpha) }

    init(_ color: Color) {
        let resolved = color.resolve(in: EnvironmentValues())
        self.init(red: Double(resolved.red), green: Double(resolved.green), blue: Double(resolved.blue), alpha: Double(resolved.opacity))
    }
}
