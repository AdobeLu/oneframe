//
//  MediaPreviewViewController.swift
//  OneFrame
//
//  相册预览页面 - 支持批量选择、双指平滑缩放变更布局列数（模拟系统相册）
//

import UIKit
import Photos

final class MediaPreviewViewController: UIViewController {

    // MARK: - UI

    private let collectionView: UICollectionView
    private let emptyLabel = UILabel()

    // 选择模式底部工具栏
    private let selectionToolbar = UIView()
    private var selectionCountLabel: UILabel!

    // MARK: - Data

    private var entries: [MediaEntry] = []

    // MARK: - Selection State

    private var isSelectionMode = false {
        didSet { updateUIForSelectionMode() }
    }
    private var selectedIndices = Set<Int>()


    // MARK: - Layout (setCollectionViewLayout 原生 fade 过渡，模拟系统相册)

    private var layout: UICollectionViewFlowLayout

    /// 当前整数列数（1/3/5）
    private var itemsPerRow: CGFloat = 3

    // MARK: - Pinch Gesture State

    /// 手势逐帧 delta 累计缩放值（追踪自上次 layout 切换以来的变化）
    private var pinchAccumulatedScale: CGFloat = 1.0
    /// 上一帧 gesture.scale 快照，用于计算 delta
    private var lastPinchScale: CGFloat = 1.0
    /// layout 切换动画进行中标记，避免重叠触发
    private var isLayoutTransitioning = false

    /// 触发 layout 切换的缩放阈值（累积变化超过 15% 即切换）
    private let pinchLayoutThreshold: CGFloat = 0.15

    // MARK: - Init

    init() {
        let initialLayout = UICollectionViewFlowLayout()
        initialLayout.minimumInteritemSpacing = 2
        initialLayout.minimumLineSpacing = 2
        initialLayout.sectionInset = UIEdgeInsets(top: 2, left: 2, bottom: 2, right: 2)

        let spacing = initialLayout.minimumInteritemSpacing * (3 - 1) + initialLayout.sectionInset.left + initialLayout.sectionInset.right
        let itemWidth = (UIScreen.main.bounds.width - spacing) / 3
        initialLayout.itemSize = CGSize(width: itemWidth, height: itemWidth)

        self.layout = initialLayout
        collectionView = UICollectionView(frame: .zero, collectionViewLayout: initialLayout)
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        title = OWLocalized("gallery.title")
        emptyLabel.text = OWLocalized("gallery.empty")
        refreshRightBarButton()
        if isSelectionMode {
            navigationItem.leftBarButtonItem = UIBarButtonItem(
                title: OWLocalized("common.cancel"),
                style: .plain,
                target: self,
                action: #selector(toggleSelectionMode)
            )
            updateSelectionToolbar()
        }
        reloadData()
    }

    // MARK: - Setup

    private func setupUI() {
        view.backgroundColor = .systemBackground
        title = OWLocalized("gallery.title")

        refreshRightBarButton()

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(languageDidChange),
            name: .languageDidChange,
            object: nil
        )

        collectionView.backgroundColor = .systemBackground
        collectionView.delegate = self
        collectionView.dataSource = self
        collectionView.register(MediaThumbnailCell.self, forCellWithReuseIdentifier: "thumb")
        collectionView.allowsMultipleSelection = true
        view.addSubview(collectionView)
        collectionView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            collectionView.topAnchor.constraint(equalTo: view.topAnchor),
            collectionView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            collectionView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            collectionView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])

        // 双指平滑缩放
        let pinch = UIPinchGestureRecognizer(target: self, action: #selector(handlePinch(_:)))
        pinch.delegate = self
        collectionView.addGestureRecognizer(pinch)

        setupSelectionToolbar()

        emptyLabel.text = OWLocalized("gallery.empty")
        emptyLabel.textColor = .secondaryLabel
        emptyLabel.textAlignment = .center
        emptyLabel.numberOfLines = 0
        emptyLabel.isHidden = true
        view.addSubview(emptyLabel)
        emptyLabel.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            emptyLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            emptyLabel.centerYAnchor.constraint(equalTo: view.centerYAnchor)
        ])
    }

    private func setupSelectionToolbar() {
        selectionToolbar.backgroundColor = UIColor.systemBackground
        selectionToolbar.isHidden = true

        let topLine = UIView()
        topLine.backgroundColor = .separator
        topLine.translatesAutoresizingMaskIntoConstraints = false
        selectionToolbar.addSubview(topLine)

        selectionCountLabel = UILabel()
        selectionCountLabel.font = .systemFont(ofSize: 14, weight: .medium)
        selectionCountLabel.textColor = .label
        selectionCountLabel.textAlignment = .center

        let config = UIImage.SymbolConfiguration(pointSize: 22, weight: .regular)

        let saveBtn = makeToolbarButton(
            icon: UIImage(systemName: "square.and.arrow.down", withConfiguration: config),
            action: #selector(saveSelectedToAlbum)
        )
        let shareBtn = makeToolbarButton(
            icon: UIImage(systemName: "square.and.arrow.up", withConfiguration: config),
            action: #selector(shareSelected)
        )
        let deleteBtn = makeToolbarButton(
            icon: UIImage(systemName: "trash", withConfiguration: config),
            action: #selector(deleteSelected)
        )
        deleteBtn.tintColor = .systemRed

        let stack = UIStackView(arrangedSubviews: [saveBtn, shareBtn, deleteBtn])
        stack.axis = .horizontal
        stack.alignment = .center
        stack.distribution = .equalSpacing
        stack.spacing = 16

        selectionToolbar.addSubview(selectionCountLabel)
        selectionToolbar.addSubview(stack)

        selectionCountLabel.translatesAutoresizingMaskIntoConstraints = false
        stack.translatesAutoresizingMaskIntoConstraints = false

        view.addSubview(selectionToolbar)
        selectionToolbar.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            topLine.topAnchor.constraint(equalTo: selectionToolbar.topAnchor),
            topLine.leadingAnchor.constraint(equalTo: selectionToolbar.leadingAnchor),
            topLine.trailingAnchor.constraint(equalTo: selectionToolbar.trailingAnchor),
            topLine.heightAnchor.constraint(equalToConstant: 0.5),

            selectionCountLabel.centerYAnchor.constraint(equalTo: selectionToolbar.centerYAnchor),
            selectionCountLabel.leadingAnchor.constraint(equalTo: selectionToolbar.leadingAnchor, constant: 20),

            stack.centerYAnchor.constraint(equalTo: selectionToolbar.centerYAnchor),
            stack.trailingAnchor.constraint(equalTo: selectionToolbar.trailingAnchor, constant: -20),

            selectionToolbar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            selectionToolbar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            selectionToolbar.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),
            selectionToolbar.heightAnchor.constraint(equalToConstant: 56),
        ])
    }

    private func makeToolbarButton(icon: UIImage?, action: Selector) -> UIButton {
        let btn = UIButton(type: .system)
        btn.setImage(icon, for: .normal)
        btn.tintColor = .label
        btn.addTarget(self, action: action, for: .touchUpInside)
        btn.widthAnchor.constraint(equalToConstant: 44).isActive = true
        btn.heightAnchor.constraint(equalToConstant: 44).isActive = true
        return btn
    }

    // MARK: - Layout Update

    /// 创建指定列数的 FlowLayout
    private func makeLayout(columns: CGFloat) -> UICollectionViewFlowLayout {
        let newLayout = UICollectionViewFlowLayout()
        newLayout.minimumInteritemSpacing = 2
        newLayout.minimumLineSpacing = 2
        newLayout.sectionInset = UIEdgeInsets(top: 2, left: 2, bottom: 2, right: 2)
        let spacing = newLayout.minimumInteritemSpacing * (columns - 1) + newLayout.sectionInset.left + newLayout.sectionInset.right
        let availableWidth = view.bounds.width - spacing
        let itemWidth = floor(availableWidth / columns)
        newLayout.itemSize = CGSize(width: itemWidth, height: itemWidth)
        return newLayout
    }

    /// 手指不离开屏幕时即时切换 layout，利用 UICollectionView 原生 fade 过渡动效
    /// 效果: 两边不变 cell 原地不动，中间变动 cell 渐变刷新
    private func switchToLayout(columns: CGFloat) {
        guard !isLayoutTransitioning, columns != itemsPerRow else { return }
        isLayoutTransitioning = true

        let newLayout = makeLayout(columns: columns)
        itemsPerRow = columns
        layout = newLayout

        collectionView.setCollectionViewLayout(newLayout, animated: true) { [weak self] _ in
            self?.isLayoutTransitioning = false
        }
    }

    // MARK: - Selection UI

    /// 刷新右上角按钮文本（国际化 + 模式切换）
    private func refreshRightBarButton() {
        if isSelectionMode {
            let title = (selectedIndices.count == entries.count && entries.count > 0)
                ? OWLocalized("gallery.deselect_all")
                : OWLocalized("gallery.select_all")
            navigationItem.rightBarButtonItem = UIBarButtonItem(
                title: title,
                style: .plain,
                target: self,
                action: #selector(toggleSelectAll)
            )
        } else {
            navigationItem.rightBarButtonItem = UIBarButtonItem(
                title: OWLocalized("gallery.select"),
                style: .plain,
                target: self,
                action: #selector(toggleSelectionMode)
            )
        }
    }

    @objc private func languageDidChange() {
        title = OWLocalized("gallery.title")
        emptyLabel.text = OWLocalized("gallery.empty")
        refreshRightBarButton()
        if isSelectionMode {
            navigationItem.leftBarButtonItem = UIBarButtonItem(
                title: OWLocalized("common.cancel"),
                style: .plain,
                target: self,
                action: #selector(toggleSelectionMode)
            )
            updateSelectionToolbar()
        }
        collectionView.reloadData()
    }

    private func updateUIForSelectionMode() {
        if isSelectionMode {
            navigationItem.title = nil
            navigationItem.leftBarButtonItem = UIBarButtonItem(
                title: OWLocalized("common.cancel"),
                style: .plain,
                target: self,
                action: #selector(toggleSelectionMode)
            )
            updateSelectionToolbar()
            refreshRightBarButton()
            selectionToolbar.isHidden = false
            // 隐藏系统 tabBar，避免与底部工具栏冲突
            tabBarController?.tabBar.isHidden = true
            collectionView.verticalScrollIndicatorInsets.bottom = 56
            // 刷新所有可见 cell 进入选择模式
            collectionView.visibleCells.compactMap { $0 as? MediaThumbnailCell }.forEach {
                $0.isSelectionMode = true
                $0.setSelected(false, animated: true)
            }
        } else {
            navigationItem.title = OWLocalized("gallery.title")
            navigationItem.leftBarButtonItem = nil
            refreshRightBarButton()
            selectedIndices.removeAll()
            selectionToolbar.isHidden = true
            tabBarController?.tabBar.isHidden = false
            collectionView.verticalScrollIndicatorInsets.bottom = 0
            collectionView.indexPathsForSelectedItems?.forEach {
                collectionView.deselectItem(at: $0, animated: false)
            }
            collectionView.visibleCells.compactMap { $0 as? MediaThumbnailCell }.forEach {
                $0.isSelectionMode = false
                $0.setSelected(false, animated: false)
            }
        }
    }

    private func updateSelectionToolbar() {
        let count = selectedIndices.count
        selectionCountLabel.text = String(format: OWLocalized("gallery.items_count"), count)
        refreshRightBarButton()
    }

    // MARK: - Data

    private func reloadData() {
        entries = MediaStorageManager.shared.entries
        collectionView.reloadData()
        emptyLabel.isHidden = !entries.isEmpty
        if isSelectionMode {
            restoreSelectionState()
        }
    }

    private func restoreSelectionState() {
        for index in selectedIndices where index < entries.count {
            let indexPath = IndexPath(item: index, section: 0)
            collectionView.selectItem(at: indexPath, animated: false, scrollPosition: [])
        }
        updateSelectionToolbar()
    }

    // MARK: - Pinch to Zoom (模拟系统相册: setCollectionViewLayout 原生 fade 过渡)

    @objc private func handlePinch(_ gesture: UIPinchGestureRecognizer) {
        guard !isSelectionMode else { return }

        switch gesture.state {
        case .began:
            pinchAccumulatedScale = 1.0
            lastPinchScale = 1.0
            isLayoutTransitioning = false

        case .changed:
            // 逐帧 delta，不受 gesture.scale 绝对值限制（手指不离开可无限累积）
            let delta = gesture.scale / lastPinchScale
            lastPinchScale = gesture.scale
            pinchAccumulatedScale *= delta

            if pinchAccumulatedScale > 1.0 + pinchLayoutThreshold {
                // 扩张 → 放大 → 减少列数
                let newColumns: CGFloat
                switch itemsPerRow {
                case 5: newColumns = 3
                case 3: newColumns = 1
                default: newColumns = 1
                }
                if newColumns != itemsPerRow {
                    switchToLayout(columns: newColumns)
                    pinchAccumulatedScale = 1.0
                }
            } else if pinchAccumulatedScale < 1.0 - pinchLayoutThreshold {
                // 收拢 → 缩小 → 增加列数
                let newColumns: CGFloat
                switch itemsPerRow {
                case 1: newColumns = 3
                case 3: newColumns = 5
                default: newColumns = 5
                }
                if newColumns != itemsPerRow {
                    switchToLayout(columns: newColumns)
                    pinchAccumulatedScale = 1.0
                }
            }

        case .ended, .cancelled:
            break

        default:
            break
        }
    }

    // MARK: - Selection Mode Actions

    @objc private func toggleSelectionMode() {
        isSelectionMode.toggle()
    }

    @objc private func toggleSelectAll() {
        if selectedIndices.count == entries.count {
            // 取消全选
            selectedIndices.removeAll()
            for i in 0..<entries.count {
                let ip = IndexPath(item: i, section: 0)
                collectionView.deselectItem(at: ip, animated: false)
            }
            collectionView.visibleCells.compactMap { $0 as? MediaThumbnailCell }.forEach {
                $0.setSelected(false, animated: true)
            }
        } else {
            // 全选
            selectedIndices = Set(0..<entries.count)
            for i in 0..<entries.count {
                let ip = IndexPath(item: i, section: 0)
                collectionView.selectItem(at: ip, animated: false, scrollPosition: [])
            }
            collectionView.visibleCells.compactMap { $0 as? MediaThumbnailCell }.forEach {
                $0.setSelected(true, animated: true)
            }
        }
        updateSelectionToolbar()
    }

    @objc private func saveSelectedToAlbum() {
        let entriesToSave = selectedIndices.compactMap { entries.indices.contains($0) ? entries[$0] : nil }
        guard !entriesToSave.isEmpty else { return }

        PHPhotoLibrary.requestAuthorization(for: .addOnly) { [weak self] status in
            DispatchQueue.main.async {
                guard let self = self, status == .authorized || status == .limited else { return }
                for entry in entriesToSave {
                    let url = MediaStorageManager.shared.originalURL(for: entry)
                    if entry.type == .photo, let data = try? Data(contentsOf: url), let image = UIImage(data: data) {
                        AlbumExporter.savePhotoToAlbum(image: image) { _, _ in }
                    } else if entry.type == .video {
                        AlbumExporter.saveVideoToAlbum(url: url) { _, _ in }
                    }
                }
                self.showAlert(message: "\(OWLocalized("gallery.export_photo")) \(entriesToSave.count) items")
            }
        }
    }

    @objc private func shareSelected() {
        let urls = selectedIndices.compactMap { index -> URL? in
            guard entries.indices.contains(index) else { return nil }
            return MediaStorageManager.shared.originalURL(for: entries[index])
        }
        guard !urls.isEmpty else { return }
        let activityVC = UIActivityViewController(activityItems: urls, applicationActivities: nil)
        activityVC.popoverPresentationController?.sourceView = view
        present(activityVC, animated: true)
    }

    @objc private func deleteSelected() {
        let count = selectedIndices.count
        let message = String(format: OWLocalized("gallery.delete_selected_confirm"), count)
        let alert = UIAlertController(title: OWLocalized("gallery.delete_selected"), message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: OWLocalized("common.cancel"), style: .cancel))
        alert.addAction(UIAlertAction(title: OWLocalized("common.confirm"), style: .destructive) { [weak self] _ in
            guard let self = self else { return }
            let entriesToDelete = self.selectedIndices.compactMap {
                self.entries.indices.contains($0) ? self.entries[$0] : nil
            }
            MediaStorageManager.shared.deleteMediaBatch(entriesToDelete)
            self.isSelectionMode = false
            self.reloadData()
        })
        present(alert, animated: true)
    }

    private func showAlert(message: String) {
        let alert = UIAlertController(title: nil, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: OWLocalized("common.ok"), style: .default))
        present(alert, animated: true)
    }
}

// MARK: - UICollectionViewDelegate, UICollectionViewDataSource

extension MediaPreviewViewController: UICollectionViewDelegate, UICollectionViewDataSource {

    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        entries.count
    }

    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: "thumb", for: indexPath) as! MediaThumbnailCell
        let entry = entries[indexPath.item]
        let thumbURL = MediaStorageManager.shared.thumbnailURL(for: entry)
        cell.configure(imageURL: thumbURL, type: entry.type)
        cell.isSelectionMode = isSelectionMode
        cell.setSelected(selectedIndices.contains(indexPath.item), animated: false)
        return cell
    }

    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        if isSelectionMode {
            selectedIndices.insert(indexPath.item)
            updateSelectionToolbar()
            if let cell = collectionView.cellForItem(at: indexPath) as? MediaThumbnailCell {
                cell.setSelected(true, animated: true)
            }
        } else {
            collectionView.deselectItem(at: indexPath, animated: false)
            let entry = entries[indexPath.item]
            showDetail(for: entry)
        }
    }

    func collectionView(_ collectionView: UICollectionView, didDeselectItemAt indexPath: IndexPath) {
        if isSelectionMode {
            selectedIndices.remove(indexPath.item)
            updateSelectionToolbar()
            if let cell = collectionView.cellForItem(at: indexPath) as? MediaThumbnailCell {
                cell.setSelected(false, animated: true)
            }
        }
    }

    private func showDetail(for entry: MediaEntry) {
        let sortedEntries = MediaStorageManager.shared.entries
        let detailVC: MediaDetailViewController
        if let index = sortedEntries.firstIndex(where: { $0.id == entry.id }) {
            detailVC = MediaDetailViewController(entries: sortedEntries, initialIndex: index)
        } else {
            detailVC = MediaDetailViewController(entry: entry)
        }
        detailVC.hidesBottomBarWhenPushed = true
        navigationController?.pushViewController(detailVC, animated: true)
    }
}

// MARK: - UIGestureRecognizerDelegate

extension MediaPreviewViewController: UIGestureRecognizerDelegate {
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                           shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        return true
    }
}

// MARK: - Cell

final class MediaThumbnailCell: UICollectionViewCell {

    private let imageView = UIImageView()
    private let typeBadge = UIImageView()
    private let selectionOverlay = UIView()
    private let checkmarkView = UIImageView()

    var isSelectionMode = false

    override init(frame: CGRect) {
        super.init(frame: frame)

        imageView.contentMode = .scaleAspectFill
        imageView.clipsToBounds = true
        contentView.addSubview(imageView)
        imageView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            imageView.topAnchor.constraint(equalTo: contentView.topAnchor),
            imageView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            imageView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            imageView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor)
        ])

        // 选择模式叠加层 - 覆盖整个 cell 提供半透明蒙版
        selectionOverlay.backgroundColor = UIColor.black.withAlphaComponent(0.35)
        selectionOverlay.isHidden = true
        selectionOverlay.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(selectionOverlay)
        NSLayoutConstraint.activate([
            selectionOverlay.topAnchor.constraint(equalTo: contentView.topAnchor),
            selectionOverlay.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            selectionOverlay.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            selectionOverlay.bottomAnchor.constraint(equalTo: contentView.bottomAnchor)
        ])

        // 勾选图标 - 右上角，白色圆形底 + 蓝色对勾
        checkmarkView.image = UIImage(systemName: "checkmark.circle.fill",
                                      withConfiguration: UIImage.SymbolConfiguration(pointSize: 28, weight: .bold))
        checkmarkView.tintColor = .systemBlue
        checkmarkView.backgroundColor = .white
        checkmarkView.layer.cornerRadius = 14
        checkmarkView.clipsToBounds = true
        checkmarkView.isHidden = true
        checkmarkView.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(checkmarkView)
        NSLayoutConstraint.activate([
            checkmarkView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 8),
            checkmarkView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -8),
            checkmarkView.widthAnchor.constraint(equalToConstant: 28),
            checkmarkView.heightAnchor.constraint(equalToConstant: 28)
        ])

        // 视频/照片标记置于叠加层之上
        typeBadge.tintColor = .white
        contentView.addSubview(typeBadge)
        typeBadge.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            typeBadge.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 4),
            typeBadge.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -4),
            typeBadge.widthAnchor.constraint(equalToConstant: 16),
            typeBadge.heightAnchor.constraint(equalToConstant: 16)
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        imageView.image = nil
        imageView.transform = .identity
        selectionOverlay.isHidden = true
        checkmarkView.isHidden = true
        selectionOverlay.backgroundColor = UIColor.black.withAlphaComponent(0.35)
    }

    func configure(imageURL: URL, type: MediaType) {
        if let data = try? Data(contentsOf: imageURL) {
            imageView.image = UIImage(data: data)
        } else {
            imageView.image = nil
        }
        typeBadge.image = type == .video
            ? UIImage(systemName: "video.fill")
            : UIImage(systemName: "photo.fill")
    }

    func setSelected(_ selected: Bool, animated: Bool) {
        let changes = {
            if self.isSelectionMode {
                self.selectionOverlay.isHidden = false
                self.selectionOverlay.backgroundColor = selected
                    ? UIColor.systemBlue.withAlphaComponent(0.35)
                    : UIColor.black.withAlphaComponent(0.22)
                self.checkmarkView.isHidden = !selected
                self.imageView.transform = selected ? CGAffineTransform(scaleX: 0.88, y: 0.88) : .identity
            } else {
                self.selectionOverlay.isHidden = true
                self.checkmarkView.isHidden = true
                self.imageView.transform = .identity
            }
        }
        if animated {
            UIView.animate(withDuration: 0.25, delay: 0, usingSpringWithDamping: 0.8, initialSpringVelocity: 0, options: [.curveEaseOut], animations: changes)
        } else {
            changes()
        }
    }
}
