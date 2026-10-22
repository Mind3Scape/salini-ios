# Релизы

## Текущая версия: 1.0 (13) — 22.10.2026

**Salini Public Beta → 1.0 (13) → Testing**, срок 90 дней. [Установить или обновить](https://testflight.apple.com/join/mUb5H7bZ). [Открыть сайт](https://mind3scape.github.io/salini/).

- Source commit `027472bb34b62a6091a68f73033622bcae9d14f7`, ветка `codex/unified-salini-experience`.
- ASC build ID `d2f0da35-1a83-443f-8569-c582ec375346`.
- Подписанный архив и codesign validation прошли; канонический каталог совпал с исходником.
- Upload завершён 23:25:37 UTC+07:00: `Upload succeeded`, `EXPORT SUCCEEDED`, exit 0.
- Processing завершён; Salini Internal подключена. What to Test сохранён для build 13.
- Сборка добавлена в Salini Public Beta через Submit for Review; итоговый статус **Testing** подтверждён в таблице публичной группы. Автоуведомление существующих тестеров включено.
- [Подтверждение](../ios/release/build-13-distribution-2026-10-22/distribution-status.json), [снимок статуса](../ios/release/build-13-distribution-2026-10-22/public-beta-testing.png).

Изменения: общая с сайтом главная Paola, типографика и скругления; ссылки на изделия и импорт подборки в избранное; публичные веб-ссылки из share sheet; кнопка сайта в профиле. Проекты и исполнения при импорте не изменяются. Все 8 затронутых XCTest прошли. Buyer, designer, profile и открытие публичного сайта из профиля проверены в Simulator. Установка на физический iPhone и camera AR этим прогоном не проверялись.

## Исходная версия: 1.0 (12)

- Приложение: **Salini**, bundle `design.salini.experience`.
- App Store Connect: `6819688748`.
- [Публичный TestFlight](https://testflight.apple.com/join/mUb5H7bZ).
- Загрузка: 9 октября 2026, 16:08:15 UTC+7, `Upload succeeded` / `EXPORT SUCCEEDED`.
- Проверка распространения: 10 октября 2026 — processing завершён, сборка в Salini Internal, **1.0 (12) Approved** в Salini Public Beta.
- [Сохранённое подтверждение](../ios/release/build-12-distribution-2026-10-10/distribution-status.json) и [проверки приложения](../ios/release/build-12-validation.txt).

Сборка 12 содержит AR, новый блок минералов и доработанный участок отгрузки Insight. Физическое тестирование комнаты через AR пока не выполнено.

При первоначальном переносе исходников в отдельный GitHub-репозиторий новая сборка не отправлялась. Этот раздел относится к историческому релизу 12; текущий релиз 13 подтверждён отдельно выше.

## Работа со следующей версией

1. Изменения разрабатываются в отдельной ветке `codex/<задача>` и проверяются перед включением в `main`.
2. Перед публикацией сверяется текущий номер сборки в App Store Connect. Bundle ID приложения не меняется.
3. Отдельно фиксируются сборка архива, загрузка, processing, внутреннее тестирование и внешний Beta App Review.
4. Учётные данные Apple, сертификаты и профили не добавляются в Git. Доступ к исходникам не равен доступу к публикации.
