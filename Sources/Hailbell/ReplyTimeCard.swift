import SwiftUI
import UserNotifications

/// The reply time card's words and button state, worked out from the message's `expect` and the
/// clock. Pure, so tests can pin the time, zone and language.
///
/// The words are rebuilt on every render from the current time, so a card read the next morning says
/// "today" instead of "tonight", and one whose time has passed shows only its title.
enum ReplyTime {
    /// The part under the words: a button to turn notifications on, a button to Settings, a line
    /// saying they're on, or nothing.
    enum Notify: Equatable { case none, ask, settings, done }

    /// Nothing when the server didn't offer it, once the team has replied, or before the permission
    /// is known (so the wrong button never flashes in).
    static func notify(offered: Bool, teamReplied: Bool, permission: UNAuthorizationStatus?) -> Notify {
        guard offered, !teamReplied, let permission else { return .none }
        switch permission {
        case .notDetermined: return .ask
        case .denied: return .settings
        default: return .done   // authorized, provisional, ephemeral
        }
    }

    struct Words: Equatable {
        /// "Vidur is offline right now" or "Vidur will reply here".
        var title: String
        /// "Usually back by 11:30 PM tonight, your time. That's in about 8 hours."
        var line: String?
        /// The part of `line` shown in bold ("11:30 PM tonight").
        var bold: String?
        /// "It's 2:22 AM for Vidur in India."
        var ownerTime: String?
    }

    static let hour: TimeInterval = 3600

    static func words(_ e: Expect, now: Date = Date(), lang: String = L10n.language,
                      locale: Locale = .current, zone: TimeZone = .current) -> Words {
        let t = { (key: String, vars: [String: String]) in L10n.text(key, vars, lang: lang) }
        var w: Words
        switch e.kind {
        case "back":
            w = Words(title: t("expectOffline", ["name": e.name]))
            let backAt = Date(timeIntervalSince1970: (e.backAt ?? 0) / 1000)
            if backAt > now {
                let when = whenPhrase(backAt, now: now, lang: lang, locale: locale, zone: zone)
                var parts = [t("expectBackBy", ["when": when])]
                let n = Int((backAt.timeIntervalSince(now) / hour).rounded())
                if n < 2 { parts.append(t("expectInHour", [:])) } else if n < 24 { parts.append(t("expectInHours", ["n": String(n)])) }
                w.line = parts.joined(separator: separator(lang))
                w.bold = when
            }
        case "typical":
            let hours = e.hours ?? 1
            w = Words(title: t("expectWillReply", ["name": e.name]),
                      line: t(hours <= 1 ? "expectTypicalHour" : "expectTypical", ["name": e.name, "n": String(hours)]))
        default:
            w = Words(title: t("expectWillReply", ["name": e.name]), line: t("expectSoon", ["name": e.name]))
        }
        if let id = e.ownerZone, let country = e.ownerCountry, let ownerZone = TimeZone(identifier: id) {
            // The country in the card's language, so the sentence never mixes two.
            let place = Locale(identifier: lang).localizedString(forRegionCode: country) ?? country
            w.ownerTime = t("expectOwnerTime", ["time": clock(now, locale: locale, zone: ownerZone), "name": e.name, "place": place])
        }
        return w
    }

    /// "11:30 PM tonight", "7:00 AM tomorrow", "9:00 AM on Monday": the reader's own day and clock.
    static func whenPhrase(_ at: Date, now: Date, lang: String, locale: Locale, zone: TimeZone) -> String {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = zone
        let time = clock(at, locale: locale, zone: zone)
        if cal.isDate(at, inSameDayAs: now) {
            return L10n.text(cal.component(.hour, from: at) >= 18 ? "expectTonight" : "expectToday", ["time": time], lang: lang)
        }
        if let tomorrow = cal.date(byAdding: .day, value: 1, to: now), cal.isDate(at, inSameDayAs: tomorrow) {
            return L10n.text("expectTomorrow", ["time": time], lang: lang)
        }
        let f = DateFormatter()
        f.locale = Locale(identifier: lang)
        f.timeZone = zone
        f.setLocalizedDateFormatFromTemplate("EEEE")
        return L10n.text("expectOnDay", ["time": time, "day": f.string(from: at)], lang: lang)
    }

    /// A short clock time in the device's format, 12- or 24-hour as the user set it.
    static func clock(_ date: Date, locale: Locale, zone: TimeZone) -> String {
        let f = DateFormatter()
        f.locale = locale
        f.timeZone = zone
        f.dateStyle = .none
        f.timeStyle = .short
        return f.string(from: date)
    }

    /// Japanese and Chinese sentences run on without a space.
    static func separator(_ lang: String) -> String { lang == "ja" || lang == "zh" ? "" : " " }

    /// The line with its day phrase in bold.
    static func styled(_ line: String, bold: String?) -> AttributedString {
        var s = AttributedString(line)
        if let bold, !bold.isEmpty, let range = s.range(of: bold) {
            s[range].inlinePresentationIntent = .stronglyEmphasized
        }
        return s
    }
}

/// When the AI hands a chat to a team that isn't around: who replies, when to expect them in the
/// customer's own time, and an offer to be notified. Drawn instead of the system message's bubble.
struct ReplyTimeCard: View {
    let expect: Expect
    let notify: ReplyTime.Notify
    let theme: ChatTheme
    /// When the message arrived, so only a new card plays its entrance.
    let createdAt: Date
    let onNotify: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shown: Bool

    init(expect: Expect, notify: ReplyTime.Notify, theme: ChatTheme, createdAt: Date = .distantPast, onNotify: @escaping () -> Void = {}) {
        self.expect = expect
        self.notify = notify
        self.theme = theme
        self.createdAt = createdAt
        self.onNotify = onNotify
        // Only a card that just arrived plays its entrance; one scrolled back to is already there.
        _shown = State(initialValue: Date().timeIntervalSince(createdAt) >= 10)
    }

    var body: some View {
        TimelineView(.everyMinute) { context in
            card(ReplyTime.words(expect, now: context.date))
        }
        .opacity(shown ? 1 : 0)
        .offset(y: shown || reduceMotion ? 0 : 8)
        .onAppear {
            guard !shown else { return }
            withAnimation(reduceMotion ? .easeOut(duration: 0.2) : .spring(response: 0.42, dampingFraction: 1)) { shown = true }
        }
    }

    private func card(_ words: ReplyTime.Words) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: "clock")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(theme.accent)
                VStack(alignment: .leading, spacing: 4) {
                    Text(words.title)
                        .font(.subheadline.weight(.semibold))
                    if let line = words.line {
                        Text(ReplyTime.styled(line, bold: words.bold))
                            .font(.subheadline)
                    }
                    if let owner = words.ownerTime {
                        Text(owner)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .padding(.top, 2)
                    }
                    if notify == .done {
                        Label {
                            Text(L10n.text("expectNotified", ["name": expect.name]))
                        } icon: {
                            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                        }
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .padding(.top, 4)
                        .transition(.opacity)
                    }
                }
                .foregroundStyle(theme.incomingText)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .accessibilityElement(children: .combine)

            if notify == .ask || notify == .settings {
                Button(action: onNotify) {
                    Text(notify == .settings ? L10n.text("expectTurnOn") : L10n.text("expectNotify", ["name": expect.name]))
                        .font(.body.weight(.semibold))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .foregroundStyle(theme.onAccent)
                        .background(theme.accent, in: Capsule())
                        .contentShape(Capsule())
                }
                .buttonStyle(CardPressStyle())
                .transition(.opacity)
            }
        }
        .padding(13)
        .background(theme.incoming, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .animation(.easeOut(duration: 0.2), value: notify)
        .frame(maxWidth: MessageRow.maxWidth)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 4)
    }
}

/// Presses in on touch-down, like the chat's other card buttons.
private struct CardPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
    }
}

#if DEBUG
private enum ReplyTimePreview {
    static let theme = ChatTheme(Appearance(), dark: false)
    static let darkTheme = ChatTheme(Appearance(), dark: true)
    static var back: Expect {
        Expect(kind: "back", name: "Vidur", backAt: (Date().timeIntervalSince1970 + 8 * 3600) * 1000, notify: true,
               ownerZone: "Asia/Kolkata", ownerCountry: "IN")
    }
    static let typical = Expect(kind: "typical", name: "Vidur", hours: 3, notify: true)
    static let soon = Expect(kind: "soon", name: "Vidur", notify: false)
}

#Preview("Back, with button") {
    ReplyTimeCard(expect: ReplyTimePreview.back, notify: .ask, theme: ReplyTimePreview.theme).padding(12)
}

#Preview("Granted") {
    ReplyTimeCard(expect: ReplyTimePreview.back, notify: .done, theme: ReplyTimePreview.theme).padding(12)
}

#Preview("Typical, denied") {
    VStack(spacing: 8) {
        ReplyTimeCard(expect: ReplyTimePreview.typical, notify: .settings, theme: ReplyTimePreview.theme)
        ReplyTimeCard(expect: ReplyTimePreview.soon, notify: .none, theme: ReplyTimePreview.theme)
    }
    .padding(12)
}

#Preview("Dark") {
    VStack(spacing: 8) {
        ReplyTimeCard(expect: ReplyTimePreview.back, notify: .ask, theme: ReplyTimePreview.darkTheme)
        ReplyTimeCard(expect: ReplyTimePreview.typical, notify: .done, theme: ReplyTimePreview.darkTheme)
    }
    .padding(12)
    .background(Color(.systemBackground))
    .preferredColorScheme(.dark)
}
#endif
