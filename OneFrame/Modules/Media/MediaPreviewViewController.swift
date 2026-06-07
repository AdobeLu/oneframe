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

    // MARK: - Layout (Transform 缩放 + 捏合中跨阈值瞬时切换，模拟系统相册)

    private let layout = UICollectionViewFlowLayout()

    /// 当前整数列数（布局基于此构建，捏合跨阈值时实时更新）
    private var itemsPerRow: CGFloat = 3

    /// 相对于当前布局的缩放系数。1.0 = 视觉与布局一致
    /// 跨阈值切换后会重新校准此值以保持视觉连续
    private var relativeScale: CGFloat = 1.0

    // MARK: - Pinch Gesture State

    /// 用于逐帧计算 delta 的上一帧 gesture.scale 快照
    private var lastGestureScale: CGFloat = 1.0
    private var lastPinchVelocity: CGFloat = 0
    private var lastPinchTime: CFTimeInterval = 0

    // MARK: - Init

    init() {
        layout.minimumInteritemSpacing = 2
        layout.minimumLineSpacing = 2
        layout.sectionInset = UIEdgeInsets(top: 2, left: 2, bottom: 2, right: 2)

        let spacing = layout.minimumInteritemSpacing * (3 - 1) + layout.sectionInset.left + layout.sectionInset.right
        let itemWidth = (UIScreen.main.bounds.width - spacing) / 3
        layout.itemSize = CGSize(width: itemWidth, height: itemWidth)

        collectionView = UICollectionView(frame: .zero, collectionViewLayout: layout)
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
        reloadData()
    }

    // MARK: - Setup

    private func setupUI() {
        view.backgroundColor = .systemBackground
        title = OWLocalized("gallery.title")

        navigationItem.rightBarButtonItem = UIBarButtonItem(
            title: OWLocalized("gallery.select"),
            style: .plain,
            target: self,
            action: #selector(toggleSelectionMode)
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
            selectionCountLabel.centerXAnchor.constraint(equalTo: selectionToolbar.centerXAnchor),

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

    /// 按整数列数更新 cell 尺寸
    private func updateItemSize(for columns: CGFloat) {
        let spacing = layout.minimumInteritemSpacing * (columns - 1) + layout.sectionInset.left + layout.sectionInset.right
        let availableWidth = view.bounds.width - spacing
        let itemWidth = floor(availableWidth / columns)
        layout.itemSize = CGSize(width: itemWidth, height: itemWidth)
        layout.invalidateLayout()
    }

    /// 捏合中跨奇数列阈值时，瞬时切换布局 + 补偿 transform。
    /// 不引入额外动画 —— 手势已按 60fps 驱动 transform，跨阈值瞬间
    /// relativeScale 精确补偿使视觉尺寸完全不变，下一帧手势继续更新即可。
    private func performLayoutTransition(to newColumns: CGFloat) {
        let oldColumns = itemsPerRow
        let visualColumnsBefore = oldColumns / relativeScale

        itemsPerRow = newColumns
        relativeScale = newColumns / visualColumnsBefore

        updateItemSize(for: newColumns)
        // 强制 layout 立即算出新 contentSize，否则下面 clamp 拿到的是旧值
        collectionView.layoutIfNeeded()

        // 列数变化（尤其 1→3、1→5）时 contentSize 可能骤降，
        // contentOffset 若不修正会超出有效范围 → 可视区全是黑屏
        let bottomInset = collectionView.adjustedContentInset.bottom
        let topInset = collectionView.adjustedContentInset.top
        let maxOffsetY = collectionView.contentSize.height + bottomInset - collectionView.bounds.height
        let minOffsetY = -topInset
        var clampedOffset = collectionView.contentOffset
        if clampedOffset.y > maxOffsetY {
            clampedOffset.y = max(maxOffsetY, minOffsetY)
        }
        collectionView.contentOffset = clampedOffset

        collectionView.transform = CGAffineTransform(scaleX: relativeScale, y: relativeScale)
    }

    // MARK: - Pinch 边界阻尼

    /// 对视觉等效列数进行橡皮筋阻尼
    private func rubberBandColumns(_ columns: CGFloat) -> CGFloat {
        if columns < 1 {
            return 1 - (1 - exp(-(1 - columns) * 2.0)) * 0.5
        } else if columns > 5 {
            return 5 + (1 - exp(-(columns - 5) * 2.0)) * 0.5
        }
        return columns
    }

    /// 取视觉等效列数最近的奇数列（1/3/5），模拟系统相册。
    /// 捏合中使用激进阈值避免黑边：1→3 在 >1 时触发，3→5 在 >3 时触发。
    private func nearestOddColumn(from visualColumns: CGFloat) -> CGFloat {
        if visualColumns <= 1 { return 1 }
        if visualColumns > 3 { return 5 }
        return 3
    }

    /// 松手吸附用中间点判断（1↔3 中点=2，3↔5 中点=4）。
    /// 与捏合中的激进阈值分开，避免"已超过中间点，松手却被拉回原列数"。
    private func nearestOddColumnForSnap(from visualColumns: CGFloat) -> CGFloat {
        if visualColumns <= 2 { return 1 }
        if visualColumns <= 4 { return 3 }
        return 5
    }

    // MARK: - Selection UI

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
            selectionToolbar.isHidden = false
            collectionView.contentInset.bottom = 56
            collectionView.verticalScrollIndicatorInsets.bottom = 56
        } else {
            navigationItem.title = OWLocalized("gallery.title")
            navigationItem.leftBarButtonItem = nil
            navigationItem.rightBarButtonItem = UIBarButtonItem(
                title: OWLocalized("gallery.select"),
                style: .plain,
                target: self,
                action: #selector(toggleSelectionMode)
            )
            selectedIndices.removeAll()
            selectionToolbar.isHidden = true
            collectionView.contentInset.bottom = 0
            collectionView.verticalScrollIndicatorInsets.bottom = 0
            collectionView.indexPathsForSelectedItems?.forEach {
                collectionView.deselectItem(at: $0, animated: false)
            }
            collectionView.visibleCells.compactMap { $0 as? MediaThumbnailCell }.forEach {
                $0.setSelected(false, animated: false)
            }
        }
    }

    private func updateSelectionToolbar() {
        let count = selectedIndices.count
        selectionCountLabel.text = String(format: OWLocalized("gallery.items_count"), count)
        if count == entries.count && count > 0 {
            navigationItem.rightBarButtonItem = UIBarButtonItem(
                title: OWLocalized("gallery.deselect_all"),
                style: .plain,
                target: self,
                action: #selector(toggleSelectAll)
            )
        } else {
            navigationItem.rightBarButtonItem = UIBarButtonItem(
                title: OWLocalized("gallery.select_all"),
                style: .plain,
                target: self,
                action: #selector(toggleSelectAll)
            )
        }
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

    // MARK: - Pinch to Zoom (逐帧增量 + 跨阈值瞬时切换 + 松手弹簧归位)

    @objc private func handlePinch(_ gesture: UIPinchGestureRecognizer) {
        guard !isSelectionMode else { return }

        switch gesture.state {
        case .began:
            lastGestureScale = 1.0
            relativeScale = 1.0
            lastPinchVelocity = 0
            lastPinchTime = CACurrentMediaTime()

        case .changed:
            let now = CACurrentMediaTime()
            let dt = max(now - lastPinchTime, 0.001)
            lastPinchTime = now

            // 逐帧增量 delta，不受之前是否跨阈值的影响
            let delta = gesture.scale / lastGestureScale
            lastGestureScale = gesture.scale

            var newRelativeScale = relativeScale * delta

            let rawColumns = itemsPerRow / newRelativeScale
            let dampedColumns = rubberBandColumns(rawColumns)

            newRelativeScale = itemsPerRow / dampedColumns
            relativeScale = newRelativeScale

            // 记录视觉列数变化速度，用于松手预测
            lastPinchVelocity = (dampedColumns - rawColumns) / dt

            // 检测是否跨越奇数列阈值（1/3/5），瞬时切换布局 + 补偿 transform
            let targetColumns = nearestOddColumn(from: dampedColumns)
            if targetColumns != itemsPerRow {
                // 瞬时切换：3列缩小→5列放大，视觉完全连续无跳变
                performLayoutTransition(to: targetColumns)
            } else {
                // 未跨阈值，仅更新 transform
                collectionView.transform = CGAffineTransform(scaleX: relativeScale,
                                                              y: relativeScale)
            }

        case .ended, .cancelled:
            let visualColumns = itemsPerRow / relativeScale
            let projected = visualColumns + lastPinchVelocity * 0.06
            let targetColumns = nearestOddColumnForSnap(from: projected)
            let needsLayoutSwitch = targetColumns != itemsPerRow

            if needsLayoutSwitch {
                itemsPerRow = targetColumns
                updateItemSize(for: targetColumns)
            }

            UIView.animate(
                withDuration: 0.32,
                delay: 0,
                usingSpringWithDamping: 0.72,
                initialSpringVelocity: 0,
                options: [.curveEaseOut, .allowUserInteraction],
                animations: {
                    self.collectionView.transform = .identity
                    self.collectionView.layoutIfNeeded()
                },
                completion: { [weak self] _ in
                    self?.relativeScale = 1.0
                }
            )

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
            selectedIndices.removeAll()
            collectionView.indexPathsForSelectedItems?.forEach {
                collectionView.deselectItem(at: $0, animated: true)
            }
        } else {
            selectedIndices = Set(0..<entries.count)
            for i in 0..<entries.count {
                collectionView.selectItem(at: IndexPath(item: i, section: 0), animated: true, scrollPosition: [])
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
        guard let index = sortedEntries.firstIndex(where: { $0.id == entry.id }) else {
            let detailVC = MediaDetailViewController(entry: entry)
            navigationController?.pushViewController(detailVC, animated: true)
            return
        }
        let detailVC = MediaDetailViewController(entries: sortedEntries, initialIndex: index)
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

        typeBadge.tintColor = .white
        contentView.addSubview(typeBadge)
        typeBadge.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            typeBadge.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -4),
            typeBadge.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -4),
            typeBadge.widthAnchor.constraint(equalToConstant: 16),
            typeBadge.heightAnchor.constraint(equalToConstant: 16)
        ])

        selectionOverlay.isHidden = true
        selectionOverlay.backgroundColor = UIColor.black.withAlphaComponent(0.25)
        selectionOverlay.layer.cornerRadius = 16
        selectionOverlay.layer.borderWidth = 2
        selectionOverlay.layer.borderColor = UIColor.white.cgColor
        selectionOverlay.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(selectionOverlay)
        NSLayoutConstraint.activate([
            selectionOverlay.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 6),
            selectionOverlay.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -6),
            selectionOverlay.widthAnchor.constraint(equalToConstant: 28),
            selectionOverlay.heightAnchor.constraint(equalToConstant: 28)
        ])

        checkmarkView.image = UIImage(systemName: "checkmark.circle.fill",
                                      withConfiguration: UIImage.SymbolConfiguration(pointSize: 28, weight: .medium))
        checkmarkView.tintColor = .systemBlue
        checkmarkView.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(checkmarkView)
        NSLayoutConstraint.activate([
            checkmarkView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 4),
            checkmarkView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -4),
            checkmarkView.widthAnchor.constraint(equalToConstant: 28),
            checkmarkView.heightAnchor.constraint(equalToConstant: 28)
        ])
        checkmarkView.isHidden = true
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(imageURL: URL, type: MediaType) {
        if let data = try? Data(contentsOf: imageURL) {
            imageView.image = UIImage(data: data)
        }
        typeBadge.image = type == .video
            ? UIImage(systemName: "video.fill")
            : UIImage(systemName: "photo.fill")
    }

    func setSelected(_ selected: Bool, animated: Bool) {
        let changes = {
            self.selectionOverlay.isHidden = !self.isSelectionMode
            self.checkmarkView.isHidden = !selected || !self.isSelectionMode
            if selected && self.isSelectionMode {
                self.selectionOverlay.backgroundColor = UIColor.black.withAlphaComponent(0.45)
            } else if self.isSelectionMode {
                self.selectionOverlay.backgroundColor = UIColor.black.withAlphaComponent(0.15)
            }
        }
        if animated {
            UIView.animate(withDuration: 0.2, animations: changes)
        } else {
            changes()
        }
    }
}
