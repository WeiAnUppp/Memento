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
            user_note TEXT,
            latitude REAL NOT NULL,
            longitude REAL NOT NULL,
            image_path TEXT,
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

        let createdAtStr = String(cString: sqlite3_column_text(stmt, 9))
        let updatedAtStr = String(cString: sqlite3_column_text(stmt, 10))

        return Item(
            id: id,
            name: name,
            itemDescription: desc,
            keywords: keywords,
            scene: scene,
            userNote: userNote,
            latitude: lat,
            longitude: lon,
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
            INSERT INTO items (name, description, keywords, scene, user_note,
                               latitude, longitude, image_path, embedding,
                               created_at, updated_at)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
            """

            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
                throw DatabaseError.insertFailed(errmsg())
            }
            defer { sqlite3_finalize(stmt) }

            let now = formatDate(Date())

            bindText(stmt, 1, item.name)
            bindText(stmt, 2, item.itemDescription)
            bindOptionalText(stmt, 3, item.keywords)
            bindOptionalText(stmt, 4, item.scene)
            bindOptionalText(stmt, 5, item.userNote)
            sqlite3_bind_double(stmt, 6, item.latitude)
            sqlite3_bind_double(stmt, 7, item.longitude)
            bindOptionalText(stmt, 8, item.imagePath)
            bindEmbedding(stmt, 9, embedding)
            bindText(stmt, 10, now)
            bindText(stmt, 11, now)

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
                   latitude, longitude, image_path, created_at, updated_at
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
                   latitude, longitude, image_path, created_at, updated_at
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
                   user_note=?, latitude=?, longitude=?, image_path=?,
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
            bindOptionalText(stmt, 5, item.userNote)
            sqlite3_bind_double(stmt, 6, item.latitude)
            sqlite3_bind_double(stmt, 7, item.longitude)
            bindOptionalText(stmt, 8, item.imagePath)
            bindText(stmt, 9, formatDate(Date()))
            sqlite3_bind_int64(stmt, 10, id)

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
}
