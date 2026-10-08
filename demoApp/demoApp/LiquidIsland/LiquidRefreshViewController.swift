//
//  LiquidRefreshViewController.swift
//  demoApp
//

import UIKit

/// Демо pull-to-refresh: список с карточкой. При оттягивании капля висит у верхнего края, падает на карточку и обтекает её
final class LiquidRefreshViewController: UIViewController, UIScrollViewDelegate {

    private let scrollView = UIScrollView()
    private let card = UIView()
    private let cardTitle = UILabel()
    private let cardSubtitle = UILabel()
    private let hintLabel = UILabel()
    private let overlay = LiquidRefreshOverlayView()
    private let closeButton = UIButton(type: .system)

    /// Карточка лежит ниже подсказки; капля висит в зазоре между краем экрана и карточкой
    private let cardTop: CGFloat = 140
    private let cardHeight: CGFloat = 300
    private var isRefreshing = false

    override func viewDidLoad() {
        super.viewDidLoad()
        overrideUserInterfaceStyle = .light
        view.backgroundColor = UIColor(white: 0.97, alpha: 1)

        setupScrollView()
        setupCard()
        setupOverlay()
        setupCloseButton()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        let width = view.bounds.width

        scrollView.contentSize = CGSize(width: width, height: view.bounds.height + 200)
        hintLabel.frame = CGRect(x: 0, y: 84, width: width, height: 20)
        card.frame = CGRect(x: 16, y: cardTop, width: width - 32, height: cardHeight)
        card.layer.shadowPath = UIBezierPath(roundedRect: card.bounds, cornerRadius: LiquidRefreshOverlayView.cardCornerRadius).cgPath
        cardTitle.frame = CGRect(x: 20, y: 24, width: card.bounds.width - 40, height: 28)
        cardSubtitle.frame = CGRect(x: 20, y: 58, width: card.bounds.width - 40, height: 20)

        syncOverlay()
    }

    // MARK: - Настройка

    private func setupScrollView() {
        scrollView.contentInsetAdjustmentBehavior = .never
        scrollView.alwaysBounceVertical = true
        scrollView.showsVerticalScrollIndicator = false
        scrollView.delegate = self
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scrollView)
        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
        ])

        hintLabel.text = "Потяните вниз, чтобы обновить"
        hintLabel.font = .systemFont(ofSize: 14, weight: .medium)
        hintLabel.textColor = .secondaryLabel
        hintLabel.textAlignment = .center
        scrollView.addSubview(hintLabel)
    }

    private func setupCard() {
        card.backgroundColor = .white
        card.layer.cornerRadius = LiquidRefreshOverlayView.cardCornerRadius
        card.layer.shadowColor = UIColor.black.cgColor
        card.layer.shadowOpacity = 0.08
        card.layer.shadowRadius = 14
        card.layer.shadowOffset = CGSize(width: 0, height: 6)

        cardTitle.text = "Bergen"
        cardTitle.font = .systemFont(ofSize: 22, weight: .bold)
        cardTitle.textColor = .black
        cardSubtitle.text = "Fjord Bridge · Norway"
        cardSubtitle.font = .systemFont(ofSize: 14, weight: .regular)
        cardSubtitle.textColor = .secondaryLabel

        card.addSubview(cardTitle)
        card.addSubview(cardSubtitle)
        scrollView.addSubview(card)
    }

    private func setupOverlay() {
        overlay.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(overlay)
        NSLayoutConstraint.activate([
            overlay.topAnchor.constraint(equalTo: view.topAnchor),
            overlay.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            overlay.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            overlay.trailingAnchor.constraint(equalTo: view.trailingAnchor),
        ])
        overlay.onFinished = { [weak self] in
            self?.finishRefresh()
        }
    }

    private func setupCloseButton() {
        var configuration = UIButton.Configuration.tinted()
        configuration.image = UIImage(systemName: "xmark")
        configuration.cornerStyle = .capsule
        closeButton.configuration = configuration
        closeButton.translatesAutoresizingMaskIntoConstraints = false
        closeButton.addAction(UIAction { [weak self] _ in
            self?.dismiss(animated: true)
        }, for: .touchUpInside)
        view.addSubview(closeButton)
        NSLayoutConstraint.activate([
            closeButton.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 16),
            closeButton.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 8),
        ])
    }

    // MARK: - Синхронизация со списком

    /// Передаёт оверлею сдвиг списка и текущее положение карточки на экране
    private func syncOverlay() {
        // Во время обновления список держится на inset, поэтому сдвиг пересчитываем от inset
        overlay.pullDistance = max(0, -(scrollView.contentOffset.y + scrollView.contentInset.top))
        overlay.cardRect = view.convert(card.bounds, from: card)
    }

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        syncOverlay()
    }

    func scrollViewWillEndDragging(
        _ scrollView: UIScrollView,
        withVelocity velocity: CGPoint,
        targetContentOffset: UnsafeMutablePointer<CGPoint>
    ) {
        let pull = max(0, -scrollView.contentOffset.y)
        guard !isRefreshing, pull >= LiquidRefreshOverlayView.triggerDistance else { return }

        isRefreshing = true
        // Список остаётся оттянутым: без отскока и инерции карточка держит место, пока капля её обтекает
        targetContentOffset.pointee = scrollView.contentOffset
        scrollView.contentInset.top = pull
        scrollView.isScrollEnabled = false
        overlay.beginRelease()
    }

    /// Обновление окончено: список возвращается наверх
    private func finishRefresh() {
        UIView.animate(withDuration: 0.4, delay: 0, usingSpringWithDamping: 0.85, initialSpringVelocity: 0) {
            self.scrollView.contentInset.top = 0
            self.scrollView.contentOffset = .zero
        } completion: { _ in
            self.scrollView.isScrollEnabled = true
            self.isRefreshing = false
            self.syncOverlay()
        }
    }
}
