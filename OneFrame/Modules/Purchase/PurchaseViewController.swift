//
//  PurchaseViewController.swift
//  OneFrame
//
//  内购页面
//

import UIKit

@available(iOS 15.0, *)
final class PurchaseViewController: UIViewController {

    // MARK: - UI

    private let titleLabel = UILabel()
    private let descriptionLabel = UILabel()
    private let purchaseButton = UIButton(type: .system)
    private let restoreButton = UIButton(type: .system)
    private let activityIndicator = UIActivityIndicatorView(style: .medium)

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        loadStoreData()
    }

    // MARK: - Setup

    private func loadStoreData() {
        activityIndicator.startAnimating()
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
        if IAPManager.shared.isWatermarkRemoved {
            purchaseButton.isEnabled = false
            purchaseButton.setTitle(OWLocalized("purchase.purchased"), for: .normal)
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

        // 图标
        let iconView = UIImageView(image: UIImage(systemName: "crown.fill"))
        iconView.tintColor = .systemYellow
        iconView.contentMode = .scaleAspectFit
        view.addSubview(iconView)
        iconView.translatesAutoresizingMaskIntoConstraints = false

        // 标题
        titleLabel.text = OWLocalized("purchase.title")
        titleLabel.font = UIFont.boldSystemFont(ofSize: 28)
        titleLabel.textAlignment = .center
        view.addSubview(titleLabel)
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        // 描述
        descriptionLabel.text = OWLocalized("purchase.description")
        descriptionLabel.font = UIFont.systemFont(ofSize: 16)
        descriptionLabel.textColor = .secondaryLabel
        descriptionLabel.textAlignment = .center
        descriptionLabel.numberOfLines = 0
        view.addSubview(descriptionLabel)
        descriptionLabel.translatesAutoresizingMaskIntoConstraints = false

        // 购买按钮
        purchaseButton.setTitle(OWLocalized("purchase.buy"), for: .normal)
        purchaseButton.backgroundColor = .systemBlue
        purchaseButton.setTitleColor(.white, for: .normal)
        purchaseButton.layer.cornerRadius = 12
        purchaseButton.titleLabel?.font = UIFont.boldSystemFont(ofSize: 18)
        purchaseButton.addTarget(self, action: #selector(purchaseTapped), for: .touchUpInside)
        view.addSubview(purchaseButton)
        purchaseButton.translatesAutoresizingMaskIntoConstraints = false

        // 恢复购买
        restoreButton.setTitle(OWLocalized("setting.restore_purchase"), for: .normal)
        restoreButton.setTitleColor(.systemBlue, for: .normal)
        restoreButton.addTarget(self, action: #selector(restoreTapped), for: .touchUpInside)
        view.addSubview(restoreButton)
        restoreButton.translatesAutoresizingMaskIntoConstraints = false

        // 加载指示器
        activityIndicator.hidesWhenStopped = true
        view.addSubview(activityIndicator)
        activityIndicator.translatesAutoresizingMaskIntoConstraints = false

        // Layout
        NSLayoutConstraint.activate([
            iconView.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            iconView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 60),
            iconView.widthAnchor.constraint(equalToConstant: 80),
            iconView.heightAnchor.constraint(equalToConstant: 80),

            titleLabel.topAnchor.constraint(equalTo: iconView.bottomAnchor, constant: 24),
            titleLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),

            descriptionLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 16),
            descriptionLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 32),
            descriptionLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -32),

            purchaseButton.topAnchor.constraint(equalTo: descriptionLabel.bottomAnchor, constant: 40),
            purchaseButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            purchaseButton.widthAnchor.constraint(equalToConstant: 220),
            purchaseButton.heightAnchor.constraint(equalToConstant: 50),

            restoreButton.topAnchor.constraint(equalTo: purchaseButton.bottomAnchor, constant: 16),
            restoreButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),

            activityIndicator.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            activityIndicator.topAnchor.constraint(equalTo: restoreButton.bottomAnchor, constant: 20)
        ])
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

                if IAPManager.shared.isWatermarkRemoved {
                    showSuccessAndDismiss()
                } else if let error = IAPManager.shared.purchaseError {
                    showAlert(message: error)
                }
            }
        }
    }

    @objc private func restoreTapped() {
        activityIndicator.startAnimating()

        Task {
            await IAPManager.shared.restorePurchases()
            await MainActor.run {
                activityIndicator.stopAnimating()

                if IAPManager.shared.isWatermarkRemoved {
                    showSuccessAndDismiss()
                } else {
                    showAlert(message: OWLocalized("purchase.failed"))
                }
            }
        }
    }

    @objc private func dismissVC() {
        dismiss(animated: true)
    }

    private func showSuccessAndDismiss() {
        let alert = UIAlertController(
            title: OWLocalized("purchase.purchased"),
            message: nil,
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
