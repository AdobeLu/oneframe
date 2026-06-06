//
//  SettingsViewController.swift
//  OneFrame
//
//  设置页面
//

import UIKit
import StoreKit
import WebKit

@available(iOS 15.0, *)
final class SettingsViewController: UIViewController {

    // MARK: - UI

    private let tableView = UITableView(frame: .zero, style: .insetGrouped)

    private enum Section: Int, CaseIterable {
        case general
        case purchase
        case about

        var title: String {
            switch self {
            case .general: return ""
            case .purchase: return ""
            case .about: return ""
            }
        }
    }

    private enum SettingItem {
        case language
        case removeWatermark
        case restorePurchase
        case privacyPolicy
        case about
        case rate

        var title: String {
            switch self {
            case .language: return OWLocalized("setting.language")
            case .removeWatermark: return OWLocalized("setting.remove_watermark")
            case .restorePurchase: return OWLocalized("setting.restore_purchase")
            case .privacyPolicy: return OWLocalized("setting.privacy_policy")
            case .about: return OWLocalized("setting.about")
            case .rate: return OWLocalized("setting.rate")
            }
        }

        var icon: String {
            switch self {
            case .language: return "globe"
            case .removeWatermark: return "crown"
            case .restorePurchase: return "arrow.counterclockwise.circle"
            case .privacyPolicy: return "hand.raised"
            case .about: return "info.circle"
            case .rate: return "star"
            }
        }
    }

    private let sections: [[SettingItem]] = [
        [.language],
        [.removeWatermark, .restorePurchase],
        [.privacyPolicy, .about, .rate]
    ]

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        setupNotifications()
    }

    // MARK: - Setup

    private func setupUI() {
        view.backgroundColor = .systemBackground
        title = OWLocalized("setting.title")

        tableView.delegate = self
        tableView.dataSource = self
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "cell")
        view.addSubview(tableView)
        tableView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: view.topAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }

    private func setupNotifications() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(languageDidChange),
            name: .languageDidChange,
            object: nil
        )
    }

    @objc private func languageDidChange() {
        title = OWLocalized("setting.title")
        tableView.reloadData()
    }

    // MARK: - Actions

    private func showLanguagePicker() {
        let alert = UIAlertController(title: OWLocalized("setting.language"), message: nil, preferredStyle: .actionSheet)

        for lang in AppLanguage.allCases {
            let action = UIAlertAction(title: lang.displayName, style: .default) { _ in
                LanguageManager.shared.setLanguage(lang)
            }
            if lang == LanguageManager.shared.currentLanguage {
                action.setValue(true, forKey: "checked")
            }
            alert.addAction(action)
        }

        alert.addAction(UIAlertAction(title: OWLocalized("common.cancel"), style: .cancel))
        present(alert, animated: true)
    }

    private func showPurchase() {
        let vc = PurchaseViewController()
        let nav = UINavigationController(rootViewController: vc)
        present(nav, animated: true)
    }

    private func restorePurchase() {
        let indicator = UIActivityIndicatorView(style: .medium)
        indicator.startAnimating()
        navigationItem.rightBarButtonItem = UIBarButtonItem(customView: indicator)

        Task {
            await IAPManager.shared.restorePurchases()
            await MainActor.run {
                navigationItem.rightBarButtonItem = nil

                let message = IAPManager.shared.isWatermarkRemoved
                    ? OWLocalized("purchase.purchased")
                    : OWLocalized("purchase.failed")

                let alert = UIAlertController(title: nil, message: message, preferredStyle: .alert)
                alert.addAction(UIAlertAction(title: OWLocalized("common.ok"), style: .default))
                self.present(alert, animated: true)
            }
        }
    }

    private func showPrivacyPolicy() {
        let vc = UIViewController()
        vc.view.backgroundColor = .systemBackground
        vc.title = OWLocalized("privacy.title")

        let webView = WKWebView()
        vc.view.addSubview(webView)
        webView.frame = vc.view.bounds
        webView.autoresizingMask = [.flexibleWidth, .flexibleHeight]

        // 从 bundle 加载隐私政策 HTML（或网络 URL）
        if let url = Bundle.main.url(forResource: "privacy", withExtension: "html") {
            webView.load(URLRequest(url: url))
        }

        navigationController?.pushViewController(vc, animated: true)
    }

    private func showAbout() {
        let vc = UIViewController()
        vc.view.backgroundColor = .systemBackground
        vc.title = OWLocalized("about.title")

        let stack = UIStackView()
        stack.axis = .vertical
        stack.alignment = .center
        stack.spacing = 12
        vc.view.addSubview(stack)
        stack.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: vc.view.centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: vc.view.centerYAnchor)
        ])

        // App Icon
        let iconView = UIImageView(image: UIImage(named: "AppIcon"))
        iconView.layer.cornerRadius = 16
        iconView.clipsToBounds = true
        stack.addArrangedSubview(iconView)

        // App 名称
        let nameLabel = UILabel()
        nameLabel.text = "OneFrame"
        nameLabel.font = UIFont.boldSystemFont(ofSize: 24)
        stack.addArrangedSubview(nameLabel)

        // 版本
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
        let versionLabel = UILabel()
        versionLabel.text = "\(OWLocalized("about.version")) \(version)"
        versionLabel.textColor = .secondaryLabel
        stack.addArrangedSubview(versionLabel)

        navigationController?.pushViewController(vc, animated: true)
    }

    private func rateApp() {
        guard let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene else { return }
        SKStoreReviewController.requestReview(in: scene)
    }
}

// MARK: - UITableViewDelegate, UITableViewDataSource

@available(iOS 15.0, *)
extension SettingsViewController: UITableViewDelegate, UITableViewDataSource {

    func numberOfSections(in tableView: UITableView) -> Int {
        sections.count
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        sections[section].count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "cell", for: indexPath)
        let item = sections[indexPath.section][indexPath.row]

        var config = cell.defaultContentConfiguration()
        config.text = item.title
        config.image = UIImage(systemName: item.icon)
        cell.contentConfiguration = config
        cell.accessoryType = .disclosureIndicator

        // 特殊处理：语言显示当前值
        if item == .language {
            cell.detailTextLabel?.text = LanguageManager.shared.currentLanguage.displayName
        }

        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        let item = sections[indexPath.section][indexPath.row]

        switch item {
        case .language: showLanguagePicker()
        case .removeWatermark: showPurchase()
        case .restorePurchase: restorePurchase()
        case .privacyPolicy: showPrivacyPolicy()
        case .about: showAbout()
        case .rate: rateApp()
        }
    }
}
