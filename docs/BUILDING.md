# Сборка и запуск

## Требования

- Mac с Xcode 27 и SDK iOS 27. Минимальная версия приложения — iOS 27.0.
- Для симулятора не нужны Apple Account и сертификаты. Для установки на устройство и отправки в TestFlight нужны соответствующие права Apple Developer / App Store Connect.
- Git LFS, CocoaPods, внешний сервер и генерация изображений для сборки не требуются. Все используемые приложением ресурсы уже включены в репозиторий.
- XcodeGen нужен только при изменении `ios/project.yml` и повторной генерации проекта. Готовый `.xcodeproj` сохранён в Git.

## Через Xcode

1. Склонируйте репозиторий или скачайте ZIP.
2. Откройте `ios/Salini.xcodeproj`.
3. Выберите схему `Salini` и установленный симулятор iOS 27.
4. Нажмите Run. Для тестов используйте Product → Test.

## Через терминал

Из корня репозитория, без запуска симулятора:

```sh
xcodebuild -project ios/Salini.xcodeproj -scheme Salini \
  -configuration Debug -sdk iphonesimulator \
  -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath .build CODE_SIGNING_ALLOWED=NO build
```

Для запуска тестов выберите **свой** симулятор и подставьте его UDID из `xcrun simctl list devices available`:

```sh
xcodebuild -project ios/Salini.xcodeproj -scheme Salini \
  -destination 'platform=iOS Simulator,id=<YOUR-SIMULATOR-UDID>' \
  -derivedDataPath .build -parallel-testing-enabled NO test
```

Исторические результаты тестов — в [`ios/QA.md`](../ios/QA.md) и [`ios/release/`](../ios/release). Проверка переноса в отдельный репозиторий — [`migration-validation.json`](migration-validation.json).

## Устройство и AR

На физическом устройстве выберите доступную вам команду разработчика в Signing & Capabilities. Сохранённый в проекте Team ID — конфигурация существующего релиза, а не переданные учётные данные. Доступ к GitHub сам по себе не предоставляет доступ к аккаунту Apple.

Размещение в комнате требует совместимого устройства с камерой и ARKit. Симулятор предоставляет просмотр модели; он не проверяет распознавание пола, якоря и стабильность реального AR. Физическая проверка AR остаётся открытой задачей.

## Подготовка ресурсов — отдельно от сборки

Приложение собирается с готовыми ресурсами. Не запускайте генераторы только ради первого запуска: они могут перезаписать текущие ассеты.

- `ios/tools/build_catalog.py` и `build_support.py` требуют локальный архив сайта от 06.10.2026. Передавайте `--archive /path/to/archive`; исторический путь по умолчанию относится к компьютеру автора. Инвентаризация продуктов сохранена в `research/site-audit-2026-10-06/inventory/`.
- `ios/prepare_assets.py` — исторический генератор начального прототипа; не используйте его для обновления текущего каталога.
- `ios/tools/insight_poc/` — Blender-пайплайн сцены. Для повторного запекания нужны Blender и исходные загрузки, перечисленные в его README. Готовая сцена уже находится в bundle.
- Полный архив сайта и исходные загрузки не входят в этот репозиторий. [Архив разработки](https://github.com/Mind3Scape/solini-render-studio/tree/ee56a2267adba72999ce03bac8351c21bd89184d/research) сохраняет исследования и происхождение ресурсов.
