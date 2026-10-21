# Metal Engine

Новая страница открывается кнопкой **METAL ENGINE · 1M+ точек** на главной странице
галереи. На ней доступны графики на 1M/2M точек, Live-стриминг, pan/pinch, bloom,
три перехода между контроллерами, Fluid Mesh и Matrix Digital Rain.

Превью: [1M](Previews/metal-engine-1m.png) · [2M](Previews/metal-engine-2m.png) ·
[VFX](Previews/metal-engine-vfx.png).

Основные файлы:

| Файл | Назначение |
| --- | --- |
| `view/MetalChartView.swift` | MTKView + MTKViewDelegate, хранение данных, жесты, GPU LOD, телеметрия |
| `view/MetalTransitionAnimator.swift` | UIViewControllerAnimatedTransitioning, три стиля, navigation delegate |
| `view/Shaders.metal` | Compute/vertex/fragment: иерархия, LOD, линии, заливка, bloom, переходы и дождь |
| `view/SharedStructures.h` | Общие C/MSL-структуры и SIMD-матрицы |
| `view/view-Bridging-Header.h` | Импорт структур в Swift; подключён в Debug/Release |
| `view/GlowBloomShader.swift` | Два Gaussian compute-прохода с HDR ping/pong |
| `view/MatrixDigitalRainView.swift` | Instanced glyph quads, атлас, FluidMeshGradientView |
| `view/MetalEngine.swift` | Общие device/queue/pipelines и явный GPU readback для снимков |
| `view/MetalEngineViewController.swift` | Страница демонстрации и реальный append-only источник данных |

## График

```swift
let chart = MetalChartView()
container.addSubview(chart) // задайте frame или Auto Layout constraints
try await chart.setPoints(samples, reserveCapacity: 1_500_000)
try chart.append(nextBatch, followLatest: true)
chart.bloomStrength = 0.8
chart.resetViewport()
```

Точки — `[SIMD2<Float>]`, X отсортирован по неубыванию, все значения конечные,
размах X положительный. Для временных меток используйте относительный X:
вычитайте начало интервала до преобразования Double → Float. Абсолютный Unix time
во Float32 не сохраняет точность близких отсчётов.

Первичная валидация, выделение памяти и копирование выполняются в detached task.
Все методы компонента и UIKit-события вызываются на main actor. Повторная загрузка
отменяет применение устаревшего результата. Данные не пересчитываются при жестах.
По умолчанию pan двухмерный; демонстрация задаёт `allowsVerticalPanning = false`,
чтобы горизонтальный жест двигал график, а вертикальный прокручивал страницу.

Один `storageModeShared` MTLBuffer хранит исходные XY. Append пишет только в свободный
хвост; уже отправленные команды читают старый count. GPU-only иерархия хранит индексы
минимума и максимума каждой группы. После append обновляются только новые листья
и затронутые предки, с buffer barriers между уровнями. Одна command queue упорядочивает
перестройку и рендеринг. Отправленные команды удерживают старые ресурсы при замене набора.

На кадр compute-kernel двоичным поиском находит отсчёты каждой физической пиксельной
колонки и запрашивает min/max в иерархии. Получаются `2 × drawableWidth` вершин вместо N.
Оба экстремума выводятся в исходном временном порядке; граничные сегменты и пустые
колонки обработаны явно. Это `O(width × log N)` запросов вместо обхода миллиона точек
каждый кадр. Начальная иерархия строится за O(N), хранение — O(capacity).

Вершинный шейдер применяет View/Projection к координатам относительно видимого начала,
что уменьшает потерю Float32-точности на глубоком зуме. Homogeneous clipping отсекает
геометрию вне экрана. Аггрегация реализована compute-проходом: vertex shader не умеет
самостоятельно компактировать произвольные соседние вызовы. Early-Z не применяется:
у двумерных line strip нет полезного depth rejection.

Линия — `.lineStrip`, заливка — `.triangleStrip`. Три независимых LOD-буфера и три
256-byte-aligned слота униформ защищены неблокирующим DispatchSemaphore(3). Занятый GPU
приводит к пропуску кадра, а не ожиданию на UI-потоке. HDR-сцена и bloom-текстуры
используются на одной queue с обычным resource hazard tracking.

Демонстрация резервирует 500 000 дополнительных точек и добавляет 2048 каждые 0.1 с.
Буфер ограничен 4 194 304 отсчётами; при заполнении возвращается `.capacity`, Live
останавливается. Это append-only streaming, не бесконечный кольцевой архив. Для удаления,
перестановки или замены исторических данных загрузите новый набор через `setPoints`.

Расход памяти зависит от округления capacity до степени двойки: XY = capacity × 8 байт,
иерархия ≈ 2 × nextPowerOfTwo(capacity) × 8 байт, плюс HDR-сцена и два half-resolution
bloom targets. На каждый кадр загружаются только униформы, а не массив отсчётов.

## Переходы

Для UINavigationController используется `MetalNavigationController`. Он устанавливается
в SceneDelegate поверх существующей галереи. Внешний код может возвращать
`MetalTransitionAnimator(style:touchOrigin:reversed:)` из собственного navigation delegate.
`touchOrigin` нормализован в диапазон 0…1 в координатах контейнера перехода.

`PerlinNoiseDissolve` использует gradient Perlin noise и светящуюся кромку;
`RippleDistortion` — радиальную волну от реальной точки касания;
`GlitchRGB` — RGB split и горизонтальные блоки. CADisplayLink передаёт progress
0…1 за 0.5 с, с запросом частоты экрана до 120 Гц. Переход завершается после финальной
GPU-команды; отмена восстанавливает исходную вьюху, уход в background завершает сессию.

Снимки UIKit и Metal снимаются один раз до запуска clock. MetalChartView, rain и fluid
поддерживают явный offscreen render/readback: `layer.render` не используется для
захвата Metal-содержимого. UIKit-элементы над Metal-поверхностями перерисовываются
поверх снимков с учётом порядка siblings и clipping. Это одноразовая CPU/GPU-подготовка,
она может задержать начало перехода на сложной странице; она не входит в 0.5 с анимации.
Для неизвестных сторонних Metal-компонентов реализуйте `MetalSnapshotProviding`.
Snapshot composition рассчитана на обычные 2D UIKit-преобразования, без 3D perspective.

При недоступности Metal/текстур используется UIKit fade. Reduce Motion заменяет
шейдерный переход коротким fade и фиксирует процедурные анимации.

## VFX и частота кадров

FluidMeshGradientView использует CAMetalLayer-рендерер первой страницы и общий
Core Motion clock. Rain создаёт атлас 96 глифов один раз на компонент и рисует все
символы одним `drawPrimitives(... instanceCount:)`; CPU не анимирует отдельные символы.
Атлас рисуется в явный RGBA8 bitmap и загружается напрямую в MTLTexture, без
зависимости от декодирования монохромных CGImage через MetalKit.
Bloom — нормализованный separable Gaussian (horizontal → vertical), HDR half-resolution.

MTKView и display links запрашивают до 120 Гц; Info.plist содержит
`CADisableMinimumFrameDurationOnPhone`. Невидимые поверхности не отправляют GPU-команды;
при background clock и рендеринг останавливаются. UI-телеметрия обновляется раз в секунду:
рендер/с — частота отправленных кадров, GPU — command buffer duration, CPU — encoding
одного выборочного кадра. Это не измерение фактического display presentation latency.

**120 FPS не подтверждены на физическом устройстве.** Достигнутая частота зависит от
GPU, размера drawable, OS policy, температуры, Low Power Mode и одновременных эффектов.
Измеряйте Release на iPhone/iPad с ProMotion через Metal System Trace/Core Animation:
полный обзор 1M/2M, глубокий зум, pan, Live, bloom и переходы. Бюджет 120 Гц — 8.33 мс;
нужны замеры CPU/GPU frame time и пропущенных presentation deadlines, а не только счётчик.

## Проверки

```sh
bash Scripts/verify-metal-engine.sh
```

Скрипт компилирует **production Shaders.metal** под macOS и запускает их на GPU Mac,
используя тот же bridging header. Проверяет C/Swift ABI, 1 000 003 точки, min/max против
CPU oracle, узкую пару peak/trough, порядок, пустые колонки, инкрементальный append,
все переходы на progress 0/0.5/1 в обоих направлениях, instanced rain и нормализацию
двух Gaussian-проходов. Это проверка GPU-корректности, не FPS-бенчмарк iPhone.

`EnginePageTests` в существующем UI-test target проверяет загрузку 1M/2M, pinch, Live и
push/pop всех трёх переходов, сохраняет скриншоты. Debug-инструментация подтверждает
Metal backend, а не резервный UIKit fade, и готовность атласа. Для прямого открытия страницы в
Debug есть launch argument `-metal-engine`. Сборка и GPU-проверки успешно выполнены
21.10.2026 на Apple M2. Заключительный `EnginePageTests` успешно завершился на
iPhone 18 Pro Simulator (iOS 27): 1M → 2M → 1M, pinch, Live, все три push/pop
с подтверждением Metal backend, готовый RGBA8-атлас и VFX. Скриншоты просмотрены.
Debug-сборка Simulator и Release-сборка для `generic/platform=iOS` без подписи
также завершились успешно. Физический ProMotion-бенчмарк не проводился.

Основа API: [Apple MTKView](https://developer.apple.com/documentation/metalkit/mtkview),
[preferredFramesPerSecond](https://developer.apple.com/documentation/metalkit/mtkview/preferredframespersecond).
