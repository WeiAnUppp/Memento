//
//  DatabaseService.swift
//  Memento
//
//  Created by WeiAnUppp on 2026/7/21.
//

import Foundation
import SQLite3

// MARK: - Database Error

enum DatabaseError: LocalizedError {
    case openFailed(String)
    case insertFailed(String)
    case fetchFailed(String)
    case updateFailed(String)
    case deleteFailed(String)

    var errorDescription: String? {
        switch self {
        case .openFailed(let msg): return "数据库打开失败: \(msg)"
        case .insertFailed(let msg): return "保存失败: \(msg)"
        case .fetchFailed(let msg): return "查询失败: \(msg)"
        case .updateFailed(let msg): return "更新失败: \(msg)"
        case .deleteFailed(let msg): return "删除失败: \(msg)"
        }
    }
}

// MARK: - Database Service

final class DatabaseService {
    static let shared = DatabaseService()

    private let queue = DispatchQueue(label: "com.memento.database")
    private var db: OpaquePointer?

    // MARK: - Init

    private init() {
        queue.sync {
            openDatabase()
            createTable()
        }
    }

    deinit {
        if let db = db {
            sqlite3_close(db)
        }
    }

    // MARK: - Setup

    private func openDatabase() {
        let url = FileManager.default
            .urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("memento.sqlite")

        if sqlite3_open(url.path, &db) != SQLITE_OK {
            print("[DatabaseService] 打开失败: \(errmsg())")
        }
    }

    private func createTable() {
        let sql = """
        CREATE TABLE IF NOT EXISTS items (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            name TEXT NOT NULL,
            description TEXT NOT NULL,
            keywords TEXT,
            scene TEXT,
            nearby_objects TEXT,
            user_note TEXT,
            latitude REAL NOT NULL,
            longitude REAL NOT NULL,
            image_path TEXT,
            emoji TEXT,
            embedding BLOB,
            created_at TEXT NOT NULL,
            updated_at TEXT NOT NULL
        );
        """

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            print("[DatabaseService] 建表失败: \(errmsg())")
            return
        }
        defer { sqlite3_finalize(statement) }

        if sqlite3_step(statement) != SQLITE_DONE {
            print("[DatabaseService] 建表执行失败: \(errmsg())")
        }

        // 迁移：为旧表添加后续版本新增的列（ALTER 失败=列已存在，忽略）
        migrateAddColumn("emoji", type: "TEXT")
        migrateAddColumn("nearby_objects", type: "TEXT")
    }

    /// 幂等地为 items 表添加列。列已存在时 ALTER 会失败，静默忽略即可。
    private func migrateAddColumn(_ name: String, type: String) {
        let sql = "ALTER TABLE items ADD COLUMN \(name) \(type);"
        var stmt: OpaquePointer?
        if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
            sqlite3_step(stmt)
        }
        sqlite3_finalize(stmt)
    }

    // MARK: - Date Helpers

    private let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm:ss"
        f.timeZone = TimeZone(secondsFromGMT: 0)
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()

    private func formatDate(_ date: Date) -> String {
        dateFormatter.string(from: date)
    }

    private func parseDate(_ string: String) -> Date? {
        dateFormatter.date(from: string)
    }

    // MARK: - SQLite Helpers

    private func errmsg() -> String {
        String(cString: sqlite3_errmsg(db))
    }

    private var SQLITE_TRANSIENT: sqlite3_destructor_type {
        unsafeBitCast(OpaquePointer(bitPattern: -1), to: sqlite3_destructor_type.self)
    }

    private func bindText(_ stmt: OpaquePointer?, _ col: Int32, _ value: String) {
        value.withCString { ptr in
            sqlite3_bind_text(stmt, col, ptr, -1, SQLITE_TRANSIENT)
        }
    }

    private func bindOptionalText(_ stmt: OpaquePointer?, _ col: Int32, _ value: String?) {
        if let value {
            bindText(stmt, col, value)
        } else {
            sqlite3_bind_null(stmt, col)
        }
    }

    private func bindEmbedding(_ stmt: OpaquePointer?, _ col: Int32, _ embedding: [Float]?) {
        guard let embedding, !embedding.isEmpty else {
            sqlite3_bind_null(stmt, col)
            return
        }
        let data = embedding.withUnsafeBytes { Data($0) }
        _ = data.withUnsafeBytes { buffer in
            sqlite3_bind_blob(stmt, col, buffer.baseAddress, Int32(data.count), SQLITE_TRANSIENT)
        }
    }

    private func columnText(_ stmt: OpaquePointer?, _ col: Int32) -> String? {
        guard let stmt, sqlite3_column_type(stmt, col) != SQLITE_NULL else { return nil }
        return String(cString: sqlite3_column_text(stmt, col))
    }

    private func rowToItem(_ stmt: OpaquePointer?) -> Item? {
        guard let stmt else { return nil }

        let id = sqlite3_column_int64(stmt, 0)
        guard let namePtr = sqlite3_column_text(stmt, 1),
              let descPtr = sqlite3_column_text(stmt, 2) else { return nil }

        let name = String(cString: namePtr)
        let desc = String(cString: descPtr)
        let keywords = columnText(stmt, 3)
        let scene = columnText(stmt, 4)
        let userNote = columnText(stmt, 5)
        let lat = sqlite3_column_double(stmt, 6)
        let lon = sqlite3_column_double(stmt, 7)
        let imagePath = columnText(stmt, 8)
        let emoji = columnText(stmt, 9)

        let createdAtStr = String(cString: sqlite3_column_text(stmt, 10))
        let updatedAtStr = String(cString: sqlite3_column_text(stmt, 11))
        // index 12 = nearby_objects（所有 SELECT 都把它放在 updated_at 之后）
        let nearbyObjects = columnText(stmt, 12)

        return Item(
            id: id,
            name: name,
            itemDescription: desc,
            keywords: keywords,
            scene: scene,
            nearbyObjects: nearbyObjects,
            userNote: userNote,
            latitude: lat,
            longitude: lon,
            emoji: emoji,
            imagePath: imagePath,
            createdAt: parseDate(createdAtStr) ?? Date(),
            updatedAt: parseDate(updatedAtStr) ?? Date()
        )
    }

    // MARK: - CRUD

    @discardableResult
    func insert(_ item: Item, embedding: [Float]? = nil) throws -> Int64 {
        return try queue.sync {
            let sql = """
            INSERT INTO items (name, description, keywords, scene, nearby_objects, user_note,
                               latitude, longitude, image_path, emoji, embedding,
                               created_at, updated_at)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
            """

            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
                throw DatabaseError.insertFailed(errmsg())
            }
            defer { sqlite3_finalize(stmt) }

            let now = formatDate(Date())
            // created_at 用物品自带的时间（= 第一张照片的拍摄时间），不再强制覆盖成保存时刻。
            // 这样"前天拍的"能按真实拍摄日过滤。updated_at 仍记为当前。
            let createdAt = formatDate(item.createdAt)

            bindText(stmt, 1, item.name)
            bindText(stmt, 2, item.itemDescription)
            bindOptionalText(stmt, 3, item.keywords)
            bindOptionalText(stmt, 4, item.scene)
            bindOptionalText(stmt, 5, item.nearbyObjects)
            bindOptionalText(stmt, 6, item.userNote)
            sqlite3_bind_double(stmt, 7, item.latitude)
            sqlite3_bind_double(stmt, 8, item.longitude)
            bindOptionalText(stmt, 9, item.imagePath)
            bindOptionalText(stmt, 10, item.emoji)
            bindEmbedding(stmt, 11, embedding)
            bindText(stmt, 12, createdAt)
            bindText(stmt, 13, now)

            guard sqlite3_step(stmt) == SQLITE_DONE else {
                throw DatabaseError.insertFailed(errmsg())
            }

            return sqlite3_last_insert_rowid(db)
        }
    }

    func fetchAll() throws -> [Item] {
        return try queue.sync {
            let sql = """
            SELECT id, name, description, keywords, scene, user_note,
                   latitude, longitude, image_path, emoji, created_at, updated_at,
                   nearby_objects
            FROM items ORDER BY created_at DESC;
            """

            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
                throw DatabaseError.fetchFailed(errmsg())
            }
            defer { sqlite3_finalize(stmt) }

            var items: [Item] = []
            while sqlite3_step(stmt) == SQLITE_ROW {
                if let item = rowToItem(stmt) {
                    items.append(item)
                }
            }
            return items
        }
    }

    func fetch(id: Int64) throws -> Item? {
        return try queue.sync {
            let sql = """
            SELECT id, name, description, keywords, scene, user_note,
                   latitude, longitude, image_path, emoji, created_at, updated_at,
                   nearby_objects
            FROM items WHERE id = ?;
            """

            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
                throw DatabaseError.fetchFailed(errmsg())
            }
            defer { sqlite3_finalize(stmt) }

            sqlite3_bind_int64(stmt, 1, id)
            guard sqlite3_step(stmt) == SQLITE_ROW else { return nil }
            return rowToItem(stmt)
        }
    }

    func update(_ item: Item) throws {
        try queue.sync {
            guard let id = item.id else {
                throw DatabaseError.updateFailed("物品ID为空")
            }

            let sql = """
            UPDATE items SET name=?, description=?, keywords=?, scene=?,
                   nearby_objects=?, user_note=?, latitude=?, longitude=?, image_path=?, emoji=?,
                   updated_at=?
            WHERE id=?;
            """

            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
                throw DatabaseError.updateFailed(errmsg())
            }
            defer { sqlite3_finalize(stmt) }

            bindText(stmt, 1, item.name)
            bindText(stmt, 2, item.itemDescription)
            bindOptionalText(stmt, 3, item.keywords)
            bindOptionalText(stmt, 4, item.scene)
            bindOptionalText(stmt, 5, item.nearbyObjects)
            bindOptionalText(stmt, 6, item.userNote)
            sqlite3_bind_double(stmt, 7, item.latitude)
            sqlite3_bind_double(stmt, 8, item.longitude)
            bindOptionalText(stmt, 9, item.imagePath)
            bindOptionalText(stmt, 10, item.emoji)
            bindText(stmt, 11, formatDate(Date()))
            sqlite3_bind_int64(stmt, 12, id)

            guard sqlite3_step(stmt) == SQLITE_DONE else {
                throw DatabaseError.updateFailed(errmsg())
            }
        }
    }

    /// 仅更新物品 GPS 坐标（长按拖拽大头针后调用）
    func updateLocation(id: Int64, latitude: Double, longitude: Double) throws {
        try queue.sync {
            let sql = "UPDATE items SET latitude=?, longitude=?, updated_at=? WHERE id=?;"
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
                throw DatabaseError.updateFailed(errmsg())
            }
            defer { sqlite3_finalize(stmt) }

            sqlite3_bind_double(stmt, 1, latitude)
            sqlite3_bind_double(stmt, 2, longitude)
            bindText(stmt, 3, formatDate(Date()))
            sqlite3_bind_int64(stmt, 4, id)

            guard sqlite3_step(stmt) == SQLITE_DONE else {
                throw DatabaseError.updateFailed(errmsg())
            }
        }
    }

    /// 仅更新 embedding 向量（重建索引时调用）
    func updateEmbedding(id: Int64, embedding: [Float]?) throws {
        try queue.sync {
            let sql = "UPDATE items SET embedding=? WHERE id=?;"
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
                throw DatabaseError.updateFailed(errmsg())
            }
            defer { sqlite3_finalize(stmt) }

            bindEmbedding(stmt, 1, embedding)
            sqlite3_bind_int64(stmt, 2, id)

            guard sqlite3_step(stmt) == SQLITE_DONE else {
                throw DatabaseError.updateFailed(errmsg())
            }
        }
    }

    /// 仅更新图标 emoji
    func updateEmoji(id: Int64, emoji: String) throws {
        try queue.sync {
            let sql = "UPDATE items SET emoji=?, updated_at=? WHERE id=?;"
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
                throw DatabaseError.updateFailed(errmsg())
            }
            defer { sqlite3_finalize(stmt) }

            bindText(stmt, 1, emoji)
            bindText(stmt, 2, formatDate(Date()))
            sqlite3_bind_int64(stmt, 3, id)

            guard sqlite3_step(stmt) == SQLITE_DONE else {
                throw DatabaseError.updateFailed(errmsg())
            }
        }
    }

    func delete(id: Int64) throws {
        try queue.sync {
            let sql = "DELETE FROM items WHERE id=?;"
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
                throw DatabaseError.deleteFailed(errmsg())
            }
            defer { sqlite3_finalize(stmt) }

            sqlite3_bind_int64(stmt, 1, id)

            guard sqlite3_step(stmt) == SQLITE_DONE else {
                throw DatabaseError.deleteFailed(errmsg())
            }
        }
    }

    // MARK: - Search

    /// 获取所有物品及其 embedding 向量（用于搜索排序）
    func fetchAllWithEmbeddings() throws -> [(Item, [Float]?)] {
        return try queue.sync {
            // nearby_objects 在 12（rowToItem 读取），embedding 顺延到 13
            let sql = """
            SELECT id, name, description, keywords, scene, user_note,
                   latitude, longitude, image_path, emoji, created_at, updated_at,
                   nearby_objects, embedding
            FROM items ORDER BY created_at DESC;
            """

            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
                throw DatabaseError.fetchFailed(errmsg())
            }
            defer { sqlite3_finalize(stmt) }

            var results: [(Item, [Float]?)] = []
            while sqlite3_step(stmt) == SQLITE_ROW {
                if let item = rowToItem(stmt) {
                    let embedding = readEmbedding(stmt, col: 13)
                    results.append((item, embedding))
                }
            }
            return results
        }
    }

    /// 读取 SQLite BLOB 列为 [Float] 向量
    private func readEmbedding(_ stmt: OpaquePointer?, col: Int32) -> [Float]? {
        guard let stmt, sqlite3_column_type(stmt, col) != SQLITE_NULL else { return nil }
        let byteCount = Int(sqlite3_column_bytes(stmt, col))
        guard byteCount > 0,
              let blob = sqlite3_column_blob(stmt, col) else { return nil }
        let floatCount = byteCount / MemoryLayout<Float>.size
        let typedPointer = blob.bindMemory(to: Float.self, capacity: floatCount)
        return Array(UnsafeBufferPointer(start: typedPointer, count: floatCount))
    }

    // MARK: - Image Helpers

    static let imagesDirectory: URL = {
        let dir = FileManager.default
            .urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("MementoImages", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    static func generateImageFileName() -> String {
        "\(UUID().uuidString).jpg"
    }

    static func saveImage(_ data: Data) throws -> String {
        let filename = generateImageFileName()
        let url = imagesDirectory.appendingPathComponent(filename)
        try data.write(to: url, options: .atomic)
        return filename
    }

    static func imageURL(for path: String?) -> URL? {
        guard let path else { return nil }
        return imagesDirectory.appendingPathComponent(path)
    }

    static func deleteImage(at path: String?) {
        guard let path, let url = imageURL(for: path) else { return }
        try? FileManager.default.removeItem(at: url)
    }

    /// 批量删除多张图片
    static func deleteImages(at paths: [String]) {
        for path in paths {
            deleteImage(at: path)
        }
    }
}
