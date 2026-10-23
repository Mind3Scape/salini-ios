import UIKit

/// Editorial additions never alter the canonical 305 product identities or saved executions.
enum CatalogAtelier {
  // Official /new/ checked 23.10.2026: only these three say «Запущено».
  // Cartella is announced as «В разработке» and is deliberately excluded.
  static let launchedIDs = ["30897", "32698", "30919"]
  static let quickColours = ["1015", "3012", "3015", "6021", "6034", "5014", "7016"]
  struct Copy: Decodable { let text: String; let sourceURL: String; let sourceDate: String }
  static let descriptions: [String: Copy] = {
    guard let url = Bundle.main.url(forResource: "catalog-descriptions", withExtension: "json"),
          let bytes = try? Data(contentsOf: url),
          let copy = try? JSONDecoder().decode([String: Copy].self, from: bytes) else { return [:] }
    return copy
  }()
}

/// Actual tappable circles; the complete existing RAL menu remains available alongside them.
final class ProductColourOrbs: UIView {
  private var buttons: [(LineColour, UIButton)] = []
  init(change: @escaping (LineColour) -> Void) {
    super.init(frame: .zero)
    let scroll = UIScrollView()
    scroll.showsHorizontalScrollIndicator = false
    let row = UIStackView()
    row.axis = .horizontal
    row.spacing = 7
    let choices: [LineColour] = [.standard] + CatalogAtelier.quickColours.map(LineColour.ral)
    for choice in choices {
      let button = UIButton(type: .custom)
      button.widthAnchor.constraint(equalToConstant: 48).isActive = true
      button.heightAnchor.constraint(equalToConstant: 48).isActive = true
      button.layer.cornerRadius = 24
      button.layer.borderWidth = 1.5
      let dot = UIView()
      dot.isUserInteractionEnabled = false
      dot.backgroundColor = choice == .standard ? UIColor(hex: 0xF1F0EA) : choice.displayColour
      dot.layer.cornerRadius = 16
      dot.layer.borderWidth = 0.5
      dot.layer.borderColor = UIColor.black.withAlphaComponent(0.15).cgColor
      dot.translatesAutoresizingMaskIntoConstraints = false
      button.addSubview(dot)
      NSLayoutConstraint.activate([dot.widthAnchor.constraint(equalToConstant: 32),dot.heightAnchor.constraint(equalToConstant: 32),dot.centerXAnchor.constraint(equalTo: button.centerXAnchor),dot.centerYAnchor.constraint(equalTo: button.centerYAnchor)])
      button.accessibilityLabel = choice.longTitle
      button.accessibilityIdentifier = "product.swatch.\(choice == .standard ? "standard" : choice.title)"
      button.addAction(UIAction { _ in change(choice); UISelectionFeedbackGenerator().selectionChanged() }, for: .touchUpInside)
      buttons.append((choice,button));row.addArrangedSubview(button)
    }
    scroll.translatesAutoresizingMaskIntoConstraints = false
    row.translatesAutoresizingMaskIntoConstraints = false
    addSubview(scroll);scroll.addSubview(row)
    NSLayoutConstraint.activate([
      scroll.topAnchor.constraint(equalTo: topAnchor),scroll.bottomAnchor.constraint(equalTo: bottomAnchor),
      scroll.leadingAnchor.constraint(equalTo: leadingAnchor),scroll.trailingAnchor.constraint(equalTo: trailingAnchor),
      scroll.heightAnchor.constraint(equalToConstant: 56),
      row.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor,constant: 4),
      row.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor,constant: -4),
      row.leadingAnchor.constraint(equalTo: scroll.contentLayoutGuide.leadingAnchor),
      row.trailingAnchor.constraint(equalTo: scroll.contentLayoutGuide.trailingAnchor),
    ])
  }
  required init?(coder: NSCoder) { fatalError() }
  func update(selected: LineColour, allowsRAL: Bool) {
    for (colour,button) in buttons {
      let isSelected = colour == selected
      button.layer.borderColor = (isSelected ? SaliniBrand.accent : .clear).cgColor
      button.accessibilityTraits = isSelected ? [.button,.selected] : .button
      button.isEnabled = colour == .standard || allowsRAL
      button.alpha = button.isEnabled ? 1 : 0.3
      button.accessibilityValue = isSelected ? "Выбран" : nil
    }
  }
}
