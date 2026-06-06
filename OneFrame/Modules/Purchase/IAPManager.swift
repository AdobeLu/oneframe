//
//  IAPManager.swift
//  OneFrame
//
//  StoreKit 2 内购管理器
//

import StoreKit
import Foundation
import Combine

@available(iOS 15.0, *)
@MainActor
final class IAPManager: ObservableObject {

    static let shared = IAPManager()

    // MARK: - Product ID

    private let removeWatermarkID = "com.oneframe.remove_watermark"

    // MARK: - State

    @Published private(set) var isWatermarkRemoved = false
    @Published private(set) var isLoading = false
    @Published private(set) var purchaseError: String?

    /// 可购买的商品
    @Published private(set) var removeWatermarkProduct: Product?

    private var updatesTask: Task<Void, Never>?

    // MARK: - Init

    private init() {
        // 仅监听 Transaction.updates 流；不主动发起网络请求，
        // 避免在 App Store Connect 沙盒未配置时产生 404 错误。
        updatesTask = Task {
            for await result in Transaction.updates {
                if case .verified(let transaction) = result {
                    await handleVerifiedTransaction(transaction)
                }
            }
        }
    }

    deinit {
        updatesTask?.cancel()
    }

    // MARK: - Load Products

    func loadProducts() async {
        do {
            let products = try await Product.products(for: [removeWatermarkID])
            removeWatermarkProduct = products.first
        } catch {
            print("Failed to load products: \(error)")
        }
    }

    // MARK: - Purchase

    func purchase() async {
        guard let product = removeWatermarkProduct else {
            purchaseError = "Product not available"
            return
        }

        isLoading = true
        purchaseError = nil

        do {
            let result = try await product.purchase()

            switch result {
            case .success(let verification):
                if case .verified(let transaction) = verification {
                    await handleVerifiedTransaction(transaction)
                    isWatermarkRemoved = true
                } else {
                    purchaseError = "Transaction unverified"
                }

            case .userCancelled:
                break

            case .pending:
                purchaseError = "Purchase pending"

            @unknown default:
                purchaseError = "Unknown result"
            }
        } catch {
            purchaseError = error.localizedDescription
        }

        isLoading = false
    }

    func restorePurchases() async {
        isLoading = true
        purchaseError = nil

        do {
            try await AppStore.sync()
            await checkEntitlements()
        } catch {
            purchaseError = error.localizedDescription
        }

        isLoading = false
    }

    // MARK: - Entitlements

    func checkEntitlements() async {
        for await result in Transaction.currentEntitlements {
            if case .verified(let transaction) = result {
                if transaction.productID == removeWatermarkID {
                    if let revocationDate = transaction.revocationDate {
                        isWatermarkRemoved = revocationDate < Date()
                    } else {
                        isWatermarkRemoved = true
                    }
                    return
                }
            }
        }
    }

    private func handleVerifiedTransaction(_ transaction: Transaction) async {
        if transaction.productID == removeWatermarkID {
            if let revocationDate = transaction.revocationDate {
                isWatermarkRemoved = revocationDate < Date()
            } else {
                isWatermarkRemoved = true
            }
        }
        await transaction.finish()
    }
}
