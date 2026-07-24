//
//  RequestListView.swift
//  Reqeast
//

import SwiftUI

struct RequestListView: View {
    @Bindable var store: ProjectStore
    let project: Project
    @Binding var selectedRequestId: Request.ID?

    @State private var showingFolderSheet = false
    @State private var editingFolder: RequestFolder?
    @State private var expandedFolderIds: Set<UUID> = []
    @State private var searchText = ""
    @State private var renamingRequest: Request?
    @State private var renameText = ""
    @State private var isRenaming = false
    @State private var showingProtocolPicker = false
    @State private var showingEnvironmentManager = false
    @State private var isSearchPresented = false
    @State private var showingSpecLinkPanel = false
    @State private var specSyncReviewContext: SpecSyncReviewContext?
    @State private var showStaleOnly = false
    @State private var showingDeleteStaleConfirmation = false

    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    private var staleCount: Int {
        SpecSyncHelpers.staleCount(for: project.id, store: store)
    }

    private var staleRequests: [Request] {
        store.staleRequests(for: project.id)
    }

    private var folders: [RequestFolder] {
        store.requestFolders(for: project.id)
    }

    var body: some View {
        Group {
            if isPhone {
                List {
                    requestListContent
                }
                .refreshable { await CloudSyncService.shared.syncChanges() }
            } else {
                List(selection: $selectedRequestId) {
                    requestListContent
                }
            }
        }
        .listStyle(.sidebar)
        .onAppear {
            expandedFolderIds = Set(folders.map(\.id))
            if store.requests(for: project.id).isEmpty {
                showingProtocolPicker = true
            }
        }
        .onChange(of: selectedRequestId) { _, newId in
            guard let newId else { return }
            let requests = store.requests(for: project.id)
            guard requests.contains(where: { $0.id == newId }) else {
                selectedRequestId = nil
                return
            }
            SessionRegistry.shared.markRead(for: newId)
            if let request = requests.first(where: { $0.id == newId }),
               let folderId = request.folderId {
                expandedFolderIds.insert(folderId)
            }
        }
        .onChange(of: folders) { _, newFolders in
            let newIds = Set(newFolders.map(\.id))
            for id in newIds where !expandedFolderIds.contains(id) {
                expandedFolderIds.insert(id)
            }
            expandedFolderIds = expandedFolderIds.intersection(newIds)
        }
        .overlay {
            if store.requests(for: project.id).isEmpty {
                ContentUnavailableView {
                    Label("No Requests", systemImage: "arrow.up.arrow.down")
                        .foregroundStyle(.secondary)
                } description: {
                    Text("Add a request to get started")
                } actions: {
                    Button(action: { showingProtocolPicker = true }) {
                        Label("New Request", systemImage: "plus.circle")
                    }
                    .buttonStyle(.borderedProminent)
                }
            } else if showStaleOnly && visibleRequestCount == 0 {
                ContentUnavailableView {
                    Label("No Stale Requests", systemImage: "clock.badge.exclamationmark")
                        .foregroundStyle(.secondary)
                } description: {
                    if staleCount == 0 {
                        Text("No requests were removed from the linked spec.")
                    } else {
                        Text("No stale requests match your search.")
                    }
                } actions: {
                    Button {
                        showStaleOnly = false
                    } label: {
                        Label("Show All Requests", systemImage: "list.bullet")
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
        }
        .navigationTitle(project.name)
        .searchable(text: $searchText, isPresented: $isSearchPresented, placement: .sidebar, prompt: "Filter Requests")
        .toolbar {
            if staleCount > 0 {
                ToolbarItem(placement: .automatic) {
                    Menu {
                        staleOperationsMenuContent
                    } label: {
                        Label("Stale Requests", systemImage: "clock.badge.exclamationmark")
                    }
                    .accessibilityLabel(String(localized: "Stale Requests"))
                }
            }

            ToolbarItemGroup(placement: .primaryAction) {
                if project.specLink != nil {
                    specToolbarBadge
                }
                addRequestMenu
            }
        }
        .sheet(isPresented: $showingFolderSheet) {
            RequestFolderSheet(store: store, projectId: project.id)
        }
        .sheet(item: $editingFolder) { folder in
            RequestFolderSheet(store: store, projectId: project.id, editingFolder: folder)
        }
        .sheet(isPresented: $showingProtocolPicker) {
            ProtocolPickerSheet { type in
                addRequest(type: type)
            }
        }
        .alert("Rename Request", isPresented: $isRenaming) {
            TextField("Name", text: $renameText)
                .devTextInput()
            Button("Cancel", role: .cancel) {}
            Button("Rename") { commitRename() }
        } message: {
            Text("Enter a new name for this request")
        }
        .onChange(of: isRenaming) { _, presented in
            if !presented {
                renamingRequest = nil
                renameText = ""
            }
        }
        #if DEBUG
        .onAppear {
            SpecSyncUITestSupport.applyRenameIfNeeded(store: store, projectId: project.id)
        }
        #endif
        .sheet(isPresented: $showingEnvironmentManager) {
            EnvironmentManagerView(
                environments: store.environmentsBinding(for: project.id),
                projectId: project.id
            )
        }
        .sheet(isPresented: $showingSpecLinkPanel) {
            NavigationStack {
                SpecLinkPanelView(store: store, project: project) { diff, fingerprint, bytes in
                    showingSpecLinkPanel = false
                    specSyncReviewContext = SpecSyncReviewContext(
                        diff: diff,
                        newFingerprint: fingerprint,
                        newBytes: bytes
                    )
                }
                .navigationTitle("Spec Link")
                .toolbarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Done") { showingSpecLinkPanel = false }
                    }
                }
            }
            #if os(macOS)
            .frame(width: 360, height: 420)
            #endif
        }
        .sheet(item: $specSyncReviewContext) { context in
            SpecSyncReviewSheet(
                store: store,
                project: project,
                diff: context.diff,
                newFingerprint: context.newFingerprint,
                newBytes: context.newBytes
            )
        }
        .confirmationDialog(
            String(localized: "Delete Stale Requests"),
            isPresented: $showingDeleteStaleConfirmation,
            titleVisibility: .visible
        ) {
            Button(SpecSyncHelpers.deleteStaleConfirmationButton(count: staleCount), role: .destructive) {
                bulkDeleteStaleRequests()
            }
        } message: {
            Text("These requests were removed from the linked spec. This action cannot be undone.")
        }
        .onChange(of: staleCount) { _, count in
            if count == 0 {
                showStaleOnly = false
            }
        }
        #if os(macOS)
        .focusedSceneValue(\.newRequest, { showingProtocolPicker = true })
        .focusedSceneValue(\.focusRequestFilter, { isSearchPresented = true })
        .focusedSceneValue(\.manageEnvironments, { showingEnvironmentManager = true })
        #endif
    }

    @ViewBuilder
    private var requestListContent: some View {
        let unfoldered = filteredRequests(store.unfolderedRequests(for: project.id))
        if !unfoldered.isEmpty || (folders.isEmpty && searchText.isEmpty && !showStaleOnly) {
            ForEach(unfoldered) { request in
                if isPhone {
                    NavigationLink {
                        RequestEditorView(store: store, requestId: request.id)
                            .navigationTitle(request.name)
                            #if !os(macOS)
                            .toolbarTitleDisplayMode(.inline)
                            #endif
                    } label: {
                        RequestRowView(request: request)
                    }
                    .contextMenu {
                        requestContextMenu(for: request)
                    }
                } else {
                    RequestRowView(request: request)
                        .tag(request.id)
                        .contextMenu {
                            requestContextMenu(for: request)
                        }
                }
            }
        }

        ForEach(folders) { folder in
            RequestFolderRow(
                folder: folder,
                store: store,
                projectId: project.id,
                expandedFolderIds: $expandedFolderIds,
                selectedRequestId: $selectedRequestId,
                folders: folders,
                searchText: searchText,
                showStaleOnly: showStaleOnly,
                onEdit: { editingFolder = $0 },
                onRenameRequest: { beginRename($0) },
                onAutoRenameRequest: { autoRename($0) }
            )
        }
    }

    private var visibleRequestCount: Int {
        let unfoldered = filteredRequests(store.unfolderedRequests(for: project.id)).count
        let foldered = folders.reduce(0) { count, folder in
            var requests = store.requests(for: project.id, inFolder: folder.id)
            if showStaleOnly {
                requests = requests.filter(\.isSpecStale)
            }
            return count + filteredRequests(requests).count
        }
        return unfoldered + foldered
    }

    // MARK: - Context Menu

    private func requestContextMenu(for request: Request) -> some View {
        RequestContextMenu(
            store: store,
            request: request,
            selectedRequestId: $selectedRequestId,
            folders: folders,
            onRename: { beginRename(request) },
            onAutoRename: { autoRename(request) }
        )
    }

    // MARK: - Rename

    private func beginRename(_ request: Request) {
        renameText = request.name
        renamingRequest = request
        isRenaming = true
    }

    private func commitRename() {
        guard let request = renamingRequest, !renameText.isEmpty else { return }
        store.renameRequest(request, to: renameText)
    }

    private func autoRename(_ request: Request) {
        Task {
            let name: String?
            switch request.type {
            case .http:
                guard let httpData = request.httpData else { return }
                name = await RequestNamingService.generateName(
                    method: httpData.method.rawLabel,
                    url: httpData.url,
                    statusCode: 0
                )
            case .tcp:
                guard let tcpData = request.tcpData, !tcpData.host.isEmpty else { return }
                let proto = tcpData.useTls ? "TLS" : "TCP"
                name = await RequestNamingService.generateNameForSocket(
                    protocol: proto, host: tcpData.host, port: tcpData.port
                )
            case .udp:
                guard let udpData = request.udpData, !udpData.host.isEmpty else { return }
                name = await RequestNamingService.generateNameForSocket(
                    protocol: "UDP", host: udpData.host, port: udpData.port
                )
            case .webSocket:
                guard let wsData = request.webSocketData, !wsData.url.isEmpty else { return }
                name = await RequestNamingService.generateName(
                    method: "", url: wsData.url, statusCode: 0, protocolType: "WebSocket"
                )
            case .sse:
                guard let sseData = request.sseData, !sseData.url.isEmpty else { return }
                name = await RequestNamingService.generateName(
                    method: "", url: sseData.url, statusCode: 0, protocolType: "SSE"
                )
            case .grpc:
                guard let grpcData = request.grpcData, !grpcData.authority.isEmpty else { return }
                name = await RequestNamingService.generateName(
                    method: grpcData.method,
                    url: grpcData.authority,
                    statusCode: 0,
                    protocolType: "gRPC"
                )
            }
            if let name {
                store.renameRequest(request, to: name)
            }
        }
    }

    // MARK: - Spec status

    @ViewBuilder
    private var staleOperationsMenuContent: some View {
        Button {
            showStaleOnly.toggle()
        } label: {
            Label(
                showStaleOnly
                    ? String(localized: "Show All Requests")
                    : String(localized: "Show Stale Only"),
                systemImage: showStaleOnly ? "list.bullet" : "line.3.horizontal.decrease.circle"
            )
        }
        .accessibilityIdentifier(SpecSyncAccessibility.staleFilterToggle)

        Divider()

        Button {
            store.dismissSpecStale(for: staleRequests)
        } label: {
            Label(
                SpecSyncHelpers.dismissAllStaleLabel(count: staleCount),
                systemImage: "checkmark.circle"
            )
        }
        .accessibilityIdentifier(SpecSyncAccessibility.dismissAllStaleButton)

        Button(role: .destructive) {
            showingDeleteStaleConfirmation = true
        } label: {
            Label(
                SpecSyncHelpers.deleteAllStaleLabel(count: staleCount),
                systemImage: "trash"
            )
        }
        .accessibilityIdentifier(SpecSyncAccessibility.deleteAllStaleButton)
    }

    private func bulkDeleteStaleRequests() {
        let targets = staleRequests
        if let selectedId = selectedRequestId, targets.contains(where: { $0.id == selectedId }) {
            selectedRequestId = nil
        }
        store.deleteRequests(targets)
    }

    private var addRequestMenu: some View {
        Menu {
            addMenuContent
        } label: {
            Image(systemName: "plus")
        }
        .accessibilityIdentifier("add-request-menu")
    }

    private var specToolbarBadge: some View {
        SpecStatusToolbarBadge(
            label: specBadgeLabel,
            accessibilityState: specBadgeAccessibilityState,
            systemImage: specToolbarIcon,
            highlightsStaleState: staleCount > 0
        ) {
            showingSpecLinkPanel = true
        }
    }

    private var specToolbarIcon: String {
        if staleCount > 0 {
            return "clock.badge.exclamationmark"
        }
        return project.specLink?.isDetached == false ? "link" : "doc.text"
    }

    private var specBadgeLabel: String {
        let isLinked = project.specLink?.isDetached == false
        let isCompact = horizontalSizeClass == .compact
        return isCompact
            ? SpecSyncHelpers.compactBadgeLabel(staleCount: staleCount)
            : SpecSyncHelpers.regularBadgeLabel(staleCount: staleCount, isLinked: isLinked)
    }

    private var specBadgeAccessibilityState: String {
        let isLinked = project.specLink?.isDetached == false
        var parts = [
            isLinked
                ? String(localized: "Linked spec")
                : String(localized: "Spec snapshot"),
        ]
        if staleCount > 0 {
            parts.append(
                String(
                    format: String(localized: "Spec · %lld stale"),
                    locale: .current,
                    staleCount
                )
            )
        }
        return parts.joined(separator: ", ")
    }

    // MARK: - Helpers

    @ViewBuilder
    private var addMenuContent: some View {
        Button(action: { showingProtocolPicker = true }) {
            Label("Choose Protocol…", systemImage: "plus.circle")
        }

        Divider()

        Button(action: { addRequest(type: .http) }) {
            Label("HTTP Request", systemImage: "arrow.up.arrow.down")
        }
        Button(action: { addRequest(type: .tcp) }) {
            Label("TCP Connection", systemImage: "cable.connector")
        }
        Button(action: { addRequest(type: .udp) }) {
            Label("UDP Datagram", systemImage: "dot.radiowaves.up.forward")
        }
        Button(action: { addRequest(type: .webSocket) }) {
            Label("WebSocket", systemImage: "arrow.left.arrow.right")
        }
        Button(action: { addRequest(type: .sse) }) {
            Label("EventSource (SSE)", systemImage: "antenna.radiowaves.left.and.right")
        }
        Button(action: { addRequest(type: .grpc) }) {
            Label("gRPC", systemImage: "arrow.up.right.and.arrow.down.left")
        }

        Divider()

        Button(action: { showingFolderSheet = true }) {
            Label("New Folder", systemImage: "folder.badge.plus")
        }
    }

    private func filteredRequests(_ requests: [Request]) -> [Request] {
        var result = requests
        if showStaleOnly {
            result = result.filter(\.isSpecStale)
        }
        guard !searchText.isEmpty else { return result }
        return result.filter { request in
            request.name.localizedCaseInsensitiveContains(searchText)
            || (request.httpData?.url ?? "").localizedCaseInsensitiveContains(searchText)
            || (request.grpcData?.authority ?? "").localizedCaseInsensitiveContains(searchText)
            || request.type.localizedName.localizedCaseInsensitiveContains(searchText)
        }
    }

    private func addRequest(type: RequestType = .http) {
        let requestCount = store.requests(for: project.id).count
        let request = Request(
            projectId: project.id,
            name: "New \(type.localizedName) Request",
            type: type,
            sortOrder: requestCount
        )
        store.addRequest(request)
        selectedRequestId = request.id
    }
}
