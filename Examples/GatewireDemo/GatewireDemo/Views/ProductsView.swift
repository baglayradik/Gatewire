import Gatewire
import SwiftUI

/// Каталог — публичная зона: работает и без входа.
struct ProductsView: View {
    let api: DemoAPI

    @State private var products: [Product] = []
    @State private var total = 0
    @State private var isLoading = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            List {
                if let errorMessage {
                    Text(errorMessage)
                        .foregroundStyle(.red)
                }

                ForEach(products) { product in
                    ProductRow(product: product)
                }

                if products.count < total {
                    Button("Загрузить ещё") {
                        Task { await loadNextPage() }
                    }
                    .disabled(isLoading)
                }
            }
            .overlay {
                if isLoading && products.isEmpty {
                    ProgressView()
                }
            }
            .navigationTitle("Каталог")
            .refreshable {
                products = []
                await loadNextPage()
            }
            .task {
                guard products.isEmpty else { return }

                await loadNextPage()
            }
        }
    }

    private func loadNextPage() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            let page = try await api.products(skip: products.count)
            products += page.products
            total = page.total
        } catch {
            errorMessage = error.userMessage
        }
    }
}

private struct ProductRow: View {
    let product: Product

    var body: some View {
        HStack(spacing: 12) {
            AsyncImage(url: product.thumbnail) { image in
                image.resizable().scaledToFit()
            } placeholder: {
                Color.secondary.opacity(0.1)
            }
            .frame(width: 48, height: 48)
            .clipShape(RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading) {
                Text(product.title)
                Text(product.price, format: .currency(code: "USD"))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
