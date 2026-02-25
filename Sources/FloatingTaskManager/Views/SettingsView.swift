import SwiftUI

struct SettingsView: View {
    @AppStorage("baseFontSize") var baseFontSize: Double = 13.0
    @AppStorage("windowOpacity") var windowOpacity: Double = 0.95
    @AppStorage("enableShadows") var enableShadows: Bool = true
    
    var body: some View {
        Form {
            Section(header: Text("Appearance")) {
                VStack(alignment: .leading, spacing: 14) {
                    // Font Size
                    HStack {
                        Image(systemName: "textformat.size")
                            .frame(width: 20)
                        Slider(value: $baseFontSize, in: 10...24, step: 1)
                        Text("\(Int(baseFontSize)) pt")
                            .frame(width: 45, alignment: .trailing)
                    }
                    
                    // Opacity
                    HStack {
                        Image(systemName: "circle.lefthalf.filled")
                            .frame(width: 20)
                        Slider(value: $windowOpacity, in: 0.1...1.0, step: 0.05)
                        Text("\(Int(windowOpacity * 100))%")
                            .frame(width: 45, alignment: .trailing)
                    }

                    // Shadows
                    Toggle("Enable Window Shadows", isOn: $enableShadows)
                        .toggleStyle(.switch)
                }
                .padding(.vertical, 8)
            }
            
            Section(header: Text("About")) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Floating Task Manager")
                        .font(.headline)
                    Text("Version 1.0.0")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .padding(.vertical, 8)
            }
        }
        .formStyle(.grouped)
        .frame(width: 400, height: 250)
    }
}


