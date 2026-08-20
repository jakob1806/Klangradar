import SwiftUI

/// Wird auf jeden der fünf Redaktions-Tab-Roots angewendet — liefert die
/// globale Suche und den zentralen "+" aus Punkt 2 des Redesigns, ohne dass
/// jeder Tab diese Logik einzeln dupliziert.
struct EditorialGlobalToolbar: ViewModifier {
    @ObservedObject var auth: AuthStore
    let repository: EditorialRepository
    var onCreated: (() -> Void)?

    @State private var showsSearch = false
    @State private var createKind: EditorialEntityKind?
    @State private var showsCreateVenue = false

    func body(content: Content) -> some View {
        content
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button {
                        showsSearch = true
                    } label: {
                        Image(systemName: "magnifyingglass")
                    }
                    .accessibilityLabel("Redaktion durchsuchen")
                }
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button("Person anlegen", systemImage: "person.badge.plus") { createKind = .person }
                        Button("Ensemble anlegen", systemImage: "person.3.sequence.fill") { createKind = .ensemble }
                        Button("Werk anlegen", systemImage: "music.note.list") { createKind = .work }
                        Button("Venue anlegen", systemImage: "building.columns") { showsCreateVenue = true }
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("Neuer Eintrag")
                }
            }
            .sheet(isPresented: $showsSearch) {
                EditorialSearchView(auth: auth, repository: repository)
            }
            .sheet(item: $createKind) { kind in
                EditorialCreateEntityView(auth: auth, repository: repository, kind: kind) { _ in onCreated?() }
            }
            .sheet(isPresented: $showsCreateVenue) {
                EditorialCreateVenueView(auth: auth, repository: repository) { _ in onCreated?() }
            }
    }
}

extension View {
    func editorialGlobalToolbar(auth: AuthStore, repository: EditorialRepository, onCreated: (() -> Void)? = nil) -> some View {
        modifier(EditorialGlobalToolbar(auth: auth, repository: repository, onCreated: onCreated))
    }
}
