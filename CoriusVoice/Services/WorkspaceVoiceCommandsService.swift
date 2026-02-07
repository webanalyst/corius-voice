import Foundation
import SwiftUI

// MARK: - Workspace Voice Commands Service

/// Handles voice commands for workspace operations
/// Integrates with the existing voice transcription system
@MainActor
class WorkspaceVoiceCommandsService: ObservableObject {
    static let shared = WorkspaceVoiceCommandsService()
    
    private let workspaceStorage: WorkspaceStorageServiceOptimized
    private let sessionIntegration: SessionIntegrationService
    
    @Published var lastCommandResult: CommandResult?
    @Published var isProcessing = false
    private var pendingConfirmation: PendingConfirmation?
    
    private init() {
        self.workspaceStorage = .shared
        self.sessionIntegration = .shared
    }

    init(
        workspaceStorage: WorkspaceStorageServiceOptimized,
        sessionIntegration: SessionIntegrationService? = nil
    ) {
        self.workspaceStorage = workspaceStorage
        self.sessionIntegration = sessionIntegration ?? .shared
    }
    
    // MARK: - Command Types
    
    enum WorkspaceCommand: String, CaseIterable {
        // Task commands
        case createTask = "crear tarea|create task|nueva tarea|new task|add task|añadir tarea"
        case moveTask = "mover tarea|move task|mover a|move to"
        case completeTask = "completar tarea|complete task|marcar completado|mark complete|done|hecho"
        case deleteTask = "eliminar tarea|delete task|borrar tarea|remove task"
        
        // Page commands
        case createPage = "crear página|create page|nueva página|new page|crear nota|create note"
        case openPage = "abrir página|open page|ir a|go to"
        
        // Board commands
        case showBoard = "mostrar tablero|show board|abrir kanban|open kanban|ver tareas|view tasks"
        case addColumn = "añadir columna|add column|nueva columna|new column"
        
        // Session integration
        case convertSession = "convertir sesión|convert session|crear tarea de sesión|session to task"
        case importSessions = "importar sesiones|import sessions"
        
        // Quick actions
        case quickNote = "nota rápida|quick note|apuntar|jot down"
        
        var patterns: [String] {
            rawValue.components(separatedBy: "|")
        }

        var metricKey: String {
            switch self {
            case .createTask: return "createTask"
            case .moveTask: return "moveTask"
            case .completeTask: return "completeTask"
            case .deleteTask: return "deleteTask"
            case .createPage: return "createPage"
            case .openPage: return "openPage"
            case .showBoard: return "showBoard"
            case .addColumn: return "addColumn"
            case .convertSession: return "convertSession"
            case .importSessions: return "importSessions"
            case .quickNote: return "quickNote"
            }
        }
    }
    
    // MARK: - Command Result
    
    struct CommandResult {
        let command: WorkspaceCommand
        let success: Bool
        let message: String
        let createdItem: WorkspaceItem?
        let timestamp: Date
        let outcome: CommandExecutionOutcome?
        
        static func success(
            _ command: WorkspaceCommand,
            message: String,
            item: WorkspaceItem? = nil,
            outcome: CommandExecutionOutcome? = nil
        ) -> CommandResult {
            CommandResult(
                command: command,
                success: true,
                message: message,
                createdItem: item,
                timestamp: Date(),
                outcome: outcome
            )
        }
        
        static func failure(
            _ command: WorkspaceCommand,
            message: String,
            outcome: CommandExecutionOutcome? = nil
        ) -> CommandResult {
            CommandResult(
                command: command,
                success: false,
                message: message,
                createdItem: nil,
                timestamp: Date(),
                outcome: outcome
            )
        }
    }

    struct ParsedIntent {
        let command: WorkspaceCommand
        let context: String
        let confidence: Double
    }

    struct CommandExecutionOutcome {
        let intent: WorkspaceCommand
        let confidence: Double
        let ambiguity: Bool
        let requiresConfirmation: Bool
        let errorReason: String?
    }

    private struct PendingConfirmation {
        let command: WorkspaceCommand
        let prompt: String
        let execute: () -> Void
    }
    
    // MARK: - Process Voice Input
    
    /// Processes transcribed text for workspace commands
    /// - Parameter text: The transcribed voice input
    /// - Returns: True if a command was recognized and executed
    @discardableResult
    func processVoiceInput(_ text: String) -> Bool {
        let lowercasedText = text.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)

        if handlePendingConfirmationIfNeeded(lowercasedText) {
            return true
        }

        guard let intent = parseIntent(from: lowercasedText) else {
            return false
        }
        
        isProcessing = true
        executeCommand(intent.command, context: intent.context, confidence: intent.confidence)
        isProcessing = false
        return true
    }

    private func handlePendingConfirmationIfNeeded(_ text: String) -> Bool {
        guard let pendingConfirmation else { return false }

        let normalized = text.lowercased()
        let accepted = normalized == "sí" || normalized == "si" || normalized == "yes" || normalized == "confirmar"
        let rejected = normalized == "no" || normalized == "cancelar" || normalized == "cancel"
        guard accepted || rejected else {
            return false
        }

        if accepted {
            pendingConfirmation.execute()
        } else {
            let outcome = CommandExecutionOutcome(
                intent: pendingConfirmation.command,
                confidence: 1,
                ambiguity: false,
                requiresConfirmation: true,
                errorReason: "User rejected confirmation"
            )
            lastCommandResult = .failure(
                pendingConfirmation.command,
                message: "Acción cancelada",
                outcome: outcome
            )
            workspaceStorage.recordMetric(
                .voiceCommand(
                    intent: pendingConfirmation.command.metricKey,
                    success: false,
                    reason: "confirmation_rejected",
                    timestamp: Date()
                )
            )
        }

        self.pendingConfirmation = nil
        return true
    }

    private func parseIntent(from text: String) -> ParsedIntent? {
        for command in WorkspaceCommand.allCases {
            for pattern in command.patterns {
                if text.contains(pattern) {
                    let context = extractContext(from: text, after: pattern)
                    return ParsedIntent(command: command, context: context, confidence: 0.85)
                }
            }
        }
        return nil
    }
    
    /// Extracts context (parameters) from the voice input after the command
    private func extractContext(from text: String, after pattern: String) -> String {
        if let range = text.range(of: pattern) {
            let afterCommand = String(text[range.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
            // Clean up common filler words
            let cleanedContext = afterCommand
                .replacingOccurrences(of: "llamada ", with: "")
                .replacingOccurrences(of: "llamado ", with: "")
                .replacingOccurrences(of: "called ", with: "")
                .replacingOccurrences(of: "named ", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return cleanedContext
        }
        return ""
    }
    
    // MARK: - Execute Commands
    
    private func executeCommand(_ command: WorkspaceCommand, context: String, confidence: Double) {
        switch command {
        case .createTask:
            executeCreateTask(title: context, confidence: confidence)
            
        case .moveTask:
            executeMoveTask(context: context, confidence: confidence)
            
        case .completeTask:
            executeCompleteTask(context: context, confidence: confidence)
            
        case .deleteTask:
            executeDeleteTask(context: context, confidence: confidence)
            
        case .createPage:
            executeCreatePage(title: context, confidence: confidence)
            
        case .openPage:
            executeOpenPage(context: context, confidence: confidence)
            
        case .showBoard:
            executeShowBoard(confidence: confidence)
            
        case .addColumn:
            executeAddColumn(name: context, confidence: confidence)
            
        case .convertSession:
            executeConvertSession(confidence: confidence)
            
        case .importSessions:
            executeImportSessions(confidence: confidence)
            
        case .quickNote:
            executeQuickNote(content: context, confidence: confidence)
        }
    }
    
    // MARK: - Task Commands
    
    private func executeCreateTask(title: String, confidence: Double) {
        guard let defaultDatabase = workspaceStorage.databases.first else {
            publishFailure(.createTask, confidence: confidence, message: "No hay tablero disponible. Crea uno primero.")
            return
        }
        
        let taskTitle = title.isEmpty ? "Nueva tarea" : title.capitalized
        let task = workspaceStorage.createTask(
            title: taskTitle,
            databaseID: defaultDatabase.id
        )
        
        publishSuccess(.createTask, confidence: confidence, message: "Tarea '\(taskTitle)' creada", item: task)
        print("🎤 Voice command: Created task '\(taskTitle)'")
    }
    
    private func executeMoveTask(context: String, confidence: Double) {
        // Parse: "mover tarea X a columna Y" or "move task X to Y"
        let parts = context.components(separatedBy: " a ").count > 1
            ? context.components(separatedBy: " a ")
            : context.components(separatedBy: " to ")
        
        guard parts.count >= 2 else {
            publishFailure(.moveTask, confidence: confidence, message: "Especifica la tarea y el destino. Ej: 'mover tarea X a completado'")
            return
        }
        
        let taskQuery = parts[0].trimmingCharacters(in: .whitespaces)
        let targetColumn = parts[1].trimmingCharacters(in: .whitespaces).lowercased()
        
        let taskResolution = resolveTask(matching: taskQuery)
        guard let task = taskResolution.item else {
            publishFailure(.moveTask, confidence: confidence, message: "No encontré la tarea '\(taskQuery)'")
            return
        }
        
        if taskResolution.isAmbiguous {
            pendingConfirmation = PendingConfirmation(
                command: .moveTask,
                prompt: "Encontré varias tareas parecidas. ¿Mover '\(task.title)'?",
                execute: { [weak self] in
                    self?.performMoveTask(task: task, targetColumn: targetColumn, confidence: confidence, ambiguity: true)
                }
            )
            publishFailure(
                .moveTask,
                confidence: confidence,
                message: pendingConfirmation?.prompt ?? "Confirma la acción",
                requiresConfirmation: true,
                ambiguity: true,
                errorReason: "Ambiguous task resolution"
            )
            return
        }

        performMoveTask(task: task, targetColumn: targetColumn, confidence: confidence, ambiguity: false)
    }

    private func performMoveTask(task: WorkspaceItem, targetColumn: String, confidence: Double, ambiguity: Bool) {
        guard let database = workspaceStorage.databases.first(where: { $0.id == task.workspaceID }),
              let column = resolveColumn(named: targetColumn, in: database) else {
            publishFailure(.moveTask, confidence: confidence, message: "No encontré la columna '\(targetColumn)'", ambiguity: ambiguity)
            return
        }
        
        workspaceStorage.moveItem(task.id, toStatus: column.name)
        publishSuccess(.moveTask, confidence: confidence, message: "Tarea movida a '\(column.name)'", ambiguity: ambiguity)
        print("🎤 Voice command: Moved task to '\(column.name)'")
    }
    
    private func executeCompleteTask(context: String, confidence: Double) {
        let taskQuery = context.trimmingCharacters(in: .whitespacesAndNewlines)

        if !taskQuery.isEmpty {
            let resolution = resolveTask(matching: taskQuery)
            guard let task = resolution.item else {
                publishFailure(.completeTask, confidence: confidence, message: "No encontré la tarea para completar")
                return
            }

            if resolution.isAmbiguous {
                pendingConfirmation = PendingConfirmation(
                    command: .completeTask,
                    prompt: "Encontré varias tareas parecidas. ¿Completar '\(task.title)'?",
                    execute: { [weak self] in
                        self?.performCompleteTask(task: task, confidence: confidence, ambiguity: true)
                    }
                )
                publishFailure(
                    .completeTask,
                    confidence: confidence,
                    message: pendingConfirmation?.prompt ?? "Confirma la acción",
                    requiresConfirmation: true,
                    ambiguity: true,
                    errorReason: "Ambiguous task resolution"
                )
                return
            }

            performCompleteTask(task: task, confidence: confidence, ambiguity: false)
            return
        }

        // Complete the most recent in-progress task when no task was provided.
        guard let taskToComplete = workspaceStorage.items
            .filter({ $0.itemType == .task })
            .filter({ item in
                guard let statusName = workspaceStorage.statusValue(for: item)?.lowercased() else {
                    return false
                }
                return statusName.contains("progress")
                    || statusName.contains("doing")
                    || statusName.contains("haciendo")
            })
            .sorted(by: { $0.updatedAt > $1.updatedAt })
            .first else {
            publishFailure(.completeTask, confidence: confidence, message: "No encontré la tarea para completar")
            return
        }

        performCompleteTask(task: taskToComplete, confidence: confidence, ambiguity: false)
    }

    private func performCompleteTask(task: WorkspaceItem, confidence: Double, ambiguity: Bool) {
        if let database = workspaceStorage.databases.first(where: { $0.id == task.workspaceID }),
           let doneColumn = database.kanbanColumns.first(where: { 
               $0.name.lowercased().contains("done") || 
               $0.name.lowercased().contains("complet") ||
               $0.name.lowercased().contains("hecho")
           }) {
            workspaceStorage.moveItem(task.id, toStatus: doneColumn.name)
            publishSuccess(
                .completeTask,
                confidence: confidence,
                message: "Tarea '\(task.title)' completada ✓",
                ambiguity: ambiguity
            )
        } else {
            publishFailure(
                .completeTask,
                confidence: confidence,
                message: "No encontré la columna de completados",
                ambiguity: ambiguity
            )
        }
    }
    
    private func executeDeleteTask(context: String, confidence: Double) {
        guard !context.isEmpty else {
            publishFailure(.deleteTask, confidence: confidence, message: "Especifica qué tarea eliminar")
            return
        }

        let resolution = resolveTask(matching: context)
        guard let task = resolution.item else {
            publishFailure(.deleteTask, confidence: confidence, message: "No encontré la tarea '\(context)'")
            return
        }

        pendingConfirmation = PendingConfirmation(
            command: .deleteTask,
            prompt: "¿Eliminar la tarea '\(task.title)'? Responde sí o no.",
            execute: { [weak self] in
                self?.workspaceStorage.deleteItem(task.id)
                self?.publishSuccess(
                    .deleteTask,
                    confidence: confidence,
                    message: "Tarea '\(task.title)' eliminada",
                    ambiguity: resolution.isAmbiguous
                )
            }
        )

        publishFailure(
            .deleteTask,
            confidence: confidence,
            message: pendingConfirmation?.prompt ?? "Confirma la eliminación",
            requiresConfirmation: true,
            ambiguity: resolution.isAmbiguous,
            errorReason: "Destructive command requires confirmation"
        )
    }
    
    // MARK: - Page Commands
    
    private func executeCreatePage(title: String, confidence: Double) {
        let pageTitle = title.isEmpty ? "Nueva página" : title.capitalized
        let page = WorkspaceItem.page(title: pageTitle, icon: "📝", parentID: nil)
        _ = workspaceStorage.createItem(page)
        publishSuccess(.createPage, confidence: confidence, message: "Página '\(pageTitle)' creada", item: page)
        print("🎤 Voice command: Created page '\(pageTitle)'")
    }
    
    private func executeOpenPage(context: String, confidence: Double) {
        let query = context.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            publishFailure(.openPage, confidence: confidence, message: "Especifica qué página abrir")
            return
        }

        let resolution = resolvePage(matching: query)
        guard let page = resolution.item else {
            publishFailure(.openPage, confidence: confidence, message: "No encontré la página '\(query)'")
            return
        }

        if resolution.isAmbiguous {
            pendingConfirmation = PendingConfirmation(
                command: .openPage,
                prompt: "Encontré varias páginas parecidas. ¿Abrir '\(page.title)'?",
                execute: { [weak self] in
                    self?.performOpenPage(page: page, confidence: confidence, ambiguity: true)
                }
            )
            publishFailure(
                .openPage,
                confidence: confidence,
                message: pendingConfirmation?.prompt ?? "Confirma la acción",
                requiresConfirmation: true,
                ambiguity: true,
                errorReason: "Ambiguous page resolution"
            )
            return
        }

        performOpenPage(page: page, confidence: confidence, ambiguity: false)
    }

    private func performOpenPage(page: WorkspaceItem, confidence: Double, ambiguity: Bool) {
        NotificationCenter.default.post(name: .openWorkspacePage, object: nil, userInfo: ["pageID": page.id])
        publishSuccess(.openPage, confidence: confidence, message: "Abriendo '\(page.title)'", item: page, ambiguity: ambiguity)
    }
    
    // MARK: - Board Commands
    
    private func executeShowBoard(confidence: Double) {
        NotificationCenter.default.post(name: .showWorkspaceBoard, object: nil)
        publishSuccess(.showBoard, confidence: confidence, message: "Mostrando tablero")
    }
    
    private func executeAddColumn(name: String, confidence: Double) {
        guard let database = workspaceStorage.databases.first else {
            publishFailure(.addColumn, confidence: confidence, message: "No hay tablero disponible")
            return
        }
        
        let columnName = name.isEmpty ? "Nueva columna" : name.capitalized
        workspaceStorage.addColumn(to: database.id, name: columnName)
        publishSuccess(.addColumn, confidence: confidence, message: "Columna '\(columnName)' añadida")
    }
    
    // MARK: - Session Integration Commands
    
    private func executeConvertSession(confidence: Double) {
        guard let defaultDatabase = workspaceStorage.databases.first else {
            publishFailure(.convertSession, confidence: confidence, message: "No hay tablero disponible")
            return
        }
        
        if let task = sessionIntegration.createTaskFromLastSession(databaseID: defaultDatabase.id) {
            publishSuccess(.convertSession, confidence: confidence, message: "Sesión convertida a tarea", item: task)
        } else {
            publishFailure(.convertSession, confidence: confidence, message: "No hay sesiones recientes para convertir")
        }
    }
    
    private func executeImportSessions(confidence: Double) {
        guard let defaultDatabase = workspaceStorage.databases.first else {
            publishFailure(.importSessions, confidence: confidence, message: "No hay tablero disponible")
            return
        }
        
        let imported = sessionIntegration.autoImportRecentSessions(databaseID: defaultDatabase.id)
        publishSuccess(.importSessions, confidence: confidence, message: "Importadas \(imported.count) sesiones")
    }
    
    // MARK: - Quick Note
    
    private func executeQuickNote(content: String, confidence: Double) {
        guard !content.isEmpty else {
            publishFailure(.quickNote, confidence: confidence, message: "Di el contenido de la nota")
            return
        }
        
        var page = WorkspaceItem.page(
            title: "Nota rápida - \(Date().formatted(date: .abbreviated, time: .shortened))",
            icon: "📝",
            parentID: nil
        )
        page.blocks = [Block(type: .paragraph, content: content)]
        _ = workspaceStorage.createItem(page)
        
        publishSuccess(.quickNote, confidence: confidence, message: "Nota guardada", item: page)
        print("🎤 Voice command: Quick note saved")
    }
    
    // MARK: - Helpers
    
    private struct TaskResolution {
        let item: WorkspaceItem?
        let isAmbiguous: Bool
    }

    private struct PageResolution {
        let item: WorkspaceItem?
        let isAmbiguous: Bool
    }

    private func resolveTask(matching query: String) -> TaskResolution {
        let lowercasedQuery = query.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        guard !lowercasedQuery.isEmpty else {
            return TaskResolution(item: nil, isAmbiguous: false)
        }

        let scored = workspaceStorage.items
            .filter { $0.itemType == .task && !$0.isArchived }
            .map { ($0, scoreMatch(text: $0.title.lowercased(), query: lowercasedQuery)) }
            .filter { $0.1 > 0 }
            .sorted {
                if $0.1 == $1.1 {
                    return $0.0.updatedAt > $1.0.updatedAt
                }
                return $0.1 > $1.1
            }

        guard let best = scored.first else {
            return TaskResolution(item: nil, isAmbiguous: false)
        }

        let secondScore = scored.count > 1 ? scored[1].1 : 0
        let isAmbiguous = secondScore > 0 && abs(best.1 - secondScore) < 0.1
        return TaskResolution(item: best.0, isAmbiguous: isAmbiguous)
    }

    private func resolveColumn(named query: String, in database: Database) -> KanbanColumn? {
        let normalized = query.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        return database.kanbanColumns
            .map { ($0, scoreMatch(text: $0.name.lowercased(), query: normalized)) }
            .filter { $0.1 > 0 }
            .sorted { $0.1 > $1.1 }
            .first?.0
    }

    private func resolvePage(matching query: String) -> PageResolution {
        let lowercasedQuery = query.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        guard !lowercasedQuery.isEmpty else {
            return PageResolution(item: nil, isAmbiguous: false)
        }

        let scored = workspaceStorage.items
            .filter { $0.itemType == .page && !$0.isArchived }
            .map { ($0, scoreMatch(text: $0.title.lowercased(), query: lowercasedQuery)) }
            .filter { $0.1 > 0 }
            .sorted {
                if $0.1 == $1.1 {
                    return $0.0.updatedAt > $1.0.updatedAt
                }
                return $0.1 > $1.1
            }

        guard let best = scored.first else {
            return PageResolution(item: nil, isAmbiguous: false)
        }

        let secondScore = scored.count > 1 ? scored[1].1 : 0
        let isAmbiguous = secondScore > 0 && abs(best.1 - secondScore) < 0.1
        return PageResolution(item: best.0, isAmbiguous: isAmbiguous)
    }

    private func scoreMatch(text: String, query: String) -> Double {
        guard !query.isEmpty else { return 0 }
        if text == query { return 1.0 }
        if text.hasPrefix(query) { return 0.9 }
        if text.contains(query) { return 0.7 }

        let queryTokens = Set(query.split(separator: " ").map(String.init))
        let textTokens = Set(text.split(separator: " ").map(String.init))
        guard !queryTokens.isEmpty else { return 0 }
        let overlap = queryTokens.intersection(textTokens).count
        if overlap == 0 { return 0 }
        return 0.4 + (Double(overlap) / Double(queryTokens.count)) * 0.2
    }

    private func publishSuccess(
        _ command: WorkspaceCommand,
        confidence: Double,
        message: String,
        item: WorkspaceItem? = nil,
        ambiguity: Bool = false
    ) {
        let outcome = CommandExecutionOutcome(
            intent: command,
            confidence: confidence,
            ambiguity: ambiguity,
            requiresConfirmation: false,
            errorReason: nil
        )
        lastCommandResult = .success(command, message: message, item: item, outcome: outcome)
        workspaceStorage.recordMetric(
            .voiceCommand(
                intent: command.metricKey,
                success: true,
                reason: nil,
                timestamp: Date()
            )
        )
    }

    private func publishFailure(
        _ command: WorkspaceCommand,
        confidence: Double,
        message: String,
        requiresConfirmation: Bool = false,
        ambiguity: Bool = false,
        errorReason: String? = nil
    ) {
        let outcome = CommandExecutionOutcome(
            intent: command,
            confidence: confidence,
            ambiguity: ambiguity,
            requiresConfirmation: requiresConfirmation,
            errorReason: errorReason
        )
        lastCommandResult = .failure(command, message: message, outcome: outcome)
        workspaceStorage.recordMetric(
            .voiceCommand(
                intent: command.metricKey,
                success: false,
                reason: errorReason,
                timestamp: Date()
            )
        )
    }
}

// MARK: - Notification Names

extension Notification.Name {
    static let openWorkspacePage = Notification.Name("openWorkspacePage")
    static let showWorkspaceBoard = Notification.Name("showWorkspaceBoard")
    static let workspaceCommandExecuted = Notification.Name("workspaceCommandExecuted")
}

// MARK: - Voice Command Trigger View

/// Floating indicator when voice command is recognized
struct VoiceCommandIndicator: View {
    @ObservedObject var voiceCommands = WorkspaceVoiceCommandsService.shared
    @State private var showResult = false
    
    var body: some View {
        Group {
            if let result = voiceCommands.lastCommandResult, showResult {
                HStack(spacing: 12) {
                    Image(systemName: result.success ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .foregroundColor(result.success ? .green : .red)
                    
                    Text(result.message)
                        .font(.callout)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(.ultraThinMaterial)
                .cornerRadius(20)
                .shadow(radius: 10)
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.3), value: showResult)
        .onChange(of: voiceCommands.lastCommandResult?.timestamp) { oldValue, newValue in
            showResult = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                showResult = false
            }
        }
    }
}
