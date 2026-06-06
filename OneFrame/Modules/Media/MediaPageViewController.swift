//
//  MediaPageViewController.swift
//  OneFrame
//
//  单页媒体预览 - 支持捏合/双击缩放，图片填充显示
//

import UIKit
import AVKit

final class MediaPageViewController: UIViewController {

    // MARK: - Properties

    private let entry: MediaEntry
    private let scrollView = UIScrollView()
    private let imageView = UIImageView()

    /// PageViewController 内部 ScrollView 的 pan 手势，用于动态判断手势优先级
    weak var externalPanGesture: UIPanGestureRecognizer?

    // MARK: - Init

    init(entry: MediaEntry) {
        self.entry = entry
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        loadMedia()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        updateImageViewFrame()
    }

    // MARK: - Setup

    private func setupUI() {
        view.backgroundColor = .black
        view.clipsToBounds = true

        // ScrollView 支持缩放
        scrollView.delegate = self
        scrollView.minimumZoomScale = 1.0
        scrollView.maximumZoomScale = 5.0
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.showsVerticalScrollIndicator = false
        scrollView.contentInsetAdjustmentBehavior = .never
        scrollView.bouncesZoom = true
        scrollView.bounces = false
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scrollView)
        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])

        // 强制立即布局，确保 scrollView.bounds 为正确的屏幕尺寸
        view.layoutIfNeeded()

        // ImageView - 使用 .scaleAspectFit 显示完整图片，手动计算 frame 避免裁切
        imageView.contentMode = .scaleAspectFit
        imageView.clipsToBounds = true
        imageView.isUserInteractionEnabled = true
        scrollView.addSubview(imageView)

        // 双击缩放
        let doubleTap = UITapGestureRecognizer(target: self, action: #selector(handleDoubleTap(_:)))
        doubleTap.numberOfTapsRequired = 2
        scrollView.addGestureRecognizer(doubleTap)

        // 视频播放按钮
        if entry.type == .video {
            let playButton = UIButton(type: .system)
            playButton.setImage(UIImage(systemName: "play.circle.fill",
                                        withConfiguration: UIImage.SymbolConfiguration(pointSize: 56, weight: .regular)),
                               for: .normal)
            playButton.tintColor = .white
            playButton.alpha = 0.85
            playButton.addTarget(self, action: #selector(playVideo), for: .touchUpInside)
            view.addSubview(playButton)
            playButton.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                playButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),
                playButton.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            ])
        }
    }

    private func updateImageViewFrame() {
        // 仅在未缩放时更新 frame；缩放中由 scrollView 自行管理 contentSize
        guard scrollView.zoomScale <= scrollView.minimumZoomScale else { return }
        recalculateImageFrame()
    }

    /// 根据图片实际宽高比计算 imageView frame，在 scrollView 中 aspect-fit 居中显示
    private func recalculateImageFrame() {
        guard let image = imageView.image, image.size.width > 0, image.size.height > 0 else {
            imageView.frame = CGRect(origin: .zero, size: scrollView.bounds.size)
            scrollView.contentSize = scrollView.bounds.size
            return
        }

        let viewSize = scrollView.bounds.size
        let imageRatio = image.size.width / image.size.height
        let viewRatio = viewSize.width / viewSize.height

        let fitSize: CGSize
        if imageRatio > viewRatio {
            fitSize = CGSize(width: viewSize.width, height: viewSize.width / imageRatio)
        } else {
            fitSize = CGSize(width: viewSize.height * imageRatio, height: viewSize.height)
        }

        imageView.frame = CGRect(origin: .zero, size: fitSize)
        scrollView.contentSize = fitSize
        centerContent()
    }

    private func loadMedia() {
        let url = MediaStorageManager.shared.originalURL(for: entry)

        if entry.type == .photo {
            if let data = try? Data(contentsOf: url) {
                imageView.image = UIImage(data: data)
                recalculateImageFrame()
            }
        } else {
            let thumbURL = MediaStorageManager.shared.thumbnailURL(for: entry)
            if let data = try? Data(contentsOf: thumbURL) {
                imageView.image = UIImage(data: data)
                recalculateImageFrame()
            }
        }
    }

    // MARK: - Actions

    @objc private func handleDoubleTap(_ gesture: UITapGestureRecognizer) {
        if scrollView.zoomScale > scrollView.minimumZoomScale {
            scrollView.setZoomScale(scrollView.minimumZoomScale, animated: true)
        } else {
            let touchPoint = gesture.location(in: imageView)
            let zoomRect = CGRect(
                x: touchPoint.x - 50,
                y: touchPoint.y - 50,
                width: 100,
                height: 100
            )
            scrollView.zoom(to: zoomRect, animated: true)
        }
    }

    func resetZoom() {
        scrollView.setZoomScale(scrollView.minimumZoomScale, animated: false)
    }

    @objc private func playVideo() {
        let url = MediaStorageManager.shared.originalURL(for: entry)
        let player = AVPlayer(url: url)
        let vc = AVPlayerViewController()
        vc.player = player
        present(vc, animated: true) {
            player.play()
        }
    }
}

// MARK: - UIScrollViewDelegate

extension MediaPageViewController: UIScrollViewDelegate {
    func viewForZooming(in scrollView: UIScrollView) -> UIView? {
        return imageView
    }

    func scrollViewDidZoom(_ scrollView: UIScrollView) {
        centerContent()
        // 放大时禁用翻页手势，未放大时恢复
        externalPanGesture?.isEnabled = scrollView.zoomScale <= scrollView.minimumZoomScale
    }

    private func centerContent() {
        let offsetX = max((scrollView.bounds.width - scrollView.contentSize.width) * 0.5, 0)
        let offsetY = max((scrollView.bounds.height - scrollView.contentSize.height) * 0.5, 0)
        scrollView.contentInset = UIEdgeInsets(top: offsetY, left: offsetX, bottom: offsetY, right: offsetX)
    }
}
