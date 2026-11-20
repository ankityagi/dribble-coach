import SwiftUI
import SwiftData

@main
struct DribbleCoachApp: App {
    @State private var session = SessionController()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(session)
        }
        .modelContainer(for: SessionRecord.self)
    }
}

struct RootView: View {
    @Environment(SessionController.self) private var session
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        NavigationStack {
            HomeView()
        }
        .fullScreenCover(isPresented: Binding(
            get: { session.phase != .idle },
            set: { presented in if !presented { session.cancel() } }
        )) {
            DrillFlowView()
                .environment(session)
        }
        .onAppear { session.modelContext = modelContext }
        .onChange(of: scenePhase) {
            if scenePhase == .background {
                session.endEarly("The drill stopped because the app was closed.")
            }
        }
    }
}
