//
//  RollDetailView.swift
//  Film Data Tagger
//

import SwiftUI
import Combine

private struct RollDetailHeader: View {
    let icon: String
    let title: String

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .frame(width: 20, height: 18, alignment: .center)
            Text(title)
        }
        .font(.system(size: 15, weight: .bold, design: .default))
        .fontWidth(.expanded)
        .foregroundStyle(Color.white.opacity(0.5))
        .padding(.horizontal, 16)
    }
}

private struct RollDetailSeparator: View {
    var body: some View {
        Rectangle()
            .frame(height: 1)
            .frame(maxWidth: .infinity)
            .padding(.leading, 16)
            .padding(.trailing, 16)
            .foregroundStyle(Color.white.opacity(0.2))
    }
}

// MARK: - Loaded Section

private struct RollDetailLoadedSection: View {
    let roll: RollSnapshot
    let exposures: [LogItemSnapshot]
    @Binding var isEditing: Bool
    var onUpdateCreatedAt: ((UUID, Date, String, String?) -> Void)?

    let editContainerColor: Color = Color(hex: 0x262626)

    @State private var isEditingDate: Bool = false
    @State private var isEditingTime: Bool = false

    private var shouldShowCompact: Bool {
        UIScreen.currentWidth < 390
    }

    var body: some View {
        VStack(alignment: .leading, spacing: isEditing ? 16 : 11) {
            RollDetailHeader(icon: "arrow.clockwise", title: "Loaded")

            HStack(alignment: .firstTextBaseline, spacing: isEditing ? 12 : 5) {
                Text(shouldShowCompact ? "Sept 24, 2026" : "September 24, 2026")
                    .frame(
                        width: isEditing ? min(UIScreen.currentWidth - 20 - 125 - 12, 267) : nil,
                        height: CGFloat(isEditing ? 44 : 20)
                    )
                    .background(Capsule().foregroundStyle(editContainerColor).opacity(isEditing ? 1 : 0))
                    .foregroundStyle(isEditingDate ? Color.accentColor : Color.white)
                    .animation(.easeInOut(duration: 0.25), value: isEditingDate) // TODO: tune
                    .accessibilityLabel("Edit roll load date")
                    .contentShape(Capsule())
                    .onTapGesture {
                        if isEditing {
                            isEditingTime = false
                            isEditingDate.toggle()
                        }
                    }

                Text("3:35 PM")
                    .frame(width: isEditing ? 125 : nil, height: isEditing ? 44 : 20)
                    .background(Capsule().foregroundStyle(editContainerColor).opacity(isEditing ? 1 : 0))
                    .foregroundStyle(isEditingTime ? Color.accentColor : Color.white.opacity(isEditing ? 1.0 : 0.7))
                    .animation(.easeInOut(duration: 0.25), value: isEditingDate) // TODO: tune
                    .accessibilityLabel("Edit roll load time")
                    .contentShape(Capsule())
                    .onTapGesture {
                        if isEditing {
                            isEditingDate = false
                            isEditingTime.toggle()
                        }
                    }
            }.font(.system(size: 17, weight: isEditing ? .medium : .semibold, design: .default))
            .fontWidth(.expanded)
            .padding(.horizontal, isEditing ? 10 : 16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .zIndex(2)
            .overlay(alignment: .top) {
                ZStack(alignment: .top) {
                    DatePicker("Roll load date", selection: .constant(.now), displayedComponents: .date)
                        .zIndex(3)
                        .datePickerStyle(.graphical)
                        .padding(.horizontal, 8) // TODO: tune padding
                        .padding(.bottom, 6)
                        .glassEffectCompat(in: RoundedRectangle(cornerRadius: 22), interactive: false)
                        .padding(.horizontal, 6)
                        .offset(y: 44 + 12)
                        .offset(y: isEditingDate ? 0 : -20) // TODO: tune
                        .opacity(isEditingDate ? 1 : 0)
                        .animation(.easeInOut(duration: 0.25), value: isEditingDate) // TODO: tune
                    DatePicker("Roll load time", selection: .constant(.now), displayedComponents: .hourAndMinute)
                        .zIndex(3)
                        .datePickerStyle(.wheel)
                        .labelsHidden()
                        .padding(.horizontal, 8) // TODO: tune padding
                        .padding(.bottom, 6)
                        .frame(maxWidth: .infinity)
                        .glassEffectCompat(in: RoundedRectangle(cornerRadius: 22), interactive: false)
                        .padding(.horizontal, 6)
                        .offset(y: 44 + 12)
                        .offset(y: isEditingTime ? 0 : -20)
                        .opacity(isEditingTime ? 1 : 0)
                        .animation(.easeInOut(duration: 0.25), value: isEditingTime) // TODO: tune
                }
            }

            // this section should only be visible if the roll was started on another timezone
            HStack(spacing: 0) {
                HStack(alignment: .firstTextBaseline, spacing: isEditing ? 13 : 6) {
                    Image(systemName: "globe.badge.clock")
                        .foregroundStyle(Color.white.opacity(0.7))
                    Text("London")
                        .foregroundStyle(Color.white.opacity(isEditing ? 0.95 : 0.7))
                }.frame(maxHeight: .infinity)
                .contentShape(Rectangle())
                .onTapGesture {
                    // switch time zone between local and the previous timezone.
                }.padding(.trailing, 16)

                Button(action: {
                    // set time zone to local
                }) {
                    Image(systemName: "xmark")
                        .font(.system(size: 16, weight: .bold, design: .default))
                        .foregroundStyle(Color.white.opacity(0.95))
                        .frame(width: 40, height: 40)
                        .contentShape(Circle())
                }.buttonStyle(.plain)
                .frame(width: 40, height: 40)
                .glassEffectCompat(in: Circle(), interactive: true)
                .padding(.trailing, 2)
                .opacity(isEditing ? 1.0 : 0)
            }.padding(.leading, isEditing ? 12 : 0)
            .font(.system(size: 17, weight: .medium, design: .default))
            .fontWidth(.expanded)
            .frame(height: isEditing ? 44 : nil)
            .background(Capsule().foregroundStyle(editContainerColor).opacity(isEditing ? 1.0 : 0))
            .padding(.horizontal, isEditing ? 10 : 16)

            if isEditing {
                Group {
                    // show the first exposure's time zone display if it's different from the roll's time zone
                    // should display "Use time zone" instead of "Switch" if the current time zone is the same as the local one.
                    if true {
                        HStack(alignment: .firstTextBaseline, spacing: 7) {
                            Image(systemName: "clock.badge.questionmark")
                            (
                                Text("Your roll started in Hong Kong • ") +
                                Text("Switch").foregroundStyle(Color.accentColor)
                            ).lineHeightCompat(points: 20, fallbackSpacing: 2.1)
                        }.contentShape(Rectangle())
                        .onTapGesture {
                            print("switch time zone")
                            // TODO: switch
                        }
                    }
                    if true {
                        HStack(alignment: .firstTextBaseline, spacing: 7) {
                            Image(systemName: "info.circle.fill")
                            // use time (e.g. after your first exposure on 2:45 PM) if is on same day, be aware that time zones between the two should be consistent.
                            Text("This is after your first exposure on April 1st")
                                .lineHeightCompat(points: 20, fallbackSpacing: 2.1)
                        }
                    }
                }.transition(.offset(y: -25).combined(with: .opacity)) // TODO: tune this value
                .foregroundStyle(Color.white.opacity(0.5))
                .font(.system(size: 15, weight: .semibold, design: .default))
                .fontWidth(.expanded)
                .padding(.horizontal, 16)
            }
        }.zIndex(1)
        .onChange(of: isEditing) { _, editing in
            if !editing {
                isEditingDate = false
                isEditingTime = false
            }
        }
    }
}

// MARK: - Notes Section

private struct RollDetailNotesSection: View {
    @Binding var draftNotes: String
    let isEditing: Bool
    var scrollProxy: ScrollViewProxy?

    let editContainerColor: Color = Color(hex: 0x262626)

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            RollDetailHeader(icon: "text.pad.header", title: "Notes")
                .id("notes")

            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 20)
                    .foregroundStyle(editContainerColor)
                if draftNotes.isEmpty {
                    Text("Add a note...")
                        .font(.system(size: 17, weight: .regular, design: .default))
                        .padding(.horizontal, 20)
                        .padding(.vertical, 19)
                        .allowsHitTesting(false)
                        .foregroundStyle(Color.white.opacity(0.5))
                }
                RichTextEditor(
                    text: $draftNotes,
                    font: .systemFont(ofSize: 17, weight: .regular),
                    textColor: .white,
                    lineHeight: 28,
                    paragraphSpacing: 8,
                    isScrollEnabled: true,
                    isEditable: !isEditing,
                    onFocus: {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                            withAnimation(.easeInOut(duration: 0.25)) {
                                scrollProxy?.scrollTo("scrollBottom", anchor: .bottom)
                            }
                        }
                    }
                )
            }
            .frame(height: 201)
            .clipShape(RoundedRectangle(cornerRadius: 20))
            .padding(.horizontal, 10)
        }
    }
}

// MARK: - Roll Detail View

struct RollDetailView: View {
    let roll: RollSnapshot
    let cameraName: String
    let exposures: [LogItemSnapshot]
    var onUpdateNotes: ((UUID, String?) -> Void)?
    var onUpdateCreatedAt: ((UUID, Date, String, String?) -> Void)?

    @State private var isEditing: Bool = false
    @State private var draftNotes: String = ""
    @State private var hasInitialized = false
    @State private var debounceTask: Task<Void, Never>?
    @State private var dirtyDate: Date?
    @State private var scrollProxy: ScrollViewProxy?
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    RollDetailLoadedSection(
                        roll: roll,
                        exposures: exposures,
                        isEditing: $isEditing,
                        onUpdateCreatedAt: onUpdateCreatedAt
                    )
                    RollDetailSeparator()
                    RollDetailNotesSection(
                        draftNotes: $draftNotes,
                        isEditing: isEditing,
                        scrollProxy: scrollProxy
                    )
                    Color.clear
                        .frame(height: 1)
                        .id("scrollBottom")
                }.offset(y: -32)
                .frame(maxWidth: .infinity, alignment: .leading)
                .animation(.easeInOut(duration: 0.25), value: isEditing) // TODO: tune this value
                .contentShape(Rectangle())
                .onTapGesture {
                    UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                }
            }
            .scrollDismissesKeyboard(.immediately)
            .onAppear { scrollProxy = proxy }
        }
        .appToolbar {
            leadingButton
        } center: {
            ToolbarTitle(primary: roll.filmStock, secondary: cameraName)
        } trailing: {
            trailingButton
        }
        .onAppear {
            if !hasInitialized {
                draftNotes = roll.notes ?? ""
                hasInitialized = true
            }
        }
        .onDisappear { flushNotes() }
        .onChange(of: draftNotes) {
            if dirtyDate == nil { dirtyDate = Date() }
            debounceTask?.cancel()
            let mustFlush = dirtyDate.map { Date().timeIntervalSince($0) >= 5 } ?? false
            if mustFlush {
                flushNotes()
            } else {
                debounceTask = Task {
                    try? await Task.sleep(for: .seconds(3))
                    guard !Task.isCancelled else { return }
                    flushNotes()
                }
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background {
                flushNotes()
            }
        }
    }

    // MARK: - Toolbar buttons

    private var leadingButton: some View {
        Button(action: {
            if isEditing {
                // do not save
                isEditing = false
            } else {
                // TODO: back
            }
        }) {
            ZStack {
                if isEditing {
                    Image(systemName: "xmark")
                        .transition(.blurReplace)
                } else {
                    Image(systemName: "chevron.left")
                        .transition(.blurReplace)
                }
            }
            .animation(.easeInOut(duration: 0.2), value: isEditing)
            .font(.system(size: 16, weight: .bold, design: .default))
            .foregroundStyle(Color.white.opacity(0.95))
            .frame(width: 44, height: 44)
            .contentShape(Circle())
        }.buttonStyle(.plain)
        .frame(width: 44, height: 44)
        .contentShape(Circle())
        .glassEffectCompat(in: Circle(), interactive: true)
    }

    private var trailingButton: some View {
        Button(action: {
            if isEditing {
                isEditing = false
            } else {
                UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                isEditing = true
            }
        }) {
            Group {
                if isEditing {
                    Image(systemName: "checkmark")
                } else {
                    Image(systemName: "pencil")
                }
            }.transition(.blurReplace)
            .animation(.easeInOut(duration: 0.2), value: isEditing)
            .font(.system(size: 16, weight: .bold, design: .default))
            .foregroundStyle(Color.white.opacity(isEditing ? 0.85 : 0.95))
            .frame(width: 44, height: 44)
            .background(Circle().foregroundStyle(Color.accentColor.opacity(isEditing ? 1.0 : 0)))
            .animation(.easeInOut(duration: 0.2), value: isEditing)
            .contentShape(Circle())
        }.buttonStyle(.plain)
        .frame(width: 44, height: 44)
        .glassEffectCompat(in: Circle(), interactive: true)
    }

    // MARK: - Notes flush

    private func flushNotes() {
        debounceTask?.cancel()
        debounceTask = nil
        dirtyDate = nil
        let trimmed = draftNotes.trimmingCharacters(in: .whitespacesAndNewlines)
        let notes: String? = trimmed.isEmpty ? nil : trimmed
        if notes != roll.notes {
            onUpdateNotes?(roll.id, notes)
        }
    }
}

#Preview("Active roll") {
    let container = PreviewSampleData.makeContainer()
    let items = PreviewSampleData.sampleItems(from: container).map { $0.snapshot }
    let roll = RollSnapshot(
        id: UUID(),
        cameraID: UUID(),
        filmStock: "Kodak Portra 400",
        capacity: 36,
        extraExposures: 0,
        isActive: true,
        createdAt: Date().addingTimeInterval(-3600),
        timeZoneIdentifier: "America/Los_Angeles",
        cityName: "Los Angeles",
        notes: "Push two stops. The advance felt a bit funky, check for potential problems in development.\nMarked with some smeared marker.",
        lastExposureDate: Date().addingTimeInterval(-300),
        exposureCount: items.count,
        totalCapacity: 36,
        formattedTime: "3:45 PM",
        formattedDate: "Apr 10, 2026",
        localFormattedTime: "3:45 PM",
        localFormattedDate: "Apr 10, 2026",
        hasDifferentTimeZone: false,
        capturedTZLabel: nil
    )
    NavigationStack {
        RollDetailView(
            roll: roll,
            cameraName: "Leica M6",
            exposures: items,
            onUpdateNotes: { id, notes in print("Notes updated: \(notes ?? "nil")") },
            onUpdateCreatedAt: { id, date, tz, city in print("Date updated: \(date)") }
        )
    }
    .preferredColorScheme(.dark)
}

#Preview("Different time zone") {
    let roll = RollSnapshot(
        id: UUID(),
        cameraID: UUID(),
        filmStock: "Fuji Superia 400",
        capacity: 24,
        extraExposures: 0,
        isActive: false,
        createdAt: Date().addingTimeInterval(-86400 * 3),
        timeZoneIdentifier: "Asia/Tokyo",
        cityName: "Tokyo",
        notes: nil,
        lastExposureDate: Date().addingTimeInterval(-86400 * 2),
        exposureCount: 18,
        totalCapacity: 24,
        formattedTime: "11:30 AM",
        formattedDate: "Apr 7, 2026",
        localFormattedTime: "7:30 PM",
        localFormattedDate: "Apr 6, 2026",
        hasDifferentTimeZone: true,
        capturedTZLabel: "Tokyo"
    )
    NavigationStack {
        RollDetailView(
            roll: roll,
            cameraName: "Canon AE-1",
            exposures: [],
            onUpdateNotes: { _, _ in },
            onUpdateCreatedAt: { _, _, _, _ in }
        )
    }
    .preferredColorScheme(.dark)
}
