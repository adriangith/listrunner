import SwiftUI

struct GroceryItem: Identifiable {
    let id = UUID()
    let name: String
    let quantity: String
}

struct GroceryListScreen: View {
    private let sampleItems = [
        GroceryItem(name: "Milk", quantity: "1"),
        GroceryItem(name: "Bread", quantity: "1"),
        GroceryItem(name: "Eggs", quantity: "12"),
        GroceryItem(name: "BBQ sauce", quantity: "1")
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    summary
                    groceryList
                    addItemsCard
                    showStoreButton
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 28)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("My groceries")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Settings", systemImage: "gearshape") { }
                        .labelStyle(.iconOnly)
                        .accessibilityLabel("Settings")
                }
            }
        }
        .tint(.listRunnerGreen)
    }

    private var summary: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Ready when you are")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            HStack(spacing: 8) {
                Label("4 pending", systemImage: "cart")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.listRunnerGreen)
                    .padding(.horizontal, 11)
                    .padding(.vertical, 7)
                    .background(Color.listRunnerGreen.opacity(0.1), in: Capsule())

                Text("0 added")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var groceryList: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("YOUR LIST")
                .font(.caption2.weight(.bold))
                .tracking(1.2)
                .foregroundStyle(.secondary)

            VStack(spacing: 0) {
                ForEach(Array(sampleItems.enumerated()), id: \.element.id) { index, item in
                    HStack(spacing: 12) {
                        Image(systemName: "circle")
                            .foregroundStyle(Color(.tertiaryLabel))
                            .accessibilityHidden(true)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.name)
                                .font(.body.weight(.medium))
                            Text("Quantity \(item.quantity)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        Text("Pending")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 5)
                            .background(Color(.tertiarySystemFill), in: Capsule())
                    }
                    .padding(.horizontal, 14)
                    .frame(minHeight: 58)
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("\(item.name), quantity \(item.quantity), pending")

                    if index < sampleItems.count - 1 {
                        Divider().padding(.leading, 50)
                    }
                }
            }
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
        }
    }

    private var addItemsCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Add grocery items")
                .font(.subheadline.weight(.semibold))

            TextField("Milk, bread, eggs", text: .constant(""), axis: .vertical)
                .lineLimit(2...4)
                .textFieldStyle(.roundedBorder)

            HStack {
                Button("Import from Paprika", systemImage: "checklist") { }
                    .font(.footnote.weight(.semibold))

                Spacer()

                Button("Add Items") { }
                    .buttonStyle(.bordered)
                    .font(.footnote.weight(.semibold))
                    .disabled(true)
            }
        }
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
    }

    private var showStoreButton: some View {
        Button("Show Store", systemImage: "cart.fill") { }
            .font(.headline)
            .frame(maxWidth: .infinity, minHeight: 52)
            .foregroundStyle(.white)
            .background(Color.listRunnerGreen, in: RoundedRectangle(cornerRadius: 15))
            .accessibilityHint("Opens Coles and starts with the first pending item")
    }
}

private extension Color {
    static let listRunnerGreen = Color(red: 0.10, green: 0.52, blue: 0.37)
}
