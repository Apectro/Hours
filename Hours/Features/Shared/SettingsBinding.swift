import SwiftUI

extension SettingsStore {
    /// A binding straight into a settings field.
    ///
    /// Writes go through `update`, so every change is persisted and every
    /// observer is notified — there is no path that mutates settings without
    /// saving them.
    func binding<Value>(_ keyPath: WritableKeyPath<AppSettings, Value>) -> Binding<Value> {
        Binding(
            get: { self.settings[keyPath: keyPath] },
            set: { newValue in self.update { $0[keyPath: keyPath] = newValue } }
        )
    }
}
