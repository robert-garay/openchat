import Foundation

/// A model-drafted skill awaiting user review (or already saved, when confirmation is off).
struct SkillProposal: Equatable, Identifiable, Sendable {
    var id = UUID()
    var name: String
    var slashName: String
    var description: String
    var instructions: String
}

/// Tool-calling surface for skills — `invoke_skill` (auto-invoke) and `create_skill` (skill-builder).
/// Mirrors WebSearchService's shape. Only ever registered for `model.supportsTools == true`;
/// there is no text-parsing fallback, matching the web-search tool-calling path.
enum SkillToolService {
    static let invokeToolName = "invoke_skill"
    static let createToolName = "create_skill"

    static func invokeToolDefinition() -> ChatToolDefinition {
        ChatToolDefinition(
            name: invokeToolName,
            description: """
            Invoke one of the user's saved OpenChat skills by its slash name to load its \
            instructions into this conversation. Use when the user's request matches a skill's \
            purpose, even if they didn't type the /slash-name themselves.
            """,
            parametersJSON: """
            {
              "type": "object",
              "properties": {
                "slash_name": {
                  "type": "string",
                  "description": "The skill's slash name, without the leading slash."
                }
              },
              "required": ["slash_name"]
            }
            """
        )
    }

    static func createToolDefinition() -> ChatToolDefinition {
        ChatToolDefinition(
            name: createToolName,
            description: """
            Draft a new OpenChat skill for the user to review and save. Use when the user asks you \
            to build/save a skill, or when following the skill-builder's instructions.
            """,
            parametersJSON: """
            {
              "type": "object",
              "properties": {
                "name": {
                  "type": "string",
                  "description": "Short display name for the skill."
                },
                "slash_name": {
                  "type": "string",
                  "description": "Lowercase slash name (letters, numbers, hyphens), without the leading slash."
                },
                "description": {
                  "type": "string",
                  "description": "One-sentence summary of what the skill does."
                },
                "instructions": {
                  "type": "string",
                  "description": "Full instructions the model should follow whenever this skill is invoked."
                }
              },
              "required": ["name", "slash_name", "instructions"]
            }
            """
        )
    }

    static func slashName(fromInvokeArguments argumentsJSON: String) -> String? {
        guard let data = argumentsJSON.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let slashName = object["slash_name"] as? String
        else {
            return nil
        }
        let trimmed = slashName.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    static func proposal(fromCreateArguments argumentsJSON: String) -> SkillProposal? {
        guard let data = argumentsJSON.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let name = (object["name"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
              let slashName = object["slash_name"] as? String,
              let instructions = (object["instructions"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !name.isEmpty, !instructions.isEmpty
        else {
            return nil
        }
        let normalizedSlashName = SkillResolver.normalizeSlashName(slashName)
        guard !normalizedSlashName.isEmpty, !SkillResolver.isReservedSlashName(normalizedSlashName) else { return nil }
        let description = (object["description"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return SkillProposal(name: name, slashName: normalizedSlashName, description: description, instructions: instructions)
    }
}
