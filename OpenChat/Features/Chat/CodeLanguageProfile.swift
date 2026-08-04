import Foundation

struct LanguageProfile: Equatable {
    var keywords: Set<String>
    var typeNames: Set<String>
    var lineCommentPattern: String?
    var blockCommentPattern: String?
    var stringPatterns: [String]
    var highlightCapitalizedTypes: Bool
    var caseInsensitiveKeywords: Bool

    static func profile(for language: String?) -> LanguageProfile {
        switch normalize(language) {
        case "swift": return .swift
        case "python", "py": return .python
        case "javascript", "js", "jsx", "typescript", "ts", "tsx": return .javaScriptFamily
        case "json": return .json
        case "bash", "sh", "shell", "zsh": return .shell
        case "html", "xml", "svg": return .markup
        case "css", "scss": return .css
        case "sql": return .sql
        case "go", "golang": return .go
        case "rust", "rs": return .rust
        case "java": return .java
        case "kotlin", "kt": return .kotlin
        case "c", "cpp", "c++", "cc", "objc", "objectivec", "objective-c": return .cFamily
        case "ruby", "rb": return .ruby
        case "yaml", "yml": return .yaml
        default: return .generic
        }
    }

    static func normalize(_ language: String?) -> String {
        (language ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
    }

    private static let cStyleStrings = [
        #""(?:\\.|[^"\\])*""#,
        #"'(?:\\.|[^'\\])*'"#,
    ]

    private static let cStyleComments = (
        line: #"//[^\n]*"#,
        block: #"/\*[\s\S]*?\*/"#
    )

    static let generic = LanguageProfile(
        keywords: [],
        typeNames: [],
        lineCommentPattern: #"//[^\n]*|#[^\n]*"#,
        blockCommentPattern: cStyleComments.block,
        stringPatterns: cStyleStrings,
        highlightCapitalizedTypes: false,
        caseInsensitiveKeywords: false
    )

    static let swift = LanguageProfile(
        keywords: [
            "associatedtype", "class", "deinit", "enum", "extension", "fileprivate", "func", "import",
            "init", "inout", "internal", "let", "open", "operator", "private", "protocol", "public",
            "rethrows", "static", "struct", "subscript", "typealias", "var", "break", "case", "catch",
            "continue", "default", "defer", "do", "else", "fallthrough", "for", "guard", "if", "in",
            "repeat", "return", "throw", "switch", "where", "while", "as", "any", "async", "await",
            "false", "is", "nil", "self", "Self", "super", "throws", "true", "try", "some", "nonisolated",
            "actor", "consuming", "borrowing", "package", "macro",
        ],
        typeNames: [
            "String", "Int", "Double", "Float", "Bool", "Character", "Array", "Dictionary", "Set",
            "Optional", "Result", "Error", "Data", "URL", "UUID", "Date", "CGFloat", "Any", "AnyObject",
            "Void", "Never",
        ],
        lineCommentPattern: cStyleComments.line,
        blockCommentPattern: cStyleComments.block,
        stringPatterns: [
            #""""[\s\S]*?""""#,
            #""(?:\\.|[^"\\])*""#,
        ],
        highlightCapitalizedTypes: true,
        caseInsensitiveKeywords: false
    )

    static let python = LanguageProfile(
        keywords: [
            "False", "None", "True", "and", "as", "assert", "async", "await", "break", "class",
            "continue", "def", "del", "elif", "else", "except", "finally", "for", "from", "global",
            "if", "import", "in", "is", "lambda", "nonlocal", "not", "or", "pass", "raise", "return",
            "try", "while", "with", "yield", "match", "case",
        ],
        typeNames: [
            "int", "float", "str", "bool", "list", "dict", "set", "tuple", "bytes", "object", "type",
            "Exception", "ValueError", "TypeError", "KeyError",
        ],
        lineCommentPattern: #"#[^\n]*"#,
        blockCommentPattern: nil,
        stringPatterns: [
            #"'''[\s\S]*?'''"#,
            #""""[\s\S]*?""""#,
            #""(?:\\.|[^"\\])*""#,
            #"'(?:\\.|[^'\\])*'"#,
            #"f"(?:\\.|[^"\\])*""#,
            #"f'(?:\\.|[^'\\])*'"#,
        ],
        highlightCapitalizedTypes: true,
        caseInsensitiveKeywords: false
    )

    static let javaScriptFamily = LanguageProfile(
        keywords: [
            "await", "break", "case", "catch", "class", "const", "continue", "debugger", "default",
            "delete", "do", "else", "enum", "export", "extends", "false", "finally", "for", "function",
            "if", "implements", "import", "in", "instanceof", "interface", "let", "new", "null",
            "package", "private", "protected", "public", "return", "super", "switch", "static", "this",
            "throw", "true", "try", "typeof", "var", "void", "while", "with", "yield", "async", "of",
            "from", "as", "type", "namespace", "readonly", "satisfies", "keyof", "infer",
        ],
        typeNames: [
            "string", "number", "boolean", "any", "unknown", "never", "void", "object", "Array",
            "Promise", "Map", "Set", "Date", "Error", "Record",
        ],
        lineCommentPattern: cStyleComments.line,
        blockCommentPattern: cStyleComments.block,
        stringPatterns: [
            #"`(?:\\.|[^`\\])*`"#,
            #""(?:\\.|[^"\\])*""#,
            #"'(?:\\.|[^'\\])*'"#,
        ],
        highlightCapitalizedTypes: true,
        caseInsensitiveKeywords: false
    )

    static let json = LanguageProfile(
        keywords: ["true", "false", "null"],
        typeNames: [],
        lineCommentPattern: nil,
        blockCommentPattern: nil,
        stringPatterns: [#""(?:\\.|[^"\\])*""#],
        highlightCapitalizedTypes: false,
        caseInsensitiveKeywords: false
    )

    static let shell = LanguageProfile(
        keywords: [
            "if", "then", "else", "elif", "fi", "for", "while", "do", "done", "case", "esac", "function",
            "return", "in", "select", "until", "time", "coproc", "export", "local", "readonly", "declare",
            "typeset", "unset", "shift", "eval", "exec", "exit", "trap", "wait", "source",
        ],
        typeNames: [],
        lineCommentPattern: #"#[^\n]*"#,
        blockCommentPattern: nil,
        stringPatterns: cStyleStrings + [#"`[^`]*`"#],
        highlightCapitalizedTypes: false,
        caseInsensitiveKeywords: false
    )

    static let markup = LanguageProfile(
        keywords: [],
        typeNames: [],
        lineCommentPattern: nil,
        blockCommentPattern: #"<!--[\s\S]*?-->"#,
        stringPatterns: [
            #""(?:\\.|[^"\\])*""#,
            #"'(?:\\.|[^'\\])*'"#,
            #"</?[A-Za-z][\w:-]*"#,
            #"/?>"#,
        ],
        highlightCapitalizedTypes: false,
        caseInsensitiveKeywords: false
    )

    static let css = LanguageProfile(
        keywords: [
            "important", "from", "to", "and", "or", "not", "only", "screen", "media", "supports",
            "keyframes", "var",
        ],
        typeNames: [],
        lineCommentPattern: nil,
        blockCommentPattern: cStyleComments.block,
        stringPatterns: cStyleStrings,
        highlightCapitalizedTypes: false,
        caseInsensitiveKeywords: true
    )

    static let sql = LanguageProfile(
        keywords: [
            "select", "from", "where", "insert", "into", "values", "update", "set", "delete", "create",
            "table", "alter", "drop", "join", "left", "right", "inner", "outer", "on", "as", "and",
            "or", "not", "null", "true", "false", "order", "by", "group", "having", "limit", "offset",
            "distinct", "union", "all", "primary", "key", "foreign", "references", "index", "view",
            "with", "case", "when", "then", "else", "end", "in", "is", "between", "like", "exists",
        ],
        typeNames: [
            "int", "integer", "bigint", "smallint", "text", "varchar", "char", "boolean", "bool",
            "date", "timestamp", "numeric", "decimal", "float", "real", "json", "uuid",
        ],
        lineCommentPattern: #"--[^\n]*"#,
        blockCommentPattern: cStyleComments.block,
        stringPatterns: [
            #"'((?:''|[^'])*)'"#,
            #""(?:\\.|[^"\\])*""#,
        ],
        highlightCapitalizedTypes: false,
        caseInsensitiveKeywords: true
    )

    static let go = LanguageProfile(
        keywords: [
            "break", "case", "chan", "const", "continue", "default", "defer", "else", "fallthrough",
            "for", "func", "go", "goto", "if", "import", "interface", "map", "package", "range",
            "return", "select", "struct", "switch", "type", "var", "true", "false", "nil", "iota",
        ],
        typeNames: [
            "string", "bool", "byte", "rune", "error", "int", "int8", "int16", "int32", "int64",
            "uint", "uint8", "uint16", "uint32", "uint64", "float32", "float64", "complex64",
            "complex128", "any",
        ],
        lineCommentPattern: cStyleComments.line,
        blockCommentPattern: cStyleComments.block,
        stringPatterns: [
            #"`[^`]*`"#,
            #""(?:\\.|[^"\\])*""#,
            #"'\\.?.'"#,
        ],
        highlightCapitalizedTypes: true,
        caseInsensitiveKeywords: false
    )

    static let rust = LanguageProfile(
        keywords: [
            "as", "async", "await", "break", "const", "continue", "crate", "dyn", "else", "enum",
            "extern", "false", "fn", "for", "if", "impl", "in", "let", "loop", "match", "mod",
            "move", "mut", "pub", "ref", "return", "self", "Self", "static", "struct", "super",
            "trait", "true", "type", "unsafe", "use", "where", "while", "yield",
        ],
        typeNames: [
            "i8", "i16", "i32", "i64", "i128", "isize", "u8", "u16", "u32", "u64", "u128", "usize",
            "f32", "f64", "bool", "char", "str", "String", "Vec", "Option", "Result", "Box",
        ],
        lineCommentPattern: cStyleComments.line,
        blockCommentPattern: cStyleComments.block,
        stringPatterns: [
            #"r#*"[^"]*"#*"#,
            #""(?:\\.|[^"\\])*""#,
            #"'(?:\\.|[^'\\])*'"#,
        ],
        highlightCapitalizedTypes: true,
        caseInsensitiveKeywords: false
    )

    static let java = LanguageProfile(
        keywords: [
            "abstract", "assert", "boolean", "break", "byte", "case", "catch", "char", "class",
            "const", "continue", "default", "do", "double", "else", "enum", "extends", "final",
            "finally", "float", "for", "goto", "if", "implements", "import", "instanceof", "int",
            "interface", "long", "native", "new", "package", "private", "protected", "public",
            "return", "short", "static", "strictfp", "super", "switch", "synchronized", "this",
            "throw", "throws", "transient", "try", "void", "volatile", "while", "true", "false",
            "null", "var", "yield", "record", "sealed", "permits", "non-sealed",
        ],
        typeNames: [
            "String", "Integer", "Boolean", "Double", "Float", "Long", "Object", "List", "Map",
            "Set", "Optional", "Exception",
        ],
        lineCommentPattern: cStyleComments.line,
        blockCommentPattern: cStyleComments.block,
        stringPatterns: [
            #""""[\s\S]*?""""#,
            #""(?:\\.|[^"\\])*""#,
            #"'(?:\\.|[^'\\])*'"#,
        ],
        highlightCapitalizedTypes: true,
        caseInsensitiveKeywords: false
    )

    static let kotlin = LanguageProfile(
        keywords: [
            "as", "break", "class", "continue", "do", "else", "false", "for", "fun", "if", "in",
            "interface", "is", "null", "object", "package", "return", "super", "this", "throw",
            "true", "try", "typealias", "typeof", "val", "var", "when", "while", "by", "catch",
            "constructor", "delegate", "dynamic", "field", "file", "finally", "get", "import",
            "init", "param", "property", "receiver", "set", "setparam", "where", "actual",
            "abstract", "annotation", "companion", "const", "crossinline", "data", "enum",
            "expect", "external", "final", "infix", "inline", "inner", "internal", "lateinit",
            "noinline", "open", "operator", "out", "override", "private", "protected", "public",
            "reified", "sealed", "suspend", "tailrec", "vararg",
        ],
        typeNames: [
            "String", "Int", "Long", "Double", "Float", "Boolean", "Char", "Byte", "Short", "Unit",
            "Any", "Nothing", "List", "Map", "Set", "Array",
        ],
        lineCommentPattern: cStyleComments.line,
        blockCommentPattern: cStyleComments.block,
        stringPatterns: [
            #""""[\s\S]*?""""#,
            #""(?:\\.|[^"\\])*""#,
            #"'(?:\\.|[^'\\])*'"#,
        ],
        highlightCapitalizedTypes: true,
        caseInsensitiveKeywords: false
    )

    static let cFamily = LanguageProfile(
        keywords: [
            "auto", "break", "case", "char", "const", "continue", "default", "do", "double", "else",
            "enum", "extern", "float", "for", "goto", "if", "inline", "int", "long", "register",
            "restrict", "return", "short", "signed", "sizeof", "static", "struct", "switch",
            "typedef", "union", "unsigned", "void", "volatile", "while", "_Bool", "_Complex",
            "class", "namespace", "template", "typename", "using", "public", "private", "protected",
            "virtual", "override", "nullptr", "true", "false", "new", "delete", "try", "catch",
            "throw", "this", "friend", "operator", "explicit", "constexpr", "consteval", "concept",
            "requires", "co_await", "co_return", "co_yield",
        ],
        typeNames: [
            "bool", "size_t", "ssize_t", "uint8_t", "uint16_t", "uint32_t", "uint64_t", "int8_t",
            "int16_t", "int32_t", "int64_t", "string", "vector", "map", "set", "optional",
        ],
        lineCommentPattern: cStyleComments.line,
        blockCommentPattern: cStyleComments.block,
        stringPatterns: cStyleStrings,
        highlightCapitalizedTypes: true,
        caseInsensitiveKeywords: false
    )

    static let ruby = LanguageProfile(
        keywords: [
            "alias", "and", "begin", "break", "case", "class", "def", "defined?", "do", "else",
            "elsif", "end", "ensure", "false", "for", "if", "in", "module", "next", "nil", "not",
            "or", "redo", "rescue", "retry", "return", "self", "super", "then", "true", "undef",
            "unless", "until", "when", "while", "yield", "require", "include", "extend", "attr_reader",
            "attr_writer", "attr_accessor",
        ],
        typeNames: ["String", "Integer", "Float", "Array", "Hash", "Symbol", "NilClass", "TrueClass", "FalseClass"],
        lineCommentPattern: #"#[^\n]*"#,
        blockCommentPattern: #"=begin[\s\S]*?=end"#,
        stringPatterns: [
            #""(?:\\.|[^"\\])*""#,
            #"'(?:\\.|[^'\\])*'"#,
            #"%[qQwW]?\{(?:\\.|[^\}])*\}"#,
        ],
        highlightCapitalizedTypes: true,
        caseInsensitiveKeywords: false
    )

    static let yaml = LanguageProfile(
        keywords: ["true", "false", "null", "yes", "no", "on", "off"],
        typeNames: [],
        lineCommentPattern: #"#[^\n]*"#,
        blockCommentPattern: nil,
        stringPatterns: [
            #""(?:\\.|[^"\\])*""#,
            #"'(?:\\.|[^'\\])*'"#,
        ],
        highlightCapitalizedTypes: false,
        caseInsensitiveKeywords: true
    )
}
