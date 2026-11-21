import Foundation

/// Pure-Swift, 100% crash-proof recursive descent mathematical expression evaluator.
/// Handles operator precedence, parentheses, unary +/-, exponents (^), percentages (%),
/// implicit multiplication (e.g. `2(3+4)`), functions (`sqrt`, `sin`, `cos`, `abs`, `log`, `ln`),
/// and gracefully previews incomplete expressions while typing (e.g. `125 *` -> `125`).
public enum MathEvaluator {
    private enum Token: Equatable {
        case number(Double)
        case op(Character)
        case lparen
        case rparen
        case percent
        case ident(String)
    }

    public static func evaluate(_ rawExpression: String) -> Double? {
        let trimmed = rawExpression.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let cleaned = trimmed
            .replacingOccurrences(of: "×", with: "*")
            .replacingOccurrences(of: "÷", with: "/")
            .replacingOccurrences(of: "−", with: "-")
            .replacingOccurrences(of: ",", with: "")

        var tokens = tokenize(cleaned)
        guard !tokens.isEmpty else { return nil }

        // Auto-trim trailing dangling operators while typing (e.g. "125 +")
        while let last = tokens.last {
            if case .op = last {
                tokens.removeLast()
            } else {
                break
            }
        }
        guard !tokens.isEmpty else { return nil }

        // Auto-balance unclosed parentheses
        let openCount = tokens.filter { $0 == .lparen }.count
        let closeCount = tokens.filter { $0 == .rparen }.count
        if openCount > closeCount {
            for _ in 0..<(openCount - closeCount) {
                tokens.append(.rparen)
            }
        }

        // Insert implicit multiplication (`2(3+4)` -> `2*(3+4)`, `(2)(3)` -> `(2)*(3)`)
        var expanded: [Token] = []
        for tok in tokens {
            if let prev = expanded.last {
                let prevIsVal: Bool = {
                    switch prev {
                    case .number, .rparen, .percent: return true
                    default: return false
                    }
                }()
                let currStartsVal: Bool = {
                    switch tok {
                    case .lparen, .ident: return true
                    default: return false
                    }
                }()
                if prevIsVal && currStartsVal {
                    expanded.append(.op("*"))
                }
            }
            expanded.append(tok)
        }

        var parser = Parser(tokens: expanded)
        guard let result = parser.parseExpression(), parser.isAtEnd, result.isFinite else {
            return nil
        }
        return result
    }

    public static func format(_ value: Double) -> String {
        if value.isNaN || !value.isFinite { return "Error" }
        if abs(value - value.rounded()) < 1e-9 && abs(value) < 1e15 {
            return String(Int64(value.rounded()))
        }
        let formatted = String(format: "%.6f", value)
        var s = formatted
        while s.contains(".") && (s.hasSuffix("0") || s.hasSuffix(".")) {
            s.removeLast()
        }
        return s
    }

    private static func tokenize(_ input: String) -> [Token] {
        var tokens: [Token] = []
        let chars = Array(input)
        var i = 0

        while i < chars.count {
            let c = chars[i]
            if c.isWhitespace {
                i += 1
                continue
            }
            if c.isNumber || c == "." {
                var numStr = ""
                while i < chars.count && (chars[i].isNumber || chars[i] == ".") {
                    numStr.append(chars[i])
                    i += 1
                }
                if let val = Double(numStr) {
                    tokens.append(.number(val))
                } else {
                    return []
                }
                continue
            }
            if c.isLetter {
                var id = ""
                while i < chars.count && chars[i].isLetter {
                    id.append(chars[i])
                    i += 1
                }
                let lower = id.lowercased()
                if lower == "pi" {
                    tokens.append(.number(Double.pi))
                } else if lower == "e" {
                    tokens.append(.number(M_E))
                } else {
                    tokens.append(.ident(lower))
                }
                continue
            }
            switch c {
            case "+", "-", "*", "/", "^":
                tokens.append(.op(c))
            case "(":
                tokens.append(.lparen)
            case ")":
                tokens.append(.rparen)
            case "%":
                tokens.append(.percent)
            default:
                return []
            }
            i += 1
        }
        return tokens
    }

    private struct Parser {
        let tokens: [Token]
        var pos: Int = 0

        var isAtEnd: Bool { pos >= tokens.count }
        var current: Token? { pos < tokens.count ? tokens[pos] : nil }

        mutating func parseExpression() -> Double? {
            guard var lhs = parseTerm() else { return nil }
            while let tok = current, case .op(let ch) = tok, ch == "+" || ch == "-" {
                pos += 1
                guard let rhs = parseTerm() else { return nil }
                lhs = (ch == "+") ? (lhs + rhs) : (lhs - rhs)
            }
            return lhs
        }

        mutating func parseTerm() -> Double? {
            guard var lhs = parsePower() else { return nil }
            while let tok = current, case .op(let ch) = tok, ch == "*" || ch == "/" {
                pos += 1
                guard let rhs = parsePower() else { return nil }
                if ch == "/" {
                    guard abs(rhs) > 1e-15 else { return nil }
                    lhs /= rhs
                } else {
                    lhs *= rhs
                }
            }
            return lhs
        }

        mutating func parsePower() -> Double? {
            guard let base = parseUnary() else { return nil }
            if let tok = current, case .op("^") = tok {
                pos += 1
                guard let exp = parsePower() else { return nil }
                return pow(base, exp)
            }
            return base
        }

        mutating func parseUnary() -> Double? {
            if let tok = current, case .op(let ch) = tok, ch == "+" || ch == "-" {
                pos += 1
                guard let val = parseUnary() else { return nil }
                return ch == "-" ? -val : val
            }
            return parsePostfix()
        }

        mutating func parsePostfix() -> Double? {
            guard var val = parsePrimary() else { return nil }
            while current == .percent {
                pos += 1
                val /= 100.0
            }
            return val
        }

        mutating func parsePrimary() -> Double? {
            guard let tok = current else { return nil }
            switch tok {
            case .number(let v):
                pos += 1
                return v
            case .lparen:
                pos += 1
                guard let inner = parseExpression(), current == .rparen else { return nil }
                pos += 1
                return inner
            case .ident(let fn):
                pos += 1
                guard current == .lparen else { return nil }
                pos += 1
                guard let arg = parseExpression(), current == .rparen else { return nil }
                pos += 1
                switch fn {
                case "sqrt": return arg >= 0 ? sqrt(arg) : nil
                case "abs":  return abs(arg)
                case "sin":  return sin(arg)
                case "cos":  return cos(arg)
                case "tan":  return tan(arg)
                case "log":  return arg > 0 ? log10(arg) : nil
                case "ln":   return arg > 0 ? log(arg) : nil
                default:     return nil
                }
            default:
                return nil
            }
        }
    }
}
