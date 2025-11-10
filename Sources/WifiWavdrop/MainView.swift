import SwiftUI

public struct MainView: View {
    @StateObject private var driveManager = ExternalDriveManager()
    @State private var selectedDrive: ExternalDrive?
    @State private var selectedTab = 0
    @State private var showingFileBrowser = false
    @State private var showingSettings = false
    @State private var isProcessing = false
    
    public init() {}
    
    public var body: some View {
        EmptyView()
    }
}
