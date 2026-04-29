import Foundation

/// Generic undo/redo history for any equatable, codable state type.
struct EditHistory<State: Equatable & Codable> {
    private(set) var undoStack: [State] = []
    private(set) var redoStack: [State] = []
    var limit: Int = 100

    /// Push a state onto the undo stack, trimming oldest if over limit.
    mutating func push(_ state: State) {
        undoStack.append(state)
        if undoStack.count > limit {
            undoStack.removeFirst()
        }
    }

    /// Undo: pops the last undo state, pushes current to redo. Returns the state to restore, or nil.
    mutating func undo(current: State) -> State? {
        guard let previous = undoStack.popLast() else { return nil }
        redoStack.append(current)
        return previous
    }

    /// Redo: pops the last redo state, pushes current to undo. Returns the state to restore, or nil.
    mutating func redo(current: State) -> State? {
        guard let next = redoStack.popLast() else { return nil }
        undoStack.append(current)
        return next
    }

    /// Clears all redo history (called after a new change invalidates the redo path).
    mutating func clearRedo() {
        redoStack.removeAll()
    }

    /// Clears all history.
    mutating func clearAll() {
        undoStack.removeAll()
        redoStack.removeAll()
    }

    /// Clears undo and sets redo to a single state (used for "reset all" where redo restores the previous state).
    mutating func resetWithRedo(_ redoState: State) {
        undoStack.removeAll()
        redoStack = [redoState]
    }

    var canUndo: Bool { !undoStack.isEmpty }
    var canRedo: Bool { !redoStack.isEmpty }
}
