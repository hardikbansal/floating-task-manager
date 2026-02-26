import SwiftUI

struct SettingsView: View {
    @AppStorage("baseFontSize") var baseFontSize: Double = 13.0
    @AppStorage("windowOpacity") var windowOpacity: Double = 0.95
    @AppStorage("enableShadows") var enableShadows: Bool = true
    
    var body: some View {
        VStack(spacing: 20) {
            // Title Header
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Settings")
                        .font(.system(size: 24, weight: .bold, design: .rounded))
                    Text("Configure your floating experience")
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundColor(.secondary)
                }
                Spacer()
                Image(systemName: "gearshape.fill")
                    .font(.system(size: 32))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundColor(.blue)
            }
            .padding(.bottom, 10)

            // Settings Grid
            VStack(spacing: 12) {
                SettingsTile(title: "Text Size", icon: "textformat.size", value: "\(Int(baseFontSize))pt") {
                    Slider(value: $baseFontSize, in: 10...24, step: 1)
                        .controlSize(.mini)
                }
                
                SettingsTile(title: "Window Opacity", icon: "circle.lefthalf.filled", value: "\(Int(windowOpacity * 100))%") {
                    Slider(value: $windowOpacity, in: 0.1...1.0, step: 0.05)
                        .controlSize(.mini)
                }

                HStack(spacing: 12) {
                    SettingsToggleTile(title: "Window Shadows", icon: "shadow", isOn: $enableShadows)
                    
                    // placeholder for future setting
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Image(systemName: "info.circle.fill")
                                .foregroundColor(.blue)
                            Text("About")
                                .font(.system(size: 12, weight: .bold, design: .rounded))
                        }
                        Text("v1.1.0 Premium")
                            .font(.system(size: 14, weight: .bold, design: .rounded))
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
                    .background(RoundedRectangle(cornerRadius: 16).fill(Color.primary.opacity(0.04)))
                }
            }
            
            Spacer()
        }
        .padding(30)
        #if os(macOS)
        .frame(width: 480, height: 380)
        .background(VisualEffectView(material: .windowBackground, blendingMode: .behindWindow))
        #else
        .background(VisualEffectView(material: .systemMaterial))
        #endif
    }
}

struct SettingsTile<Content: View>: View {
    let title: String
    let icon: String
    let value: String
    let content: () -> Content
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: icon)
                    .foregroundColor(.blue)
                    .font(.system(size: 14, weight: .bold))
                Text(title)
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                Spacer()
                Text(value)
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundColor(.blue)
            }
            
            content()
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 16).fill(Color.primary.opacity(0.04)))
    }
}

struct SettingsToggleTile: View {
    let title: String
    let icon: String
    @Binding var isOn: Bool
    
    var body: some View {
        Button(action: { isOn.toggle() }) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Image(systemName: icon)
                        .foregroundColor(isOn ? .blue : .secondary)
                        .font(.system(size: 14, weight: .bold))
                    Spacer()
                    Toggle("", isOn: $isOn)
                        .toggleStyle(.switch)
                        .labelsHidden()
                        .scaleEffect(0.7)
                }
                Text(title)
                    .font(.system(size: 13, weight: .bold, design: .rounded))
            }
            .padding(16)
            .background(RoundedRectangle(cornerRadius: 16).fill(isOn ? Color.blue.opacity(0.1) : Color.primary.opacity(0.04)))
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(isOn ? Color.blue.opacity(0.3) : Color.clear, lineWidth: 1)
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
}

