import Foundation

func positions(_ points: [SIMD3<Float>]) -> Data {
    var data = Data()
    for point in points {
        for var value in [point.x, point.y, point.z, Float(0)] {
            withUnsafeBytes(of: &value) { data.append(contentsOf: $0) }
        }
    }
    return data
}
func faces(_ indices: [Int32]) -> Data {
    var data = Data()
    for index in indices {
        var value = index.littleEndian
        withUnsafeBytes(of: &value) { data.append(contentsOf: $0) }
    }
    return data
}
func uint(_ data: Data, at offset: Int) -> UInt32 {
    data.withUnsafeBytes { UInt32(littleEndian: $0.loadUnaligned(fromByteOffset: offset, as: UInt32.self)) }
}
func float(_ data: Data, at offset: Int) -> Float { Float(bitPattern: uint(data, at: offset)) }
func rejects(_ body: () throws -> Data) {
    do { _ = try body(); fatalError("Invalid geometry was accepted") }
    catch STLWriter.ExportError.invalidGeometry { }
    catch { fatalError("Unexpected error: \(error)") }
}
let triangle = positions([.zero, SIMD3<Float>(0.1, 0, 0), SIMD3<Float>(0, 0.2, 0)])
let indices = faces([0, 1, 2])
let stl = try STLWriter.encode(positions: triangle, vertexCount: 3, faces: indices, faceCount: 1)
precondition(stl.count == 84 + 50, "Binary STL record size")
precondition(uint(stl, at: 80) == 1, "Triangle count must be little endian")
precondition(abs(float(stl, at: 108) - 100) < 0.001, "0.1 m must export as 100 mm")
precondition(abs(float(stl, at: 124) - 200) < 0.001, "0.2 m must export as 200 mm")
precondition(float(stl, at: 84) == 0 && float(stl, at: 88) == 0 && float(stl, at: 92) == 1, "Normal and winding")
let mixed = try STLWriter.encode(positions: triangle, vertexCount: 3, faces: faces([0,0,0,0,1,2]), faceCount: 2)
precondition(mixed.count == stl.count && uint(mixed, at: 80) == 1, "Degenerate faces must not change the STL count")
rejects { try STLWriter.encode(positions: Data(), vertexCount: 0, faces: indices, faceCount: 1) }
rejects { try STLWriter.encode(positions: triangle, vertexCount: 3, faces: faces([0,1,3]), faceCount: 1) }
rejects { try STLWriter.encode(positions: triangle, vertexCount: 3, faces: faces([-1,1,2]), faceCount: 1) }
rejects { try STLWriter.encode(positions: triangle, vertexCount: 3, faces: Data([0]), faceCount: 1) }
rejects { try STLWriter.encode(positions: positions([SIMD3<Float>(.nan,0,0), .zero, SIMD3<Float>(0,1,0)]), vertexCount: 3, faces: indices, faceCount: 1) }
rejects { try STLWriter.encode(positions: triangle, vertexCount: 3, faces: faces([0,0,0]), faceCount: 1) }
print("STL checks passed: binary layout, millimetres, winding, degenerates, empty/truncated buffers, invalid indices and NaN")
