//
//  GPUComputeViewController.swift
//  demo
//

import UIKit

/// Tab 4: simulations where the GPU does real computation every frame, not just drawing.
final class GPUComputeViewController: LabViewController {
    init() {
        super.init(modes: [
            Mode(
                title: "Гравитация",
                hint: "Каждое тело притягивает каждое — n² взаимодействий за шаг. Переключите на CPU: тот же алгоритм на всех ядрах с векторными функциями Accelerate. Палец — массивный аттрактор.",
                make: { NBodyView() }
            ),
            Mode(
                title: "Жидкость",
                hint: "Частицы воды с давлением и вязкостью (Position Based Fluids): уберите перегородку, наклоните телефон, раздвигайте воду пальцем.",
                make: { AquariumFluidView() }
            ),
            Mode(
                title: "Реакция",
                hint: "Реакция–диффузия Грея–Скотта: десятки шагов по всей сетке за кадр. Рисуйте пальцем, чтобы посеять узор.",
                make: { ReactionDiffusionView() }
            ),
            Mode(
                title: "Дым",
                hint: "Несжимаемая жидкость на сетке (Stable Fluids): адвекция, завихрённость и решение давления. Ведите пальцем, чтобы толкнуть дым.",
                make: { SmokeFluidView() }
            ),
        ], launchKey: "computeMode")
    }
}
