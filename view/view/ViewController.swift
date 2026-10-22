import UIKit

private enum LabStyle {
    static let background = UIColor(red: 0.039, green: 0.043, blue: 0.059, alpha: 1)
    static let panel = UIColor(red: 0.075, green: 0.082, blue: 0.102, alpha: 1)
    static let muted = UIColor(red: 0.53, green: 0.55, blue: 0.61, alpha: 1)
    static let accent = UIColor(red: 0.78, green: 0.93, blue: 0.63, alpha: 1)

    static func label(_ text: String, size: CGFloat, weight: UIFont.Weight = .regular,
                      color: UIColor = .white) -> UILabel {
        let label = UILabel()
        label.text = text
        label.font = UIFontMetrics(forTextStyle: .body).scaledFont(for: .systemFont(ofSize: size, weight: weight))
        label.adjustsFontForContentSizeCategory = true
        label.textColor = color
        label.numberOfLines = 0
        return label
    }
}

/// Hosts UIKit source content separately so Metal never snapshots itself.
private final class EffectTile: UIView {
    let surface: MetalEffectView
    private let source: UIView?
    private var capturedSize = CGSize.zero
    var sourceLayout: ((UIView) -> Void)?

    init(effect: MetalEffect, height: CGFloat, source: UIView? = nil) {
        surface = MetalEffectView(effect: effect)
        self.source = source
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        backgroundColor = LabStyle.panel
        layer.cornerRadius = 24
        layer.cornerCurve = .continuous
        clipsToBounds = true
        NotificationCenter.default.addObserver(self, selector: #selector(invalidateCapture),
                                               name: UIContentSizeCategory.didChangeNotification, object: nil)
        if let source { addSubview(source) }
        addSubview(surface)
        heightAnchor.constraint(equalToConstant: height).isActive = true
        if effect == .dissolve {
            let empty = LabStyle.label("Удалено. Нажмите «Восстановить» ниже.", size: 14, color: LabStyle.muted)
            empty.textAlignment = .center
            empty.translatesAutoresizingMaskIntoConstraints = false
            insertSubview(empty, belowSubview: surface)
            NSLayoutConstraint.activate([
                empty.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 24),
                empty.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -24),
                empty.centerYAnchor.constraint(equalTo: centerYAnchor)
            ])
        }
    }

    required init?(coder: NSCoder) { fatalError("Use init(effect:height:source:)") }

    @objc private func invalidateCapture() {
        capturedSize = .zero
        setNeedsLayout()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        surface.frame = bounds
        guard let source, capturedSize != bounds.size else { return }
        source.isHidden = false
        source.frame = bounds
        sourceLayout?(source)
        source.setNeedsLayout()
        if surface.capture(source) { capturedSize = bounds.size }
        source.isHidden = true
    }

    func overlay(_ view: UIView, alignment: NSLayoutConstraint.Attribute = .centerY,
                 inset: CGFloat = 26) {
        view.isUserInteractionEnabled = false
        view.translatesAutoresizingMaskIntoConstraints = false
        addSubview(view)
        let vertical: NSLayoutConstraint
        if alignment == .bottom {
            vertical = view.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -inset)
        } else if alignment == .top {
            vertical = view.topAnchor.constraint(equalTo: topAnchor, constant: inset)
        } else {
            vertical = view.centerYAnchor.constraint(equalTo: centerYAnchor)
        }
        NSLayoutConstraint.activate([
            view.leadingAnchor.constraint(equalTo: leadingAnchor, constant: inset),
            view.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -inset), vertical
        ])
    }
}

final class ViewController: UIViewController {
    private let scroll = UIScrollView()
    private let content = UIStackView()
    private let filterStack = UIStackView()
    private var sections: [(view: UIView, category: Int)] = []
    private var surfaces: [MetalEffectView] = []
    private var filters: [UIButton] = []
    private let pauseButton = UIButton(type: .system)
    private let valueLabel = LabStyle.label("75%", size: 12, weight: .medium, color: LabStyle.accent)
    private var selectedFilter = 0

    override var preferredStatusBarStyle: UIStatusBarStyle { .lightContent }

    override func viewDidLoad() {
        super.viewDidLoad()
        overrideUserInterfaceStyle = .dark
        view.backgroundColor = LabStyle.background
        configureLayout()
        buildHeader()
        buildEngineEntry()
        buildMascotEntry()
        buildFilters()
        buildEffects()
        let footer = LabStyle.label("СОЗДАНО ИЗ СВЕТА, КОДА И КАСАНИЙ\nUIKit + Metal · 7 экспериментов", size: 10,
                                    weight: .medium, color: LabStyle.muted)
        footer.textAlignment = .center
        footer.setContentCompressionResistancePriority(.required, for: .vertical)
        content.addArrangedSubview(footer)
    }

    private func configureLayout() {
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.alwaysBounceVertical = true
        scroll.showsVerticalScrollIndicator = false
        scroll.delaysContentTouches = false
        view.addSubview(scroll)
        content.axis = .vertical
        content.spacing = 30
        content.translatesAutoresizingMaskIntoConstraints = false
        scroll.addSubview(content)
        let controls = makeControls()
        controls.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(controls)
        NSLayoutConstraint.activate([
            controls.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 20),
            controls.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -20),
            controls.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -8),
            scroll.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scroll.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scroll.bottomAnchor.constraint(equalTo: controls.topAnchor, constant: -8),
            scroll.contentLayoutGuide.widthAnchor.constraint(equalTo: scroll.frameLayoutGuide.widthAnchor),
            content.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor, constant: 24),
            content.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor, constant: -30),
            content.centerXAnchor.constraint(equalTo: scroll.frameLayoutGuide.centerXAnchor),
            content.widthAnchor.constraint(equalTo: scroll.frameLayoutGuide.widthAnchor, constant: -40)
                .withPriority(.defaultHigh),
            content.widthAnchor.constraint(lessThanOrEqualToConstant: 680),
            content.leadingAnchor.constraint(greaterThanOrEqualTo: scroll.contentLayoutGuide.leadingAnchor, constant: 20),
            content.trailingAnchor.constraint(lessThanOrEqualTo: scroll.contentLayoutGuide.trailingAnchor, constant: -20)
        ])
    }

    private func buildHeader() {
        let brand = UIStackView()
        brand.alignment = .center
        let wordmark = LabStyle.label("◈  MATTER", size: 15, weight: .heavy)
        wordmark.accessibilityLabel = "Matter"
        brand.addArrangedSubview(wordmark)
        brand.addArrangedSubview(UIView())
        let live = LabStyle.label("●  METAL LAB", size: 10, weight: .semibold, color: LabStyle.accent)
        brand.addArrangedSubview(live)
        content.addArrangedSubview(brand)
        content.setCustomSpacing(34, after: brand)

        let heading = LabStyle.label("Интерфейс.\nС характером.", size: 40, weight: .semibold)
        heading.accessibilityTraits = .header
        content.addArrangedSubview(heading)
        content.setCustomSpacing(12, after: heading)
        let subtitle = LabStyle.label("Свет, фактура и движение. Семь способов\nпочувствовать обычный UIView по-новому.",
                                      size: 14, color: LabStyle.muted)
        content.addArrangedSubview(subtitle)
    }

    private func buildEngineEntry() {
        let button = UIButton(type: .system)
        var config = UIButton.Configuration.filled()
        config.title = "METAL ENGINE   ·   1M+ точек  ↗"
        config.baseBackgroundColor = LabStyle.panel
        config.baseForegroundColor = LabStyle.accent
        config.cornerStyle = .large
        config.contentInsets = NSDirectionalEdgeInsets(top: 18, leading: 16, bottom: 18, trailing: 16)
        button.configuration = config
        button.accessibilityIdentifier = "openMetalEngine"
        button.addAction(UIAction { [weak self] _ in
            self?.navigationController?.pushViewController(MetalEngineViewController(), animated: true)
        }, for: .touchUpInside)
        content.addArrangedSubview(button)
    }

    /// The login form with a Rive mascot (MascotLogin/, the only screen that uses RiveRuntime).
    private func buildMascotEntry() {
        let button = UIButton(type: .system)
        var config = UIButton.Configuration.filled()
        config.title = "LOGIN MASCOT   ·   Rive  ↗"
        config.baseBackgroundColor = LabStyle.panel
        config.baseForegroundColor = LabStyle.accent
        config.cornerStyle = .large
        config.contentInsets = NSDirectionalEdgeInsets(top: 18, leading: 16, bottom: 18, trailing: 16)
        button.configuration = config
        button.accessibilityIdentifier = "openMascotLogin"
        button.addAction(UIAction { [weak self] _ in
            self?.navigationController?.pushViewController(MascotLoginViewController(), animated: true)
        }, for: .touchUpInside)
        content.addArrangedSubview(button)
    }

    private func buildFilters() {
        let scroller = UIScrollView()
        scroller.showsHorizontalScrollIndicator = false
        filterStack.spacing = 8
        filterStack.distribution = .fillEqually
        filterStack.translatesAutoresizingMaskIntoConstraints = false
        scroller.addSubview(filterStack)
        NSLayoutConstraint.activate([
            filterStack.leadingAnchor.constraint(equalTo: scroller.contentLayoutGuide.leadingAnchor),
            filterStack.trailingAnchor.constraint(equalTo: scroller.contentLayoutGuide.trailingAnchor),
            filterStack.topAnchor.constraint(equalTo: scroller.contentLayoutGuide.topAnchor),
            filterStack.bottomAnchor.constraint(equalTo: scroller.contentLayoutGuide.bottomAnchor),
            filterStack.heightAnchor.constraint(equalTo: scroller.frameLayoutGuide.heightAnchor),
            filterStack.widthAnchor.constraint(equalTo: scroller.frameLayoutGuide.widthAnchor),
            scroller.heightAnchor.constraint(greaterThanOrEqualToConstant: 40)
        ])
        for (index, title) in ["Все", "Фоны", "Отклик", "Медиа"].enumerated() {
            let button = UIButton(type: .system)
            var config = UIButton.Configuration.filled()
            config.title = title
            config.cornerStyle = .capsule
            config.contentInsets = NSDirectionalEdgeInsets(top: 10, leading: 12, bottom: 10, trailing: 12)
            config.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { attributes in
                var result = attributes
                result.font = .systemFont(ofSize: 11, weight: .medium)
                return result
            }
            button.configuration = config
            button.tag = index
            button.addTarget(self, action: #selector(selectFilter(_:)), for: .touchUpInside)
            filters.append(button)
            filterStack.addArrangedSubview(button)
        }
        updateFilters()
        content.addArrangedSubview(scroller)
    }

    private func buildEffects() {
        let fluid = EffectTile(effect: .fluid, height: 245)
        let fluidCopy = UIStackView(arrangedSubviews: [
            LabStyle.label("БЕЗ ГРАНИЦ. БЕЗ ПОВТОРОВ.", size: 9, weight: .semibold, color: UIColor.white.withAlphaComponent(0.7)),
            LabStyle.label("Stay in the flow.", size: 29, weight: .medium)
        ])
        fluidCopy.axis = .vertical
        fluidCopy.spacing = 10
        fluid.overlay(fluidCopy, alignment: .bottom)
        fluid.overlay(LabStyle.label("◌   ЖИВАЯ ПОВЕРХНОСТЬ", size: 10, weight: .semibold), alignment: .top)
        addSection("01", title: "Fluid gradient", detail: "Цвет, который не стоит на месте.",
                   hint: "Проведите пальцем или наклоните устройство", category: 1, tile: fluid)

        let frostSource = makeFrostSource()
        let frost = EffectTile(effect: .frost, height: 220, source: frostSource)
        frost.sourceLayout = { source in
            source.layer.sublayers?.first?.frame = source.bounds
            for (index, orb) in source.subviews.enumerated() {
                let diameter: CGFloat = index == 0 ? 175 : 135
                orb.frame = CGRect(x: source.bounds.width * (index == 0 ? 0.06 : 0.58),
                                   y: index == 0 ? -35 : 100, width: diameter, height: diameter)
                orb.layer.cornerRadius = diameter / 2
            }
        }
        let frostCopy = UIStackView(arrangedSubviews: [
            LabStyle.label("◈", size: 24, weight: .medium),
            LabStyle.label("A little more clarity.", size: 19, weight: .medium),
            LabStyle.label("Меньше шума. Больше глубины.", size: 11, color: UIColor.white.withAlphaComponent(0.7))
        ])
        frostCopy.axis = .vertical
        frostCopy.alignment = .center
        frostCopy.spacing = 10
        frost.overlay(frostCopy)
        addSection("02", title: "Dynamic frost", detail: "Преломление, размытие и свет по краям.",
                   hint: "Двигайте пальцем по стеклу", category: 1, tile: frost)

        let aurora = EffectTile(effect: .aurora, height: 120)
        let auroraText = LabStyle.label("Открыть новые возможности   ↗", size: 16, weight: .semibold)
        auroraText.textAlignment = .center
        aurora.overlay(auroraText)
        aurora.surface.onActivate = { [weak auroraText, weak surface = aurora.surface] in
            let opened = surface?.accessibilityValue != "Доступ открыт"
            auroraText?.text = opened ? "Вы внутри. Добро пожаловать ✦" : "Открыть новые возможности   ↗"
            surface?.accessibilityValue = opened ? "Доступ открыт" : "Открыть возможности"
        }
        addSection("03", title: "Aurora border", detail: "Северное сияние на границе действия.",
                   hint: "Нажмите на светящийся контур", category: 2, tile: aurora)

        let pulse = EffectTile(effect: .pulse, height: 132)
        let pulseText = LabStyle.label("↯   Почувствуйте энергию", size: 18, weight: .semibold,
                                       color: UIColor(red: 0.72, green: 1, blue: 0.87, alpha: 1))
        pulseText.textAlignment = .center
        pulse.overlay(pulseText)
        addSection("04", title: "Touch energy", detail: "Каждое касание оставляет свой импульс.",
                   hint: "Нажмите в любой точке кнопки", category: 2, tile: pulse)

        let foil = EffectTile(effect: .foil, height: 225, source: makeFoilSource())
        addSection("05", title: "Holographic foil", detail: "Новый угол. Новый спектр.",
                   hint: "Наклоняйте устройство или двигайте пальцем", category: 3, tile: foil)

        let dissolve = EffectTile(effect: .dissolve, height: 180, source: makeDeleteSource())
        let action = UIButton(type: .system)
        action.setTitle("Удалить карточку  ↗", for: .normal)
        action.setTitleColor(UIColor(red: 0.99, green: 0.65, blue: 0.44, alpha: 1), for: .normal)
        action.titleLabel?.font = .systemFont(ofSize: 13, weight: .medium)
        action.contentHorizontalAlignment = .leading
        action.accessibilityIdentifier = "dissolveAction"
        action.addAction(UIAction { [weak dissolve, weak action] _ in
            guard let surface = dissolve?.surface else { return }
            if action?.isSelected == true {
                surface.restore()
                action?.isSelected = false
                action?.setTitle("Удалить карточку  ↗", for: .normal)
            } else { surface.activate() }
        }, for: .touchUpInside)
        dissolve.surface.onActivate = { [weak action] in
            action?.isSelected = true
            action?.setTitle("Восстановить карточку  ↺", for: .normal)
        }
        dissolve.surface.onDissolveComplete = {
            UIAccessibility.post(notification: .announcement, argument: "Карточка удалена. Можно восстановить.")
        }
        addSection("06", title: "Dissolve", detail: "Исчезнуть. И оставить впечатление.",
                   hint: "Коснитесь карточки, чтобы рассыпать её в пыль", category: 3, tile: dissolve, action: action)

        let glow = EffectTile(effect: .glow, height: 200, source: makeGlowSource())
        addSection("07", title: "Particle discharge", detail: "Типографика с собственной энергией.",
                   hint: "Коснитесь текста — выпустите искры", category: 2, tile: glow)
    }

    private func addSection(_ number: String, title: String, detail: String, hint: String,
                            category: Int, tile: EffectTile, action: UIButton? = nil) {
        let section = UIStackView()
        section.axis = .vertical
        section.spacing = 12
        let titleRow = UIStackView()
        titleRow.alignment = .firstBaseline
        titleRow.spacing = 10
        titleRow.addArrangedSubview(LabStyle.label(number, size: 10, weight: .medium, color: LabStyle.muted))
        let heading = LabStyle.label(title, size: 19, weight: .semibold)
        heading.accessibilityTraits = .header
        titleRow.addArrangedSubview(heading)
        titleRow.addArrangedSubview(UIView())
        section.addArrangedSubview(titleRow)
        section.addArrangedSubview(LabStyle.label(detail, size: 12, color: LabStyle.muted))
        section.addArrangedSubview(tile)
        let instruction = LabStyle.label("↳  " + hint, size: 11, color: LabStyle.muted)
        section.addArrangedSubview(instruction)
        if let action { section.addArrangedSubview(action) }
        tile.surface.accessibilityLabel = title
        tile.surface.accessibilityHint = hint
        tile.surface.accessibilityIdentifier = "effect" + number
        // Snapshot artwork and decorative overlays are represented by the surface's spoken label.
        for subview in tile.subviews where subview !== tile.surface { subview.accessibilityElementsHidden = true }
        surfaces.append(tile.surface)
        sections.append((section, category))
        content.addArrangedSubview(section)
    }

    private func makeControls() -> UIView {
        let panel = UIView()
        panel.backgroundColor = LabStyle.panel
        panel.layer.cornerRadius = 20
        panel.layer.borderColor = UIColor.white.withAlphaComponent(0.07).cgColor
        panel.layer.borderWidth = 1
        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = 6
        stack.translatesAutoresizingMaskIntoConstraints = false
        panel.addSubview(stack)
        let row = UIStackView()
        row.alignment = .center
        row.spacing = 12
        row.addArrangedSubview(LabStyle.label("ИНТЕНСИВНОСТЬ", size: 9, weight: .semibold, color: LabStyle.muted))
        row.addArrangedSubview(valueLabel)
        row.addArrangedSubview(UIView())
        pauseButton.tintColor = .white
        pauseButton.setImage(UIImage(systemName: "pause.fill"), for: .normal)
        pauseButton.accessibilityLabel = "Приостановить эффекты"
        pauseButton.accessibilityIdentifier = "pauseEffects"
        pauseButton.addTarget(self, action: #selector(togglePause), for: .touchUpInside)
        NSLayoutConstraint.activate([
            pauseButton.widthAnchor.constraint(equalToConstant: 44),
            pauseButton.heightAnchor.constraint(equalToConstant: 44)
        ])
        row.addArrangedSubview(pauseButton)
        let slider = UISlider()
        slider.minimumValue = 0
        slider.maximumValue = 1
        slider.value = 0.75
        slider.minimumTrackTintColor = LabStyle.accent
        slider.maximumTrackTintColor = UIColor.white.withAlphaComponent(0.1)
        slider.thumbTintColor = LabStyle.accent
        slider.accessibilityLabel = "Интенсивность эффектов"
        slider.accessibilityValue = "75 процентов"
        slider.accessibilityIdentifier = "effectIntensity"
        slider.addTarget(self, action: #selector(changeIntensity(_:)), for: .valueChanged)
        stack.addArrangedSubview(row)
        stack.addArrangedSubview(slider)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: panel.leadingAnchor, constant: 18),
            stack.trailingAnchor.constraint(equalTo: panel.trailingAnchor, constant: -18),
            stack.topAnchor.constraint(equalTo: panel.topAnchor, constant: 2),
            stack.bottomAnchor.constraint(equalTo: panel.bottomAnchor, constant: -12)
        ])
        return panel
    }

    @objc private func selectFilter(_ sender: UIButton) {
        selectedFilter = sender.tag
        updateFilters()
        for section in sections { section.view.isHidden = selectedFilter != 0 && selectedFilter != section.category }
    }

    private func updateFilters() {
        for button in filters {
            let selected = button.tag == selectedFilter
            button.configuration?.baseBackgroundColor = selected ? LabStyle.accent : LabStyle.panel
            button.configuration?.baseForegroundColor = selected ? LabStyle.background : LabStyle.muted
            button.accessibilityTraits = selected ? [.button, .selected] : [.button]
        }
    }

    @objc private func togglePause() {
        MetalEffectView.isPaused.toggle()
        let paused = MetalEffectView.isPaused
        pauseButton.setImage(UIImage(systemName: paused ? "play.fill" : "pause.fill"), for: .normal)
        pauseButton.accessibilityLabel = paused ? "Продолжить эффекты" : "Приостановить эффекты"
        pauseButton.tintColor = paused ? LabStyle.accent : .white
    }

    @objc private func changeIntensity(_ slider: UISlider) {
        surfaces.forEach { $0.intensity = slider.value }
        let percent = Int((slider.value * 100).rounded())
        valueLabel.text = "\(percent)%"
        slider.accessibilityValue = "\(percent) процентов"
    }

    private func makeFrostSource() -> UIView {
        let source = UIView()
        let gradient = CAGradientLayer()
        gradient.colors = [UIColor(red: 0.13, green: 0.16, blue: 0.44, alpha: 1).cgColor,
                           UIColor(red: 0.34, green: 0.20, blue: 0.44, alpha: 1).cgColor,
                           UIColor(red: 0.17, green: 0.35, blue: 0.43, alpha: 1).cgColor]
        gradient.startPoint = .zero
        gradient.endPoint = CGPoint(x: 1, y: 1)
        source.layer.addSublayer(gradient)
        for color in [UIColor(red: 0.95, green: 0.60, blue: 0.43, alpha: 1),
                      UIColor(red: 0.47, green: 0.47, blue: 0.96, alpha: 1)] {
            let orb = UIView()
            orb.backgroundColor = color
            source.addSubview(orb)
        }
        return source
    }

    private func makeFoilSource() -> UIView {
        let source = UIView()
        let mark = UIImageView(image: UIImage(systemName: "seal.fill"))
        mark.tintColor = UIColor.white.withAlphaComponent(0.85)
        mark.contentMode = .scaleAspectFit
        mark.translatesAutoresizingMaskIntoConstraints = false
        source.addSubview(mark)
        let symbol = UIImageView(image: UIImage(systemName: "sparkle"))
        symbol.tintColor = LabStyle.background
        symbol.contentMode = .scaleAspectFit
        symbol.translatesAutoresizingMaskIntoConstraints = false
        source.addSubview(symbol)
        let title = LabStyle.label("MEMBER OF THE UNEXPECTED", size: 10, weight: .bold)
        title.textAlignment = .center
        title.translatesAutoresizingMaskIntoConstraints = false
        source.addSubview(title)
        let serial = LabStyle.label("MATTER CLUB     /     № 0001", size: 9, weight: .medium,
                                    color: UIColor.white.withAlphaComponent(0.6))
        serial.translatesAutoresizingMaskIntoConstraints = false
        source.addSubview(serial)
        NSLayoutConstraint.activate([
            mark.widthAnchor.constraint(equalToConstant: 90), mark.heightAnchor.constraint(equalToConstant: 90),
            mark.centerXAnchor.constraint(equalTo: source.centerXAnchor),
            mark.centerYAnchor.constraint(equalTo: source.centerYAnchor, constant: -10),
            symbol.centerXAnchor.constraint(equalTo: mark.centerXAnchor),
            symbol.centerYAnchor.constraint(equalTo: mark.centerYAnchor),
            symbol.widthAnchor.constraint(equalToConstant: 38), symbol.heightAnchor.constraint(equalToConstant: 38),
            title.topAnchor.constraint(equalTo: mark.bottomAnchor, constant: 18),
            title.leadingAnchor.constraint(equalTo: source.leadingAnchor, constant: 16),
            title.trailingAnchor.constraint(equalTo: source.trailingAnchor, constant: -16),
            serial.topAnchor.constraint(equalTo: source.topAnchor, constant: 22),
            serial.leadingAnchor.constraint(equalTo: source.leadingAnchor, constant: 24)
        ])
        return source
    }

    private func makeDeleteSource() -> UIView {
        let source = UIView()
        source.backgroundColor = UIColor(red: 0.23, green: 0.16, blue: 0.13, alpha: 1)
        let copy = UIStackView(arrangedSubviews: [
            LabStyle.label("⌘   TEMPORARY THINGS", size: 10, weight: .semibold,
                           color: UIColor(red: 0.97, green: 0.68, blue: 0.47, alpha: 1)),
            LabStyle.label("Отпускайте красиво.", size: 24, weight: .medium),
            LabStyle.label("Даже у последнего кадра есть своя магия.", size: 11, color: LabStyle.muted)
        ])
        copy.axis = .vertical
        copy.spacing = 16
        copy.translatesAutoresizingMaskIntoConstraints = false
        source.addSubview(copy)
        NSLayoutConstraint.activate([
            copy.leadingAnchor.constraint(equalTo: source.leadingAnchor, constant: 25),
            copy.trailingAnchor.constraint(equalTo: source.trailingAnchor, constant: -25),
            copy.centerYAnchor.constraint(equalTo: source.centerYAnchor)
        ])
        return source
    }

    private func makeGlowSource() -> UIView {
        let source = UIView()
        let copy = UIStackView(arrangedSubviews: [
            LabStyle.label("✦", size: 36, weight: .light,
                           color: UIColor(red: 0.77, green: 0.64, blue: 1, alpha: 1)),
            LabStyle.label("Brilliant.", size: 36, weight: .semibold,
                           color: UIColor(red: 0.86, green: 0.79, blue: 1, alpha: 1))
        ])
        copy.axis = .vertical
        copy.alignment = .center
        copy.spacing = 8
        copy.translatesAutoresizingMaskIntoConstraints = false
        source.addSubview(copy)
        NSLayoutConstraint.activate([
            copy.centerXAnchor.constraint(equalTo: source.centerXAnchor),
            copy.centerYAnchor.constraint(equalTo: source.centerYAnchor),
            copy.widthAnchor.constraint(lessThanOrEqualTo: source.widthAnchor, constant: -40)
        ])
        return source
    }
}

private extension NSLayoutConstraint {
    func withPriority(_ priority: UILayoutPriority) -> NSLayoutConstraint {
        self.priority = priority
        return self
    }
}
