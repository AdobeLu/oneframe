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
        case premiumMembership
        case watermark
        case privacyPolicy
        case about
        case rate

        var title: String {
            switch self {
            case .language: return OWLocalized("setting.language")
            case .premiumMembership: return OWLocalized("setting.premium_membership")
            case .watermark: return OWLocalized("setting.watermark")
            case .privacyPolicy: return OWLocalized("setting.privacy_policy")
            case .about: return OWLocalized("setting.about")
            case .rate: return OWLocalized("setting.rate")
            }
        }

        var icon: String {
            switch self {
            case .language: return "globe"
            case .premiumMembership: return "crown"
            case .watermark: return "textformat.size.smaller"
            case .privacyPolicy: return "hand.raised"
            case .about: return "info.circle"
            case .rate: return "star"
            }
        }
    }

    private let sections: [[SettingItem]] = [
        [.language],
        [.premiumMembership, .watermark],
        [.privacyPolicy, .about, .rate]
    ]

    /// UserDefaults key for brand watermark toggle
    private static let brandWatermarkHiddenKey = "OneFrame.BrandWatermarkHidden"

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        setupNotifications()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        // 返回此页面时刷新购买状态
        Task {
            await IAPManager.shared.checkEntitlements()
            await MainActor.run {
                tableView.reloadData()
            }
        }
    }

    // MARK: - Setup

    private func setupUI() {
        view.backgroundColor = .systemBackground
        title = OWLocalized("setting.title")

        tableView.delegate = self
        tableView.dataSource = self
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "cell")
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "premiumCell")
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "watermarkCell")
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

    private func showPremiumMembership() {
        let vc = PurchaseViewController()
        let nav = UINavigationController(rootViewController: vc)
        present(nav, animated: true)
    }

    @objc private func watermarkSwitchChanged(_ sender: UISwitch) {
        let hidden = !sender.isOn
        UserDefaults.standard.set(hidden, forKey: Self.brandWatermarkHiddenKey)
        // 刷新 footer 状态
        tableView.reloadSections(IndexSet(integer: 1), with: .none)
    }

    private func showPrivacyPolicy() {
        let vc = UIViewController()
        vc.view.backgroundColor = .systemBackground
        vc.title = OWLocalized("privacy.title")

        let webView = WKWebView()
        vc.view.addSubview(webView)
        webView.frame = vc.view.bounds
        webView.autoresizingMask = [.flexibleWidth, .flexibleHeight]

        // 根据当前语言加载对应的隐私政策 HTML
        let fileName: String
        switch LanguageManager.shared.currentLanguage {
        case .chinese: fileName = "privacy_zh-Hans"
        case .english:  fileName = "privacy_en"
        }
        if let url = Bundle.main.url(forResource: fileName, withExtension: "html") {
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

    func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        if section == 1 {
            if !IAPManager.shared.isPremium {
                return OWLocalized("setting.watermark_footer")
            }
            return nil
        }
        return nil
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let item = sections[indexPath.section][indexPath.row]

        let reuseID: String
        if item == .watermark {
            reuseID = "watermarkCell"
        } else if item == .premiumMembership {
            reuseID = "premiumCell"
        } else {
            reuseID = "cell"
        }

        let cell = tableView.dequeueReusableCell(withIdentifier: reuseID, for: indexPath)

        var config = cell.defaultContentConfiguration()
        config.text = item.title
        config.image = UIImage(systemName: item.icon)
        cell.contentConfiguration = config

        // Logo 水印开关：仅高级会员可关闭品牌水印
        if item == .watermark {
            let toggle = UISwitch()
            toggle.isOn = !UserDefaults.standard.bool(forKey: Self.brandWatermarkHiddenKey)
            toggle.isEnabled = IAPManager.shared.isPremium
            toggle.addTarget(self, action: #selector(watermarkSwitchChanged(_:)), for: .valueChanged)
            cell.accessoryView = toggle
            cell.selectionStyle = .none
            return cell
        }

        // 高级会员行：已购买显示绿色勾
        if item == .premiumMembership {
            if IAPManager.shared.isPremium {
                cell.accessoryView = UIImageView(image: UIImage(systemName: "checkmark.seal.fill"))
                (cell.accessoryView as? UIImageView)?.tintColor = .systemGreen
            } else {
                cell.accessoryView = nil
                cell.accessoryType = .disclosureIndicator
            }
        } else if item == .language {
            cell.accessoryType = .disclosureIndicator
            // 在 detailText 显示当前语言
            var detailConfig = config
            detailConfig.secondaryText = LanguageManager.shared.currentLanguage.displayName
            cell.contentConfiguration = detailConfig
        } else {
            cell.accessoryType = .disclosureIndicator
            cell.accessoryView = nil
        }

        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        let item = sections[indexPath.section][indexPath.row]

        switch item {
        case .language: showLanguagePicker()
        case .premiumMembership: showPremiumMembership()
        case .privacyPolicy: showPrivacyPolicy()
        case .about: showAbout()
        case .rate: rateApp()
        case .watermark: break // UISwitch 处理，无需 didSelect
        }
    }
}
