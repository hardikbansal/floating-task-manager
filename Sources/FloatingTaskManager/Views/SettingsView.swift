import SwiftUI

struct SettingsView: View {
    @AppStorage("baseFontSize") var baseFontSize: Double = 13.0
    
    var body: some View {
        Form {
            Section(header: Text("Appearance")) {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Image(systemName: "textformat.size")
                        Slider(value: $baseFontSize, in: 10...24, step: 1)
                        Text("\(Int(baseFontSize)) pt")
                            .frame(width: 40, alignment: .trailing)
                    }
                    Text("Adjust the global text size for all task lists and notes.")
                        .font(.caption)
                        .foregroundColor(.secondary)
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


