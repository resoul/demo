//
//  ViewController.swift
//  controller
//
//  Created by resoul on 21.10.2026.
//

import UIKit

/// Demo: pick an effect, then push or present a screen with it.
/// Swipe from the left edge of the opened screen to go back interactively.
class ViewController: UIViewController, UITableViewDataSource, UITableViewDelegate, UIGestureRecognizerDelegate {

    // Strong reference: `navigationController.delegate` and `transitioningDelegate` are weak.
    private let transitions = MetalTransitionDelegate()
    private let tableView = UITableView(frame: .zero, style: .insetGrouped)
    private let modeControl = UISegmentedControl(items: ["Push", "Present"])
    private var lastTouch: CGPoint?
    private let sections = MetalTransitionEffect.Category.allCases.map { category in
        (category, MetalTransitionEffect.allCases.filter { $0.category == category })
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Metal Transitions"
        navigationController?.delegate = transitions
        // The system back swipes can't drive a custom animator; MetalInteractiveTransition replaces them.
        navigationController?.interactivePopGestureRecognizer?.isEnabled = false
        navigationController?.interactiveContentPopGestureRecognizer?.isEnabled = false
        MetalTransitionRenderer.shared?.prewarm()

        modeControl.selectedSegmentIndex = 0
        navigationItem.rightBarButtonItem = UIBarButtonItem(customView: modeControl)
        navigationItem.leftBarButtonItems = [
            UIBarButtonItem(title: "VFX", primaryAction: UIAction { [weak self] _ in
                self?.navigationController?.pushViewController(VFXDemoMenuViewController(), animated: true)
            }),
            UIBarButtonItem(title: "Login", primaryAction: UIAction { [weak self] _ in
                self?.navigationController?.pushViewController(MascotLoginViewController(), animated: true)
            }),
        ]

        tableView.dataSource = self
        tableView.delegate = self
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "cell")
        tableView.frame = view.bounds
        tableView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(tableView)

        // Remember where the finger lands so ripple / zoom / portal / burn start from it.
        let touchTracker = UILongPressGestureRecognizer(target: self, action: #selector(trackTouch(_:)))
        touchTracker.minimumPressDuration = 0
        touchTracker.cancelsTouchesInView = false
        touchTracker.delegate = self
        tableView.addGestureRecognizer(touchTracker)
    }

    @objc private func trackTouch(_ gesture: UILongPressGestureRecognizer) {
        if gesture.state == .began {
            lastTouch = gesture.location(in: nil)
        }
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                           shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
        true
    }

    private func open(_ effect: MetalTransitionEffect) {
        transitions.effect = effect
        transitions.touchPoint = lastTouch
        let detail = TransitionDemoViewController(effect: effect, transitions: transitions)

        if modeControl.selectedSegmentIndex == 0 {
            navigationController?.pushViewController(detail, animated: true)
        } else {
            detail.modalPresentationStyle = .fullScreen
            detail.transitioningDelegate = transitions
            present(detail, animated: true)
        }
    }

    // MARK: UITableViewDataSource / UITableViewDelegate

    func numberOfSections(in tableView: UITableView) -> Int {
        sections.count
    }

    func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        sections[section].0.rawValue
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        sections[section].1.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "cell", for: indexPath)
        let effect = sections[indexPath.section].1[indexPath.row]
        var content = cell.defaultContentConfiguration()
        content.text = effect.title
        content.secondaryText = String(format: "%.2f s", effect.defaultDuration)
        content.image = UIImage(systemName: effect.symbolName)
        content.imageProperties.tintColor = effect.color
        cell.contentConfiguration = content
        cell.accessoryType = .disclosureIndicator
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: false)
        open(sections[indexPath.section].1[indexPath.row])
    }
}

/// Colorful destination screen, so the effects have something to chew on.
final class TransitionDemoViewController: UIViewController {
    private let effect: MetalTransitionEffect
    private let transitions: MetalTransitionDelegate
    private let gradient = CAGradientLayer()

    init(effect: MetalTransitionEffect, transitions: MetalTransitionDelegate) {
        self.effect = effect
        self.transitions = transitions
        super.init(nibName: nil, bundle: nil)
        title = effect.title
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        gradient.colors = [effect.color.cgColor, UIColor.black.cgColor]
        gradient.startPoint = CGPoint(x: 0, y: 0)
        gradient.endPoint = CGPoint(x: 1, y: 1)
        view.layer.addSublayer(gradient)

        let symbol = UIImageView(image: UIImage(systemName: effect.symbolName))
        symbol.tintColor = .white
        symbol.contentMode = .scaleAspectFit
        symbol.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 120, weight: .bold)

        let titleLabel = UILabel()
        titleLabel.text = effect.title
        titleLabel.font = .systemFont(ofSize: 34, weight: .heavy)
        titleLabel.textColor = .white
        titleLabel.textAlignment = .center
        titleLabel.numberOfLines = 0

        let hint = UILabel()
        hint.text = "\(effect.category.rawValue)\nSwipe from the left edge to go back"
        hint.font = .preferredFont(forTextStyle: .subheadline)
        hint.textColor = UIColor.white.withAlphaComponent(0.75)
        hint.textAlignment = .center
        hint.numberOfLines = 0

        let stack = UIStackView(arrangedSubviews: [symbol, titleLabel, hint])
        stack.axis = .vertical
        stack.spacing = 20
        stack.alignment = .center
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.centerYAnchor.constraint(equalTo: view.safeAreaLayoutGuide.centerYAnchor),
            stack.leadingAnchor.constraint(equalTo: view.layoutMarginsGuide.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: view.layoutMarginsGuide.trailingAnchor),
        ])

        if navigationController == nil {
            var config = UIButton.Configuration.filled()
            config.title = "Close"
            config.cornerStyle = .capsule
            config.baseBackgroundColor = UIColor.white.withAlphaComponent(0.25)
            let close = UIButton(configuration: config, primaryAction: UIAction { [weak self] action in
                guard let self, let button = action.sender as? UIView else { return }
                self.transitions.touchPoint = button.convert(CGPoint(x: button.bounds.midX, y: button.bounds.midY), to: nil)
                self.dismiss(animated: true)
            })
            close.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(close)
            NSLayoutConstraint.activate([
                close.centerXAnchor.constraint(equalTo: view.centerXAnchor),
                close.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -24),
            ])
        }

        transitions.interaction.attach(to: view)
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        // The interaction controller is shared, so point it at whichever screen is on top.
        transitions.interaction.onBegan = { [weak self] point in
            guard let self else { return }
            self.transitions.touchPoint = point
            if let navigationController = self.navigationController {
                navigationController.popViewController(animated: true)
            } else {
                self.dismiss(animated: true)
            }
        }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        gradient.frame = view.bounds
    }
}

private extension MetalTransitionEffect {
    var symbolName: String {
        switch self {
        case .rippleDissolve: "drop.fill"
        case .vortex: "tornado"
        case .pageCurl: "book.pages.fill"
        case .noiseDissolve: "flame.fill"
        case .pixelate: "square.grid.3x3.fill"
        case .glitch: "tv.fill"
        case .zoomBlur: "scope"
        case .chromaticPortal: "circle.hexagongrid.fill"
        }
    }

    var color: UIColor {
        let index = MetalTransitionEffect.allCases.firstIndex(of: self) ?? 0
        return UIColor(hue: CGFloat(index) / CGFloat(MetalTransitionEffect.allCases.count),
                       saturation: 0.75, brightness: 0.85, alpha: 1)
    }
}
