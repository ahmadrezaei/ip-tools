// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Ahmad Rezaei

import SharedUI
import SwiftUI

/// Presets, limits and validation for the ping count (DESIGN §4.3.1). `nil` means "until stopped".
enum PingCount {
    static let presets: [Int] = [5, 10, 20, 50, 100]
    static let range = 1...10_000

    /// The count when it is not one of the presets, else nil.
    static func customValue(_ count: Int?) -> Int? {
        guard let count, !presets.contains(count) else { return nil }
        return count
    }

    /// An integer inside `range`, otherwise nil.
    static func validated(_ text: String) -> Int? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let value = Int(trimmed), range.contains(value) else { return nil }
        return value
    }

    /// True when the text is an integer above the upper limit (the alert shows a warning).
    static func exceedsLimit(_ text: String) -> Bool {
        guard let value = Int(text.trimmingCharacters(in: .whitespacesAndNewlines)) else { return false }
        return value > range.upperBound
    }

    /// Progress shown in the run header: "3 of 10", or "3 sent" for until stopped.
    static func progress(sent: Int, count: Int?) -> String {
        if let count { return String(localized: "\(sent) of \(count)") }
        return String(localized: "\(sent) sent")
    }

    static func label(_ count: Int?) -> String {
        guard let count else { return String(localized: "Until stopped") }
        if count == 1 { return String(localized: "1 ping", comment: "Ping count chip, singular") }
        return String(localized: "\(count) pings", comment: "Ping count chip, plural")
    }
}

extension View {
    /// The "Number of Pings" alert shared by the chip and Ping Settings.
    func pingCountAlert(isPresented: Binding<Bool>, count: Binding<Int?>) -> some View {
        modifier(PingCountAlert(isPresented: isPresented, count: count))
    }
}

private struct PingCountAlert: ViewModifier {
    @Binding var isPresented: Bool
    @Binding var count: Int?
    @AppStorage("ping.lastCustomCount") private var lastCustom = 0
    @State private var text = ""

    func body(content: Content) -> some View {
        content
            .alert("Number of Pings", isPresented: $isPresented) {
                TextField(PingCount.exceedsLimit(text) ? "Maximum is 10,000" : "Number", text: $text)
                    #if os(iOS)
                    .keyboardType(.numberPad)
                    #endif
                Button("Set") {
                    if let value = PingCount.validated(text) {
                        lastCustom = value
                        count = value
                    }
                }
                .disabled(PingCount.validated(text) == nil)
                Button("Cancel", role: .cancel) {}
            } message: {
                Text(PingCount.exceedsLimit(text) ? "Too many: enter a number between 1 and 10,000." : "Between 1 and 10,000.")
            }
            .onChange(of: isPresented) {
                guard isPresented else { return }
                let seed = lastCustom > 0 ? lastCustom : PingCount.customValue(count)
                text = seed.map(String.init) ?? ""
            }
    }
}

/// The count chip under the target bar: a capsule `Menu` bound to `SettingsStore.ping.count`.
struct PingCountMenu: View {
    @Binding var count: Int?
    let isDisabled: Bool
    @State private var showCustom = false

    var body: some View {
        Menu {
            Picker("Ping count", selection: $count) {
                ForEach(PingCount.presets, id: \.self) { value in
                    Text(PingCount.label(value)).tag(Optional(value))
                }
                Text("Until stopped").tag(Optional<Int>.none)
                if let custom = PingCount.customValue(count) {
                    Text("Custom (\(custom))").tag(Optional(custom))
                }
            }
            .pickerStyle(.inline)
            Divider()
            Button("Custom…") { showCustom = true }
        } label: {
            HStack(spacing: 4) {
                Text(PingCount.label(count))
                Image(systemName: "chevron.down").font(.caption2.weight(.bold))
                    .opacity(isDisabled ? 0 : 1)
            }
            .font(.footnote.weight(.semibold))
            .foregroundStyle(isDisabled ? Color.secondary : Color.accentColor)
            .padding(.horizontal, 12)
            .frame(minHeight: 32)
            .background(Color.fieldFill, in: Capsule())
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .disabled(isDisabled)
        .pingCountAlert(isPresented: $showCustom, count: $count)
        .accessibilityLabel("Ping count, \(PingCount.label(count))")
        .accessibilityHint(isDisabled ? "Available when ping is stopped." : "Double-tap to change.")
    }
}

#Preview {
    @Previewable @State var count: Int? = 10
    return VStack(alignment: .leading) {
        PingCountMenu(count: $count, isDisabled: false)
        PingCountMenu(count: .constant(37), isDisabled: true)
    }
    .padding()
}
