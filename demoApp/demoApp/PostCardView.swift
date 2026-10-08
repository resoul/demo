//
//  PostCardView.swift
//  demoApp
//

import UIKit

/// Данные поста для ленты
struct FeedPost {
    let tags: [String]
    let author: String
    let title: String
    let body: String
    let totalReactions: Int
    let reactionCounts: [ReactionType: Int]
    let comments: Int
    let discussing: Int
}

/// Карточка поста. Долгое нажатие на пилюлю реакций отдаёт жест наружу (`onReactionGesture`),
/// а дугу рисует контроллер: она должна лежать поверх всей ленты
final class PostCardView: UIView {

    var onReactionGesture: ((UILongPressGestureRecognizer, PostCardView) -> Void)?

    private(set) var reactionCounts: [ReactionType: Int]
    private var totalReactions: Int
    /// Реакция, которую поставил пользователь на этом посте
    private var userReaction: ReactionType?

    let reactionPill = UIView()
    private let pillIcons = UIStackView()
    private let pillCount = UILabel()

    private let reactedTint = UIColor.systemRed
    /// Размер кружка из дуги: такой же у летящей иконки
    private let flyingDiameter: CGFloat = 36

    init(post: FeedPost) {
        reactionCounts = post.reactionCounts
        totalReactions = post.totalReactions
        super.init(frame: .zero)
        setup(post)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setup(_ post: FeedPost) {
        backgroundColor = .systemBackground
        layer.cornerRadius = 16

        let tagRow = UIStackView(arrangedSubviews: post.tags.map { makeChip($0) } + [makeSpacer()])
        tagRow.spacing = 6

        let avatar = UIView()
        avatar.backgroundColor = .systemIndigo
        avatar.layer.cornerRadius = 12
        avatar.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            avatar.widthAnchor.constraint(equalToConstant: 24),
            avatar.heightAnchor.constraint(equalToConstant: 24),
        ])
        let authorLabel = makeLabel(post.author, font: .systemFont(ofSize: 13, weight: .semibold), color: .secondaryLabel)
        let authorRow = UIStackView(arrangedSubviews: [avatar, authorLabel, makeSpacer()])
        authorRow.spacing = 8
        authorRow.alignment = .center

        let titleLabel = makeLabel(post.title, font: .systemFont(ofSize: 17, weight: .bold), color: .label)
        let bodyLabel = makeLabel(post.body, font: .systemFont(ofSize: 14), color: .secondaryLabel)
        bodyLabel.numberOfLines = 3

        setupPill()
        let commentsLabel = makeLabel("\(post.comments) comments", font: .systemFont(ofSize: 13), color: .secondaryLabel)
        let footerRow = UIStackView(arrangedSubviews: [reactionPill, makeSpacer(), commentsLabel])
        footerRow.alignment = .center

        let divider = UIView()
        divider.backgroundColor = .separator
        divider.translatesAutoresizingMaskIntoConstraints = false
        divider.heightAnchor.constraint(equalToConstant: 1).isActive = true

        let flame = UIImageView(image: UIImage(systemName: "flame.fill"))
        flame.tintColor = .systemPink
        let discussingLabel = makeLabel("\(post.discussing) people are discussing this", font: .systemFont(ofSize: 13), color: .secondaryLabel)
        let discussingRow = UIStackView(arrangedSubviews: [flame, discussingLabel, makeSpacer()])
        discussingRow.spacing = 6
        discussingRow.alignment = .center

        let stack = UIStackView(arrangedSubviews: [tagRow, authorRow, titleLabel, bodyLabel, footerRow, divider, discussingRow])
        stack.axis = .vertical
        stack.alignment = .fill
        stack.spacing = 10
        stack.setCustomSpacing(14, after: footerRow)
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: topAnchor, constant: 14),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -14),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14),
        ])
    }

    private func setupPill() {
        reactionPill.layer.cornerRadius = 14
        reactionPill.layer.borderWidth = 1
        reactionPill.translatesAutoresizingMaskIntoConstraints = false

        pillIcons.spacing = 4
        pillCount.font = .monospacedDigitSystemFont(ofSize: 13, weight: .medium)
        let content = UIStackView(arrangedSubviews: [pillIcons, pillCount])
        content.spacing = 6
        content.alignment = .center
        content.translatesAutoresizingMaskIntoConstraints = false
        reactionPill.addSubview(content)
        NSLayoutConstraint.activate([
            content.topAnchor.constraint(equalTo: reactionPill.topAnchor, constant: 4),
            content.bottomAnchor.constraint(equalTo: reactionPill.bottomAnchor, constant: -4),
            content.leadingAnchor.constraint(equalTo: reactionPill.leadingAnchor, constant: 8),
            content.trailingAnchor.constraint(equalTo: reactionPill.trailingAnchor, constant: -10),
        ])

        let press = UILongPressGestureRecognizer(target: self, action: #selector(handleLongPress(_:)))
        press.minimumPressDuration = 0.3
        // Палец может уехать с пилюли по дуге, жест при этом не должен отмениться
        press.allowableMovement = 1000
        reactionPill.addGestureRecognizer(press)

        // Короткое нажатие на уже поставленную реакцию её снимает
        let tap = UITapGestureRecognizer(target: self, action: #selector(handleTap))
        reactionPill.addGestureRecognizer(tap)

        refreshPill()
    }

    /// Три самые популярные реакции и реакция пользователя слева, справа общий счётчик
    private func refreshPill() {
        pillIcons.arrangedSubviews.forEach { $0.removeFromSuperview() }
        var shown = reactionCounts.sorted { $0.value > $1.value }.prefix(3).map { $0.key }
        if let userReaction, !shown.contains(userReaction) {
            shown.append(userReaction)
        }
        for reaction in shown {
            let icon = UIImageView(
                image: UIImage(systemName: reaction.symbolName, withConfiguration: UIImage.SymbolConfiguration(pointSize: 11, weight: .medium))
            )
            pillIcons.addArrangedSubview(icon)
        }

        let tint: UIColor = userReaction == nil ? .label : reactedTint
        reactionPill.layer.borderColor = tint.cgColor
        reactionPill.backgroundColor = userReaction == nil ? .clear : reactedTint.withAlphaComponent(0.12)
        pillCount.text = "\(totalReactions)"
        pillCount.textColor = tint
        pillIcons.arrangedSubviews.forEach { $0.tintColor = tint }
    }

    @objc private func handleLongPress(_ gesture: UILongPressGestureRecognizer) {
        onReactionGesture?(gesture, self)
    }

    @objc private func handleTap() {
        removeReaction()
    }

    /// Снимает реакцию пользователя: счётчик -1, пилюля возвращается к обычному виду
    func removeReaction() {
        guard let previous = userReaction else { return }
        reactionCounts[previous, default: 0] -= 1
        totalReactions -= 1
        userReaction = nil
        refreshPill()
        showCountChange("−1")
    }

    // MARK: - Публичное

    /// Ставит реакцию: иконка выбранного кружка летит из `origin` (координаты карточки) в пилюлю,
    /// затем пилюля дрожит, счётчик прокручивается и появляется «+1»
    func react(with reaction: ReactionType, from origin: CGPoint) {
        let flying = reaction.makeBadge(diameter: flyingDiameter)
        flying.transform = CGAffineTransform(scaleX: 1.25, y: 1.25)
        flying.center = origin
        addSubview(flying)

        let target = reactionPill.convert(CGPoint(x: reactionPill.bounds.midX, y: reactionPill.bounds.midY), to: self)
        UIView.animate(withDuration: 0.2, delay: 0, options: [.curveEaseIn], animations: {
            flying.center = target
            flying.transform = CGAffineTransform(scaleX: 0.4, y: 0.4)
            flying.alpha = 0.3
        }, completion: { _ in
            flying.removeFromSuperview()
            self.applyReaction(reaction)
        })
    }

    /// Пересчитывает счётчики и показывает результат в пилюле
    private func applyReaction(_ reaction: ReactionType) {
        if let previous = userReaction {
            reactionCounts[previous, default: 0] -= 1
        } else {
            totalReactions += 1
        }
        reactionCounts[reaction, default: 0] += 1
        userReaction = reaction
        refreshPill()
        wobblePill()
        rollCount()
        showCountChange("+1")
    }

    /// Затухающее покачивание пилюли, как будто иконка её толкнула
    private func wobblePill() {
        let wobble = CAKeyframeAnimation(keyPath: "transform.rotation.z")
        wobble.values = [0, -0.14, 0.11, -0.07, 0.04, 0]
        wobble.keyTimes = [0, 0.2, 0.4, 0.6, 0.8, 1]
        wobble.duration = 0.5
        reactionPill.layer.add(wobble, forKey: "wobble")
    }

    /// Новое число въезжает снизу
    private func rollCount() {
        pillCount.transform = CGAffineTransform(translationX: 0, y: 8)
        pillCount.alpha = 0
        UIView.animate(withDuration: 0.25, delay: 0, options: [.curveEaseOut], animations: {
            self.pillCount.transform = .identity
            self.pillCount.alpha = 1
        })
    }

    // MARK: - Вспомогательное

    /// «+1» или «−1» над пилюлей: появляется, держится около секунды и гаснет
    private func showCountChange(_ text: String) {
        let label = UILabel()
        label.text = text
        label.font = .systemFont(ofSize: 12, weight: .semibold)
        label.textColor = text == "+1" ? reactedTint : .secondaryLabel
        label.sizeToFit()

        let pill = reactionPill.convert(reactionPill.bounds, to: self)
        label.center = CGPoint(x: pill.midX, y: pill.minY - 10)
        label.alpha = 0
        addSubview(label)

        UIView.animate(withDuration: 0.15, animations: {
            label.alpha = 1
        }, completion: { _ in
            UIView.animate(
                withDuration: 0.4,
                delay: 0.3,
                options: [.curveEaseIn],
                animations: {
                    label.alpha = 0
                    label.center.y -= 6
                },
                completion: { _ in label.removeFromSuperview() }
            )
        })
    }

    private func makeLabel(_ text: String, font: UIFont, color: UIColor) -> UILabel {
        let label = UILabel()
        label.text = text
        label.font = font
        label.textColor = color
        label.numberOfLines = 0
        return label
    }

    private func makeChip(_ text: String) -> UIView {
        let label = makeLabel(text, font: .systemFont(ofSize: 12, weight: .medium), color: .secondaryLabel)
        label.numberOfLines = 1

        let chip = UIView()
        chip.layer.cornerRadius = 12
        chip.layer.borderWidth = 1
        chip.layer.borderColor = UIColor.separator.cgColor
        label.translatesAutoresizingMaskIntoConstraints = false
        chip.addSubview(label)
        NSLayoutConstraint.activate([
            label.topAnchor.constraint(equalTo: chip.topAnchor, constant: 4),
            label.bottomAnchor.constraint(equalTo: chip.bottomAnchor, constant: -4),
            label.leadingAnchor.constraint(equalTo: chip.leadingAnchor, constant: 10),
            label.trailingAnchor.constraint(equalTo: chip.trailingAnchor, constant: -10),
        ])
        return chip
    }

    /// Пустой элемент, который забирает лишнее место и прижимает содержимое к левому краю
    private func makeSpacer() -> UIView {
        let spacer = UIView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        return spacer
    }
}
