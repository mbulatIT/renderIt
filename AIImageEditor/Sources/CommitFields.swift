import SwiftUI

/// `TextField` wrapper that holds its edit buffer in local `@State` and only writes back to the
/// caller-supplied binding on `.onSubmit` (Enter) or focus loss. Useful for inspector fields
/// where every per-keystroke mutation would re-render the canvas and snowball into the undo
/// stack. External updates to the bound value (e.g. when the user drags the layer on the
/// canvas) refresh the text — but only while the field isn't focused, so we don't fight a
/// typing user.
struct CommitDoubleField: View {
    let title: String
    @Binding var value: Double
    /// Optional value transform applied at commit time — used by callers to clamp ranges
    /// (e.g. opacity 0…1, corner radius ≥ 0) before writing the result back.
    var clamp: (Double) -> Double = { $0 }
    /// Number of digits to show after the decimal point. Inspector defaults to 0 for "x, y, w,
    /// h"-style fields and 2 for things like opacity.
    var fractionDigits: Int = 0

    @State private var text: String = ""
    @FocusState private var focused: Bool

    var body: some View {
        TextField(title, text: $text)
            .focused($focused)
            .multilineTextAlignment(.trailing)
            .monospacedDigit()
            .onAppear { text = format(value) }
            .onChange(of: value) { newValue in
                // Only refresh the buffer when the user isn't actively editing — otherwise a
                // canvas drag mid-typing would steal their input.
                if !focused { text = format(newValue) }
            }
            .onSubmit { commit() }
            .onChange(of: focused) { isFocused in
                // Focus loss commits the pending edit (or reverts the buffer if it doesn't
                // parse), so clicking elsewhere doesn't silently throw away a typed value.
                if !isFocused { commit() }
            }
    }

    private func commit() {
        if let parsed = Double(text.trimmingCharacters(in: .whitespaces)) {
            let next = clamp(parsed)
            if next != value { value = next }
            text = format(next)
        } else {
            // Unparseable — restore the canonical text from the current value.
            text = format(value)
        }
    }

    private func format(_ v: Double) -> String {
        if fractionDigits == 0 { return String(Int(v.rounded())) }
        return String(format: "%.\(fractionDigits)f", v)
    }
}

/// String flavour of `CommitDoubleField` — commits the text on Enter / focus loss instead of on
/// every keystroke, so renaming a layer is a single undo step (and one canvas re-render) rather
/// than one per character. Empty input is rejected and reverts to the current value.
struct CommitTextField: View {
    let title: String
    @Binding var value: String

    @State private var text: String = ""
    @FocusState private var focused: Bool

    var body: some View {
        TextField(title, text: $text)
            .focused($focused)
            .onAppear { text = value }
            .onChange(of: value) { newValue in
                // Refresh from external changes (selection switch, undo) unless mid-edit.
                if !focused { text = newValue }
            }
            .onSubmit { commit() }
            .onChange(of: focused) { isFocused in
                if !isFocused { commit() }
            }
    }

    private func commit() {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            text = value                       // reject blank names
        } else if trimmed != value {
            value = trimmed
        } else {
            text = value                       // normalise (e.g. trimmed whitespace)
        }
    }
}

/// Integer flavour of `CommitDoubleField`. Same commit semantics; the binding is `Int`.
struct CommitIntField: View {
    let title: String
    @Binding var value: Int
    var clamp: (Int) -> Int = { $0 }

    @State private var text: String = ""
    @FocusState private var focused: Bool

    var body: some View {
        TextField(title, text: $text)
            .focused($focused)
            .multilineTextAlignment(.trailing)
            .monospacedDigit()
            .onAppear { text = String(value) }
            .onChange(of: value) { newValue in
                if !focused { text = String(newValue) }
            }
            .onSubmit { commit() }
            .onChange(of: focused) { isFocused in
                if !isFocused { commit() }
            }
    }

    private func commit() {
        if let parsed = Int(text.trimmingCharacters(in: .whitespaces)) {
            let next = clamp(parsed)
            if next != value { value = next }
            text = String(next)
        } else {
            text = String(value)
        }
    }
}

/// Slider + side text field that commits as a single unit. The slider tracks a local live
/// value continuously, but writes back to the bound value only when the user finishes the drag
/// (`onEditingChanged: false`). The text field commits on Enter / focus loss — same semantics
/// as `CommitDoubleField`. Either path keeps the canvas re-render budget to **one** mutation
/// per gesture instead of one per frame.
struct CommitSlider: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    /// Number of digits to show in the side-readout (and accepted in keyboard input).
    var fractionDigits: Int = 0
    /// Optional value transform applied at commit time. Same role as `CommitDoubleField.clamp`.
    var clamp: (Double) -> Double = { $0 }

    @State private var liveValue: Double = 0
    @State private var text: String = ""
    @FocusState private var fieldFocused: Bool

    var body: some View {
        HStack {
            Text(title)
            Slider(value: $liveValue, in: range, onEditingChanged: { editing in
                if !editing {
                    // Drag released — commit once.
                    let next = clamp(liveValue)
                    if next != value { value = next }
                    text = format(next)
                    liveValue = next
                }
            })
            TextField("", text: $text)
                .focused($fieldFocused)
                .multilineTextAlignment(.trailing)
                .monospacedDigit()
                .frame(width: 56)
                .onSubmit { commitText() }
                .onChange(of: fieldFocused) { focused in
                    if !focused { commitText() }
                }
        }
        .onAppear {
            liveValue = value
            text = format(value)
        }
        .onChange(of: value) { newValue in
            // External update (drag on canvas, undo, etc.) — refresh both views unless the
            // user is actively typing into the side field.
            liveValue = newValue
            if !fieldFocused { text = format(newValue) }
        }
    }

    private func commitText() {
        if let parsed = Double(text.trimmingCharacters(in: .whitespaces)) {
            let next = clamp(parsed.clamped(to: range))
            if next != value { value = next }
            liveValue = next
            text = format(next)
        } else {
            text = format(value)
        }
    }

    private func format(_ v: Double) -> String {
        if fractionDigits == 0 { return String(Int(v.rounded())) }
        return String(format: "%.\(fractionDigits)f", v)
    }
}

private extension Comparable {
    func clamped(to r: ClosedRange<Self>) -> Self {
        if self < r.lowerBound { return r.lowerBound }
        if self > r.upperBound { return r.upperBound }
        return self
    }
}
