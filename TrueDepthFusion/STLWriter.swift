import Foundation

/// SCMesh positions are padded float3 values (16-byte stride), faces are packed Int32 triples.
/// Reconstruction uses metres; STL has no unit metadata, so export coordinates in millimetres.
enum STLWriter {
    enum ExportError: LocalizedError {
        case invalidGeometry
        var errorDescription: String? { "Модель содержит пустую или некорректную геометрию." }
    }

    static func encode(positions: Data, vertexCount: Int, faces: Data, faceCount: Int) throws -> Data {
        guard vertexCount > 0, faceCount > 0, faceCount <= Int(UInt32.max),
              vertexCount <= positions.count / 16, faceCount <= faces.count / 12 else {
            throw ExportError.invalidGeometry
        }
        var output = Data("Limb Scanner; coordinates in millimetres".utf8)
        output.append(Data(count: 80 - output.count))
        append(UInt32(0), to: &output)
        var written: UInt32 = 0
        try positions.withUnsafeBytes { (vertices: UnsafeRawBufferPointer) in
            try faces.withUnsafeBytes { (indices: UnsafeRawBufferPointer) in
                func vertex(_ face: Int, _ corner: Int) throws -> SIMD3<Float> {
                    let raw = indices.loadUnaligned(fromByteOffset: face * 12 + corner * 4, as: Int32.self)
                    let index = Int(Int32(littleEndian: raw))
                    guard index >= 0, index < vertexCount else { throw ExportError.invalidGeometry }
                    let offset = index * 16
                    let p = SIMD3<Float>(
                        vertices.loadUnaligned(fromByteOffset: offset, as: Float.self),
                        vertices.loadUnaligned(fromByteOffset: offset + 4, as: Float.self),
                        vertices.loadUnaligned(fromByteOffset: offset + 8, as: Float.self)) * 1000
                    guard p.x.isFinite, p.y.isFinite, p.z.isFinite else { throw ExportError.invalidGeometry }
                    return p
                }
                for face in 0..<faceCount {
                    let a = try vertex(face, 0), b = try vertex(face, 1), c = try vertex(face, 2)
                    let u = b - a, v = c - a
                    var normal = SIMD3<Float>(u.y * v.z - u.z * v.y,
                                              u.z * v.x - u.x * v.z,
                                              u.x * v.y - u.y * v.x)
                    let length = (normal.x * normal.x + normal.y * normal.y + normal.z * normal.z).squareRoot()
                    guard length.isFinite else { throw ExportError.invalidGeometry }
                    if length == 0 { continue } // Degenerate triangles carry no surface.
                    normal /= length
                    for p in [normal, a, b, c] {
                        append(p.x.bitPattern, to: &output)
                        append(p.y.bitPattern, to: &output)
                        append(p.z.bitPattern, to: &output)
                    }
                    output.append(contentsOf: [0, 0]) // STL attribute byte count.
                    written += 1
                }
            }
        }
        guard written > 0 else { throw ExportError.invalidGeometry }
        var count = Data()
        append(written, to: &count)
        output.replaceSubrange(80..<84, with: count)
        return output
    }

    private static func append(_ value: UInt32, to data: inout Data) {
        var littleEndian = value.littleEndian
        withUnsafeBytes(of: &littleEndian) { data.append(contentsOf: $0) }
    }
}
