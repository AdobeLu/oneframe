//
//  MediaPreviewViewController.swift
//  OneFrame
//
//  相册预览页面
//

import UIKit

final class MediaPreviewViewController: UIViewController {

    // MARK: - UI

    private let collectionView: UICollectionView
    private let emptyLabel = UILabel()

    // MARK: - Data

    private var entries: [MediaEntry] = []

    // MARK: - Init

    init() {
        let layout = UICollectionViewFlowLayout()
        layout.minimumInteritemSpacing = 2
        layout.minimumLineSpacing = 2
        layout.sectionInset = UIEdgeInsets(top: 2, left: 2, bottom: 2, right: 2)

        let itemsPerRow: CGFloat = 3
        let spacing = layout.minimumInteritemSpacing * (itemsPerRow - 1) + layout.sectionInset.left + layout.sectionInset.right
        let itemWidth = (UIScreen.main.bounds.width - spacing) / itemsPerRow
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

        collectionView.backgroundColor = .systemBackground
        collectionView.delegate = self
        collectionView.dataSource = self
        collectionView.register(MediaThumbnailCell.self, forCellWithReuseIdentifier: "thumb")
        view.addSubview(collectionView)
        collectionView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            collectionView.topAnchor.constraint(equalTo: view.topAnchor),
            collectionView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            collectionView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            collectionView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])

        // 空状态
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

    private func reloadData() {
        entries = MediaStorageManager.shared.entries
        collectionView.reloadData()
        emptyLabel.isHidden = !entries.isEmpty
    }

    // MARK: - Actions

    private func showDetail(for entry: MediaEntry) {
        // 按创建时间降序排列（与 entries 一致），确保滑动顺序正确
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
        return cell
    }

    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        let entry = entries[indexPath.item]
        showDetail(for: entry)
    }
}

// MARK: - Cell

final class MediaThumbnailCell: UICollectionViewCell {

    private let imageView = UIImageView()
    private let typeBadge = UIImageView()

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

        // 类型角标
        typeBadge.tintColor = .white
        contentView.addSubview(typeBadge)
        typeBadge.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            typeBadge.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -4),
            typeBadge.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -4),
            typeBadge.widthAnchor.constraint(equalToConstant: 16),
            typeBadge.heightAnchor.constraint(equalToConstant: 16)
        ])
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
}
