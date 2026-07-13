//
//  PurchaseViewController.swift
//  OneFrame
//
//  同框相机高级会员 - 内购页面（包月 / 包年 / 买断）
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

    /// 三个方案按钮 + 恢复购买
    private var planButtons: [UIButton] = []
    private let restoreButton = UIButton(type: .system)
    private let activityIndicator = UIActivityIndicatorView(style: .medium)
    private let legalLabel = UILabel()

    /// 方案按钮容器（用于统一管理布局）
    private let plansStack = UIStackView()

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        setupPurchaseCallback()
        loadStoreData()
    }

    // MARK: - Setup

    /// 注册购买结果回调（异步 fire-and-forget 模式，不阻塞 UI）
    private func setupPurchaseCallback() {
        IAPManager.shared.onPurchaseFinished = { [weak self] in
            guard let self = self else { return }
            self.activityIndicator.stopAnimating()
            self.planButtons.forEach { $0.isEnabled = true }

            if IAPManager.shared.isPremium {
                self.updateButtonStates()
                self.showSuccessAndDismiss()
            } else if let error = IAPManager.shared.purchaseError {
                self.showAlert(message: error)
            }
            // 取消购买（isPremium=false, purchaseError=nil）→ 静默恢复
        }
    }

    private func loadStoreData() {
        activityIndicator.startAnimating()
        planButtons.forEach { $0.isEnabled = false }

        Task.detached { [weak self] in
            await IAPManager.shared.loadProducts()
            await IAPManager.shared.checkEntitlements()
            await MainActor.run {
                guard let self = self else { return }
                self.activityIndicator.stopAnimating()
                self.updateButtonStates()
            }
        }
    }

    private func updateButtonStates() {
        if IAPManager.shared.isPremium {
            for button in planButtons {
                button.isEnabled = false
                button.setTitle(OWLocalized("purchase.purchased"), for: .normal)
                button.backgroundColor = .systemGreen
            }
        } else {
            updatePlanButton(
                button: planButtons[safe: 0],
                product: IAPManager.shared.monthlyProduct,
                fallbackKey: "purchase.monthly"
            )
            updatePlanButton(
                button: planButtons[safe: 1],
                product: IAPManager.shared.yearlyProduct,
                fallbackKey: "purchase.yearly"
            )
            updatePlanButton(
                button: planButtons[safe: 2],
                product: IAPManager.shared.lifetimeProduct,
                fallbackKey: "purchase.lifetime"
            )
        }
    }

    private func updatePlanButton(button: UIButton?, product: Product?, fallbackKey: String) {
        guard let button = button else { return }
        button.isEnabled = (product != nil)
        if let product = product {
            let title = "\(OWLocalized(fallbackKey)) - \(product.displayPrice)"
            button.setTitle(title, for: .normal)
            button.backgroundColor = .systemBlue
        } else {
            button.setTitle(OWLocalized(fallbackKey), for: .normal)
            button.backgroundColor = .systemGray
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

        // 图标
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

        // 三个方案按钮容器
        plansStack.axis = .vertical
        plansStack.spacing = 12
        plansStack.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(plansStack)

        // 创建三个方案按钮
        let monthlyBtn = makePlanButton(tag: 0)
        let yearlyBtn = makePlanButton(tag: 1)
        let lifetimeBtn = makePlanButton(tag: 2)

        planButtons = [monthlyBtn, yearlyBtn, lifetimeBtn]
        plansStack.addArrangedSubview(monthlyBtn)
        plansStack.addArrangedSubview(yearlyBtn)
        plansStack.addArrangedSubview(lifetimeBtn)

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
            iconView.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            iconView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 40),
            iconView.widthAnchor.constraint(equalToConstant: 72),
            iconView.heightAnchor.constraint(equalToConstant: 72),

            titleLabel.topAnchor.constraint(equalTo: iconView.bottomAnchor, constant: 20),
            titleLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 32),
            titleLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -32),

            subtitleLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 10),
            subtitleLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 32),
            subtitleLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -32),

            featuresStack.topAnchor.constraint(equalTo: subtitleLabel.bottomAnchor, constant: 36),
            featuresStack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 40),
            featuresStack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -40),

            plansStack.topAnchor.constraint(equalTo: featuresStack.bottomAnchor, constant: 32),
            plansStack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 24),
            plansStack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -24),

            restoreButton.topAnchor.constraint(equalTo: plansStack.bottomAnchor, constant: 16),
            restoreButton.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),

            legalLabel.topAnchor.constraint(equalTo: restoreButton.bottomAnchor, constant: 24),
            legalLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 32),
            legalLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -32),

            activityIndicator.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            activityIndicator.topAnchor.constraint(equalTo: legalLabel.bottomAnchor, constant: 20),
            activityIndicator.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -40)
        ])
    }

    // MARK: - Helpers

    private func makePlanButton(tag: Int) -> UIButton {
        let button = UIButton(type: .system)
        button.backgroundColor = .systemBlue
        button.setTitleColor(.white, for: .normal)
        button.layer.cornerRadius = 14
        button.titleLabel?.font = UIFont.boldSystemFont(ofSize: 17)
        button.tag = tag
        button.addTarget(self, action: #selector(planButtonTapped(_:)), for: .touchUpInside)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.heightAnchor.constraint(equalToConstant: 50).isActive = true
        return button
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

    @objc private func planButtonTapped(_ sender: UIButton) {
        let product: Product?
        switch sender.tag {
        case 0: product = IAPManager.shared.monthlyProduct
        case 1: product = IAPManager.shared.yearlyProduct
        case 2: product = IAPManager.shared.lifetimeProduct
        default: return
        }
        guard let product = product else { return }

        // 🔥 fire-and-forget：不 await，购买结果通过 onPurchaseFinished 异步回调
        //    避免 product.purchase() 内部的 StoreKit dismiss 过程阻塞主线程
        sender.isEnabled = false
        activityIndicator.startAnimating()
        IAPManager.shared.purchase(product)
    }

    @objc private func restoreTapped() {
        restoreButton.isEnabled = false
        activityIndicator.startAnimating()

        Task.detached { [weak self] in
            await IAPManager.shared.restorePurchases()
            await MainActor.run {
                guard let self = self else { return }
                self.restoreButton.isEnabled = true
                self.activityIndicator.stopAnimating()

                if IAPManager.shared.isPremium {
                    self.updateButtonStates()
                    self.showSuccessAndDismiss()
                } else {
                    self.showAlert(message: OWLocalized("purchase.restore_failed"))
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
        let alert = UIAlertController(title: nil, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: OWLocalized("common.ok"), style: .default))
        present(alert, animated: true)
    }
}

// MARK: - Array safe subscript

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
