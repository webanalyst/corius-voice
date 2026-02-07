import Foundation

// MARK: - Relation Service

/// Service for managing relations between workspace items and calculating rollups
class RelationService {
    static let shared = RelationService()
    
    private init() {}
    
    // MARK: - Two-Way Relations
    
    /// Creates a reverse relation when a two-way relation is configured
    func createReverseRelation(
        from sourceItem: WorkspaceItem,
        to targetItem: inout WorkspaceItem,
        relationProperty: PropertyDefinition,
        storage: WorkspaceStorageService
    ) {
        guard let config = relationProperty.relationConfig,
              config.isTwoWay,
              let reversePropertyId = config.reversePropertyId else { return }
        
        // Find or create the reverse relation value
        var reverseValue = targetItem.properties[reversePropertyId.uuidString] ?? .relations([])
        
        switch reverseValue {
        case .relation(let existingId):
            if existingId != sourceItem.id {
                reverseValue = .relations([existingId, sourceItem.id])
            }
        case .relations(var ids):
            if !ids.contains(sourceItem.id) {
                ids.append(sourceItem.id)
                reverseValue = .relations(ids)
            }
        default:
            reverseValue = .relation(sourceItem.id)
        }
        
        targetItem.properties[reversePropertyId.uuidString] = reverseValue
    }
    
    /// Removes a reverse relation when a relation is removed
    func removeReverseRelation(
        from sourceItem: WorkspaceItem,
        in targetItem: inout WorkspaceItem,
        relationProperty: PropertyDefinition
    ) {
        guard let config = relationProperty.relationConfig,
              config.isTwoWay,
              let reversePropertyId = config.reversePropertyId else { return }
        
        guard var reverseValue = targetItem.properties[reversePropertyId.uuidString] else { return }
        
        switch reverseValue {
        case .relation(let existingId):
            if existingId == sourceItem.id {
                reverseValue = .empty
            }
        case .relations(var ids):
            ids.removeAll { $0 == sourceItem.id }
            reverseValue = ids.isEmpty ? .empty : (ids.count == 1 ? .relation(ids[0]) : .relations(ids))
        default:
            break
        }
        
        targetItem.properties[reversePropertyId.uuidString] = reverseValue
    }
    
    // MARK: - Rollup Calculations
    
    /// Calculates the rollup value for a given item
    func calculateRollup(
        for item: WorkspaceItem,
        rollupProperty: PropertyDefinition,
        allItems: [WorkspaceItem]
    ) -> PropertyValue {
        guard let config = rollupProperty.rollupConfig else { return .empty }
        
        // Get related item IDs from the relation property
        guard let relationValue = item.properties[config.relationPropertyId.uuidString] else {
            return .empty
        }
        
        let relatedIds: [UUID]
        switch relationValue {
        case .relation(let id): relatedIds = [id]
        case .relations(let ids): relatedIds = ids
        default: return .empty
        }
        
        // Get the related items
        let relatedItems = allItems.filter { relatedIds.contains($0.id) }
        
        if relatedItems.isEmpty { return .empty }
        
        // Get the values from the target property
        let values = relatedItems.compactMap { $0.properties[config.targetPropertyId.uuidString] }
        
        return calculate(values: values, calculation: config.calculation)
    }
    
    private func calculate(values: [PropertyValue], calculation: RollupConfig.RollupCalculation) -> PropertyValue {
        switch calculation {
        case .countAll:
            return .number(Double(values.count))
            
        case .countValues:
            let count = values.filter { !$0.isEmpty }.count
            return .number(Double(count))
            
        case .countUnique:
            let unique = Set(values.map { $0.displayValue })
            return .number(Double(unique.count))
            
        case .countEmpty:
            let count = values.filter { $0.isEmpty }.count
            return .number(Double(count))
            
        case .percentEmpty:
            guard !values.isEmpty else { return .number(0) }
            let empty = values.filter { $0.isEmpty }.count
            return .number(Double(empty) / Double(values.count) * 100)
            
        case .percentNotEmpty:
            guard !values.isEmpty else { return .number(0) }
            let notEmpty = values.filter { !$0.isEmpty }.count
            return .number(Double(notEmpty) / Double(values.count) * 100)
            
        case .sum:
            let numbers = values.compactMap { value -> Double? in
                if case .number(let n) = value { return n }
                return nil
            }
            return .number(numbers.reduce(0, +))
            
        case .average:
            let numbers = values.compactMap { value -> Double? in
                if case .number(let n) = value { return n }
                return nil
            }
            guard !numbers.isEmpty else { return .empty }
            return .number(numbers.reduce(0, +) / Double(numbers.count))
            
        case .median:
            let numbers = values.compactMap { value -> Double? in
                if case .number(let n) = value { return n }
                return nil
            }.sorted()
            guard !numbers.isEmpty else { return .empty }
            let mid = numbers.count / 2
            if numbers.count.isMultiple(of: 2) {
                return .number((numbers[mid - 1] + numbers[mid]) / 2)
            } else {
                return .number(numbers[mid])
            }
            
        case .min:
            let numbers = values.compactMap { value -> Double? in
                if case .number(let n) = value { return n }
                return nil
            }
            guard let min = numbers.min() else { return .empty }
            return .number(min)
            
        case .max:
            let numbers = values.compactMap { value -> Double? in
                if case .number(let n) = value { return n }
                return nil
            }
            guard let max = numbers.max() else { return .empty }
            return .number(max)
            
        case .range:
            let numbers = values.compactMap { value -> Double? in
                if case .number(let n) = value { return n }
                return nil
            }
            guard let min = numbers.min(), let max = numbers.max() else { return .empty }
            return .number(max - min)
            
        case .earliest:
            let dates = values.compactMap { value -> Date? in
                if case .date(let d) = value { return d }
                return nil
            }
            guard let earliest = dates.min() else { return .empty }
            return .date(earliest)
            
        case .latest:
            let dates = values.compactMap { value -> Date? in
                if case .date(let d) = value { return d }
                return nil
            }
            guard let latest = dates.max() else { return .empty }
            return .date(latest)
            
        case .dateRange:
            let dates = values.compactMap { value -> Date? in
                if case .date(let d) = value { return d }
                return nil
            }
            guard let earliest = dates.min(), let latest = dates.max() else { return .empty }
            let days = Calendar.current.dateComponents([.day], from: earliest, to: latest).day ?? 0
            return .text("\(days) days")
            
        case .showOriginal:
            return .text(values.map { $0.displayValue }.joined(separator: ", "))
            
        case .showUnique:
            let unique = Array(Set(values.map { $0.displayValue }))
            return .text(unique.joined(separator: ", "))
            
        case .checked:
            let count = values.filter { value in
                if case .checkbox(true) = value { return true }
                return false
            }.count
            return .number(Double(count))
            
        case .unchecked:
            let count = values.filter { value in
                if case .checkbox(false) = value { return true }
                return false
            }.count
            return .number(Double(count))
        }
    }
    
    // MARK: - Filter Evaluation
    
    /// Evaluates if an item matches a filter
    func matches(item: WorkspaceItem, filter: DatabaseFilter, allItems: [WorkspaceItem]) -> Bool {
        if filter.conditions.isEmpty { return true }
        
        switch filter.logic {
        case .and:
            return filter.conditions.allSatisfy { matches(item: item, condition: $0, allItems: allItems) }
        case .or:
            return filter.conditions.contains { matches(item: item, condition: $0, allItems: allItems) }
        }
    }
    
    private func matches(item: WorkspaceItem, condition: FilterCondition, allItems: [WorkspaceItem]) -> Bool {
        let value = item.properties[condition.propertyId.uuidString] ?? .empty
        
        switch condition.operation {
        case .equals:
            return matchEquals(value: value, filterValue: condition.value)
        case .notEquals:
            return !matchEquals(value: value, filterValue: condition.value)
        case .contains:
            return matchContains(value: value, filterValue: condition.value)
        case .notContains:
            return !matchContains(value: value, filterValue: condition.value)
        case .startsWith:
            if case .string(let search) = condition.value {
                return value.displayValue.lowercased().hasPrefix(search.lowercased())
            }
            return false
        case .endsWith:
            if case .string(let search) = condition.value {
                return value.displayValue.lowercased().hasSuffix(search.lowercased())
            }
            return false
        case .isEmpty:
            return value.isEmpty
        case .isNotEmpty:
            return !value.isEmpty
        case .greaterThan, .lessThan, .greaterOrEqual, .lessOrEqual:
            return matchNumber(value: value, filterValue: condition.value, operation: condition.operation)
        case .isBefore, .isAfter, .isOnOrBefore, .isOnOrAfter:
            return matchDate(value: value, filterValue: condition.value, operation: condition.operation)
        case .pastWeek, .pastMonth, .pastYear, .nextWeek, .nextMonth, .nextYear:
            return matchDateRange(value: value, operation: condition.operation)
        case .isChecked:
            if case .checkbox(let checked) = value { return checked }
            return false
        case .isNotChecked:
            if case .checkbox(let checked) = value { return !checked }
            return true
        case .relationContains:
            return matchRelation(value: value, filterValue: condition.value, contains: true)
        case .relationNotContains:
            return matchRelation(value: value, filterValue: condition.value, contains: false)
        }
    }
    
    private func matchEquals(value: PropertyValue, filterValue: FilterValue) -> Bool {
        switch (value, filterValue) {
        case (.text(let v), .string(let f)): return v.lowercased() == f.lowercased()
        case (.number(let v), .number(let f)): return v == f
        case (.select(let v), .string(let f)): return v.lowercased() == f.lowercased()
        case (.checkbox(let v), .bool(let f)): return v == f
        default: return false
        }
    }
    
    private func matchContains(value: PropertyValue, filterValue: FilterValue) -> Bool {
        guard case .string(let search) = filterValue else { return false }
        
        switch value {
        case .text(let v): return v.lowercased().contains(search.lowercased())
        case .multiSelect(let values): return values.contains { $0.lowercased().contains(search.lowercased()) }
        default: return value.displayValue.lowercased().contains(search.lowercased())
        }
    }
    
    private func matchNumber(value: PropertyValue, filterValue: FilterValue, operation: LinkedFilterOperation) -> Bool {
        guard case .number(let v) = value, case .number(let f) = filterValue else { return false }
        
        switch operation {
        case .greaterThan: return v > f
        case .lessThan: return v < f
        case .greaterOrEqual: return v >= f
        case .lessOrEqual: return v <= f
        default: return false
        }
    }
    
    private func matchDate(value: PropertyValue, filterValue: FilterValue, operation: LinkedFilterOperation) -> Bool {
        guard case .date(let v) = value, case .date(let f) = filterValue else { return false }
        
        switch operation {
        case .isBefore: return v < f
        case .isAfter: return v > f
        case .isOnOrBefore: return v <= f
        case .isOnOrAfter: return v >= f
        default: return false
        }
    }
    
    private func matchDateRange(value: PropertyValue, operation: LinkedFilterOperation) -> Bool {
        guard case .date(let v) = value else { return false }
        
        let now = Date()
        let calendar = Calendar.current
        
        switch operation {
        case .pastWeek:
            guard let weekAgo = calendar.date(byAdding: .day, value: -7, to: now) else { return false }
            return v >= weekAgo && v <= now
        case .pastMonth:
            guard let monthAgo = calendar.date(byAdding: .month, value: -1, to: now) else { return false }
            return v >= monthAgo && v <= now
        case .pastYear:
            guard let yearAgo = calendar.date(byAdding: .year, value: -1, to: now) else { return false }
            return v >= yearAgo && v <= now
        case .nextWeek:
            guard let weekAhead = calendar.date(byAdding: .day, value: 7, to: now) else { return false }
            return v >= now && v <= weekAhead
        case .nextMonth:
            guard let monthAhead = calendar.date(byAdding: .month, value: 1, to: now) else { return false }
            return v >= now && v <= monthAhead
        case .nextYear:
            guard let yearAhead = calendar.date(byAdding: .year, value: 1, to: now) else { return false }
            return v >= now && v <= yearAhead
        default:
            return false
        }
    }
    
    private func matchRelation(value: PropertyValue, filterValue: FilterValue, contains: Bool) -> Bool {
        let ids: [UUID]
        switch value {
        case .relation(let id): ids = [id]
        case .relations(let relationIds): ids = relationIds
        default: return contains ? false : true
        }
        
        switch filterValue {
        case .id(let searchId):
            let found = ids.contains(searchId)
            return contains ? found : !found
        case .ids(let searchIds):
            let found = ids.contains { searchIds.contains($0) }
            return contains ? found : !found
        default:
            return contains ? false : true
        }
    }
}

// MARK: - Property Value Resolution

struct PropertyValueResolver {
    static func value(
        for item: WorkspaceItem,
        definition: PropertyDefinition,
        database: Database,
        storage: WorkspaceStorageServiceOptimized
    ) -> PropertyValue {
        value(for: item, definition: definition, database: database, storage: storage, resolving: [])
    }

    private static func value(
        for item: WorkspaceItem,
        definition: PropertyDefinition,
        database: Database,
        storage: WorkspaceStorageServiceOptimized,
        resolving: Set<UUID>
    ) -> PropertyValue {
        if resolving.contains(definition.id) {
            return .empty
        }

        var resolving = resolving
        resolving.insert(definition.id)

        switch definition.type {
        case .rollup:
            return rollupValue(for: item, definition: definition, database: database, storage: storage, resolving: resolving)
        case .formula:
            let formula = definition.formula ?? ""
            return FormulaEvaluator.evaluate(formula) { name in
                if name.lowercased() == "title" {
                    return .text(item.title)
                }
                if let ref = database.properties.first(where: { $0.name == name }) {
                    return value(for: item, definition: ref, database: database, storage: storage, resolving: resolving)
                }
                return .empty
            }
        case .createdTime:
            return .date(item.createdAt)
        case .lastEdited:
            return .date(item.updatedAt)
        case .createdBy:
            return .empty
        default:
            return storedValue(for: item, definition: definition)
        }
    }

    private static func storedValue(for item: WorkspaceItem, definition: PropertyDefinition) -> PropertyValue {
        item.properties[definition.storageKey]
            ?? item.properties[PropertyDefinition.legacyKey(for: definition.name)]
            ?? .empty
    }

    private static func rollupValue(
        for item: WorkspaceItem,
        definition: PropertyDefinition,
        database: Database,
        storage: WorkspaceStorageServiceOptimized,
        resolving: Set<UUID>
    ) -> PropertyValue {
        guard let config = definition.rollupConfig else { return .empty }
        guard let relationDefinition = database.properties.first(where: { $0.id == config.relationPropertyId }) else { return .empty }
        guard let relationConfig = relationDefinition.relationConfig else { return .empty }
        guard let targetDatabase = storage.database(withID: relationConfig.targetDatabaseId) else { return .empty }
        guard let targetDefinition = targetDatabase.properties.first(where: { $0.id == config.targetPropertyId }) else { return .empty }

        let relationValue = item.properties[relationDefinition.storageKey]
            ?? item.properties[PropertyDefinition.legacyKey(for: relationDefinition.name)]
            ?? .empty

        let relatedIds: [UUID]
        switch relationValue {
        case .relation(let id):
            relatedIds = [id]
        case .relations(let ids):
            relatedIds = ids
        default:
            relatedIds = []
        }

        guard !relatedIds.isEmpty else { return .empty }

        let relatedItems = storage.items.filter { relatedIds.contains($0.id) }
        let values = relatedItems.map { relatedItem in
            value(for: relatedItem, definition: targetDefinition, database: targetDatabase, storage: storage, resolving: resolving)
        }

        return rollupCalculation(values: values, calculation: config.calculation)
    }

    private static func rollupCalculation(values: [PropertyValue], calculation: RollupConfig.RollupCalculation) -> PropertyValue {
        switch calculation {
        case .countAll:
            return .number(Double(values.count))
        case .countValues:
            let count = values.filter { !$0.isEmpty }.count
            return .number(Double(count))
        case .countUnique:
            let unique = Set(values.map { $0.displayValue })
            return .number(Double(unique.count))
        case .countEmpty:
            let count = values.filter { $0.isEmpty }.count
            return .number(Double(count))
        case .percentEmpty:
            guard !values.isEmpty else { return .number(0) }
            let empty = values.filter { $0.isEmpty }.count
            return .number(Double(empty) / Double(values.count) * 100)
        case .percentNotEmpty:
            guard !values.isEmpty else { return .number(0) }
            let notEmpty = values.filter { !$0.isEmpty }.count
            return .number(Double(notEmpty) / Double(values.count) * 100)
        case .sum:
            let numbers = values.compactMap { value -> Double? in
                if case .number(let n) = value { return n }
                return nil
            }
            return .number(numbers.reduce(0, +))
        case .average:
            let numbers = values.compactMap { value -> Double? in
                if case .number(let n) = value { return n }
                return nil
            }
            guard !numbers.isEmpty else { return .empty }
            return .number(numbers.reduce(0, +) / Double(numbers.count))
        case .median:
            let numbers = values.compactMap { value -> Double? in
                if case .number(let n) = value { return n }
                return nil
            }.sorted()
            guard !numbers.isEmpty else { return .empty }
            let mid = numbers.count / 2
            if numbers.count.isMultiple(of: 2) {
                return .number((numbers[mid - 1] + numbers[mid]) / 2)
            } else {
                return .number(numbers[mid])
            }
        case .min:
            let numbers = values.compactMap { value -> Double? in
                if case .number(let n) = value { return n }
                return nil
            }
            guard let min = numbers.min() else { return .empty }
            return .number(min)
        case .max:
            let numbers = values.compactMap { value -> Double? in
                if case .number(let n) = value { return n }
                return nil
            }
            guard let max = numbers.max() else { return .empty }
            return .number(max)
        case .range:
            let numbers = values.compactMap { value -> Double? in
                if case .number(let n) = value { return n }
                return nil
            }
            guard let min = numbers.min(), let max = numbers.max() else { return .empty }
            return .number(max - min)
        case .earliest:
            let dates = values.compactMap { value -> Date? in
                if case .date(let d) = value { return d }
                return nil
            }
            guard let earliest = dates.min() else { return .empty }
            return .date(earliest)
        case .latest:
            let dates = values.compactMap { value -> Date? in
                if case .date(let d) = value { return d }
                return nil
            }
            guard let latest = dates.max() else { return .empty }
            return .date(latest)
        case .dateRange:
            let dates = values.compactMap { value -> Date? in
                if case .date(let d) = value { return d }
                return nil
            }
            guard let earliest = dates.min(), let latest = dates.max() else { return .empty }
            let days = Calendar.current.dateComponents([.day], from: earliest, to: latest).day ?? 0
            return .text("\(days) days")
        case .showOriginal:
            return .text(values.map { $0.displayValue }.joined(separator: ", "))
        case .showUnique:
            let unique = Array(Set(values.map { $0.displayValue }))
            return .text(unique.joined(separator: ", "))
        case .checked:
            let count = values.filter { value in
                if case .checkbox(true) = value { return true }
                return false
            }.count
            return .number(Double(count))
        case .unchecked:
            let count = values.filter { value in
                if case .checkbox(false) = value { return true }
                return false
            }.count
            return .number(Double(count))
        }
    }
}

// MARK: - Formula Evaluation

struct FormulaEvaluator {
    static func evaluate(_ formula: String, resolve: (String) -> PropertyValue) -> PropertyValue {
        let trimmed = formula.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .empty }

        if let name = singlePropertyReference(in: trimmed) {
            return resolve(name)
        }

        let numericExpression = replacePropertyReferences(in: trimmed) { name in
            let value = resolve(name)
            return numericString(from: value)
        }

        if containsMathOperators(in: trimmed) || containsNumber(in: trimmed) {
            if let result = evaluateNumericExpression(numericExpression) {
                return .number(result)
            }
        }

        let text = replacePropertyReferences(in: trimmed) { name in
            resolve(name).displayValue
        }
        return .text(stripQuotes(text))
    }

    private static func singlePropertyReference(in formula: String) -> String? {
        if let name = matchPropertyName(pattern: "^\\s*prop\\((.+)\\)\\s*$", in: formula) {
            return name
        }
        if let name = matchPropertyName(pattern: "^\\s*\\{([^}]+)\\}\\s*$", in: formula) {
            return name
        }
        return nil
    }

    private static func matchPropertyName(pattern: String, in formula: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { return nil }
        let range = NSRange(formula.startIndex..., in: formula)
        guard let match = regex.firstMatch(in: formula, options: [], range: range),
              match.numberOfRanges > 1,
              let nameRange = Range(match.range(at: 1), in: formula) else { return nil }
        return normalizePropertyName(String(formula[nameRange]))
    }

    private static func replacePropertyReferences(in formula: String, replacement: (String) -> String) -> String {
        var result = formula
        let patterns = [
            "prop\\((\"[^\"]+\"|'[^']+'|[^\\)]+)\\)",
            "\\{([^}]+)\\}"
        ]
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { continue }
            let range = NSRange(result.startIndex..., in: result)
            let matches = regex.matches(in: result, options: [], range: range)
            for match in matches.reversed() {
                guard match.numberOfRanges > 1,
                      let nameRange = Range(match.range(at: 1), in: result) else { continue }
                let rawName = String(result[nameRange])
                let name = normalizePropertyName(rawName)
                let replacementText = replacement(name)
                if let matchRange = Range(match.range, in: result) {
                    result.replaceSubrange(matchRange, with: replacementText)
                }
            }
        }
        return result
    }

    private static func normalizePropertyName(_ name: String) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if (trimmed.hasPrefix("\"") && trimmed.hasSuffix("\"")) ||
            (trimmed.hasPrefix("'") && trimmed.hasSuffix("'")) {
            return String(trimmed.dropFirst().dropLast())
        }
        return trimmed
    }

    private static func numericString(from value: PropertyValue) -> String {
        switch value {
        case .number(let number):
            return String(number)
        case .checkbox(let flag):
            return flag ? "1" : "0"
        default:
            let text = value.displayValue
            return Double(text.replacingOccurrences(of: ",", with: ".")) != nil ? text : "0"
        }
    }

    private static func stripQuotes(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if (trimmed.hasPrefix("\"") && trimmed.hasSuffix("\"")) ||
            (trimmed.hasPrefix("'") && trimmed.hasSuffix("'")) {
            return String(trimmed.dropFirst().dropLast())
        }
        return trimmed
    }

    private static func containsMathOperators(in formula: String) -> Bool {
        formula.contains("+") || formula.contains("-") || formula.contains("*") || formula.contains("/")
    }

    private static func containsNumber(in formula: String) -> Bool {
        formula.rangeOfCharacter(from: .decimalDigits) != nil
    }

    private static func evaluateNumericExpression(_ expression: String) -> Double? {
        let allowed = CharacterSet(charactersIn: "0123456789.+-*/() ").inverted
        if expression.rangeOfCharacter(from: allowed) != nil {
            return nil
        }

        let tokens = tokenize(expression)
        guard !tokens.isEmpty else { return nil }

        var output: [Token] = []
        var ops: [Token] = []

        for token in tokens {
            switch token {
            case .number:
                output.append(token)
            case .op(let op1):
                while let last = ops.last, case .op(let op2) = last, precedence(op2) >= precedence(op1) {
                    output.append(ops.removeLast())
                }
                ops.append(token)
            case .lparen:
                ops.append(token)
            case .rparen:
                while let last = ops.last {
                    ops.removeLast()
                    if case .lparen = last {
                        break
                    }
                    output.append(last)
                }
            }
        }

        while let last = ops.popLast() {
            output.append(last)
        }

        var stack: [Double] = []
        for token in output {
            switch token {
            case .number(let value):
                stack.append(value)
            case .op(let op):
                guard stack.count >= 2 else { return nil }
                let rhs = stack.removeLast()
                let lhs = stack.removeLast()
                let result: Double
                switch op {
                case "+": result = lhs + rhs
                case "-": result = lhs - rhs
                case "*": result = lhs * rhs
                case "/":
                    guard rhs != 0 else { return nil }
                    result = lhs / rhs
                default:
                    return nil
                }
                stack.append(result)
            default:
                return nil
            }
        }

        return stack.last
    }

    private enum Token {
        case number(Double)
        case op(Character)
        case lparen
        case rparen
    }

    private static func tokenize(_ expression: String) -> [Token] {
        var tokens: [Token] = []
        var index = expression.startIndex
        var lastWasOperator = true

        while index < expression.endIndex {
            let char = expression[index]
            if char.isWhitespace {
                index = expression.index(after: index)
                continue
            }

            if char == "(" {
                tokens.append(.lparen)
                lastWasOperator = true
                index = expression.index(after: index)
                continue
            }
            if char == ")" {
                tokens.append(.rparen)
                lastWasOperator = false
                index = expression.index(after: index)
                continue
            }

            if "+-*/".contains(char) {
                if char == "-", lastWasOperator, let number = readNumber(from: expression, index: expression.index(after: index), sign: -1) {
                    tokens.append(.number(number.value))
                    index = number.nextIndex
                    lastWasOperator = false
                } else {
                    tokens.append(.op(char))
                    lastWasOperator = true
                    index = expression.index(after: index)
                }
                continue
            }

            if let number = readNumber(from: expression, index: index, sign: 1) {
                tokens.append(.number(number.value))
                index = number.nextIndex
                lastWasOperator = false
                continue
            }

            index = expression.index(after: index)
        }

        return tokens
    }

    private static func readNumber(from expression: String, index: String.Index, sign: Double) -> (value: Double, nextIndex: String.Index)? {
        var current = index
        var hasDot = false
        var digits = ""

        while current < expression.endIndex {
            let char = expression[current]
            if char == "." {
                if hasDot { break }
                hasDot = true
                digits.append(char)
                current = expression.index(after: current)
                continue
            }
            if char.isNumber {
                digits.append(char)
                current = expression.index(after: current)
                continue
            }
            break
        }

        guard !digits.isEmpty else { return nil }
        let value = (Double(digits) ?? 0) * sign
        return (value, current)
    }

    private static func precedence(_ op: Character) -> Int {
        switch op {
        case "*", "/": return 2
        case "+", "-": return 1
        default: return 0
        }
    }
}

// MARK: - Database View Query Engine

/// Shared query engine for database views and linked database embeds.
/// Keeps filter/sort behavior consistent across the workspace UI.
enum DatabaseViewQueryEngine {
    static func apply(
        filters: [ViewFilter],
        sorts: [ViewSort],
        to items: [WorkspaceItem],
        database: Database,
        storage: any WorkspaceStorageProtocol
    ) -> [WorkspaceItem] {
        let filtered = applyFilters(filters, to: items, database: database, storage: storage)
        return applySorts(sorts, to: filtered, database: database, storage: storage)
    }

    static func applyFilters(
        _ filters: [ViewFilter],
        to items: [WorkspaceItem],
        database: Database,
        storage: any WorkspaceStorageProtocol
    ) -> [WorkspaceItem] {
        guard !filters.isEmpty else { return items }
        return items.filter { item in
            filters.allSatisfy { filter in
                matchesFilter(filter, item: item, database: database, storage: storage)
            }
        }
    }

    static func applySorts(
        _ sorts: [ViewSort],
        to items: [WorkspaceItem],
        database: Database,
        storage: any WorkspaceStorageProtocol
    ) -> [WorkspaceItem] {
        guard !sorts.isEmpty else { return items }
        return items.sorted { lhs, rhs in
            for sort in sorts {
                let leftValue = resolvedPropertyValue(
                    for: lhs,
                    propertyName: sort.propertyName,
                    propertyId: sort.propertyId,
                    key: storageKey(for: sort, in: database),
                    database: database,
                    storage: storage
                )
                let rightValue = resolvedPropertyValue(
                    for: rhs,
                    propertyName: sort.propertyName,
                    propertyId: sort.propertyId,
                    key: storageKey(for: sort, in: database),
                    database: database,
                    storage: storage
                )
                if leftValue.displayValue == rightValue.displayValue {
                    continue
                }
                let order = compareValue(leftValue, to: rightValue)
                return sort.ascending ? order == .orderedAscending : order == .orderedDescending
            }
            return lhs.updatedAt > rhs.updatedAt
        }
    }

    private static func matchesFilter(
        _ filter: ViewFilter,
        item: WorkspaceItem,
        database: Database,
        storage: any WorkspaceStorageProtocol
    ) -> Bool {
        let key = storageKey(for: filter, in: database)
        let value: PropertyValue
        if filter.propertyName.lowercased() == "title" {
            value = .text(item.title)
        } else {
            value = resolvedPropertyValue(
                for: item,
                propertyName: filter.propertyName,
                propertyId: filter.propertyId,
                key: key,
                database: database,
                storage: storage
            )
        }

        switch filter.operation {
        case .equals:
            return compareValue(value, to: filter.value) == .orderedSame
        case .notEquals:
            return compareValue(value, to: filter.value) != .orderedSame
        case .contains:
            return value.displayValue.localizedCaseInsensitiveContains(filter.value.displayValue)
        case .notContains:
            return !value.displayValue.localizedCaseInsensitiveContains(filter.value.displayValue)
        case .isEmpty:
            return value.isEmpty
        case .isNotEmpty:
            return !value.isEmpty
        case .greaterThan:
            return compareValue(value, to: filter.value) == .orderedDescending
        case .lessThan:
            return compareValue(value, to: filter.value) == .orderedAscending
        }
    }

    private static func resolvedPropertyValue(
        for item: WorkspaceItem,
        propertyName: String,
        propertyId: UUID?,
        key: String,
        database: Database,
        storage: any WorkspaceStorageProtocol
    ) -> PropertyValue {
        if propertyName.lowercased() == "title" {
            return .text(item.title)
        }

        let definition = propertyDefinition(for: propertyName, propertyId: propertyId, database: database)
        if let definition,
           definition.type == .rollup || definition.type == .formula
            || definition.type == .createdTime || definition.type == .lastEdited || definition.type == .createdBy {
            guard let optimizedStorage = storage as? WorkspaceStorageServiceOptimized else {
                return item.properties[key] ?? item.properties[PropertyDefinition.legacyKey(for: propertyName)] ?? .empty
            }
            return PropertyValueResolver.value(
                for: item,
                definition: definition,
                database: database,
                storage: optimizedStorage
            )
        }

        let legacyKey = PropertyDefinition.legacyKey(for: propertyName)
        return item.properties[key] ?? item.properties[legacyKey] ?? .empty
    }

    private static func propertyDefinition(
        for propertyName: String,
        propertyId: UUID?,
        database: Database
    ) -> PropertyDefinition? {
        if let id = propertyId, let definition = database.properties.first(where: { $0.id == id }) {
            return definition
        }
        return database.properties.first(where: { $0.name == propertyName })
    }

    private static func compareValue(_ lhs: PropertyValue, to rhs: PropertyValue) -> ComparisonResult {
        switch (lhs, rhs) {
        case (.number(let left), .number(let right)):
            return left == right ? .orderedSame : (left < right ? .orderedAscending : .orderedDescending)
        case (.date(let left), .date(let right)):
            return left.compare(right)
        default:
            return lhs.displayValue.localizedStandardCompare(rhs.displayValue)
        }
    }

    private static func storageKey(for filter: ViewFilter, in database: Database) -> String {
        if let id = filter.propertyId {
            return id.uuidString
        }
        if let definition = database.properties.first(where: { $0.name == filter.propertyName }) {
            return definition.storageKey
        }
        return PropertyDefinition.legacyKey(for: filter.propertyName)
    }

    private static func storageKey(for sort: ViewSort, in database: Database) -> String {
        if let id = sort.propertyId {
            return id.uuidString
        }
        if let definition = database.properties.first(where: { $0.name == sort.propertyName }) {
            return definition.storageKey
        }
        return PropertyDefinition.legacyKey(for: sort.propertyName)
    }
}
