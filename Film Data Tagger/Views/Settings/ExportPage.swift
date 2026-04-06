//
//  ExportPage.swift
//  Film Data Tagger
//

import SwiftUI

struct ExportPage: View {
    let viewModel: FilmLogViewModel
    @State private var activeExport: ExportType?
    @State private var shareURL: URL?

    private enum ExportType { case json, csv }

    var body: some View {
        SettingsDetailPage(title: "Export") {
            SettingsHeroSection(
                icon: {
                    ZStack {
                        RoundedRectangle(cornerRadius: 16)
                            .fill(Color.init(hex: 0x303030))
                            .overlay {
                                RoundedRectangle(cornerRadius: 16)
                                    .inset(by: 2)
                                    .stroke(Color.init(hex: 0x787878), lineWidth: 2)
                            }
                        Image(systemName: "square.and.arrow.up")
                            .font(.system(size: 21, weight: .bold, design: .default))
                            .foregroundStyle(Color.white)
                    }
                },
                title: "Data export",
                subtitle: "Export your data for backup, external programs, or spreadsheet analysis."
            )
            SettingsSection(caption: "JSON is best for backup and external programs. CSV is best for spreadsheets.\nSome data, like reference photos, is not included in exports.") {
                SettingsTaskRow(text: "Export as JSON", color: .accentColor, isActive: activeExport == .json, isDisabled: activeExport != nil) {
                    guard activeExport == nil else { return }
                    activeExport = .json
                    Task(priority: .medium) {
                        shareURL = await viewModel.exportJSON()
                        activeExport = nil
                    }
                }
                SettingsSeparator()
                SettingsTaskRow(text: "Export as CSV", color: .accentColor, isActive: activeExport == .csv, isDisabled: activeExport != nil) {
                    guard activeExport == nil else { return }
                    activeExport = .csv
                    Task(priority: .medium) {
                        shareURL = await viewModel.exportCSV()
                        activeExport = nil
                    }
                }
            }
        }
        .sheet(isPresented: Binding(get: { shareURL != nil }, set: { if !$0 { shareURL = nil } })) {
            if let shareURL {
                ShareSheet(url: shareURL)
            }
        }
    }
}

#Preview {
    let container = PreviewSampleData.makeContainer()
    let viewModel = FilmLogViewModel(store: PreviewSampleData.makeStore(container: container))
    NavigationStack {
        ExportPage(viewModel: viewModel)
    }
    .modelContainer(container)
    .preferredColorScheme(.dark)
}
