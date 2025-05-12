const std = @import("std");
const gtk = @import("gtk");
const g = @import("gobject");
const gio = @import("gio");
const gdk = @import("gdk");
const glib = @import("glib");
const c = @cImport({
    @cInclude("playerctl.h");
});

const ButtonType = enum {
    Prev,
    PlayPause,
    Next,
    SeekBack,
    SeekForward,
    Quit,
    PrevPlayer,
    NextPlayer,
};
const ButtonInfo = struct {
    label: [:0]const u8,
    action: *const fn () void,
};

const Buttons = std.EnumArray(ButtonType, ButtonInfo);
var buttons = Buttons.init(.{
    .Prev = .{ .label = "⏮", .action = &PlayerMgr.action_prev },
    .PlayPause = .{ .label = "⏯", .action = &PlayerMgr.action_play_pause },
    .Next = .{ .label = "⏭", .action = &PlayerMgr.action_next },
    .NextPlayer = .{ .label = "➡", .action = &PlayerMgr.action_next_player },
    .PrevPlayer = .{ .label = "⬅", .action = &PlayerMgr.action_prev_player },
    .SeekBack = .{ .label = "⏪", .action = &PlayerMgr.action_seek_back },
    .SeekForward = .{ .label = "⏩", .action = &PlayerMgr.action_seek_forward },
    .Quit = .{ .label = "❌", .action = &quit },
});

var app: *gtk.Application = undefined;
var title_label: *gtk.Label = undefined;
var artist_label: *gtk.Label = undefined;
var player_label: *gtk.Label = undefined;
var progress_bar: *gtk.ProgressBar = undefined;
var play_pause_label: *gtk.Label = undefined;
var background: *gtk.Image = undefined;
var _label: *gtk.Label = undefined;
var stay_on_lost_focus = false;

pub fn main() !void {
    var args = std.process.args();
    _ = args.skip();
    while (args.next()) |arg| {
        if (std.mem.eql(u8, arg, "--stay")) {
            stay_on_lost_focus = true;
            break;
        }
    }
    args.deinit();

    var argc: c_int = 0;
    gtk.init(&argc, null);
    app = gtk.Application.new("dev.media.menu", .flags_flags_none);
    defer app.unref();
    _ = gio.Application.signals.activate.connect(app, ?*anyopaque, &activate, null, .{});
    if (app.as(gio.Application).run(0, null) != 0) {
        return error.ApplicationError;
    }
    if (PlayerMgr.global) |*p| p.deinit();
    std.process.exit(0);
}

fn activate(a: *gtk.Application, _: ?*anyopaque) callconv(.C) void {
    const win = gtk.Window.new(.toplevel);
    a.addWindow(win);

    win.setTitle("Media Menu");
    win.setResizable(0);
    win.setDecorated(0);
    win.setPosition(.center_always);

    // const layout = gtk.Layout.new(null, null);
    // win.as(gtk.Container).add(layout.as(gtk.Widget));

    // background = gtk.Image.newFromResource("https://i.scdn.co/image/ab67616d0000b27360598238c74a200c937a678d");
    // layout.put(background.as(gtk.Widget), 0, 0);

    const vbox = gtk.Box.new(.vertical, 10);
    // layout.put(vbox.as(gtk.Widget), 0, 0);
    win.as(gtk.Container).add(vbox.as(gtk.Widget));

    const player_box = gtk.Box.new(.horizontal, 10);
    vbox.packStart(player_box.as(gtk.Widget), 1, 1, 10);

    player_box.packStart(addButton(.PrevPlayer, null).as(gtk.Widget), 0, 1, 0);

    const track_box = gtk.Box.new(.vertical, 10);
    player_box.packStart(track_box.as(gtk.Widget), 1, 1, 10);

    player_box.packStart(addButton(.NextPlayer, null).as(gtk.Widget), 0, 1, 0);

    progress_bar = gtk.ProgressBar.new();
    vbox.packStart(progress_bar.as(gtk.Widget), 1, 1, 5);

    player_label = gtk.Label.new("");
    track_box.packStart(player_label.as(gtk.Widget), 1, 1, 10);
    title_label = gtk.Label.new("");
    track_box.packStart(title_label.as(gtk.Widget), 1, 1, 10);
    artist_label = gtk.Label.new("");
    track_box.packStart(artist_label.as(gtk.Widget), 1, 1, 10);

    const ctrl_box = gtk.Box.new(.horizontal, 10);
    vbox.packStart(ctrl_box.as(gtk.Widget), 1, 1, 10);

    ctrl_box.packStart(addButton(.Prev, null).as(gtk.Widget), 1, 1, 0);
    ctrl_box.packStart(addButton(.PlayPause, &play_pause_label).as(gtk.Widget), 1, 1, 0);
    ctrl_box.packStart(addButton(.Next, null).as(gtk.Widget), 1, 1, 0);

    _ = gtk.Widget.signals.key_press_event.connect(win, ?*anyopaque, &handle_key_press, null, .{});
    _ = gtk.Widget.signals.focus_out_event.connect(win, ?*anyopaque, &handle_focus_out, null, .{});

    _ = PlayerMgr.init() catch {
        std.log.err("Failed to initialize player manager", .{});
        quit();
        return;
    };

    win.as(gtk.Widget).showAll();
}

fn handle_focus_out(_: *gtk.Window, _: *gdk.EventFocus, _: ?*anyopaque) callconv(.C) c_int {
    if (stay_on_lost_focus) return gtk.false();
    quit();
    return gtk.false();
}

fn addButton(kind: ButtonType, label: ?**gtk.Label) *gtk.Button {
    const button = buttons.get(kind);

    const btn = gtk.Button.newWithLabel(button.label.ptr);
    const lbl = btn.as(gtk.Bin).getChild();
    if (label) |l| {
        l.* = @ptrCast(lbl.?);
    }
    _ = gtk.Button.signals.clicked.connect(btn, *allowzero anyopaque, &handle_button_click, @ptrFromInt(@intFromEnum(kind)), .{});
    return btn;
}

fn handle_key_press(_: ?*gtk.Window, event: *gdk.EventKey, _: ?*anyopaque) callconv(.C) c_int {
    const btn: ButtonType = switch (event.f_keyval) {
        gdk.KEY_p => .Prev,
        gdk.KEY_k => .PlayPause,
        gdk.KEY_n => .Next,

        gdk.KEY_h => if (event.f_state.control_mask) .PrevPlayer else .SeekBack,
        gdk.KEY_l => if (event.f_state.control_mask) .NextPlayer else .SeekForward,
        gdk.KEY_H => .Prev,
        gdk.KEY_L => .Next,
        gdk.KEY_Escape, gdk.KEY_q => {
            quit();
            return gtk.false();
        },
        else => return gtk.false(),
    };

    buttons.get(btn).action();
    return gtk.false();
}

fn handle_button_click(_: *gtk.Button, data: *allowzero anyopaque) callconv(.C) void {
    const btn: ButtonType = @enumFromInt(@intFromPtr(data));
    buttons.get(btn).action();
}

fn run_command(args: []const []const u8) void {
    const gpa = std.heap.c_allocator;
    var child = std.process.Child.init(args, gpa);

    child.stdin_behavior = .Ignore;
    child.stdout_behavior = .Ignore;
    child.stderr_behavior = .Ignore;

    _ = child.spawnAndWait() catch |err| {
        std.log.err("failed to run command: {s}", .{@errorName(err)});
    };
}

fn quit() void {
    app.as(gio.Application).quit();
}

const PlayerMgr = struct {
    mgr: *c.PlayerctlPlayerManager,
    player: ?Player,

    const Daemon = struct {
        conn: *gio.DBusConnection,

        const bus_name = "org.mpris.MediaPlayer2.playerctld";
        const object_path = "/org/mpris/MediaPlayer2";
        const interface_name = "com.github.altdesktop.playerctld";

        pub fn connect() ?Daemon {
            var err: ?*glib.Error = null;
            const addr_maybe = gio.dbusAddressGetForBusSync(.session, null, &err);
            if (err) |e| {
                std.log.err("failed to get dbus address: {} {s}", .{ e.*.f_code, e.*.f_message orelse "" });
                return null;
            }
            const addr = addr_maybe orelse return null;
            defer glib.free(addr);
            err = null;
            const conn_maybe = gio.DBusConnection.newForAddressSync(
                addr,
                .{
                    .authentication_client = true,
                    .message_bus_connection = true,
                },
                null,
                null,
                &err,
            );
            if (err) |e| {
                std.log.err("failed to create dbus connection: {} {s}", .{ e.*.f_code, e.*.f_message orelse "" });
                return null;
            }
            const conn = conn_maybe orelse return null;
            return Daemon{ .conn = conn };
        }
        pub fn shift(self: Daemon) void {
            var err: ?*glib.Error = null;
            _ = self.conn.callSync(
                bus_name,
                object_path,
                interface_name,
                "Shift",
                null,
                null,
                .flags_no_auto_start,
                -1,
                null,
                &err,
            );
            if (err) |e| {
                std.log.err("failed to shift: {} {s}", .{ e.*.f_code, e.*.f_message orelse "" });
                return;
            }
        }
        pub fn unshift(self: Daemon) void {
            var err: ?*glib.Error = null;
            _ = self.conn.callSync(
                bus_name,
                object_path,
                interface_name,
                "Unshift",
                null,
                null,
                .flags_no_auto_start,
                -1,
                null,
                &err,
            );
            if (err) |e| {
                std.log.err("failed to unshift: {} {s}", .{ e.*.f_code, e.*.f_message orelse "" });
                return;
            }
        }
        pub fn close(self: Daemon) void {
            self.conn.as(g.Object).unref();
        }
    };

    const Player = struct {
        plr: *c.PlayerctlPlayer,
        length: u64 = 0,

        const Metadata = struct {
            length: u64 = 0,

            pub fn init(plr: *c.PlayerctlPlayer) ?Metadata {
                var err: ?*glib.Error = null;
                const res = c.playerctl_player_print_metadata_prop(plr, null, &err);
                defer c.g_free(res);
                if (err) |e| {
                    std.log.err("failed to get metadata: {} {s}", .{ e.*.f_code, e.*.f_message orelse "" });
                    return null;
                }
                var self: Metadata = .{};
                const data: []const u8 = std.mem.span(res orelse return null);
                var lines = std.mem.splitScalar(u8, data, '\n');
                while (lines.next()) |line| {
                    const player_end = std.mem.indexOfScalar(u8, line, ' ') orelse continue;
                    var rem = line[player_end + 1 ..];
                    const key_end = std.mem.indexOfScalar(u8, rem, ' ') orelse continue;
                    const key = rem[0..key_end];
                    rem = rem[key_end..];
                    const val = std.mem.trimLeft(u8, rem, " ");

                    if (std.mem.eql(u8, key, "mpris:length")) {
                        self.length = std.fmt.parseInt(u64, val, 10) catch continue;
                    }

                    // std.log.info("{s} = {s}", .{ key, val });
                }

                return self;
            }
        };

        const Status = enum(u2) {
            Playing = c.PLAYERCTL_PLAYBACK_STATUS_PLAYING,
            Paused = c.PLAYERCTL_PLAYBACK_STATUS_PAUSED,
            Stopped = c.PLAYERCTL_PLAYBACK_STATUS_STOPPED,

            fn label(self: Status) [:0]const u8 {
                return switch (self) {
                    .Playing => "⏸",
                    .Paused, .Stopped => "▶",
                };
            }
        };

        fn init(mgr: *c.PlayerctlPlayerManager) ?Player {
            var available_players: ?*glib.List = null;
            g.Object.get(@ptrCast(mgr), "player-names", &available_players, @as(?*anyopaque, null));
            // defer if (available_players) |players| players.free();

            if (available_players) |player_elem| {
                const player_info: *c.PlayerctlPlayerName = @ptrCast(@alignCast(player_elem.f_data));
                player_label.setText(player_info.name);
                var err: [*c]glib.Error = null;
                const player: ?*c.PlayerctlPlayer = c.playerctl_player_new_from_name(player_info, &err);
                if (err) |e| {
                    std.log.err("failed to create player: {} {s}", .{ e.*.f_code, e.*.f_message orelse "" });
                    return null;
                }

                const p = player orelse return null;
                const metadata = Metadata.init(p) orelse return null;
                _ = g.signalConnectData(@ptrCast(p), "playback-status", @ptrCast(&on_status_changed), null, null, .flags_default);
                _ = g.signalConnectData(@ptrCast(p), "seeked", @ptrCast(&on_seeked), null, null, .flags_default);
                _ = g.signalConnectData(@ptrCast(p), "metadata", @ptrCast(&on_metadata), null, null, .flags_default);

                return .{ .plr = p, .length = metadata.length };
            }
            return null;
        }
        fn update_artist(self: Player) void {
            var err: [*c]glib.Error = null;
            const artist = c.playerctl_player_get_artist(self.plr, &err);
            if (err) |e| {
                std.log.err("failed to get artist: {} {s}", .{ e.*.f_code, e.*.f_message orelse "" });
                return;
            }
            if (artist) |a| {
                artist_label.setText(a);
            }
        }
        fn update_progress(self: Player, pos: ?u64) void {
            if (self.length == 0) return;

            const position: u64 = pos orelse blk: {
                var err: ?*glib.Error = null;
                const res = c.playerctl_player_get_position(self.plr, &err);
                if (err) |e| {
                    std.log.err("failed to get position: {} {s}", .{ e.*.f_code, e.*.f_message orelse "" });
                    return;
                }
                break :blk @intCast(res);
            };

            const f_len: f64 = @floatFromInt(self.length);
            const f_pos: f64 = @floatFromInt(position);
            const frac = f_pos / f_len;
            progress_bar.setFraction(frac);
        }
        fn update_title(self: Player) void {
            var err: [*c]glib.Error = null;
            const title = c.playerctl_player_get_title(self.plr, &err);
            if (err) |e| {
                std.log.err("failed to get title: {} {s}", .{ e.*.f_code, e.*.f_message orelse "" });
                return;
            }
            if (title) |t| {
                title_label.setText(t);
            }
        }
        fn update_status(self: Player) void {
            var cstatus: c.PlayerctlPlaybackStatus = undefined;
            g.Object.get(@ptrCast(self.plr), "playback-status", &cstatus, @as(?*anyopaque, null));
            const status: Status = @enumFromInt(cstatus);
            play_pause_label.setText(status.label());
        }
        fn can_play(self: Player) bool {
            var can_play_val: c.gboolean = c.FALSE;
            c.g_object_get(self.plr, "can-play", &can_play_val, @as(?*anyopaque, null));
            if (can_play_val == c.FALSE)
                std.log.debug("can-play is false, skipping", .{});
            return can_play_val != c.FALSE;
        }
        fn deinit(self: Player) void {
            c.g_object_unref(self.plr);
        }
        fn on_status_changed(plr: *c.PlayerctlPlayer, cstatus: c.PlayerctlPlaybackStatus, _: ?*anyopaque) callconv(.C) void {
            _ = plr;
            const status: Status = @enumFromInt(cstatus);
            play_pause_label.setText(status.label());
        }
        fn on_seeked(plr: *c.PlayerctlPlayer, position: c.gint64, _: ?*anyopaque) callconv(.C) void {
            _ = plr;
            const mgr = global orelse return;
            const self = mgr.player orelse return;
            self.update_progress(@intCast(position));
        }
        fn on_metadata(plr: *c.PlayerctlPlayer, data: [*c]const u8, _: ?*anyopaque) callconv(.C) void {
            const mgr = &(global orelse return);
            const self = &(mgr.player orelse return);
            const metadata = Metadata.init(plr) orelse return;
            self.length = metadata.length;
            self.update_artist();
            self.update_title();
            self.update_progress(null);
            _ = data;
        }
    };

    var global: ?PlayerMgr = null;
    const seek_amount = 5 * std.time.us_per_s;

    pub fn init() !PlayerMgr {
        if (global) |*m| m.deinit();
        global = null;
        const manager: *c.PlayerctlPlayerManager = mgr: {
            var err: [*c]glib.Error = null;
            const mgr = c.playerctl_player_manager_new(&err);
            if (err) |e| {
                std.log.err("failed to create player manager: {} {s}", .{ e.*.f_code, e.*.f_message orelse "" });
                return error.PlayerManager;
            }
            break :mgr @ptrCast(mgr);
        };
        errdefer c.g_object_unref(manager);

        _ = g.signalConnectData(@ptrCast(manager), "name-appeared", @ptrCast(&on_name_appeared), null, null, .flags_default);

        var mgr = PlayerMgr{
            .mgr = manager,
            .player = null,
        };
        mgr.update_all();
        global = mgr;
        _ = glib.timeoutAdd(std.time.ms_per_s / 4, &timeout_update, null);

        return mgr;
    }

    fn on_name_appeared(mgr: *c.PlayerctlPlayerManager, name: *c.PlayerctlPlayerName, _: ?*anyopaque) callconv(.C) void {
        _ = mgr;
        _ = name;
        // std.log.info("Name appeared: {s}", .{name.name});
        // _ = init() catch return;
    }

    fn update_all(self: *PlayerMgr) void {
        if (self.player) |p| p.deinit();
        self.player = null;
        const player = Player.init(self.mgr) orelse return;
        self.player = player;
        player.update_title();
        player.update_artist();
        player.update_status();
        player.update_progress(null);
    }

    fn timeout_update(_: ?*anyopaque) callconv(.C) c_int {
        const repeat = 1;
        const mgr = global orelse return c.FALSE;
        const player = mgr.player orelse return c.FALSE;
        player.update_progress(null);
        return repeat;
    }

    fn action_next() void {
        const mgr = global orelse return;
        const player = mgr.player orelse return;
        if (!player.can_play()) return;
        var err: [*c]glib.Error = null;
        c.playerctl_player_next(player.plr, &err);
        if (err) |e| {
            std.log.err("failed to next: {} {s}", .{ e.*.f_code, e.*.f_message orelse "" });
            return;
        }
    }
    fn action_prev() void {
        const mgr = global orelse return;
        const player = mgr.player orelse return;
        if (!player.can_play()) return;
        var err: [*c]glib.Error = null;
        c.playerctl_player_previous(player.plr, &err);
        if (err) |e| {
            std.log.err("failed to prevois: {} {s}", .{ e.*.f_code, e.*.f_message orelse "" });
            return;
        }
    }
    fn action_play_pause() void {
        const mgr = global orelse return;
        const player = mgr.player orelse return;
        if (!player.can_play()) return;
        var err: [*c]glib.Error = null;
        c.playerctl_player_play_pause(player.plr, &err);
        if (err) |e| {
            std.log.err("failed to play/pause: {} {s}", .{ e.*.f_code, e.*.f_message orelse "" });
            return;
        }
    }
    fn action_prev_player() void {
        const daemon = Daemon.connect() orelse return;
        daemon.unshift();
        daemon.close();
        _ = init() catch return;
    }
    fn action_next_player() void {
        const daemon = Daemon.connect() orelse return;
        daemon.shift();
        daemon.close();
        _ = init() catch return;
    }
    fn action_seek_back() void {
        const mgr = global orelse return;
        const player = mgr.player orelse return;
        if (!player.can_play()) return;
        var err: [*c]glib.Error = null;
        const pos = c.playerctl_player_get_position(player.plr, &err);
        if (err) |e| {
            std.log.err("failed to get position: {} {s}", .{ e.*.f_code, e.*.f_message orelse "" });
            return;
        }
        c.playerctl_player_set_position(player.plr, pos -| seek_amount, &err);
        if (err) |e| {
            std.log.err("failed to set position: {} {s}", .{ e.*.f_code, e.*.f_message orelse "" });
            return;
        }
    }
    fn action_seek_forward() void {
        const mgr = global orelse return;
        const player = mgr.player orelse return;
        if (!player.can_play()) return;
        var err: [*c]glib.Error = null;
        const pos = c.playerctl_player_get_position(player.plr, &err);
        if (err) |e| {
            std.log.err("failed to get position: {} {s}", .{ e.*.f_code, e.*.f_message orelse "" });
            return;
        }
        c.playerctl_player_set_position(player.plr, pos +| seek_amount, &err);
        if (err) |e| {
            std.log.err("failed to set position: {} {s}", .{ e.*.f_code, e.*.f_message orelse "" });
            return;
        }
    }

    pub fn deinit(self: *PlayerMgr) void {
        if (self.player) |p| {
            p.deinit();
        }
        c.g_object_unref(self.mgr);
    }
};
