import SwiftUI

// MARK: - Full-screen zoomable exercise infographic
struct MyofascialExerciseImageViewer: View {

    let exercise: MyofascialExercise

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.background.ignoresSafeArea()

                ZoomableImageScrollView(imageName: exercise.imageName)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(.horizontal, 8)
            }
            .navigationTitle(exercise.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Theme.background, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .fontWeight(.semibold)
                        .foregroundStyle(Theme.accent)
                }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                Text("Double-tap to zoom in or out · pinch and drag to pan")
                    .font(.caption)
                    .foregroundStyle(Theme.labelSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .frame(maxWidth: .infinity)
                    .background(Theme.background.opacity(0.92))
            }
        }
    }
}

#if DEBUG
#Preview {
    MyofascialExerciseImageViewer(exercise: .tongueHasAHome)
}
#endif
