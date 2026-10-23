import UIKit

/// Home feature «Камень изнутри»: the two Salini materials as an illustrative mineral composition
/// — S-Stone a homogeneous mass, S-Sense a mineral core under a Gelcoat skin. Shared cutaway
/// covers introduce each material; an explicit action reveals the existing six-fragment
/// layered 2.5D study. Full 3D stays in the studio; the CTA opens it on a form that sells the
/// chosen finish. All generated illustrations remain labelled as illustrative.
///
/// Integration (Codex): `EssenceFeatureView(open:)` replaces `MaterialFeatureView` on Home; create
/// it with `active = false` and switch `active` while `animationBounds` is in the viewport. The
/// view also pauses itself off-window, in the background and with Reduce Motion. If the bundled
/// fragments are missing (never expected; covered by a test), the stage is omitted and the block
/// stays a quiet text + studio link.
final class EssenceFeatureView: UIView {
  private(set) var finish: StudioFinish = .stoneMatte
  /// The host's visibility: when false nothing animates and no frames are drawn.
  var active = true {
    didSet { updatePlaying() }
  }
  /// The layered stage, nil if its fragments are not in the bundle.
  private let stage: EssenceLayerStage? = {
    let layers = EssenceLayers.manifest()
    return EssenceLayers.available(layers) ? EssenceLayerStage(layers: layers) : nil
  }()
  /// Whether the illustration is shown (tests, diagnostics).
  var illustrated: Bool { stage != nil }
  /// The stage (with its reserved overflow margin) in this view's coordinates: the host turns
  /// `active` on only while this rect is in the viewport. `.zero` without a stage.
  var animationBounds: CGRect { stage.map { $0.convert($0.bounds, to: self) } ?? .zero }
  private var chips: [(StudioFinish, UIButton)] = []
  private var inspection: UIButton?
  private let caption = label("", 15, .regular, Palette.muted)
  private let open: (StudioForm?, StudioFinish) -> Void
  private var observers: [NSObjectProtocol] = []

  init(open: @escaping (StudioForm?, StudioFinish) -> Void) {
    self.open = open
    super.init(frame: .zero)
    let title = label("Камень изнутри.", 40, .regular, serif: true)
    let lead = label("Однородный S-Stone. Минеральное ядро под тонким слоем Gelcoat — S-Sense.", 16, .regular, Palette.muted)
    stage?.accessibilityIdentifier = "essence.stage"
    stage?.onSelect = { [weak self] f in self?.select(f) }
    if let stage, stage.canShowCover {
      var c = UIButton.Configuration.plain()
      c.baseForegroundColor = Palette.ink
      c.contentInsets = .init(top: 12, leading: 16, bottom: 12, trailing: 16)
      c.imagePadding = 8
      c.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { incoming in
        var a = incoming
        a.font = UIFontMetrics(forTextStyle: .subheadline).scaledFont(for: .systemFont(ofSize: 14, weight: .semibold))
        return a
      }
      let button = UIButton(configuration: c, primaryAction: UIAction { [weak stage] _ in
        guard let stage else { return }
        stage.setExpanded(!stage.isExpanded)
      })
      button.accessibilityIdentifier = "essence.inspect"
      inspection = button
      stage.onExpanded = { [weak self] _ in self?.updateInspection() }
      updateInspection()
    }
    let tabs = stack([], axis: .horizontal, spacing: 8)
    tabs.distribution = .fillEqually
    for f in StudioFinish.allCases {
      var c = UIButton.Configuration.filled()
      c.title = f == .stoneMatte ? "S-Stone" : "S-Sense"
      c.subtitle = f == .senseGloss ? "глянец" : "матовый"
      c.titleAlignment = .center
      c.titlePadding = 2
      c.cornerStyle = .capsule
      c.contentInsets = .init(top: 10, leading: 4, bottom: 10, trailing: 4)
      c.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { incoming in
        var a = incoming
        a.font = UIFontMetrics(forTextStyle: .footnote).scaledFont(for: .systemFont(ofSize: 13.5, weight: .semibold), maximumPointSize: 17)
        return a
      }
      c.subtitleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { incoming in
        var a = incoming
        a.font = UIFontMetrics(forTextStyle: .caption1).scaledFont(for: .systemFont(ofSize: 11.5, weight: .medium), maximumPointSize: 15)
        return a
      }
      let b = UIButton(configuration: c, primaryAction: UIAction { [weak self] _ in self?.select(f) })
      b.titleLabel?.adjustsFontSizeToFitWidth = true
      b.titleLabel?.minimumScaleFactor = 0.9
      b.titleLabel?.numberOfLines = 1
      b.titleLabel?.textAlignment = .center
      b.accessibilityIdentifier = "essence.\(f.rawValue)"
      b.accessibilityLabel = f.title
      chips.append((f, b))
      tabs.addArrangedSubview(b)
    }
    let note = label("Художественная визуализация состава. Форма и толщина слоёв условны.", 12, .regular, Palette.muted)
    let more = ActionButton("Студия материалов", icon: "arrow.up.right", prominent: true) { [weak self] in
      guard let self else { return }
      self.open(Self.form(for: self.finish), self.finish)
    }
    more.accessibilityIdentifier = "essence.explore"
    more.accessibilityHint = "Открывает студию: формы Salini, сравнение исполнений и цвет"
    let body = stack([eyebrow("МАТЕРИАЛЫ SALINI"), title, lead] + [stage, inspection].compactMap { $0 } + [tabs, caption, note, more],
                     spacing: 14)
    body.setCustomSpacing(4, after: lead)
    if let stage { body.setCustomSpacing(16, after: stage) }
    body.setCustomSpacing(18, after: note)
    pin(body)
    select(.stoneMatte, animated: false)
    let center = NotificationCenter.default
    observers.append(center.addObserver(forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main) {
      [weak self] _ in MainActor.assumeIsolated { self?.updatePlaying() }
    })
    // Resume on didBecomeActive: at willEnterForeground the state can still read .background.
    observers.append(center.addObserver(forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main) {
      [weak self] _ in MainActor.assumeIsolated { self?.updatePlaying() }
    })
    observers.append(center.addObserver(forName: UIAccessibility.reduceMotionStatusDidChangeNotification, object: nil, queue: .main) {
      [weak self] _ in MainActor.assumeIsolated { self?.updatePlaying() }
    })
  }
  required init?(coder: NSCoder) { fatalError() }
  deinit { observers.forEach(NotificationCenter.default.removeObserver) }

  private func updateInspection() {
    let expanded = stage?.isExpanded == true
    inspection?.configuration?.title = expanded ? "Вернуться к образцу" : "Разобрать слои"
    inspection?.configuration?.image = UIImage(systemName: expanded ? "arrow.uturn.backward" : "square.3.layers.3d")
    inspection?.accessibilityHint = expanded ? "Показывает цельную иллюстрацию выбранного материала" : "Показывает художественную схему состава материала"
  }

  /// A real form that sells the finish (Noemi first, as the studio's default).
  static func form(for finish: StudioFinish) -> StudioForm? {
    if let n = StudioForm.noemi, n.finishes.contains(finish) { return n }
    return StudioForm.all.first { $0.finishes.contains(finish) } ?? StudioForm.noemi
  }

  func select(_ f: StudioFinish, animated: Bool = true) {
    let changed = f != finish
    finish = f
    for (value, b) in chips {
      let on = value == f
      b.configuration?.baseBackgroundColor = on ? SaliniBrand.accent : .white
      b.configuration?.baseForegroundColor = on ? .white : Palette.ink
      b.accessibilityTraits = on ? [.button, .selected] : .button
    }
    caption.text = MaterialFacts.short(f)
    stage?.show(f, animated: animated && !UIAccessibility.isReduceMotionEnabled)
    if animated && changed { UISelectionFeedbackGenerator().selectionChanged() }
  }

  override func didMoveToWindow() {
    super.didMoveToWindow()
    updatePlaying()
  }
  private func updatePlaying() {
    let visible = active && window != nil && UIApplication.shared.applicationState != .background
    stage?.setRunning(visible)
  }
}

/// A small callout: a dot on the layer and a label beside it.
final class EssenceCallout: UIView {
  private let text: UILabel
  private let plate = UIView()
  private let dot = UIView()
  private let line = UIView()
  init(_ string: String) {
    text = label(string, 13, .semibold, Palette.ink)
    super.init(frame: .zero)
    isUserInteractionEnabled = false
    isAccessibilityElement = false
    dot.backgroundColor = Palette.ink
    dot.layer.cornerRadius = 3
    dot.layer.borderColor = UIColor.white.cgColor
    dot.layer.borderWidth = 1.5
    line.backgroundColor = Palette.ink.withAlphaComponent(0.4)
    plate.backgroundColor = SaliniBrand.paper.withAlphaComponent(0.96)
    plate.layer.cornerRadius = 10
    plate.layer.cornerCurve = .continuous
    for v in [line, dot, plate, text] { addSubview(v) }
    text.numberOfLines = 0
  }
  required init?(coder: NSCoder) { fatalError() }

  /// Dot at the anchor and a short vertical leader to the label centred above or below it,
  /// kept inside the stage.
  func place(at p: CGPoint, in bounds: CGRect, above: Bool) {
    let textSize = text.sizeThatFits(CGSize(width: min(190, max(1, bounds.width - 32)), height: .greatestFiniteMagnitude))
    let size = CGSize(width: textSize.width + 16, height: textSize.height + 12)
    let lead: CGFloat = 30
    let x = min(max(8, p.x - size.width / 2), bounds.width - size.width - 8)
    var y = above ? p.y - lead - size.height : p.y + lead
    y = min(max(4, y), bounds.height - size.height - 4)
    frame = bounds
    dot.frame = CGRect(x: p.x - 4, y: p.y - 4, width: 8, height: 8)
    plate.frame = CGRect(x: x, y: y, width: size.width, height: size.height)
    text.frame = plate.frame.insetBy(dx: 8, dy: 6)
    text.textAlignment = .center
    let y0 = above ? y + size.height + 3 : p.y + 4, y1 = above ? p.y - 4 : y - 3
    line.frame = CGRect(x: p.x - 0.25, y: min(y0, y1), width: 0.5, height: max(0, abs(y1 - y0)))
  }
}
