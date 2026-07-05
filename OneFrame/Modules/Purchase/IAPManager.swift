//
//  IAPManager.swift
//  OneFrame
//
//  StoreKit 2 内购管理器 - 同框相机高级会员
//

import StoreKit
import Foundation
import Combine

@available(iOS 15.0, *)
@MainActor
final class IAPManager: ObservableObject {

    static let shared = IAPManager()

    // MARK: - Product ID

    private let premiumID = "com.feiyuntech.OneFrame.Premium"

    // MARK: - State

    /// 是否为高级会员（已购买去水印等增值功能）
    @Published private(set) var isPremium = false
    @Published private(set) var isLoading = false
    @Published private(set) var purchaseError: String?

    /// 可购买的高级会员商品
    @Published private(set) var premiumProduct: Product?

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
            let products = try await Product.products(for: [premiumID])
            premiumProduct = products.first
        } catch {
            print("Failed to load products: \(error)")
        }
    }

    // MARK: - Purchase

    func purchase() async {
        guard let product = premiumProduct else {
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
                    // isPremium 已在 handleVerifiedTransaction 中根据 revocationDate 正确设置
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

    // MARK: - Restore Purchases

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
                if transaction.productID == premiumID {
                    // revocationDate 非 nil 表示已退款，nil 表示有效购买
                    isPremium = (transaction.revocationDate == nil)
                    return
                }
            }
        }
        // 未找到有效凭证，确保状态为未购买
        isPremium = false
    }

    private func handleVerifiedTransaction(_ transaction: Transaction) async {
        if transaction.productID == premiumID {
            // revocationDate 非 nil 表示已退款，nil 表示有效购买
            isPremium = (transaction.revocationDate == nil)
        }
        await transaction.finish()
    }
}
