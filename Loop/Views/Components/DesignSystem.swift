import SwiftUI

public final class ThemeManager: ObservableObject {
    public static let shared = ThemeManager()
    
    public enum Theme: String, CaseIterable, Identifiable {
        case earthySage = "Earthy Sage"
        case forestTeal = "Forest Teal"
        case warmOchre = "Warm Ochre"
        case coralRed = "Coral Red"
        case royalBlue = "Royal Blue"
        case classicGreen = "Classic Green"
        
        public var id: String { rawValue }
        
        public var color: Color {
            switch self {
            case .earthySage: return Color(red: 0.28, green: 0.46, blue: 0.31)
            case .forestTeal: return Color(red: 0.12, green: 0.35, blue: 0.32)
            case .warmOchre: return Color(red: 0.71, green: 0.45, blue: 0.20)
            case .coralRed: return Color(red: 0.82, green: 0.34, blue: 0.30)
            case .royalBlue: return Color(red: 0.18, green: 0.36, blue: 0.68)
            case .classicGreen: return Color(red: 0.32, green: 0.49, blue: 0.34)
            }
        }
        
        public var deepColor: Color {
            switch self {
            case .earthySage: return Color(red: 0.15, green: 0.27, blue: 0.17)
            case .forestTeal: return Color(red: 0.06, green: 0.20, blue: 0.18)
            case .warmOchre: return Color(red: 0.45, green: 0.25, blue: 0.08)
            case .coralRed: return Color(red: 0.50, green: 0.18, blue: 0.15)
            case .royalBlue: return Color(red: 0.08, green: 0.18, blue: 0.38)
            case .classicGreen: return Color(red: 0.18, green: 0.30, blue: 0.21)
            }
        }
        
        public var mistColor: Color {
            switch self {
            case .earthySage: return Color(red: 0.93, green: 0.96, blue: 0.94)
            case .forestTeal: return Color(red: 0.92, green: 0.95, blue: 0.95)
            case .warmOchre: return Color(red: 0.97, green: 0.94, blue: 0.90)
            case .coralRed: return Color(red: 0.98, green: 0.93, blue: 0.93)
            case .royalBlue: return Color(red: 0.92, green: 0.94, blue: 0.98)
            case .classicGreen: return Color(red: 0.94, green: 0.965, blue: 0.93)
            }
        }
    }
    
    public var selectedTheme: Theme {
        get {
            let name = UserDefaults.standard.string(forKey: "appAccentTheme") ?? "Earthy Sage"
            return Theme(rawValue: name) ?? .earthySage
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: "appAccentTheme")
            DispatchQueue.main.async {
                self.objectWillChange.send()
            }
        }
    }
}

extension Color {
    public static var loopGreen: Color { ThemeManager.shared.selectedTheme.color }
    public static var loopGreenDeep: Color { ThemeManager.shared.selectedTheme.deepColor }
    public static let loopInk = Color(red: 0.08, green: 0.10, blue: 0.09)
    public static var loopPanel: Color { Color.white }
    public static let loopSurface = Color.white
    public static let loopLine = Color.black.opacity(0.08)
    public static let loopWarm = Color(red: 0.73, green: 0.36, blue: 0.24)
    public static var loopMist: Color { ThemeManager.shared.selectedTheme.mistColor }
    public static let loopSubtext = Color(red: 0.39, green: 0.43, blue: 0.40)

    init(hex: String) {
        let cleaned = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var value: UInt64 = 0
        Scanner(string: cleaned).scanHexInt64(&value)
        let red = Double((value >> 16) & 0xff) / 255
        let green = Double((value >> 8) & 0xff) / 255
        let blue = Double(value & 0xff) / 255
        self.init(red: red, green: green, blue: blue)
    }
}

extension ShapeStyle where Self == Color {
    static var loopGreen: Color { Color.loopGreen }
    static var loopGreenDeep: Color { Color.loopGreenDeep }
    static var loopInk: Color { Color.loopInk }
    static var loopPanel: Color { Color.loopPanel }
    static var loopSurface: Color { Color.loopSurface }
    static var loopWarm: Color { Color.loopWarm }
    static var loopMist: Color { Color.loopMist }
    static var loopSubtext: Color { Color.loopSubtext }
}

enum LoopFont {
    static func logo(_ size: CGFloat) -> Font {
        .custom("AvenirNextCondensed-Heavy", size: size, relativeTo: .largeTitle)
    }

    static func display(_ size: CGFloat, weight: Font.Weight = .black) -> Font {
        .system(size: size, weight: weight, design: .rounded)
    }

    static func body(_ size: CGFloat = 15, weight: Font.Weight = .semibold) -> Font {
        .system(size: size, weight: weight, design: .default)
    }
}

extension Int {
    var compactCount: String {
        if self >= 1_000_000 {
            return String(format: "%.1fM", Double(self) / 1_000_000)
        }
        if self >= 1_000 {
            return String(format: "%.1fK", Double(self) / 1_000)
        }
        return "\(self)"
    }
}

extension Double {
    var oneDecimal: String {
        String(format: "%.1f", self)
    }
}

struct AvatarView: View {
    let user: LoopUser
    var size: CGFloat = 52

    var body: some View {
        Group {
            if let avatarURL = user.avatarURL {
                AsyncImage(url: avatarURL) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFill()
                    default:
                        fallbackAvatar
                    }
                }
            } else {
                fallbackAvatar
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .overlay {
            Circle()
                .stroke(.white.opacity(0.72), lineWidth: max(1, size * 0.035))
        }
        .accessibilityLabel(user.displayName)
    }

    private var fallbackAvatar: some View {
        ZStack {
            LinearGradient(
                colors: [Color(hex: user.avatarColor), .loopGreenDeep],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            Image(systemName: "person.fill")
                .font(.system(size: size * 0.36, weight: .black))
                .foregroundStyle(.white.opacity(0.9))

            Text(String(user.displayName.prefix(1)).uppercased())
                .font(LoopFont.logo(size * 0.48))
                .foregroundStyle(.white)
                .offset(y: size * 0.02)
        }
    }
}

struct GlassPill<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(.black.opacity(0.48), in: Capsule())
            .overlay {
                Capsule()
                    .stroke(.white.opacity(0.16), lineWidth: 1)
            }
    }
}

struct PrimaryLoopButton: View {
    let title: String
    let systemImage: String
    var isLoading = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                if isLoading {
                    ProgressView()
                        .tint(.black)
                } else {
                    Image(systemName: systemImage)
                }
                Text(title)
                    .fontWeight(.bold)
            }
            .frame(maxWidth: .infinity)
            .font(.system(size: 15, weight: .black, design: .rounded))
            .padding(.vertical, 12)
            .foregroundStyle(.white)
            .background(.loopGreen, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(isLoading)
    }
}

struct LoopTextFieldStyle: ViewModifier {
    var dark = false

    func body(content: Content) -> some View {
        content
            .font(LoopFont.body(15))
            .padding(.horizontal, 13)
            .padding(.vertical, 12)
            .foregroundStyle(dark ? Color.white : Color.loopInk)
            .background(dark ? Color.black.opacity(0.28) : Color.loopPanel, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(dark ? Color.white.opacity(0.14) : Color.loopLine, lineWidth: 1)
            }
    }
}

extension View {
    func loopField(dark: Bool = false) -> some View {
        modifier(LoopTextFieldStyle(dark: dark))
    }

    func loopCard(radius: CGFloat = 16) -> some View {
        background(Color.loopSurface, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .stroke(Color.loopLine, lineWidth: 1)
            }
    }
}
