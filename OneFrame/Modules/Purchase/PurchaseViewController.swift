//
//  PurchaseViewController.swift
//  OneFrame
//
//  同框相机高级会员 - 内购页面
//

import UIKit
import StoreKit

@available(iOS 15.0, *)
final class PurchaseViewController: UIViewController {

    // MARK: - UI

    private let scrollView = UIScrollView()
    private let contentView = UIView()
    private let iconView = UIImageView()
    private let titleLabel = UILabel()
    private let subtitleLabel = UILabel()
    private let featuresStack = UIStackView()
    private let purchaseButton = UIButton(type: .system)
    private let restoreButton = UIButton(type: .system)
    private let activityIndicator = UIActivityIndicatorView(style: .medium)
    private let legalLabel = UILabel()

    // 价格格式化
    private var priceText: String?

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        loadStoreData()
    }

    // MARK: - Setup

    private func loadStoreData() {
        activityIndicator.startAnimating()
        purchaseButton.isEnabled = false

        Task {
            await IAPManager.shared.loadProducts()
            await IAPManager.shared.checkEntitlements()
            await MainActor.run {
                activityIndicator.stopAnimating()
                updatePurchaseButtonState()
            }
        }
    }

    private func updatePurchaseButtonState() {
        if IAPManager.shared.isPremium {
            purchaseButton.isEnabled = false
            purchaseButton.setTitle(OWLocalized("purchase.purchased"), for: .normal)
            purchaseButton.backgroundColor = .systemGreen
        } else {
            purchaseButton.isEnabled = true
            if let product = IAPManager.shared.premiumProduct {
                priceText = product.displayPrice
                purchaseButton.setTitle("\(OWLocalized("purchase.buy")) - \(product.displayPrice)", for: .normal)
            } else {
                purchaseButton.setTitle(OWLocalized("purchase.buy"), for: .normal)
            }
        }
    }

    private func setupUI() {
        view.backgroundColor = .systemBackground
        title = OWLocalized("purchase.title")
        navigationItem.leftBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .close,
            target: self,
            action: #selector(dismissVC)
        )

        // ScrollView
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scrollView)
        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])

        contentView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(contentView)
        NSLayoutConstraint.activate([
            contentView.topAnchor.constraint(equalTo: scrollView.topAnchor),
            contentView.leadingAnchor.constraint(equalTo: scrollView.leadingAnchor),
            contentView.trailingAnchor.constraint(equalTo: scrollView.trailingAnchor),
            contentView.bottomAnchor.constraint(equalTo: scrollView.bottomAnchor),
            contentView.widthAnchor.constraint(equalTo: scrollView.widthAnchor)
        ])

        // 图标 (会员皇冠)
        iconView.image = UIImage(systemName: "crown.fill")
        iconView.tintColor = .systemYellow
        iconView.contentMode = .scaleAspectFit
        contentView.addSubview(iconView)
        iconView.translatesAutoresizingMaskIntoConstraints = false

        // 标题
        titleLabel.text = OWLocalized("purchase.member_title")
        titleLabel.font = UIFont.boldSystemFont(ofSize: 28)
        titleLabel.textAlignment = .center
        titleLabel.textColor = .label
        contentView.addSubview(titleLabel)
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        // 副标题
        subtitleLabel.text = OWLocalized("purchase.member_subtitle")
        subtitleLabel.font = UIFont.systemFont(ofSize: 15)
        subtitleLabel.textColor = .secondaryLabel
        subtitleLabel.textAlignment = .center
        subtitleLabel.numberOfLines = 0
        contentView.addSubview(subtitleLabel)
        subtitleLabel.translatesAutoresizingMaskIntoConstraints = false

        // 功能列表
        featuresStack.axis = .vertical
        featuresStack.spacing = 16
        featuresStack.alignment = .leading
        featuresStack.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(featuresStack)

        let featureItems: [(icon: String, text: String)] = [
            ("sparkles", OWLocalized("purchase.feature_watermark"))
        ]

        for (iconName, text) in featureItems {
            let row = createFeatureRow(icon: iconName, text: text)
            featuresStack.addArrangedSubview(row)
        }

        // 购买按钮
        purchaseButton.backgroundColor = .systemBlue
        purchaseButton.setTitleColor(.white, for: .normal)
        purchaseButton.layer.cornerRadius = 14
        purchaseButton.titleLabel?.font = UIFont.boldSystemFont(ofSize: 18)
        purchaseButton.addTarget(self, action: #selector(purchaseTapped), for: .touchUpInside)
        contentView.addSubview(purchaseButton)
        purchaseButton.translatesAutoresizingMaskIntoConstraints = false

        // 恢复购买
        restoreButton.setTitle(OWLocalized("purchase.restore"), for: .normal)
        restoreButton.setTitleColor(.systemBlue, for: .normal)
        restoreButton.titleLabel?.font = UIFont.systemFont(ofSize: 14)
        restoreButton.addTarget(self, action: #selector(restoreTapped), for: .touchUpInside)
        contentView.addSubview(restoreButton)
        restoreButton.translatesAutoresizingMaskIntoConstraints = false

        // 法律声明
        legalLabel.text = OWLocalized("purchase.legal")
        legalLabel.font = UIFont.systemFont(ofSize: 11)
        legalLabel.textColor = .tertiaryLabel
        legalLabel.textAlignment = .center
        legalLabel.numberOfLines = 0
        contentView.addSubview(legalLabel)
        legalLabel.translatesAutoresizingMaskIntoConstraints = false

        // 加载指示器
        activityIndicator.hidesWhenStopped = true
        contentView.addSubview(activityIndicator)
        activityIndicator.translatesAutoresizingMaskIntoConstraints = false

        // Layout
        NSLayoutConstraint.activate([
            // 图标
            iconView.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            iconView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 40),
            iconView.widthAnchor.constraint(equalToConstant: 72),
            iconView.heightAnchor.constraint(equalToConstant: 72),

            // 标题
            titleLabel.topAnchor.constraint(equalTo: iconView.bottomAnchor, constant: 20),
            titleLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 32),
            titleLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -32),

            // 副标题
            subtitleLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 10),
            subtitleLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 32),
            subtitleLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -32),

            // 功能列表
            featuresStack.topAnchor.constraint(equalTo: subtitleLabel.bottomAnchor, constant: 36),
            featuresStack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 40),
            featuresStack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -40),

            // 购买按钮
            purchaseButton.topAnchor.constraint(equalTo: featuresStack.bottomAnchor, constant: 40),
            purchaseButton.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            purchaseButton.widthAnchor.constraint(equalTo: contentView.widthAnchor, constant: -48),
            purchaseButton.heightAnchor.constraint(equalToConstant: 52),

            // 恢复购买
            restoreButton.topAnchor.constraint(equalTo: purchaseButton.bottomAnchor, constant: 16),
            restoreButton.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),

            // 法律声明
            legalLabel.topAnchor.constraint(equalTo: restoreButton.bottomAnchor, constant: 24),
            legalLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 32),
            legalLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -32),

            // 加载指示器
            activityIndicator.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            activityIndicator.topAnchor.constraint(equalTo: legalLabel.bottomAnchor, constant: 20),
            activityIndicator.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -40)
        ])
    }

    private func createFeatureRow(icon: String, text: String) -> UIView {
        let container = UIView()
        container.translatesAutoresizingMaskIntoConstraints = false

        let iconView = UIImageView(image: UIImage(systemName: icon))
        iconView.tintColor = .systemBlue
        iconView.contentMode = .scaleAspectFit
        iconView.translatesAutoresizingMaskIntoConstraints = false

        let label = UILabel()
        label.text = text
        label.font = UIFont.systemFont(ofSize: 15)
        label.textColor = .label
        label.numberOfLines = 0
        label.translatesAutoresizingMaskIntoConstraints = false

        container.addSubview(iconView)
        container.addSubview(label)

        NSLayoutConstraint.activate([
            iconView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            iconView.centerYAnchor.constraint(equalTo: label.centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 22),
            iconView.heightAnchor.constraint(equalToConstant: 22),

            label.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 12),
            label.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            label.topAnchor.constraint(equalTo: container.topAnchor),
            label.bottomAnchor.constraint(equalTo: container.bottomAnchor)
        ])

        return container
    }

    // MARK: - Actions

    @objc private func purchaseTapped() {
        purchaseButton.isEnabled = false
        activityIndicator.startAnimating()

        Task {
            await IAPManager.shared.purchase()
            await MainActor.run {
                purchaseButton.isEnabled = true
                activityIndicator.stopAnimating()

                if IAPManager.shared.isPremium {
                    purchaseButton.setTitle(OWLocalized("purchase.purchased"), for: .normal)
                    purchaseButton.backgroundColor = .systemGreen
                    showSuccessAndDismiss()
                } else if let error = IAPManager.shared.purchaseError {
                    showAlert(message: error)
                }
            }
        }
    }

    @objc private func restoreTapped() {
        restoreButton.isEnabled = false
        activityIndicator.startAnimating()

        Task {
            await IAPManager.shared.restorePurchases()
            await MainActor.run {
                restoreButton.isEnabled = true
                activityIndicator.stopAnimating()

                if IAPManager.shared.isPremium {
                    purchaseButton.setTitle(OWLocalized("purchase.purchased"), for: .normal)
                    purchaseButton.backgroundColor = .systemGreen
                    purchaseButton.isEnabled = false
                    showSuccessAndDismiss()
                } else {
                    showAlert(message: OWLocalized("purchase.restore_failed"))
                }
            }
        }
    }

    @objc private func dismissVC() {
        dismiss(animated: true)
    }

    private func showSuccessAndDismiss() {
        let alert = UIAlertController(
            title: OWLocalized("purchase.success_title"),
            message: OWLocalized("purchase.success_message"),
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: OWLocalized("common.ok"), style: .default) { [weak self] _ in
            self?.dismiss(animated: true)
        })
        present(alert, animated: true)
    }

    private func showAlert(message: String) {
        let alert = UIAlertController(
            title: nil,
            message: message,
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: OWLocalized("common.ok"), style: .default))
        present(alert, animated: true)
    }
}
