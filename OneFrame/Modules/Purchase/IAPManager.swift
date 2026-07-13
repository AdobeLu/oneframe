//
//  IAPManager.swift
//  OneFrame
//
//  StoreKit 2 内购管理器 - 同框相机高级会员
//  支持三种方案：包月 / 包年 / 买断
//

import StoreKit
import Foundation
import Combine

@available(iOS 15.0, *)
final class IAPManager: ObservableObject {

    static let shared = IAPManager()

    // MARK: - Product IDs

    private let monthlyID  = "com.feiyuntech.oneframe.monthly"
    private let yearlyID   = "com.feiyuntech.oneframe.yearly"
    private let lifetimeID = "com.feiyuntech.OneFrame.Premium"

    private var allPremiumIDs: Set<String> {
        [monthlyID, yearlyID, lifetimeID]
    }

    // MARK: - State

    @Published private(set) var isPremium = false
    @Published private(set) var isLoading = false
    @Published private(set) var purchaseError: String?

    /// 购买完成回调（成功/失败/取消后触发，供 VC 更新 UI）
    var onPurchaseFinished: (() -> Void)?

    @Published private(set) var monthlyProduct: Product?
    @Published private(set) var yearlyProduct: Product?
    @Published private(set) var lifetimeProduct: Product?

    private var updatesTask: Task<Void, Never>?

    // MARK: - Init

    private init() {
        updatesTask = Task {
            for await result in Transaction.updates {
                if case .verified(let transaction) = result {
                    await handleVerifiedTransaction(transaction)
                    await MainActor.run { self.onPurchaseFinished?() }
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
            let products = try await Product.products(for: Array(allPremiumIDs))
            await MainActor.run { [products] in
                for product in products {
                    switch product.id {
                    case self.monthlyID:  self.monthlyProduct = product
                    case self.yearlyID:   self.yearlyProduct = product
                    case self.lifetimeID: self.lifetimeProduct = product
                    default: break
                    }
                }
            }
        } catch {
            print("Failed to load products: \(error)")
        }
    }

    // MARK: - Purchase (fire-and-forget，不阻塞主线程)

    /// 发起购买（不 await 结果，通过 onPurchaseFinished 回调获取结果）
    /// product.purchase() 内部会在 window 上做视图层级操作，
    /// 取消购买后 dismiss 期间会阻塞 presenting VC → 必须 fire-and-forget
    func purchase(_ product: Product) {
        Task {
            await MainActor.run {
                isLoading = true
                purchaseError = nil
            }

            let result = try await product.purchase()

            switch result {
            case .success(let verification):
                if case .verified(let transaction) = verification {
                    await handleVerifiedTransaction(transaction)
                } else {
                    await MainActor.run { purchaseError = "Transaction unverified" }
                }

            case .userCancelled:
                break

            case .pending:
                await MainActor.run { purchaseError = "Purchase pending" }

            @unknown default:
                await MainActor.run { purchaseError = "Unknown result" }
            }

            await MainActor.run {
                isLoading = false
                onPurchaseFinished?()
            }
        }
    }

    // MARK: - Restore Purchases

    func restorePurchases() async {
        await MainActor.run {
            isLoading = true
            purchaseError = nil
        }

        do {
            try await AppStore.sync()
            await checkEntitlements()
        } catch {
            await MainActor.run { purchaseError = error.localizedDescription }
        }

        await MainActor.run { isLoading = false }
    }

    // MARK: - Entitlements

    func checkEntitlements() async {
        for await result in Transaction.currentEntitlements {
            if case .verified(let transaction) = result {
                if allPremiumIDs.contains(transaction.productID) {
                    let premium = (transaction.revocationDate == nil)
                    await MainActor.run { isPremium = premium }
                    return
                }
            }
        }
        await MainActor.run { isPremium = false }
    }

    private func handleVerifiedTransaction(_ transaction: Transaction) async {
        if allPremiumIDs.contains(transaction.productID) {
            let premium = (transaction.revocationDate == nil)
            await MainActor.run { isPremium = premium }
        }
        await transaction.finish()
    }
}
