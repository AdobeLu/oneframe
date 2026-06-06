//
//  MediaDetailViewController.swift
//  OneFrame
//
//  媒体详情页 - 支持滑动翻页、捏合/双击缩放、导出/分享/删除
//

import UIKit
import AVKit

final class MediaDetailViewController: UIViewController {

    // MARK: - Properties

    private let entries: [MediaEntry]
    private let initialIndex: Int
    private var currentIndex: Int

    private let pageViewController = UIPageViewController(
        transitionStyle: .scroll,
        navigationOrientation: .horizontal,
        options: [.interPageSpacing: 20]
    )

    private var pageControllers: [Int: MediaPageViewController] = [:]

    // 自定义底部工具栏（替代 UIToolbar 避免约束冲突）
    private let bottomToolbar = UIView()

    // MARK: - Init

    init(entries: [MediaEntry], initialIndex: Int) {
        self.entries = entries
        self.initialIndex = initialIndex
        self.currentIndex = initialIndex
        super.init(nibName: nil, bundle: nil)
    }

    /// 兼容旧的单条目初始化
    convenience init(entry: MediaEntry) {
        self.init(entries: [entry], initialIndex: 0)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        showPage(at: initialIndex, animated: false)
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        configureGestureDependencies()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        navigationController?.navigationBar.barStyle = .black
        navigationController?.navigationBar.tintColor = .white
    }

    override var prefersStatusBarHidden: Bool { true }

    // MARK: - Setup

    private func setupUI() {
        view.backgroundColor = .black

        // 导航栏标题
        updateNavigationTitle()

        // PageViewController
        pageViewController.dataSource = self
        pageViewController.delegate = self
        pageViewController.view.backgroundColor = .clear
        addChild(pageViewController)
        view.addSubview(pageViewController.view)
        pageViewController.view.translatesAutoresizingMaskIntoConstraints = false
        pageViewController.didMove(toParent: self)

        // 底部工具栏
        bottomToolbar.backgroundColor = UIColor.black.withAlphaComponent(0.85)
        view.addSubview(bottomToolbar)
        bottomToolbar.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            pageViewController.view.topAnchor.constraint(equalTo: view.topAnchor),
            pageViewController.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            pageViewController.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            pageViewController.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            bottomToolbar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            bottomToolbar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            bottomToolbar.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),
            bottomToolbar.heightAnchor.constraint(equalToConstant: 56),
        ])

        setupToolbarButtons()
    }

    /// 将翻页手势引用注入每个页面，让页面内的 ScrollView 动态判断手势优先级
    private func configureGestureDependencies() {
        guard let pagePan = pageViewController.view.subviews.compactMap({ $0 as? UIScrollView }).first?.panGestureRecognizer else {
            return
        }
        for (_, pageVC) in pageControllers {
            pageVC.externalPanGesture = pagePan
        }
    }

    private func setupToolbarButtons() {
        let config = UIImage.SymbolConfiguration(pointSize: 22, weight: .regular)
        let stack = UIStackView()
        stack.axis = .horizontal
        stack.alignment = .center
        stack.distribution = .equalSpacing
        stack.spacing = 12

        let shareBtn = makeToolbarButton(
            icon: UIImage(systemName: "square.and.arrow.up", withConfiguration: config),
            action: #selector(shareMedia)
        )
        let saveBtn = makeToolbarButton(
            icon: UIImage(systemName: "square.and.arrow.down", withConfiguration: config),
            action: #selector(saveToAlbum)
        )
        let deleteBtn = makeToolbarButton(
            icon: UIImage(systemName: "trash", withConfiguration: config),
            action: #selector(deleteMedia)
        )
        deleteBtn.tintColor = .systemRed

        let spacer1 = UIView()
        let spacer2 = UIView()
        spacer1.widthAnchor.constraint(equalToConstant: 40).isActive = true
        spacer2.widthAnchor.constraint(equalToConstant: 40).isActive = true

        stack.addArrangedSubview(saveBtn)
        stack.addArrangedSubview(spacer1)
        stack.addArrangedSubview(shareBtn)
        stack.addArrangedSubview(spacer2)
        stack.addArrangedSubview(deleteBtn)

        bottomToolbar.addSubview(stack)
        stack.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: bottomToolbar.centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: bottomToolbar.centerYAnchor),
        ])
    }

    private func makeToolbarButton(icon: UIImage?, action: Selector) -> UIButton {
        let btn = UIButton(type: .system)
        btn.setImage(icon, for: .normal)
        btn.tintColor = .white
        btn.addTarget(self, action: action, for: .touchUpInside)
        btn.widthAnchor.constraint(equalToConstant: 44).isActive = true
        btn.heightAnchor.constraint(equalToConstant: 44).isActive = true
        return btn
    }

    private func updateNavigationTitle() {
        title = "\(currentIndex + 1) / \(entries.count)"
    }

    // MARK: - Page Management

    private func pageController(for index: Int) -> MediaPageViewController? {
        guard entries.indices.contains(index) else { return nil }
        if let existing = pageControllers[index] { return existing }
        let vc = MediaPageViewController(entry: entries[index])
        pageControllers[index] = vc
        configureGestureForPage(vc)
        return vc
    }

    /// 为新创建的页面注入翻页手势引用
    private func configureGestureForPage(_ pageVC: MediaPageViewController) {
        guard let pagePan = pageViewController.view.subviews.compactMap({ $0 as? UIScrollView }).first?.panGestureRecognizer else {
            return
        }
        pageVC.externalPanGesture = pagePan
    }

    private func showPage(at index: Int, animated: Bool) {
        guard let vc = pageController(for: index) else { return }
        let direction: UIPageViewController.NavigationDirection = index >= currentIndex ? .forward : .reverse
        currentIndex = index
        updateNavigationTitle()
        // 重置前一个页面的缩放
        for (i, ctrl) in pageControllers where i != index {
            ctrl.resetZoom()
        }
        pageViewController.setViewControllers([vc], direction: direction, animated: animated)
    }

    // MARK: - Actions

    @objc private func shareMedia() {
        let entry = entries[currentIndex]
        let url = MediaStorageManager.shared.originalURL(for: entry)
        AlbumExporter.share(mediaURL: url, from: self)
    }

    @objc private func saveToAlbum() {
        let entry = entries[currentIndex]
        let url = MediaStorageManager.shared.originalURL(for: entry)

        if entry.type == .photo {
            guard let data = try? Data(contentsOf: url),
                  let image = UIImage(data: data) else { return }
            AlbumExporter.savePhotoToAlbum(image: image) { [weak self] success, _ in
                self?.showExportResult(success)
            }
        } else {
            AlbumExporter.saveVideoToAlbum(url: url) { [weak self] success, _ in
                self?.showExportResult(success)
            }
        }
    }

    @objc private func deleteMedia() {
        let alert = UIAlertController(
            title: OWLocalized("gallery.delete"),
            message: OWLocalized("gallery.delete_confirm"),
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: OWLocalized("common.cancel"), style: .cancel))
        alert.addAction(UIAlertAction(title: OWLocalized("common.confirm"), style: .destructive) { [weak self] _ in
            guard let self = self else { return }
            let entry = self.entries[self.currentIndex]
            MediaStorageManager.shared.deleteMedia(entry)

            // 如果只剩一条，返回上一页
            if self.entries.count <= 1 {
                self.navigationController?.popViewController(animated: true)
                return
            }

            // 重新加载列表
            let newEntries = MediaStorageManager.shared.entries
            // 简单处理：pop 回去让列表刷新
            self.navigationController?.popViewController(animated: true)
        })
        present(alert, animated: true)
    }

    private func showExportResult(_ success: Bool) {
        let message = success ? "Saved to album" : "Save failed"
        let alert = UIAlertController(title: nil, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: OWLocalized("common.ok"), style: .default))
        present(alert, animated: true)
    }
}

// MARK: - UIPageViewControllerDataSource

extension MediaDetailViewController: UIPageViewControllerDataSource {

    func pageViewController(_ pageViewController: UIPageViewController,
                            viewControllerBefore viewController: UIViewController) -> UIViewController? {
        return pageController(for: currentIndex - 1)
    }

    func pageViewController(_ pageViewController: UIPageViewController,
                            viewControllerAfter viewController: UIViewController) -> UIViewController? {
        return pageController(for: currentIndex + 1)
    }
}

// MARK: - UIPageViewControllerDelegate

extension MediaDetailViewController: UIPageViewControllerDelegate {

    func pageViewController(_ pageViewController: UIPageViewController,
                            didFinishAnimating finished: Bool,
                            previousViewControllers: [UIViewController],
                            transitionCompleted completed: Bool) {
        guard completed, let visibleVC = pageViewController.viewControllers?.first as? MediaPageViewController else { return }
        // 找到当前页面对应的索引
        for (index, ctrl) in pageControllers where ctrl === visibleVC {
            currentIndex = index
            updateNavigationTitle()
            // 重置之前页面的缩放
            for (i, ctrl) in pageControllers where i != index {
                ctrl.resetZoom()
            }
            break
        }
    }
}
