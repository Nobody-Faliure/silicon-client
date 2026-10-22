import Foundation

enum Language {
	static var sentences: [String: String] = [:]
	
	static func load(from file: URL) {
		sentences = (try? JSONDecoder().decode([String: String].self, from: Data(contentsOf: file))) ?? [:]
	}
	
	static func plainText(_ tag: NBTTag) -> String {
		switch tag {
		case .string(let text): return text
		case .byte(let n), .short(let n), .int(let n), .long(let n): return String(n)
		case .compound(let fields): return compoundText(fields)
		default: return ""
		}
	}
	
	static func compoundText(_ fields: [String: NBTTag]) -> String {
		var result = ""
		if case .string(let text)? = fields["text"] { result += text }
		if let wrapped = fields[""] { result += plainText(wrapped) }
		if case .string(let key)? = fields["translate"] { result += translate(key, fields["with"]) }
		if case .list(let parts)? = fields["extra"] { for part in parts { result += plainText(part) } }
		return result
	}
	
	static func translate(_ key: String, _ with: NBTTag?) -> String {
		var sentence = sentences[key] ?? key
		guard case .list(let values)? = with else { return sentence }
		for (i, value) in values.enumerated() {
			let filled = plainText(value)
			sentence = sentence.replacingOccurrences(of: "%\(i + 1)$s", with: filled)
			if let gap = sentence.range(of: "%s") { sentence.replaceSubrange(gap, with: filled) }
		}
		return sentence
	}
}
