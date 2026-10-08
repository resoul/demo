//
//  LiquidIslandViewController.swift
//  demoApp
//

import UIKit

/// Демо-экран Liquid Island: светлый фон, системный Dynamic Island сверху и чёрная капля, которую можно тянуть к острову
final class LiquidIslandViewController: UIViewController {

    private let islandView = LiquidIslandView()
    private let debugPanel = LiquidIslandDebugPanel()
    private let hintLabel = UILabel()
    private let debugButton = UIButton(type: .system)
    private let refreshButton = UIButton(type: .system)

    override func viewDidLoad() {
        super.viewDidLoad()
        // Фон и капля всегда светлые: в тёмной теме эффект выглядел бы иначе, чем на референсе
        overrideUserInterfaceStyle = .light
        view.backgroundColor = UIColor(white: 0.97, alpha: 1)

        setupIslandView()
        setupHint()
        setupDebugPanel()
        setupDebugButton()
        setupRefreshButton()

        islandView.configuration = debugPanel.configuration
    }

    // MARK: - Настройка

    private func setupIslandView() {
        islandView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(islandView)
        NSLayoutConstraint.activate([
            islandView.topAnchor.constraint(equalTo: view.topAnchor),
            islandView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            islandView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            islandView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
        ])
    }

    private func setupHint() {
        hintLabel.text = "Перетащите каплю к острову"
        hintLabel.font = .systemFont(ofSize: 14, weight: .medium)
        hintLabel.textColor = .secondaryLabel
        hintLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(hintLabel)
        NSLayoutConstraint.activate([
            hintLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            hintLabel.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 80),
        ])
    }

    private func setupDebugPanel() {
        debugPanel.translatesAutoresizingMaskIntoConstraints = false
        debugPanel.isHidden = true
        debugPanel.onChange = { [weak self] configuration in
            self?.islandView.configuration = configuration
        }
        view.addSubview(debugPanel)
        NSLayoutConstraint.activate([
            debugPanel.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 16),
            debugPanel.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -16),
            debugPanel.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -16),
        ])
    }

    private func setupDebugButton() {
        var configuration = UIButton.Configuration.tinted()
        configuration.image = UIImage(systemName: "slider.horizontal.3")
        configuration.cornerStyle = .capsule
        debugButton.configuration = configuration
        debugButton.translatesAutoresizingMaskIntoConstraints = false
        debugButton.addAction(UIAction { [weak self] _ in
            self?.toggleDebugPanel()
        }, for: .touchUpInside)
        view.addSubview(debugButton)
        NSLayoutConstraint.activate([
            debugButton.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -16),
            debugButton.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 8),
        ])
    }

    /// Вход на демо pull-to-refresh с той же каплей
    private func setupRefreshButton() {
        var configuration = UIButton.Configuration.tinted()
        configuration.title = "Refresh"
        configuration.cornerStyle = .capsule
        refreshButton.configuration = configuration
        refreshButton.translatesAutoresizingMaskIntoConstraints = false
        refreshButton.addAction(UIAction { [weak self] _ in
            let refresh = LiquidRefreshViewController()
            refresh.modalPresentationStyle = .fullScreen
            self?.present(refresh, animated: true)
        }, for: .touchUpInside)
        view.addSubview(refreshButton)
        NSLayoutConstraint.activate([
            refreshButton.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 16),
            refreshButton.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 8),
        ])
    }

    private func toggleDebugPanel() {
        let willShow = debugPanel.isHidden
        if willShow {
            debugPanel.isHidden = false
            debugPanel.alpha = 0
        }
        UIView.animate(withDuration: 0.25) {
            self.debugPanel.alpha = willShow ? 1 : 0
        } completion: { _ in
            self.debugPanel.isHidden = !willShow
        }
    }
}
