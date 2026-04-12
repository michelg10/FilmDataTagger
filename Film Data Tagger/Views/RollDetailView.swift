//
//  RollDetailView.swift
//  Film Data Tagger
//

import SwiftUI

// a lot of the complexity in this file is due to how expensive
// the date picker is to build AND to update (fuck you SwiftUI.
// actually for once it's probably UIKit's fault since i'm pretty
// sure that it actually uses UIKit behind the scenes)
//
// Anyway, point being, we try to perform date picker updates
// when the UI is not actively drawing an animation, so that
// the hitch is not visible. We can't throw this task
// off-main either, since it's UI. so this is the best we can
// do.
//
// Use timers to fire when we hope the user's not looking.

// should be longer than every animation to not hitch animations.
// add 0.1 to catch the long tail of animations
private let pickerUpdateDelay: Double = 0.25 + 0.1
private let layoutChangeAnimationDuration: Double = 0.25
private let layoutChangeAnimation: Animation = .snappy(duration: layoutChangeAnimationDuration, extraBounce: 0.02)
private let datePickerSelectAnimationDuration: Double = 0.2
private let datePickerSelectAnimation: Animation = .easeInOut(duration: datePickerSelectAnimationDuration)
private let datePickerTransitionYOffset: CGFloat = -16

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

// MARK: - Pickers

private struct RollDetailPickers: View, Equatable {
    @Binding var draftDate: Date
    let timeZone: TimeZone
    let isEditingDate: Bool
    let isEditingTime: Bool

    static func == (lhs: RollDetailPickers, rhs: RollDetailPickers) -> Bool {
        lhs.draftDate == rhs.draftDate &&
        lhs.timeZone == rhs.timeZone &&
        lhs.isEditingDate == rhs.isEditingDate &&
        lhs.isEditingTime == rhs.isEditingTime
    }

    var body: some View {
        ZStack(alignment: .top) {
            DatePicker("Roll load date", selection: $draftDate, displayedComponents: .date)
                .environment(\.timeZone, timeZone)
                .zIndex(4)
                .datePickerStyle(.graphical)
                .padding(.top, 0)
                .padding(.bottom, 6)
                .padding(.leading, 8)
                .padding(.trailing, 8)
                .glassEffectCompat(in: RoundedRectangle(cornerRadius: 22), interactive: false)
                .offset(y: 44 + 12)
                .offset(y: isEditingDate ? 0 : datePickerTransitionYOffset)
                .opacity(isEditingDate ? 1 : 0)
                .allowsHitTesting(isEditingDate)
                .animation(datePickerSelectAnimation, value: isEditingDate)
            DatePicker("Roll load time", selection: $draftDate, displayedComponents: .hourAndMinute)
                .environment(\.timeZone, timeZone)
                .zIndex(4)
                .datePickerStyle(.wheel)
                .labelsHidden()
                .padding(.top, 6)
                .padding(.bottom, 6)
                .padding(.leading, 16)
                .padding(.trailing, 16)
                .frame(maxWidth: .infinity)
                .glassEffectCompat(in: RoundedRectangle(cornerRadius: 22), interactive: false)
                .padding(.horizontal, 6)
                .offset(y: 44 + 12)
                .offset(y: isEditingTime ? 0 : datePickerTransitionYOffset)
                .opacity(isEditingTime ? 1 : 0)
                .allowsHitTesting(isEditingTime)
                .animation(datePickerSelectAnimation, value: isEditingTime)
        }
    }
}

// MARK: - Loaded Section

private struct RollDetailLoadedSection: View {
    let roll: RollSnapshot
    let exposures: [LogItemSnapshot]
    let isEditing: Bool
    var currentCityName: String?
    @Binding var draftDate: Date
    @Binding var draftTimeZoneIdentifier: String
    @Binding var draftCityName: String?

    let editContainerColor: Color = Color(hex: 0x262626)

    @State private var isEditingDate: Bool = false
    @State private var isEditingTime: Bool = false
    @State private var showingLocalTime: Bool = false
    @State private var pickersConstructed: Bool = false
    @State private var pickerRebuildTimer: Timer?
    /// Frozen timezone for the pickers — only updated when pickers are reconstructed,
    /// not when displayTimeZone changes, to avoid picker re-layout during teardown.
    @State private var pickerTimeZone: TimeZone = .current

    private var shouldShowCompact: Bool {
        UIScreen.currentWidth < 390
    }

    private var displayTimeZone: TimeZone {
        showingLocalTime ? .current : draftTimeZone
    }

    private var displayDate: String {
        let date = isEditing ? draftDate : roll.createdAt
        var fmt = Date.FormatStyle.dateTime.month(shouldShowCompact ? .abbreviated : .wide).day().year()
        fmt.timeZone = displayTimeZone
        return date.formatted(fmt)
    }

    private var displayTime: String {
        let date = isEditing ? draftDate : roll.createdAt
        var fmt = Date.FormatStyle.dateTime.hour().minute()
        fmt.timeZone = displayTimeZone
        return date.formatted(fmt)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: isEditing ? 16 : 11) {
            RollDetailHeader(icon: "arrow.clockwise", title: "Loaded")
            
            HStack(alignment: .firstTextBaseline, spacing: isEditing ? 12 : 5) {
                Text(displayDate)
                    .frame(
                        width: isEditing ? min(UIScreen.currentWidth - 20 - 125 - 12, 267) : nil,
                        height: CGFloat(isEditing ? 44 : 20)
                    )
                    .background(Capsule().foregroundStyle(editContainerColor).opacity(isEditing ? 1 : 0))
                    .foregroundStyle(isEditingDate ? Color.accentColor : Color.white)
                    .animation(datePickerSelectAnimation, value: isEditingDate)
                    .accessibilityLabel("Edit roll load date")
                    .contentShape(Capsule())
                    .onTapGesture {
                        if isEditing {
                            isEditingTime = false
                            isEditingDate.toggle()
                        }
                    }

                Text(displayTime)
                    .frame(width: isEditing ? 125 : nil, height: isEditing ? 44 : 20)
                    .background(Capsule().foregroundStyle(editContainerColor).opacity(isEditing ? 1 : 0))
                    .foregroundStyle(isEditingTime ? Color.accentColor : Color.white.opacity(isEditing ? 1.0 : 0.7))
                    .animation(datePickerSelectAnimation, value: isEditingDate)
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
            .background(alignment: .top) {
                ZStack(alignment: .top) {
                    Group {
                        ProgressView()
                            .frame(height: 228)
                            .frame(maxWidth: .infinity)
                            .glassEffectCompat(in: RoundedRectangle(cornerRadius: 22), interactive: false)
                            .opacity((isEditingTime && !pickersConstructed) ? 1 : 0)
                            .offset(y: isEditingTime ? 0 : datePickerTransitionYOffset)
                            .animation(datePickerSelectAnimation, value: isEditingTime)
                            .animation(datePickerSelectAnimation, value: pickersConstructed)
                        
                        ProgressView()
                            .frame(height: 381)
                            .frame(maxWidth: .infinity)
                            .glassEffectCompat(in: RoundedRectangle(cornerRadius: 22), interactive: false)
                            .opacity((isEditingDate && !pickersConstructed) ? 1 : 0)
                            .offset(y: isEditingDate ? 0 : datePickerTransitionYOffset)
                            .animation(datePickerSelectAnimation, value: isEditingDate)
                            .animation(datePickerSelectAnimation, value: pickersConstructed)
                    }
                    .zIndex(3)
                    .tint(.white)
                    .offset(y: 44 + 12)
                    .padding(.horizontal, 6)
                    .allowsHitTesting((isEditingDate || isEditingTime) && !pickersConstructed)
                    if pickersConstructed {
                        RollDetailPickers(
                            draftDate: $draftDate,
                            timeZone: pickerTimeZone,
                            isEditingDate: isEditingDate,
                            isEditingTime: isEditingTime
                        )
                        .equatable()
                    }
                }
            }

            if hasDifferentTimeZone {
                HStack(spacing: 0) {
                    HStack(alignment: .firstTextBaseline, spacing: isEditing ? 13 : 6) {
                        Image(systemName: "globe.badge.clock")
                            .foregroundStyle(Color.white.opacity(0.7))
                        Text(showingLocalTime ? "Local" : draftTimeZoneLabel)
                            .foregroundStyle(Color.white.opacity(isEditing ? 0.95 : 0.7))
                    }.drawingGroup() // make SwiftUI animate this view as a group
                    .contentShape(Rectangle())
                    .onTapGesture {
                        showingLocalTime.toggle()
                    }.padding(.trailing, 16)

                    Button(action: {
                        guard isEditing else {
                            return
                        }
                        withAnimation(.easeInOut(duration: layoutChangeAnimationDuration)) {
                            draftTimeZoneIdentifier = TimeZone.current.identifier
                            draftCityName = currentCityName
                        }
                    }) {
                        Image(systemName: "xmark")
                            .font(.system(size: 16, weight: .bold, design: .default))
                            .foregroundStyle(Color.white.opacity(0.95))
                            .frame(width: 40, height: 40)
                            .contentShape(Circle())
                    }.buttonStyle(.plain)
                    .frame(width: isEditing ? 40 : 20, height: isEditing ? 40 : 20)
                    .glassEffectCompat(in: Circle(), interactive: true)
                    .padding(.trailing, 2)
                    .opacity(isEditing ? 1.0 : 0)
                }.padding(.leading, isEditing ? 12 : 0)
                .font(.system(size: 17, weight: .medium, design: .default))
                .fontWidth(.expanded)
                .frame(height: isEditing ? 44 : nil)
                .background(Capsule().foregroundStyle(editContainerColor).opacity(isEditing ? 1.0 : 0))
                .padding(.horizontal, isEditing ? 10 : 16)
                .animation(layoutChangeAnimation, value: showingLocalTime && isEditing)
                .transition(.opacity)
                .zIndex(1)
            }

            if isEditing {
                if let firstExposureTZ = firstExposureTimeZone, let label = firstExposureTZLabel {
                    let actionText = hasDifferentTimeZone ? "Switch" : "Use time zone"
                    HStack(alignment: .firstTextBaseline, spacing: 7) {
                        Image(systemName: "clock.badge.questionmark")
                        (
                            Text("Your roll started in \(label) · ") +
                            Text(actionText).foregroundStyle(Color.accentColor)
                        ).lineHeightCompat(points: 20, fallbackSpacing: 2.1)
                    }.compositingGroup()
                    .contentShape(Rectangle())
                    .onTapGesture {
                        withAnimation(.easeInOut(duration: layoutChangeAnimationDuration)) {
                            draftTimeZoneIdentifier = firstExposureTZ.identifier
                            draftCityName = firstExposure?.cityName
                        }
                    }
                    .transition(.opacity)
                    .foregroundStyle(Color.white.opacity(0.5))
                    .font(.system(size: 15, weight: .medium, design: .default))
                    .fontWidth(.expanded)
                    .padding(.horizontal, 16)
                }
                if isDraftAfterFirstExposure {
                    HStack(alignment: .firstTextBaseline, spacing: 7) {
                        Image(systemName: "info.circle.fill")
                        Text("This is after your first exposure on \(firstExposureReferenceText ?? "")")
                            .lineHeightCompat(points: 20, fallbackSpacing: 2.1)
                    }.drawingGroup() // make SwiftUI animate this view as a group
                    .transition(.opacity)
                    .foregroundStyle(Color.white.opacity(0.5))
                    .font(.system(size: 15, weight: .medium, design: .default))
                    .fontWidth(.expanded)
                    .padding(.horizontal, 16)
                }
            }
        }.zIndex(1)
        .onChange(of: isEditing) { _, editing in
            if editing && !pickersConstructed {
                schedulePickerRebuild()
            }
            if !editing {
                isEditingDate = false
                isEditingTime = false
            }
        }
        .onChange(of: displayTimeZone) {
            guard pickersConstructed else { return }
            pickerRebuildTimer?.invalidate()
            pickersConstructed = false
            schedulePickerRebuild()
        }
    }

    private var draftTimeZone: TimeZone {
        TimeZone(identifier: draftTimeZoneIdentifier) ?? .current
    }

    /// Schedule picker reconstruction after a delay, using RunLoop.default mode
    /// so it won't fire during scroll tracking.
    private func schedulePickerRebuild() {
        pickerRebuildTimer?.invalidate()
        let timer = Timer(timeInterval: pickerUpdateDelay, repeats: false) { [self] _ in
            pickerTimeZone = displayTimeZone
            pickersConstructed = true
        }
        RunLoop.main.add(timer, forMode: .default)
        pickerRebuildTimer = timer
    }

    private var hasDifferentTimeZone: Bool {
        draftTimeZone.secondsFromGMT(for: draftDate) != TimeZone.current.secondsFromGMT(for: draftDate)
    }

    /// Human-readable label for the draft time zone (e.g. "Tokyo", "Los Angeles")
    private var draftTimeZoneLabel: String {
        draftCityName ?? {
            let components = draftTimeZoneIdentifier.split(separator: "/")
            let last = components.last.map(String.init) ?? draftTimeZoneIdentifier
            return last.replacingOccurrences(of: "_", with: " ")
        }()
    }

    // MARK: - First exposure hint logic

    private var firstExposure: LogItemSnapshot? {
        exposures.first(where: { $0.hasRealCreatedAt })
    }

    /// The first exposure's time zone, if it differs from the current draft TZ.
    private var firstExposureTimeZone: TimeZone? {
        guard let tzId = firstExposure?.timeZoneIdentifier,
              let tz = TimeZone(identifier: tzId),
              tz.secondsFromGMT(for: draftDate) != draftTimeZone.secondsFromGMT(for: draftDate)
        else { return nil }
        return tz
    }

    /// City label for the first exposure's time zone.
    private var firstExposureTZLabel: String? {
        guard let tzId = firstExposure?.timeZoneIdentifier else { return nil }
        if let city = firstExposure?.cityName { return city }
        let components = tzId.split(separator: "/")
        let last = components.last.map(String.init) ?? tzId
        return last.replacingOccurrences(of: "_", with: " ")
    }

    /// Whether draftDate is after the first exposure.
    private var isDraftAfterFirstExposure: Bool {
        guard let first = firstExposure else { return false }
        return draftDate > first.createdAt
    }

    /// Formatted first exposure reference — time if same day, date otherwise.
    private var firstExposureReferenceText: String? {
        guard let first = firstExposure else { return nil }
        var cal = Calendar.current
        cal.timeZone = displayTimeZone
        if cal.isDate(draftDate, inSameDayAs: first.createdAt) {
            var fmt = Date.FormatStyle.dateTime.hour().minute()
            fmt.timeZone = displayTimeZone
            return first.createdAt.formatted(fmt)
        } else {
            var fmt = Date.FormatStyle.dateTime.month(.wide).day()
            fmt.timeZone = displayTimeZone
            return first.createdAt.formatted(fmt)
        }
    }
}

// MARK: - Notes Section

private struct RollDetailNotesSection: View {
    @Binding var draftNotes: String
    let isEditing: Bool
    var scrollProxy: ScrollViewProxy?
    var onFocus: (() -> Void)?
    var onBlur: (() -> Void)?

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
                        onFocus?()
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                            withAnimation(.easeInOut(duration: 0.25)) {
                                scrollProxy?.scrollTo("scrollBottom", anchor: .bottom)
                            }
                        }
                    },
                    onBlur: onBlur
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
    var currentCityName: String?
    var onUpdateNotes: ((UUID, String?, Bool) -> Void)?
    var onUpdateCreatedAt: ((UUID, Date, String, String?) -> Void)?

    @State private var isEditing: Bool = false
    @State private var isNotesFocused: Bool = false
    @State private var draftNotes: String = ""
    @State private var draftDate: Date = .distantPast
    @State private var draftTimeZoneIdentifier: String = TimeZone.current.identifier
    @State private var draftCityName: String?
    @State private var hasInitialized = false
    @State private var debounceTask: Task<Void, Never>?
    @State private var dirtyDate: Date?
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    RollDetailLoadedSection(
                        roll: roll,
                        exposures: exposures,
                        isEditing: isEditing,
                        currentCityName: currentCityName,
                        draftDate: $draftDate,
                        draftTimeZoneIdentifier: $draftTimeZoneIdentifier,
                        draftCityName: $draftCityName
                    )
                    RollDetailSeparator()
                    RollDetailNotesSection(
                        draftNotes: $draftNotes,
                        isEditing: isEditing,
                        scrollProxy: proxy,
                        onFocus: { isNotesFocused = true },
                        onBlur: { isNotesFocused = false; flushNotes() }
                    )
                    Color.clear
                        .frame(height: 1)
                        .id("scrollBottom")
                }.padding(.top, 20)
                .frame(maxWidth: .infinity, alignment: .leading)
                .animation(layoutChangeAnimation, value: isEditing)
            }
            .scrollDismissesKeyboard(.immediately)
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
                draftDate = roll.createdAt
                draftTimeZoneIdentifier = roll.timeZoneIdentifier ?? TimeZone.current.identifier
                draftCityName = roll.cityName
                hasInitialized = true
            }
        }
        .onDisappear { flushNotes() }
        .onChange(of: draftNotes) {
            // Update in-memory snapshot immediately so other views (e.g. RollListView) see the draft
            let trimmed = draftNotes.trimmingCharacters(in: .whitespacesAndNewlines)
            onUpdateNotes?(roll.id, trimmed.isEmpty ? nil : trimmed, false)
            // Debounced persist to store
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
        // MARK: - CloudKit sync
        // When the roll snapshot updates from a remote change, sync drafts for
        // sections the user isn't actively editing. This avoids overwriting
        // in-progress edits (the same user made the change on another device —
        // they know what happened, don't yank the floor from under them).
        // Each section is independent: date editing (isEditing) and notes
        // editing (isNotesFocused) are tracked separately.
        .onChange(of: roll.notes) { _, newNotes in
            if !isNotesFocused {
                draftNotes = newNotes ?? ""
            }
        }
        .onChange(of: roll.createdAt) { _, newDate in
            if !isEditing { draftDate = newDate }
        }
        .onChange(of: roll.timeZoneIdentifier) { _, newTZ in
            if !isEditing { draftTimeZoneIdentifier = newTZ ?? TimeZone.current.identifier }
        }
        .onChange(of: roll.cityName) { _, newCity in
            if !isEditing { draftCityName = newCity }
        }
    }

    // MARK: - Toolbar buttons
    
    // we manually emulate .blurReplace() here because
    // it doesn't work on our toolbar for some reason.

    private var leadingButton: some View {
        Button(action: {
            if isEditing {
                // Discard — reset drafts to roll values
                draftDate = roll.createdAt
                draftTimeZoneIdentifier = roll.timeZoneIdentifier ?? TimeZone.current.identifier
                draftCityName = roll.cityName
                isEditing = false
            } else {
                dismiss()
            }
        }) {
            ZStack {
                Image(systemName: "xmark")
                    .blur(radius: isEditing ? 0 : 4)
                    .opacity(isEditing ? 1 : 0)
                Image(systemName: "chevron.left")
                    .blur(radius: isEditing ? 4 : 0)
                    .opacity(isEditing ? 0 : 1)
            }
            .animation(.easeInOut(duration: layoutChangeAnimationDuration), value: isEditing)
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
                // Save — fire callback with draft values
                onUpdateCreatedAt?(roll.id, draftDate, draftTimeZoneIdentifier, draftCityName)
                isEditing = false
            } else {
                UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                isEditing = true
            }
        }) {
            ZStack {
                Image(systemName: "checkmark")
                    .blur(radius: isEditing ? 0 : 4)
                    .opacity(isEditing ? 1 : 0)
                Image(systemName: "pencil")
                    .blur(radius: isEditing ? 4 : 0)
                    .opacity(isEditing ? 0 : 1)
            }
            .font(.system(size: 16, weight: .bold, design: .default))
            .foregroundStyle(Color.white.opacity(isEditing ? 0.85 : 0.95))
            .frame(width: 44, height: 44)
            .background(Circle().foregroundStyle(Color.accentColor.opacity(isEditing ? 1.0 : 0)))
            .animation(.easeInOut(duration: layoutChangeAnimationDuration), value: isEditing)
            .contentShape(Circle())
        }.buttonStyle(.plain)
        .frame(width: 44, height: 44)
        .glassEffectCompat(in: Circle(), interactive: true)
    }

    // MARK: - Notes flush

    private func flushNotes() {
        debounceTask?.cancel()
        debounceTask = nil
        guard dirtyDate != nil else { return }
        dirtyDate = nil
        let trimmed = draftNotes.trimmingCharacters(in: .whitespacesAndNewlines)
        let notes: String? = trimmed.isEmpty ? nil : trimmed
        onUpdateNotes?(roll.id, notes, true)
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
        totalCapacity: 36
    )
    NavigationStack {
        RollDetailView(
            roll: roll,
            cameraName: "Leica M6",
            exposures: items,
            onUpdateNotes: { id, notes, persist in print("Notes updated: \(notes ?? "nil") persist: \(persist)") },
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
        totalCapacity: 24
    )
    NavigationStack {
        RollDetailView(
            roll: roll,
            cameraName: "Canon AE-1",
            exposures: [],
            onUpdateNotes: { _, _, _ in },
            onUpdateCreatedAt: { _, _, _, _ in }
        )
    }
    .preferredColorScheme(.dark)
}
