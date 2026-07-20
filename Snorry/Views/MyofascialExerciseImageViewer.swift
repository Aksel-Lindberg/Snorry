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
            .overlay(alignment: .bottom) {
                Text("Pinch to zoom · double-tap to zoom in or out")
                    .font(.caption2)
                    .foregroundStyle(Theme.labelTertiary)
                    .padding(.bottom, 12)
                    .accessibilityHidden(true)
            }
        }
    }
}

#if DEBUG
#Preview {
    MyofascialExerciseImageViewer(exercise: .tongueHasAHome)
}
#endif
