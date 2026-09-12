import SwiftUI
import VMSCore

/// §7-1/§8 "共通の数値入力"/"複数選択時は共通値と混在値を区別する": every property
/// control in the inspector reads/writes across the *current selection* (one clip or
/// many) through one of these, instead of each control re-deriving "is this a multi-
/// select, are the values mixed, is the clip locked" logic itself.
extension ProjectStore {
    /// For continuously-updating controls (sliders/number fields): the setter applies the
    /// value across the selection but does *not* push undo history itself — the control
    /// calls `beginUndoableChange()` once per drag/edit session (see
    /// `NumericPropertyControl`), not once per intermediate value.
    func numericBinding(get: @escaping (Clip) -> Double, set: @escaping (inout Clip, Double) -> Void) -> Binding<Double?> {
        Binding<Double?>(
            get: {
                let clips = self.selectedClips
                guard let first = clips.first else { return nil }
                let firstValue = get(first)
                return clips.allSatisfy { abs(get($0) - firstValue) < 0.0001 } ? firstValue : nil
            },
            set: { newValue in
                guard let newValue else { return }
                for var clip in self.selectedClips where !clip.isLocked {
                    set(&clip, newValue)
                    self.updateClip(clip)
                }
            }
        )
    }

    /// For discrete controls (toggle/picker/color): each `set` call is a complete user
    /// action on its own, so it pushes one undo step per call.
    func mixedBinding<Value: Equatable>(get: @escaping (Clip) -> Value, set: @escaping (inout Clip, Value) -> Void) -> Binding<Value?> {
        Binding<Value?>(
            get: {
                let clips = self.selectedClips
                guard let first = clips.first else { return nil }
                let firstValue = get(first)
                return clips.allSatisfy { get($0) == firstValue } ? firstValue : nil
            },
            set: { newValue in
                guard let newValue else { return }
                self.beginUndoableChange()
                for var clip in self.selectedClips where !clip.isLocked {
                    set(&clip, newValue)
                    self.updateClip(clip)
                }
            }
        )
    }
}
