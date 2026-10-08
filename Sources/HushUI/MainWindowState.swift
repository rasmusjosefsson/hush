import Foundation
import SwiftUI

@MainActor
@Observable
public final class MainWindowState {
    public var selectedItem: SidebarItem = .transcribe {
        didSet {
            guard oldValue != selectedItem, !isTraversingHistory else { return }
            backStack.append(oldValue)
            forwardStack.removeAll()
        }
    }
    private var backStack: [SidebarItem] = []
    private var forwardStack: [SidebarItem] = []
    private var isTraversingHistory = false

    public var canGoBack: Bool { !backStack.isEmpty }
    public var canGoForward: Bool { !forwardStack.isEmpty }

    public func goBack() {
        guard let item = backStack.popLast() else { return }
        forwardStack.append(selectedItem)
        traverse(to: item)
    }

    public func goForward() {
        guard let item = forwardStack.popLast() else { return }
        backStack.append(selectedItem)
        traverse(to: item)
    }

    private func traverse(to item: SidebarItem) {
        isTraversingHistory = true
        selectedItem = item
        isTraversingHistory = false
    }
    public var showingProgressDetail = false

    public init() {}

    /// Navigate to the Transcribe tab to show a transcription detail.
    public func navigateToTranscription() {
        selectedItem = .transcribe
    }
}

