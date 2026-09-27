import SwiftUI

struct ContentView: View {
    @State private var catalog: AmiiboCatalog?
    @State private var errorMessage: String?
    @State private var searchText = ""
    @State private var arSelection: Amiibo?

    private var filteredFigures: [Amiibo] {
        (catalog?.figures ?? []).filter {
            searchText.isEmpty || $0.name.localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                if let errorMessage {
                    ContentUnavailableView("Catalog unavailable", systemImage: "exclamationmark.triangle",
                                           description: Text(errorMessage))
                } else if catalog == nil {
                    ProgressView("Opening your collection…")
                } else {
                    List {
                        Section {
                            VStack(alignment: .leading, spacing: 8) {
                                Label("A little Hyrule, anywhere", systemImage: "arkit").font(.headline)
                                Text("Explore your figures, then bring Young Link or Ocarina of Time Link into your room.")
                                    .foregroundStyle(.secondary)
                                Text("2 figures ready for AR · \(catalog?.figures.count ?? 0) in the catalog")
                                    .font(.caption).foregroundStyle(.secondary)
                            }.padding(.vertical, 6)
                        }
                        Section("Figures") {
                            ForEach(filteredFigures) { figure in
                                NavigationLink {
                                    FigureDetailView(figure: figure) { arSelection = figure }
                                } label: {
                                    HStack(spacing: 14) {
                                        Image(figure.imageName)
                                            .resizable().scaledToFit().frame(width: 64, height: 76)
                                            .accessibilityHidden(true)
                                        VStack(alignment: .leading, spacing: 5) {
                                            Text(figure.name).font(.headline)
                                            Label(figure.model == nil ? "Catalog only" : "Ready for AR",
                                                  systemImage: figure.model == nil ? "photo" : "arkit")
                                                .font(.caption).foregroundStyle(.secondary)
                                        }
                                    }.padding(.vertical, 4)
                                }
                            }
                        }
                    }
                    .overlay {
                        if filteredFigures.isEmpty { ContentUnavailableView.search(text: searchText) }
                    }
                    .searchable(text: $searchText, prompt: "Find a figure")
                }
            }
            .navigationTitle("Amiibo Collection")
        }
        .task {
            do { catalog = try AmiiboCatalog.bundled() }
            catch { errorMessage = error.localizedDescription }
        }
        .fullScreenCover(item: $arSelection) { figure in
            if let catalog { ARExperienceView(catalog: catalog, initialFigure: figure) }
        }
        .tint(.teal)
    }
}

private struct FigureDetailView: View {
    let figure: Amiibo
    let openAR: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Image(figure.imageName)
                    .resizable().scaledToFit().frame(maxWidth: .infinity).frame(height: 260)
                    .accessibilityLabel(figure.name)
                if figure.model != nil {
                    Button(action: openAR) {
                        Label("Place in your room", systemImage: "arkit")
                            .frame(maxWidth: .infinity).padding(.vertical, 6)
                    }.buttonStyle(.borderedProminent)
                    Text("Move your phone to find a table or floor, then tap to place. You can also scan another figure’s QR code from the camera.")
                        .font(.subheadline).foregroundStyle(.secondary)
                } else {
                    Label("3D model not yet available", systemImage: "cube.transparent")
                        .foregroundStyle(.secondary)
                }
                VStack(alignment: .leading, spacing: 10) {
                    Text("Exclusive rewards").font(.title2.bold())
                    Text(figure.exclusives)
                }
                VStack(alignment: .leading, spacing: 10) {
                    Text("Additional drops").font(.title2.bold())
                    Text(figure.extras)
                }
                Text("Tears of the Kingdom reward notes from your original collection.")
                    .font(.caption).foregroundStyle(.secondary)
            }.padding()
        }
        .navigationTitle(figure.name)
        .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview { ContentView() }
