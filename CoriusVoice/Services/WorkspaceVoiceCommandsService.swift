import Foundation
import SwiftUI

// MARK: - Workspace Voice Commands Service

/// Handles voice commands for workspace operations
/// Integrates with the existing voice transcription system
@MainActor
class WorkspaceVoiceCommandsService: ObservableObject {
    static let shared = WorkspaceVoiceCommandsService()
    
    private let workspaceStorage = WorkspaceStorageServiceOptimized.shared
    private let sessionIntegration = SessionIntegrationService.shared
    
    @Published var lastCommandResult: CommandResult?
    @Published var isProcessing = false
    
    private init() {}
    
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
    }
    
    // MARK: - Command Result
    
    struct CommandResult {
        let command: WorkspaceCommand
        let success: Bool
        let message: String
        let createdItem: WorkspaceItem?
        let timestamp: Date
        
        static func success(_ command: WorkspaceCommand, message: String, item: WorkspaceItem? = nil) -> CommandResult {
            CommandResult(command: command, success: true, message: message, createdItem: item, timestamp: Date())
        }
        
        static func failure(_ command: WorkspaceCommand, message: String) -> CommandResult {
            CommandResult(command: command, success: false, message: message, createdItem: nil, timestamp: Date())
        }
    }
    
    // MARK: - Process Voice Input
    
    /// Processes transcribed text for workspace commands
    /// - Parameter text: The transcribed voice input
    /// - Returns: True if a command was recognized and executed
    @discardableResult
    func processVoiceInput(_ text: String) -> Bool {
        let lowercasedText = text.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Try to match commands
        for command in WorkspaceCommand.allCases {
            for pattern in command.patterns {
                if lowercasedText.contains(pattern) {
                    isProcessing = true
                    executeCommand(command, context: extractContext(from: lowercasedText, after: pattern))
                    isProcessing = false
                    return true
                }
            }
        }
        
        return false
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
    
    private func executeCommand(_ command: WorkspaceCommand, context: String) {
        switch command {
        case .createTask:
            executeCreateTask(title: context)
            
        case .moveTask:
            executeMoveTask(context: context)
            
        case .completeTask:
            executeCompleteTask(context: context)
            
        case .deleteTask:
            executeDeleteTask(context: context)
            
        case .createPage:
            executeCreatePage(title: context)
            
        case .openPage:
            executeOpenPage(context: context)
            
        case .showBoard:
            executeShowBoard()
            
        case .addColumn:
            executeAddColumn(name: context)
            
        case .convertSession:
            executeConvertSession()
            
        case .importSessions:
            executeImportSessions()
            
        case .quickNote:
            executeQuickNote(content: context)
        }
    }
    
    // MARK: - Task Commands
    
    private func executeCreateTask(title: String) {
        guard let defaultDatabase = workspaceStorage.databases.first else {
            lastCommandResult = .failure(.createTask, message: "No hay tablero disponible. Crea uno primero.")
            return
        }
        
        let taskTitle = title.isEmpty ? "Nueva tarea" : title.capitalized
        let task = workspaceStorage.createTask(
            title: taskTitle,
            databaseID: defaultDatabase.id
        )
        
        lastCommandResult = .success(.createTask, message: "Tarea '\(taskTitle)' creada", item: task)
        print("🎤 Voice command: Created task '\(taskTitle)'")
    }
    
    private func executeMoveTask(context: String) {
        // Parse: "mover tarea X a columna Y" or "move task X to Y"
        let parts = context.components(separatedBy: " a ").count > 1
            ? context.components(separatedBy: " a ")
            : context.components(separatedBy: " to ")
        
        guard parts.count >= 2 else {
            lastCommandResult = .failure(.moveTask, message: "Especifica la tarea y el destino. Ej: 'mover tarea X a completado'")
            return
        }
        
        let taskQuery = parts[0].trimmingCharacters(in: .whitespaces)
        let targetColumn = parts[1].trimmingCharacters(in: .whitespaces).lowercased()
        
        // Find the task
        guard let task = findTask(matching: taskQuery) else {
            lastCommandResult = .failure(.moveTask, message: "No encontré la tarea '\(taskQuery)'")
            return
        }
        
        // Find target column
        guard let database = workspaceStorage.databases.first(where: { $0.id == task.workspaceID }),
              let column = database.kanbanColumns.first(where: { 
                  $0.name.lowercased().contains(targetColumn) 
              }) else {
            lastCommandResult = .failure(.moveTask, message: "No encontré la columna '\(targetColumn)'")
            return
        }
        
        // Move the task
        workspaceStorage.moveItem(task.id, toStatus: column.name)
        lastCommandResult = .success(.moveTask, message: "Tarea movida a '\(column.name)'")
        print("🎤 Voice command: Moved task to '\(column.name)'")
    }
    
    private func executeCompleteTask(context: String) {
        let taskQuery = context.isEmpty ? nil : context
        
        // Find task to complete
        let task: WorkspaceItem?
        if let query = taskQuery {
            task = findTask(matching: query)
        } else {
            // Complete the most recent in-progress task
            task = workspaceStorage.items
                .filter { $0.itemType == .task }
                .filter { item in
                    guard let statusName = workspaceStorage.statusValue(for: item)?.lowercased() else {
                        return false
                    }
                    return statusName.contains("progress")
                        || statusName.contains("doing")
                        || statusName.contains("haciendo")
                }
                .sorted { $0.updatedAt > $1.updatedAt }
                .first
        }
        
        guard let taskToComplete = task else {
            lastCommandResult = .failure(.completeTask, message: "No encontré la tarea para completar")
            return
        }
        
        // Find "Done" or "Completed" column
        if let database = workspaceStorage.databases.first(where: { $0.id == taskToComplete.workspaceID }),
           let doneColumn = database.kanbanColumns.first(where: { 
               $0.name.lowercased().contains("done") || 
               $0.name.lowercased().contains("complet") ||
               $0.name.lowercased().contains("hecho")
           }) {
            workspaceStorage.moveItem(taskToComplete.id, toStatus: doneColumn.name)
            lastCommandResult = .success(.completeTask, message: "Tarea '\(taskToComplete.title)' completada ✓")
        } else {
            lastCommandResult = .failure(.completeTask, message: "No encontré la columna de completados")
        }
    }
    
    private func executeDeleteTask(context: String) {
        guard !context.isEmpty, let task = findTask(matching: context) else {
            lastCommandResult = .failure(.deleteTask, message: "Especifica qué tarea eliminar")
            return
        }
        
        workspaceStorage.deleteItem(task.id)
        lastCommandResult = .success(.deleteTask, message: "Tarea '\(task.title)' eliminada")
    }
    
    // MARK: - Page Commands
    
    private func executeCreatePage(title: String) {
        let pageTitle = title.isEmpty ? "Nueva página" : title.capitalized
        let page = WorkspaceItem.page(title: pageTitle, icon: "📝", parentID: nil)
        workspaceStorage.createItem(page)
        lastCommandResult = .success(.createPage, message: "Página '\(pageTitle)' creada", item: page)
        print("🎤 Voice command: Created page '\(pageTitle)'")
    }
    
    private func executeOpenPage(context: String) {
        guard let page = workspaceStorage.items.first(where: { 
            $0.itemType == .page && $0.title.lowercased().contains(context.lowercased())
        }) else {
            lastCommandResult = .failure(.openPage, message: "No encontré la página '\(context)'")
            return
        }
        
        // Post notification to open page (UI will handle this)
        NotificationCenter.default.post(
            name: .openWorkspacePage,
            object: nil,
            userInfo: ["pageID": page.id]
        )
        lastCommandResult = .success(.openPage, message: "Abriendo '\(page.title)'", item: page)
    }
    
    // MARK: - Board Commands
    
    private func executeShowBoard() {
        NotificationCenter.default.post(name: .showWorkspaceBoard, object: nil)
        lastCommandResult = .success(.showBoard, message: "Mostrando tablero")
    }
    
    private func executeAddColumn(name: String) {
        guard let database = workspaceStorage.databases.first else {
            lastCommandResult = .failure(.addColumn, message: "No hay tablero disponible")
            return
        }
        
        let columnName = name.isEmpty ? "Nueva columna" : name.capitalized
        workspaceStorage.addColumn(to: database.id, name: columnName)
        lastCommandResult = .success(.addColumn, message: "Columna '\(columnName)' añadida")
    }
    
    // MARK: - Session Integration Commands
    
    private func executeConvertSession() {
        guard let defaultDatabase = workspaceStorage.databases.first else {
            lastCommandResult = .failure(.convertSession, message: "No hay tablero disponible")
            return
        }
        
        if let task = sessionIntegration.createTaskFromLastSession(databaseID: defaultDatabase.id) {
            lastCommandResult = .success(.convertSession, message: "Sesión convertida a tarea", item: task)
        } else {
            lastCommandResult = .failure(.convertSession, message: "No hay sesiones recientes para convertir")
        }
    }
    
    private func executeImportSessions() {
        guard let defaultDatabase = workspaceStorage.databases.first else {
            lastCommandResult = .failure(.importSessions, message: "No hay tablero disponible")
            return
        }
        
        let imported = sessionIntegration.autoImportRecentSessions(databaseID: defaultDatabase.id)
        lastCommandResult = .success(.importSessions, message: "Importadas \(imported.count) sesiones")
    }
    
    // MARK: - Quick Note
    
    private func executeQuickNote(content: String) {
        guard !content.isEmpty else {
            lastCommandResult = .failure(.quickNote, message: "Di el contenido de la nota")
            return
        }
        
        var page = WorkspaceItem.page(
            title: "Nota rápida - \(Date().formatted(date: .abbreviated, time: .shortened))",
            icon: "📝",
            parentID: nil
        )
        page.blocks = [Block(type: .paragraph, content: content)]
        workspaceStorage.createItem(page)
        
        lastCommandResult = .success(.quickNote, message: "Nota guardada", item: page)
        print("🎤 Voice command: Quick note saved")
    }
    
    // MARK: - Helpers
    
    private func findTask(matching query: String) -> WorkspaceItem? {
        let lowercasedQuery = query.lowercased()
        return workspaceStorage.items
            .filter { $0.itemType == .task }
            .first { $0.title.lowercased().contains(lowercasedQuery) }
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
