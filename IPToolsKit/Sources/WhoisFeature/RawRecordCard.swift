// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Ahmad Rezaei

import Foundation
import RIPEstat
import SharedUI
import SwiftUI

/// One key of an object, or a run of lines that read as one paragraph.
struct RawRecordBlock: Identifiable, Hashable {
    let id: Int
    let key: String
    let lines: [String]
    let link: URL?
}

/// How an object's fields are grouped and named (DESIGN §14.10). Pure, so it is tested without views.
enum RawRecordLayout {
    static let collapseThreshold = 6
    private static let paragraphKeys: Set<String> = ["remarks", "Remarks", "Comment", "comment"]

    /// Consecutive lines of `remarks`/`Comment` (and `descr` with more than three lines) become one block.
    static func blocks(_ record: WhoisRecord) -> [RawRecordBlock] {
        let descrCount = record.fields.filter { $0.key == "descr" }.count
        func isParagraph(_ key: String) -> Bool { paragraphKeys.contains(key) || (key == "descr" && descrCount > 3) }
        var blocks: [RawRecordBlock] = []
        var index = 0
        let fields = record.fields
        while index < fields.count {
            let field = fields[index]
            guard isParagraph(field.key) else {
                blocks.append(RawRecordBlock(id: blocks.count, key: field.key, lines: [field.value], link: field.link))
                index += 1
                continue
            }
            var lines: [String] = []
            while index < fields.count, fields[index].key == field.key {
                lines.append(fields[index].value)
                index += 1
            }
            blocks.append(RawRecordBlock(id: blocks.count, key: field.key, lines: lines, link: nil))
        }
        return blocks
    }

    /// "Network · 8.8.8.0/24", "Abuse contact · ABUSE5250-ARIN", "route 8.8.8.0/24".
    static func title(_ record: WhoisRecord) -> String {
        let key = record.primaryKey
        let value = record.primaryValue
        let name: String
        switch key {
        case "NetRange", "inetnum", "inet6num": name = String(localized: "Network")
        case "ASNumber", "aut-num": name = String(localized: "AS")
        case "OrgName": name = String(localized: "Organization")
        case "OrgAbuseHandle", "RAbuseHandle": name = String(localized: "Abuse contact")
        case "OrgTechHandle", "RTechHandle": name = String(localized: "Technical contact")
        case "OrgNOCHandle", "RNOCHandle": name = String(localized: "NOC contact")
        case "OrgRoutingHandle": name = String(localized: "Routing contact")
        default: name = key
        }
        return value.isEmpty ? name : "\(name) · \(value)"
    }

    /// Lines made only of `+ - * = | #` and spaces keep their layout.
    static func isBanner(_ line: String) -> Bool {
        !line.isEmpty && line.allSatisfy { "+-*=|# ".contains($0) } && line.contains { $0 != " " }
    }

    /// The value with links: the record's own link, or e-mail addresses found in the text.
    static func attributed(_ text: String, link: URL?) -> AttributedString {
        var result = AttributedString(text)
        if let link {
            result.link = link
            return result
        }
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else { return result }
        let range = NSRange(text.startIndex..., in: text)
        for match in detector.matches(in: text, range: range) {
            guard let url = match.url, url.scheme == "mailto", let target = Range(match.range, in: result) else { continue }
            result[target].link = url
        }
        return result
    }
}

/// One registry or routing registry object.
struct RawRecordCard: View {
    let record: WhoisRecord
    var isUsedInSummary = false
    var headerSuffix: String?

    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            ForEach(RawRecordLayout.blocks(record)) { block in
                RawRecordRow(block: block, stacked: typeSize >= .accessibility1)
            }
        }
        .padding(.bottom, 6)
        .background(Color.cardBackground, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(RawRecordLayout.title(record) + (headerSuffix.map { " · \($0)" } ?? ""))
                    .font(.subheadline.weight(.semibold))
                    .accessibilityAddTraits(.isHeader)
                if isUsedInSummary {
                    Text("Used in summary").font(.caption2.weight(.semibold)).foregroundStyle(.tint)
                }
            }
            Spacer(minLength: 0)
            Menu {
                Button { Clipboard.copy(WhoisExport.objectLines(record).joined(separator: "\n")) } label: {
                    Label("Copy Object", systemImage: "doc.on.doc")
                }
            } label: {
                Image(systemName: "ellipsis.circle").frame(width: 32, height: 32)
            }
            .accessibilityLabel(Text("Object actions"))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }
}

struct RawRecordRow: View {
    let block: RawRecordBlock
    let stacked: Bool
    @State private var expanded = false

    private var hidden: Int { max(block.lines.count - RawRecordLayout.collapseThreshold, 0) }
    private var visibleLines: [String] {
        expanded || hidden == 0 ? block.lines : Array(block.lines.prefix(RawRecordLayout.collapseThreshold))
    }

    var body: some View {
        Group {
            if stacked {
                VStack(alignment: .leading, spacing: 2) { key; value }
            } else {
                HStack(alignment: .firstTextBaseline, spacing: 8) { key.frame(width: 128, alignment: .leading); value }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 3)
        .contextMenu {
            Button { Clipboard.copy(block.lines.joined(separator: "\n")) } label: { Label("Copy Value", systemImage: "doc.on.doc") }
            Button { Clipboard.copy("\(block.key): " + block.lines.joined(separator: "\n")) } label: {
                Label("Copy \"key: value\"", systemImage: "doc.on.doc.fill")
            }
        }
    }

    private var key: some View {
        Text(block.key).font(.footnote.monospaced()).foregroundStyle(.secondary)
    }

    private var value: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(Array(visibleLines.enumerated()), id: \.offset) { _, line in
                Text(RawRecordLayout.attributed(line.isEmpty ? " " : line, link: block.link))
                    .font(.footnote.monospaced())
                    .textSelection(.enabled)
                    .fixedSize(horizontal: RawRecordLayout.isBanner(line), vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            if hidden > 0 {
                Button(expanded ? String(localized: "Show fewer lines") : String(localized: "Show \(hidden) more lines")) {
                    expanded.toggle()
                }
                .font(.footnote)
                .accessibilityHint(expanded ? "" : String(localized: "\(hidden) more lines"))
            }
        }
    }
}
