# Matter — UIKit × Metal

Новая страница **Metal Engine**: графики 1M/2M, GPU min/max LOD, streaming,
ProMotion request, shader-переходы и VFX. Открывается отдельной кнопкой на главной.
Архитектура, интеграция, ограничения и проверки: [METAL_ENGINE.md](METAL_ENGINE.md).
Для новой страницы успешно прошли GPU-проверки на Apple M2 и `EnginePageTests`
на iPhone 18 Pro Simulator: 1M/2M, streaming, pinch, Metal push/pop и VFX.

Интерактивная галерея семи эффектов: Fluid Gradient, Dynamic Frost, Aurora Border,
Touch Energy, Holographic Foil, Dissolve и Text Glow с искрами.

Откройте `view.xcodeproj`, выберите схему `view` и запустите на iPhone или iPad.
Проект использует установленный iOS 27 SDK. Для сборки шейдеров нужен компонент
Metal Toolchain в Xcode. Сторонних зависимостей нет.

## Подключение к UIKit

`MetalEffectView.swift` содержит переиспользуемый `UIView`, чей backing layer —
`CAMetalLayer`. Шейдеры находятся в `Effects.metal` и автоматически входят в target
через синхронизируемую папку Xcode.

```swift
let effect = MetalEffectView(effect: .fluid)
effect.frame = card.bounds
effect.autoresizingMask = [.flexibleWidth, .flexibleHeight]
card.insertSubview(effect, at: 0)
// Чтобы фон не перехватывал касания элементов карточки:
effect.isUserInteractionEnabled = false
effect.isAccessibilityElement = false
effect.intensity = 0.8
```

Для эффекта поверх кнопки используйте прозрачный `.glow` либо `.pulse` как её
внутреннюю подложку. Отключите обработку касаний у Metal-вьюхи и передавайте
точку события из собственного UIControl:

```swift
effect.activate(at: touch.location(in: effect))
```

Для обработки содержимого обычной вьюхи:

```swift
source.layoutIfNeeded()
if effect.capture(source) {
    source.isHidden = true
}
// Для .dissolve: activate() запускает распад, restore() восстанавливает изображение.
```

Источник и Metal-вьюха должны иметь одинаковые bounds. Снимайте отдельный источник,
не родителя, включающего сам Metal-слой. `capture` возвращает успех; снимок нужно
обновлять после изменения исходного контента, размера или оформления. Пример
`EffectTile` переснимает исходную UIKit-вьюху при изменении размера.

## Рендеринг и ограничения

- Один display link, Metal device, pipeline, command queue и motion manager на галерею.
- До трёх GPU-команд в работе; занятый GPU не блокирует главный поток.
- Невидимые карточки пропускаются, при уходе приложения в фон clock и motion останавливаются.
- Reduce Motion фиксирует непрерывную анимацию и сразу завершает удаление.
- Пауза сохраняет время всех эффектов; ползунок меняет интенсивность от 0 до 100%.
- Масштаб текстур ограничен 2× для снижения нагрузки. UIKit-снимки делаются при изменениях,
  а не каждый кадр. Видео, другие Metal-слои и системный backdrop blur таким способом не захватываются.
- Frost преломляет и размывает снимок демонстрационного фона. Для динамического фона
  приложение должно явно обновлять входную текстуру; автоматического захвата экрана нет.
- Искры и пыль вычисляются в fragment shader по времени и seed. Это ограниченная
  аналитическая система частиц без накопленной физической симуляции.
- Наклоны используют gravity из Core Motion. В симуляторе вместо наклона работает палец;
  motion и haptics проверяются на физическом устройстве.

Основа интеграции: [Apple: CAMetalLayer](https://developer.apple.com/documentation/quartzcore/cametallayer).

## Проверка

Схема `view` включает `viewUITests`. Запуск: Product → Test (`⌘U`). Smoke-тест
проверяет фильтры, паузу, интенсивность, состояние CTA, удаление и восстановление;
сохраняет снимки эффектов как attachments в test report. Анимацию и композицию
нужно оценивать по снимкам и при запуске приложения: проверки accessibility
сами по себе не подтверждают корректность GPU-изображения.

Проверка первой галереи 21.10.2026: `xcodebuild build` и `build-for-testing` завершились успешно,
главный экран с Metal-градиентом проверен по снимку iPhone 17. UI-прогон подтвердил
запуск галереи и паузу, но целиком не завершился: iOS 27 Simulator сообщал
`Data Migration Failed`, XCTest зависал при запуске/остановке приложения.
Полный `GalleryTests` первой галереи и физические motion/haptics остаются для повторной проверки.
