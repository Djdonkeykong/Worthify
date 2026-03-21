import SwiftUI

struct HomeView: View {
    var body: some View {
        WorthifyScreen {
            VStack(alignment: .leading, spacing: 16) {
                Text("Get an artwork estimate in seconds.")
                    .font(.title2.weight(.semibold))

                Text("Upload a clear image of your art and we will run an instant analysis.")
                    .font(.body)
                    .foregroundStyle(.secondary)
            }
            .padding(.top, 8)

            NavigationLink {
                AnalyzeView()
            } label: {
                Label("Upload Artwork", systemImage: "photo.badge.plus")
                    .font(.title3.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 24)
                    .foregroundStyle(.white)
                    .background(AppTheme.accent, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            }
            .buttonStyle(.plain)
        }
        .navigationTitle("Home")
        .navigationBarTitleDisplayMode(.inline)
    }
}
