const std = @import("std");

const c = @cImport({
    @cInclude("sqlite3.h");
});

pub const Connection = struct {
    db: ?*c.sqlite3,

    pub fn init(path: []const u8) !Connection {
        var db: ?*c.sqlite3 = null;
        const rc = c.sqlite3_open(path.ptr, &db);
        if (rc != c.SQLITE_OK) {
            return error.OpenFailed;
        }
        return Connection{ .db = db };
    }

    pub fn execute(self: *Connection, sql: []const u8) !void {
        var errmsg: ?[*:0]u8 = null;
        const rc = c.sqlite3_exec(
            self.db,
            sql.ptr,
            null, null,
            &errmsg
        );
        if (rc != c.SQLITE_OK) {
            return error.ExecuteFailed;
        }
    }

    pub fn close(self: *Connection) void {
        _ = c.sqlite3_close(self.db);
    }
};

/// Python-compatible API: connect() returns a Connection
pub fn connect(path: []const u8) !Connection {
    return Connection.init(path);
}
