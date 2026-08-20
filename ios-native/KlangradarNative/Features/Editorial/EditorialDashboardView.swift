import PhotosUI
import SwiftUI
import UniformTypeIdentifiers
import UIKit

struct EditorialDashboardView: View {
    @ObservedObject var auth: AuthStore
    let repository: EditorialRepository

    @State private var events: [EditorialEvent] = []
    @State private var entities: [EditorialEntity] = []
    @State private var searchText = ""
    @State private var scope: EditorialScope = .events
    @State private var createKind: EditorialEntityKind?
    @State private var isLoading = true
    @State private var errorMessage: String?

    var body: some View {
        ZStack {
            EditorialBackground()
            VStack(spacing: 0) {
                EditorialScopePicker(selection: $scope)
                    .padding(.vertical, 8)

                Group {
                if isLoading { ProgressView("Redaktionsdaten werden geladen …").tint(KlangradarTheme.accent) }
                else if let errorMessage { ContentUnavailableView("Redaktion nicht verfügbar", systemImage: "exclamationmark.shield", description: Text(errorMessage)) }
                else { resultList }
                }
            }
        }
        .navigationTitle("Redaktion")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $searchText, prompt: "\(scope.title) durchsuchen")
        .toolbar {
            if let kind = scope.creatableKind {
                ToolbarItem(placement: .primaryAction) {
                    Button("\(kind.singularTitle) hinzufügen", systemImage: "plus") { createKind = kind }
                }
            }
        }
        .sheet(item: $createKind) { kind in
            EditorialCreateEntityView(auth: auth, repository: repository, kind: kind) { _ in
                Task { await load() }
            }
        }
        .task(id: scope) { await load() }
    }

    private var resultList: some View {
        List {
            Section { EditorialModeBanner() }
                .listRowBackground(Color.clear)
                .listRowInsets(.init(top: 8, leading: 16, bottom: 8, trailing: 16))

            Section {
                if scope == .events {
                    ForEach(filteredEvents) { event in
                        NavigationLink {
                            EditorialEventEditorView(auth: auth, repository: repository, initialEvent: event)
                        } label: {
                            EditorialEventRow(event: event)
                        }
                    }
                } else {
                    ForEach(filteredEntities) { entity in
                        NavigationLink {
                            EditorialEntityEditorView(auth: auth, repository: repository, entity: entity)
                        } label: {
                            Label {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(entity.title)
                                    if let subtitle = entity.subtitle { Text(subtitle).font(.caption).foregroundStyle(.secondary) }
                                }
                            } icon: {
                                EditorialThumbnail(url: entity.imageURL, symbol: entity.kind.symbol)
                            }
                        }
                    }
                }
            } header: {
                HStack {
                    Text(scope.title)
                    Spacer()
                    Text("\(scope == .events ? filteredEvents.count : filteredEntities.count)")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .listStyle(.insetGrouped)
        .refreshable { await load() }
    }

    private var filteredEvents: [EditorialEvent] {
        guard !searchText.isEmpty else { return events }
        return events.filter { $0.title.localizedStandardContains(searchText) || ($0.subtitle?.localizedStandardContains(searchText) == true) || $0.venueName.localizedStandardContains(searchText) }
    }

    private var filteredEntities: [EditorialEntity] {
        guard !searchText.isEmpty else { return entities }
        return entities.filter { $0.title.localizedStandardContains(searchText) || ($0.subtitle?.localizedStandardContains(searchText) == true) }
    }

    @MainActor private func load() async {
        guard let token = auth.accessToken else { errorMessage = "Bitte zuerst anmelden."; isLoading = false; return }
        isLoading = events.isEmpty
        defer { isLoading = false }
        do {
            if scope == .events {
                events = try await repository.events(search: "", token: token)
            } else if let kind = scope.entityKind {
                entities = try await repository.entities(kind: kind, token: token)
            }
            errorMessage = nil
        } catch { errorMessage = error.localizedDescription }
    }
}

private struct EditorialScopePicker: View {
    @Binding var selection: EditorialScope

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(EditorialScope.allCases) { scope in
                    Button {
                        withAnimation(.snappy(duration: 0.22)) { selection = scope }
                    } label: {
                        Label(scope.title, systemImage: scope.symbol)
                            .font(.subheadline.weight(selection == scope ? .semibold : .medium))
                            .padding(.horizontal, 13)
                            .padding(.vertical, 9)
                            .foregroundStyle(selection == scope ? Color.white : Color.primary)
                            .background(selection == scope ? KlangradarTheme.accent : Color.clear, in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(selection == scope ? .isSelected : [])
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 4)
        }
        .background(.ultraThinMaterial)
    }
}

private enum EditorialScope: String, CaseIterable, Identifiable {
    case events, venues, persons, ensembles, works
    var id: String { rawValue }
    var title: String { switch self { case .events: "Veranstaltungen"; case .venues: "Venues"; case .persons: "Personen"; case .ensembles: "Ensembles"; case .works: "Werke" } }
    var symbol: String { switch self { case .events: "calendar"; case .venues: "building.columns"; case .persons: "person"; case .ensembles: "person.3"; case .works: "music.note" } }
    var entityKind: EditorialEntityKind? { switch self { case .events: nil; case .venues: .venue; case .persons: .person; case .ensembles: .ensemble; case .works: .work } }
    var creatableKind: EditorialEntityKind? { switch self { case .persons: .person; case .ensembles: .ensemble; case .works: .work; default: nil } }
}

private struct EditorialThumbnail: View {
    let url: String?
    let symbol: String
    var body: some View {
        AsyncImage(url: url.flatMap(URL.init(string:))) { image in image.resizable().scaledToFill() } placeholder: {
            Color.secondary.opacity(0.1).overlay { Image(systemName: symbol).foregroundStyle(.secondary) }
        }
        .frame(width: 42, height: 42).clipShape(.rect(cornerRadius: 9)).clipped()
    }
}

