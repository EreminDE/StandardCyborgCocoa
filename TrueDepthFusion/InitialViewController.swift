import AVFoundation
import UIKit

class InitialViewController: UIViewController {
    @IBOutlet weak var introLabel: UILabel!

    override func viewDidLoad() {
        super.viewDidLoad()
        view.subviews.forEach { $0.removeFromSuperview() }
        view.backgroundColor = .systemGroupedBackground
        title = "Сканер культи"

        let scroll = UIScrollView()
        scroll.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scroll)
        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = 20
        stack.translatesAutoresizingMaskIntoConstraints = false
        scroll.addSubview(stack)
        NSLayoutConstraint.activate([
            scroll.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scroll.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scroll.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),
            stack.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor, constant: 32),
            stack.leadingAnchor.constraint(equalTo: scroll.contentLayoutGuide.leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(equalTo: scroll.contentLayoutGuide.trailingAnchor, constant: -24),
            stack.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor, constant: -32),
            stack.widthAnchor.constraint(equalTo: scroll.frameLayoutGuide.widthAnchor, constant: -48)
        ])

        let icon = UIImageView(image: UIImage(systemName: "viewfinder"))
        icon.tintColor = .systemTeal
        icon.contentMode = .scaleAspectFit
        icon.heightAnchor.constraint(equalToConstant: 72).isActive = true
        stack.addArrangedSubview(icon)
        stack.addArrangedSubview(label("Сканер культи", style: .largeTitle))
        stack.addArrangedSubview(label("3D-сканирование фронтальной камерой TrueDepth", style: .title3))
        stack.addArrangedSubview(label("Расположите культю перед фронтальной камерой. Начните примерно с 25–30 см и проверьте, что поверхность видна в предпросмотре.\n\nПациент сохраняет неподвижность, вы медленно перемещаете iPhone вокруг культи. Нажмите кнопку съёмки для старта и ещё раз для завершения.", style: .body))
        stack.addArrangedSubview(button("Новый скан", action: #selector(scan(_:)), primary: true))
        stack.addArrangedSubview(button("Библиотека сканов", action: #selector(showScans), primary: false))
        stack.addArrangedSubview(button("Настройки", action: #selector(showSettings), primary: false))
        let note = label("Экспериментальная версия. Измерения и пригодность модели для изготовления гильзы требуют отдельной проверки.", style: .footnote)
        note.textColor = .secondaryLabel
        stack.addArrangedSubview(note)
    }

    private func label(_ text: String, style: UIFont.TextStyle) -> UILabel {
        let label = UILabel()
        label.text = text
        label.numberOfLines = 0
        label.font = .preferredFont(forTextStyle: style)
        label.adjustsFontForContentSizeCategory = true
        return label
    }

    private func button(_ title: String, action: Selector, primary: Bool) -> UIButton {
        let button = UIButton(type: .system)
        button.setTitle(title, for: .normal)
        button.titleLabel?.font = .preferredFont(forTextStyle: .headline)
        button.titleLabel?.adjustsFontForContentSizeCategory = true
        button.titleLabel?.numberOfLines = 0
        button.contentEdgeInsets = UIEdgeInsets(top: 16, left: 16, bottom: 16, right: 16)
        button.backgroundColor = primary ? .systemTeal : .secondarySystemGroupedBackground
        button.setTitleColor(primary ? .black : .label, for: .normal)
        button.layer.cornerRadius = 14
        button.addTarget(self, action: action, for: .touchUpInside)
        button.heightAnchor.constraint(greaterThanOrEqualToConstant: 56).isActive = true
        return button
    }

    @IBAction private func scan(_ sender: UIButton?) {
        guard AVCaptureDevice.default(.builtInTrueDepthCamera, for: .video, position: .front) != nil else {
            let alert = UIAlertController(title: "TrueDepth недоступна", message: "Для сканирования нужна фронтальная камера TrueDepth. На симуляторе можно проверить библиотеку и интерфейс.", preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "Понятно", style: .cancel))
            present(alert, animated: true)
            return
        }
        let raw = UserDefaults.standard.bool(forKey: "dump_raw_frames_to_bply", defaultValue: false)
        performSegue(withIdentifier: raw ? "BPLYScanningViewController" : "ScanningViewController", sender: nil)
    }

    @objc private func showScans() {
        let controller = storyboard!.instantiateViewController(withIdentifier: "ScansViewController")
        navigationController?.pushViewController(controller, animated: true)
    }

    @objc private func showSettings() {
        present(UINavigationController(rootViewController: ScannerSettingsController(style: .insetGrouped)), animated: true)
    }
}

private class ScannerSettingsController: UITableViewController {
    private let options: [(title: String, key: String, fallback: Bool)] = [
        ("Ручной старт и стоп", "tap_to_start_stop", true),
        ("Полное разрешение глубины", "full_resolution_depth_frames", false),
        ("Завершать при потере трекинга", "stop_scanning_on_reconstruction_failure", false)
    ]

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Настройки"
        navigationItem.rightBarButtonItem = UIBarButtonItem(title: "Готово", style: .done, target: self, action: #selector(close))
        tableView.rowHeight = UITableView.automaticDimension
        tableView.estimatedRowHeight = 64
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { options.count }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let option = options[indexPath.row]
        let cell = UITableViewCell(style: .default, reuseIdentifier: nil)
        cell.textLabel?.text = option.title
        cell.textLabel?.numberOfLines = 0
        cell.textLabel?.font = .preferredFont(forTextStyle: .body)
        cell.textLabel?.adjustsFontForContentSizeCategory = true
        cell.selectionStyle = .none
        let toggle = UISwitch()
        toggle.isOn = UserDefaults.standard.bool(forKey: option.key, defaultValue: option.fallback)
        toggle.accessibilityLabel = option.title
        toggle.tag = indexPath.row
        toggle.addTarget(self, action: #selector(changed(_:)), for: .valueChanged)
        cell.accessoryView = toggle
        return cell
    }

    override func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        "Ручной режим запускает скан сразу и работает до повторного нажатия. Если его выключить, включаются обратный отсчёт и таймер.\n\nПолное разрешение увеличивает плотность точек и нагрузку, но не гарантирует большей точности. Для сравнения с оригиналом оставьте его выключенным. При потере трекинга вернитесь к последнему снятому участку и ненадолго задержите iPhone. Если совмещение восстановится, съёмка продолжится."
    }

    @objc private func changed(_ sender: UISwitch) {
        UserDefaults.standard.set(sender.isOn, forKey: options[sender.tag].key)
    }

    @objc private func close() { dismiss(animated: true) }
}

extension UserDefaults {
    func bool(forKey key: String, defaultValue: Bool) -> Bool {
        (object(forKey: key) as? NSNumber)?.boolValue ?? defaultValue
    }
}
