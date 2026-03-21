import SwiftUI

struct SplashView: View {
    var body: some View {
        ZStack {
            AppBackdrop()
            Text("Worthify")
                .font(.largeTitle.weight(.semibold))
        }
    }
}
