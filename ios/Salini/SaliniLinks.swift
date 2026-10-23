import Foundation
import UIKit

/// Versioned bridge shared with the website. v2 carries an explicitly chosen execution and RAL.
/// It never transfers account data, a price or a reservation, or changes project lines.
enum SaliniLink: Equatable {
  case product(String)
  case configuredProduct(String, String, String?)
  case selection([String])
  static let websiteHome = URL(string: "https://mind3scape.github.io/salini/")!

  static func parse(_ url: URL, knownIDs: Set<String>) -> SaliniLink? {
    guard url.absoluteString.utf8.count <= 8192,
      let c = URLComponents(url: url, resolvingAgainstBaseURL: false),
      c.scheme == "salini", c.user == nil, c.password == nil, c.port == nil,
      c.fragment == nil, let host = c.host,
      host == "product" || host == "selection"
    else { return nil }
    let items = c.queryItems ?? []
    guard Set(items.map(\.name)).count == items.count else { return nil }
    let query = Dictionary(uniqueKeysWithValues: items.map { ($0.name, $0.value ?? "") })
    guard query["v"] == "1" || query["v"] == "2" else { return nil }
    if host == "product" {
      guard c.path.hasPrefix("/") else { return nil }
      let id = String(c.path.dropFirst())
      guard !id.isEmpty, !id.contains("/"), knownIDs.contains(id) else { return nil }
      if query["v"] == "2" {
        guard Set(query.keys).isSubset(of: ["v","variant","ral"]),
              let variant = query["variant"], !variant.isEmpty,
              variant.range(of: "^[A-Za-z0-9-]{1,80}$", options: .regularExpression) != nil,
              query["ral"] == nil || RALPalette.colour(query["ral"]!) != nil else { return nil }
        return .configuredProduct(id, variant, query["ral"])
      }
      guard Set(query.keys) == ["v"] else { return nil }
      return .product(id)
    }
    guard query["v"] == "1", c.path.isEmpty, Set(query.keys) == ["v", "ids"], let raw = query["ids"] else { return nil }
    let ids = raw.split(separator: ",", omittingEmptySubsequences: false).map(String.init)
    guard !ids.isEmpty, ids.count <= 100, ids.allSatisfy({ knownIDs.contains($0) }) else { return nil }
    var seen = Set<String>()
    return .selection(ids.filter { seen.insert($0).inserted })
  }

  var appURL: URL {
    var c = URLComponents()
    c.scheme = "salini"
    switch self {
    case .product(let id):
      c.host = "product"
      c.path = "/" + id
      c.queryItems = [.init(name: "v", value: "1")]
    case .configuredProduct(let id, let variant, let ral):
      c.host = "product"; c.path = "/" + id
      c.queryItems = [.init(name: "v", value: "2"),.init(name: "variant", value: variant)]
      if let ral { c.queryItems?.append(.init(name:"ral",value:ral)) }
    case .selection(let ids):
      c.host = "selection"
      c.queryItems = [.init(name: "v", value: "1"), .init(name: "ids", value: ids.joined(separator: ","))]
    }
    return c.url!
  }

  /// Public web counterpart; opening an app link remains an explicit website action.
  var websiteURL: URL {
    var c = URLComponents(url: Self.websiteHome, resolvingAgainstBaseURL: false)!
    switch self {
    case .product(let id): c.fragment = "/product/" + id
    case .configuredProduct(let id, let variant, let ral):
      c.path += "product/" + id + "/"
      c.queryItems = [.init(name:"variant",value:variant)]
      if let ral { c.queryItems?.append(.init(name:"ral",value:ral)) }
    case .selection(let ids): c.fragment = "/selection?ids=" + ids.joined(separator: ",")
    }
    return c.url!
  }
}

extension UIViewController {
  func shareSaliniLink(_ link: SaliniLink, anchor: UIBarButtonItem?) {
    let sheet = UIActivityViewController(activityItems: [link.websiteURL], applicationActivities: nil)
    sheet.popoverPresentationController?.barButtonItem = anchor
    if anchor == nil {
      sheet.popoverPresentationController?.sourceView = view
      sheet.popoverPresentationController?.sourceRect = CGRect(x: view.bounds.midX, y: view.bounds.midY, width: 1, height: 1)
    }
    present(sheet, animated: true)
  }
}

extension MainTabs {
  func openSaliniLink(_ url: URL) {
    loadViewIfNeeded()
    let known = Set(Catalog.shared.products.map(\.id))
    guard let link = SaliniLink.parse(url, knownIDs: known) else {
      let alert = UIAlertController(title: "Ссылка не поддерживается", message: "Возможно, изделие отсутствует в этой версии каталога. Другие данные и проекты не изменены.", preferredStyle: .alert)
      alert.addAction(UIAlertAction(title: "Понятно", style: .default))
      present(alert, animated: true)
      return
    }
    let navigate = { [weak self] in
      guard let self, let nav = self.viewControllers?[MainTabs.catalogTabIndex] as? UINavigationController else { return }
      self.selectedIndex = MainTabs.catalogTabIndex
      nav.popToRootViewController(animated: false)
      switch link {
      case .product(let id):
        guard let product = Catalog.shared.product(id) else { return }
        nav.pushViewController(CatalogProductController(product), animated: false)
      case .configuredProduct(let id, let key, let ral):
        guard let product = Catalog.shared.product(id), let variant = product.variants.first(where: { $0.key == key }),
              ral == nil || variant.allowsRAL else {
          let alert = UIAlertController(title:"Исполнение не найдено",message:"Проверьте ссылку или обновите каталог. Другое исполнение автоматически не выбрано.",preferredStyle:.alert)
          alert.addAction(UIAlertAction(title:"Понятно",style:.default));self.present(alert,animated:true);return
        }
        nav.pushViewController(CatalogProductController(product,variantKey:key,colour:ral.map(LineColour.ral) ?? .standard),animated:false)
      case .selection(let ids):
        // An id-only selection is inspiration, not an order. Do not choose a variant or mutate ProjectStore.
        DemoStore.shared.favorites.formUnion(ids)
        let favorites = CatalogController()
        favorites.showsFavoritesOnly = true
        nav.pushViewController(favorites, animated: false)
      }
    }
    if presentedViewController != nil { dismiss(animated: false, completion: navigate) }
    else { navigate() }
  }
}
