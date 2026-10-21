//
//  GPUWorldsViewController.swift
//  demo
//

import UIKit

/// Tab 5: whole GPU-driven worlds — collective behaviour, GPU culling, ray tracing, cloth and
/// volumetric smoke.
final class GPUWorldsViewController: LabViewController {
    init() {
        super.init(modes: [
            Mode(
                title: "Рой",
                hint: "Стая рыб (boids): каждая смотрит на соседей через пространственную сетку на GPU. Сравните с независимыми частицами. Палец — хищник.",
                make: { BoidsView() }
            ),
            Mode(
                title: "Город",
                hint: "Сотни тысяч зданий и деревьев. На GPU отбор по пирамиде видимости и LOD, а команды отрисовки формирует сам GPU (Indirect Command Buffer на устройстве, indirect draw в симуляторе). Ведите пальцем, чтобы осмотреться.",
                make: { CityView() }
            ),
            Mode(
                title: "Лучи",
                hint: "Трассировка лучей: стекло, зеркало, золото и мягкие тени от движущейся лампы. Палец двигает лампу.",
                make: { RayTracedRoomView() }
            ),
            Mode(
                title: "Ткань",
                hint: "Ткань из тысяч узлов падает на шар. Тяните её пальцем — сильный рывок рвёт. Свайп по пустому месту вращает камеру.",
                make: { ClothView() }
            ),
            Mode(
                title: "Дым 3D",
                hint: "Объёмный дым в кубе: 3D-сетка скорости и плотности, самозатенение и ray marching. Режим пальца: впрыск, вращение или свет.",
                make: { VolumeSmokeView() }
            ),
        ], launchKey: "worldsMode")
    }
}
