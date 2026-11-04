import Foundation
import StandardCyborgFusion
import SceneKit
import UIKit

class ScanPreviewViewController: UIViewController {
    @IBOutlet private weak var sceneView: SCNView!
    @IBOutlet private weak var meshButton: UIButton!
    @IBOutlet private weak var meshingProgressContainer: UIView!
    @IBOutlet private weak var meshingProgressView: UIProgressView!

    var deletionHandler: (() -> Void)?
    var doneHandler: (() -> Void)?
    var scan: Scan? {
        didSet {
            loadViewIfNeeded()
            _mesh = nil
            _pointCloudNode = scan?.pointCloud.buildNode()
            meshButton.isHidden = scan == nil
            meshButton.isEnabled = true
        }
    }

    private var _mesh: SCMesh?
    private var _meshingOperation: SCMeshingOperation?
    private var _working = false
    private var _cancelMeshingRequested = false
    private var _initialPointOfView = SCNMatrix4Identity
    private var _pointCloudNode: SCNNode? {
        willSet { _pointCloudNode?.removeFromParentNode() }
        didSet {
            _pointCloudNode?.name = "scan geometry"
            if let node = _pointCloudNode { sceneView.scene?.rootNode.addChildNode(node) }
        }
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        _initialPointOfView = sceneView.pointOfView?.transform ?? SCNMatrix4Identity
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        sceneView.pointOfView?.transform = _initialPointOfView
        isModalInPresentation = true // Save/discard explicitly; avoid losing an unsaved scan.
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        if let scan = scan, scan.thumbnail == nil {
            scan.thumbnail = sceneView.snapshot().resized(toWidth: 640)
        }
    }

    func showFileError(_ message: String) {
        let alert = UIAlertController(title: "Не удалось выполнить действие", message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Понятно", style: .cancel))
        present(alert, animated: true)
    }

    @IBAction private func _export(_ sender: AnyObject) {
        guard !_working, scan != nil else { return }
        let formats = UIAlertController(title: "Экспорт скана", message: "PLY — исходное облако точек в метрах. STL — поверхность в миллиметрах, без цвета.", preferredStyle: .actionSheet)
        formats.addAction(UIAlertAction(title: "PLY · облако точек", style: .default) { _ in self.exportPLY(anchor: sender as? UIView) })
        formats.addAction(UIAlertAction(title: "STL · поверхность, мм", style: .default) { _ in
            if self._mesh != nil { self.exportSTL(anchor: sender as? UIView) }
            else { self.buildMesh { self.exportSTL(anchor: sender as? UIView) } }
        })
        formats.addAction(UIAlertAction(title: "Отмена", style: .cancel))
        formats.popoverPresentationController?.sourceView = sender as? UIView ?? view
        formats.popoverPresentationController?.sourceRect = (sender as? UIView)?.bounds ?? view.bounds
        present(formats, animated: true)
    }

    private func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func share(_ url: URL, anchor: UIView?) {
        let controller = UIActivityViewController(activityItems: [url], applicationActivities: nil)
        controller.popoverPresentationController?.sourceView = anchor ?? view
        controller.popoverPresentationController?.sourceRect = anchor?.bounds ?? view.bounds
        controller.completionWithItemsHandler = { _, _, _, _ in
            try? FileManager.default.removeItem(at: url.deletingLastPathComponent())
        }
        present(controller, animated: true)
    }

    private func exportPLY(anchor: UIView?) {
        guard let scan = scan else { return }
        do {
            let url = try temporaryDirectory().appendingPathComponent("Scan-\(Scan.string(from: scan.dateCreated)).ply")
            guard scan.pointCloud.writeToPLY(atPath: url.path) else {
                throw CocoaError(.fileWriteUnknown)
            }
            share(url, anchor: anchor)
        } catch { showFileError(error.localizedDescription) }
    }

    private func exportSTL(anchor: UIView?) {
        guard let mesh = _mesh else { return }
        _working = true
        meshButton.isEnabled = false
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let data = try STLWriter.encode(positions: mesh.positionData, vertexCount: mesh.vertexCount,
                                                faces: mesh.facesData, faceCount: mesh.faceCount)
                let url = try self.temporaryDirectory().appendingPathComponent("Scan-mm.stl")
                try data.write(to: url, options: .atomic)
                DispatchQueue.main.async {
                    self._working = false
                    self.meshButton.isEnabled = true
                    self.share(url, anchor: anchor)
                }
            } catch {
                DispatchQueue.main.async {
                    self._working = false
                    self.meshButton.isEnabled = true
                    self.showFileError(error.localizedDescription)
                }
            }
        }
    }

    @IBAction private func _delete(_ sender: Any) {
        guard !_working else { return }
        let alert = UIAlertController(title: scan?.plyPath == nil ? "Отбросить скан?" : "Удалить скан?", message: "Это действие нельзя отменить.", preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Отмена", style: .cancel))
        alert.addAction(UIAlertAction(title: "Удалить", style: .destructive) { _ in self.deletionHandler?() })
        present(alert, animated: true)
    }

    @IBAction private func _done(_ sender: Any) {
        guard !_working else { return }
        doneHandler?()
    }

    @IBAction private func _runMeshing(_ sender: Any) { buildMesh(completion: nil) }

    // Geometric meshing works for saved PLY files too; no transient camera/texturing session is required.
    private func buildMesh(completion: (() -> Void)?) {
        guard !_working, let scan = scan else { return }
        _working = true
        _cancelMeshingRequested = false
        meshButton.isEnabled = false
        meshingProgressContainer.isHidden = false
        meshingProgressContainer.alpha = 1
        meshingProgressView.progress = 0
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let directory = try self.temporaryDirectory()
                defer { try? FileManager.default.removeItem(at: directory) }
                let input = directory.appendingPathComponent("input.ply")
                let output = directory.appendingPathComponent("mesh.ply")
                guard scan.pointCloud.writeToPLY(atPath: input.path) else { throw CocoaError(.fileWriteUnknown) }
                let operation = SCMeshingOperation(inputPLYPath: input.path, outputPLYPath: output.path)
                operation.parameters.closed = false // Do not invent a cap over an unscanned region.
                operation.progressHandler = { progress in
                    DispatchQueue.main.async { self.meshingProgressView.progress = progress }
                }
                DispatchQueue.main.sync {
                    self._meshingOperation = operation
                    if self._cancelMeshingRequested { operation.cancel() }
                }
                operation.start()
                if operation.isCancelled {
                    DispatchQueue.main.async { self.finishMeshing() }
                    return
                }
                guard FileManager.default.fileExists(atPath: output.path) else { throw CocoaError(.fileReadUnknown) }
                guard let mesh = SCMesh(plyPath: output.path, jpegPath: ""), mesh.faceCount > 0 else {
                    throw STLWriter.ExportError.invalidGeometry
                }
                DispatchQueue.main.async {
                    let node = mesh.buildMeshNode()
                    node.transform = self._pointCloudNode?.transform ?? SCNMatrix4Identity
                    self._pointCloudNode = node
                    self._mesh = mesh
                    self.finishMeshing()
                    completion?()
                }
            } catch {
                DispatchQueue.main.async {
                    self.finishMeshing()
                    self.showFileError("Не удалось построить поверхность. \(error.localizedDescription)")
                }
            }
        }
    }

    private func finishMeshing() {
        _working = false
        _meshingOperation = nil
        meshButton.isEnabled = true
        meshingProgressContainer.isHidden = true
    }

    @IBAction private func cancelMeshing(_ sender: Any) {
        _cancelMeshingRequested = true
        _meshingOperation?.cancel()
    }
}
