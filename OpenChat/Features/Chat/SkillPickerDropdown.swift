import SwiftUI

struct SkillPickerDropdown: View {
    let skills: [SkillMatchable]
    let onSelect: (SkillMatchable) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(skills.enumerated()), id: \.offset) { index, skill in
                Button { onSelect(skill) } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "bolt.fill").foregroundStyle(Color.accentColor)
                            .frame(width: 28, height: 28)
                            .background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 7))
                        VStack(alignment: .leading, spacing: 2) {
                            Text("/\(skill.slashName)").font(.body.weight(.medium))
                            if !skill.name.isEmpty, skill.name.lowercased() != skill.slashName {
                                Text(skill.name).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                            }
                        }
                        Spacer(minLength: 8)
                    }
                    .padding(.horizontal, 14).padding(.vertical, 10).contentShape(Rectangle())
                }.buttonStyle(.plain)
                if index < skills.count - 1 { Divider().padding(.leading, 54) }
            }
        }
        .padding(.vertical, 6).frame(minWidth: 240, maxWidth: 320)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.12), radius: 8, y: -2)
    }
}
