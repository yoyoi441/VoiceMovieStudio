import SwiftUI
import VMSCore

/// §7-5: gradient kind, a live preview strip, and per-stop add/remove/move/recolor. Edits
/// write straight into the effect's `GradientEffect`, which `CompositeFrameView` reads via
/// `Text.foregroundStyle` — so this preview and the actual rendered text always agree.
struct GradientEditor: View {
    @Environment(ProjectStore.self) private var store
    let clip: Clip
    let effectID: UUID
    let gradient: GradientEffect

    @State private var selectedStopID: UUID?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("種類").font(Theme.labelFont).foregroundColor(.secondary).frame(width: 64, alignment: .leading)
                Picker("", selection: kindBinding) {
                    ForEach(GradientKind.allCases, id: \.self) { kind in
                        Text(kind.displayName).tag(kind)
                    }
                }
                .labelsHidden()
            }

            preview
                .frame(height: 28)
                .overlay(RoundedRectangle(cornerRadius: 3).strokeBorder(Theme.border))
                .overlay(stopHandles)

            HStack {
                Button {
                    addStop()
                } label: {
                    IconCatalog.resolve(.addStop).font(.system(size: 10))
                }
                .buttonStyle(.plain)
                .help("ストップの追加")

                Button {
                    removeSelectedStop()
                } label: {
                    IconCatalog.resolve(.removeStop).font(.system(size: 10))
                }
                .buttonStyle(.plain)
                .disabled(gradient.stops.count <= 2 || selectedStopID == nil)
                .help("ストップの削除")

                Spacer()
            }

            if let stop = gradient.stops.first(where: { $0.id == selectedStopID }) {
                NumericPropertyControl(label: "位置", value: positionBinding(for: stop.id), range: 0...1, decimalPlaces: 2)
                ColorPropertyControl(label: "色", value: colorBinding(for: stop.id))
            }
        }
        .onAppear {
            if selectedStopID == nil { selectedStopID = gradient.stops.first?.id }
        }
    }

    private var preview: some View {
        let stops = gradient.stops.map { Gradient.Stop(color: $0.color.color, location: $0.position) }
        return LinearGradient(stops: stops, startPoint: .leading, endPoint: .trailing)
            .cornerRadius(3)
    }

    private var stopHandles: some View {
        GeometryReader { proxy in
            ForEach(gradient.stops) { stop in
                Circle()
                    .fill(stop.color.color)
                    .frame(width: 12, height: 12)
                    .overlay(Circle().strokeBorder(selectedStopID == stop.id ? Theme.selectionBorder : .white, lineWidth: 2))
                    .position(x: stop.position * proxy.size.width, y: proxy.size.height / 2)
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                selectedStopID = stop.id
                                let position = min(1, max(0, value.location.x / proxy.size.width))
                                moveStop(stop.id, to: position)
                            }
                    )
            }
        }
    }

    private var kindBinding: Binding<GradientKind> {
        Binding(
            get: { gradient.kind },
            set: { newValue in
                store.beginUndoableChange()
                mutateGradient { $0.kind = newValue }
            }
        )
    }

    private func addStop() {
        store.beginUndoableChange()
        mutateGradient { grad in
            let newStop = GradientColorStop(position: 0.5, color: .white)
            grad.stops.append(newStop)
            grad.stops.sort { $0.position < $1.position }
            selectedStopID = newStop.id
        }
    }

    private func removeSelectedStop() {
        guard let id = selectedStopID, gradient.stops.count > 2 else { return }
        store.beginUndoableChange()
        mutateGradient { $0.stops.removeAll { $0.id == id } }
        selectedStopID = nil
    }

    private func moveStop(_ id: UUID, to position: Double) {
        mutateGradient { grad in
            guard let index = grad.stops.firstIndex(where: { $0.id == id }) else { return }
            grad.stops[index].position = position
        }
    }

    private func positionBinding(for stopID: UUID) -> Binding<Double?> {
        Binding(
            get: { gradient.stops.first { $0.id == stopID }?.position },
            set: { newValue in
                guard let newValue else { return }
                mutateGradient { grad in
                    guard let index = grad.stops.firstIndex(where: { $0.id == stopID }) else { return }
                    grad.stops[index].position = min(1, max(0, newValue))
                }
            }
        )
    }

    private func colorBinding(for stopID: UUID) -> Binding<CodableColor?> {
        Binding(
            get: { gradient.stops.first { $0.id == stopID }?.color },
            set: { newValue in
                guard let newValue else { return }
                store.beginUndoableChange()
                mutateGradient { grad in
                    guard let index = grad.stops.firstIndex(where: { $0.id == stopID }) else { return }
                    grad.stops[index].color = newValue
                }
            }
        )
    }

    private func mutateGradient(_ mutate: (inout GradientEffect) -> Void) {
        var updated = clip
        guard let index = updated.effects.effectsList.firstIndex(where: { $0.id == effectID }),
              case .gradient(var grad) = updated.effects.effectsList[index].kind else { return }
        mutate(&grad)
        updated.effects.effectsList[index].kind = .gradient(grad)
        store.updateClip(updated)
    }
}
