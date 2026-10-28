import SwiftUI

/// Atribuirile cerute de licențele Creative Commons pentru fotografiile din reel.
struct CreditsSheet: View {
    let credits: [MediaCredit]

    var body: some View {
        NavigationStack {
            List(credits, id: \.sourceURL) { credit in
                VStack(alignment: .leading, spacing: 6) {
                    Text(credit.title)
                        .font(.headline)
                    Text("Autor: \(credit.author)")
                        .font(.subheadline)
                    HStack(spacing: 16) {
                        if let url = credit.licenseURL.flatMap(URL.init(string:)) {
                            Link(credit.license, destination: url)
                        } else {
                            Text(credit.license)
                        }
                        if let url = URL(string: credit.sourceURL) {
                            Link("Sursa", destination: url)
                        }
                    }
                    .font(.caption)
                }
                .padding(.vertical, 4)
            }
            .navigationTitle("Fotografii")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}
