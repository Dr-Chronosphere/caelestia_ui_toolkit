.pragma library

// Tab bookkeeping for the file manager. Pure functions over a window record
// { tabs: [tabId...], active: tabId } so they can be unit-tested without QML. Tab *content*
// (path, history, view mode) lives in a separate map keyed by tab id, so a tab can move to
// another window without being recreated from scratch.

var _n = 0;
function newId() {
    _n++;
    return "t" + _n;
}

function make(tabs, active) {
    return { tabs: tabs.slice(), active: active === undefined ? (tabs.length ? tabs[0] : "") : active };
}

// Insert `id` right after the active tab (like a browser) and activate it.
function open(win, id) {
    var i = win.tabs.indexOf(win.active);
    var tabs = win.tabs.slice();
    tabs.splice(i < 0 ? tabs.length : i + 1, 0, id);
    return { tabs: tabs, active: id };
}

// Remove `id`. If it was active, the tab that slides into its place (its right neighbour, else
// its left one) becomes active. active is "" when no tabs are left.
function close(win, id) {
    var i = win.tabs.indexOf(id);
    if (i < 0)
        return win;
    var tabs = win.tabs.slice();
    tabs.splice(i, 1);
    var active = win.active;
    if (id === win.active)
        active = tabs.length ? tabs[Math.min(i, tabs.length - 1)] : "";
    return { tabs: tabs, active: active };
}

function activate(win, id) {
    return win.tabs.indexOf(id) < 0 ? win : { tabs: win.tabs, active: id };
}

// Next (dir = 1) or previous (dir = -1) tab, wrapping.
function cycle(win, dir) {
    if (win.tabs.length < 2)
        return win;
    var i = win.tabs.indexOf(win.active);
    var j = (i + dir + win.tabs.length) % win.tabs.length;
    return { tabs: win.tabs, active: win.tabs[j] };
}

// Move `id` to index `to` (clamped).
function move(win, id, to) {
    var i = win.tabs.indexOf(id);
    if (i < 0)
        return win;
    var tabs = win.tabs.slice();
    tabs.splice(i, 1);
    tabs.splice(Math.max(0, Math.min(to, tabs.length)), 0, id);
    return { tabs: tabs, active: win.active };
}

// Fold `source` into `target`: its tabs are appended and its active tab becomes active.
function merge(target, source) {
    var tabs = target.tabs.slice();
    source.tabs.forEach(function (t) {
        if (tabs.indexOf(t) < 0)
            tabs.push(t);
    });
    return { tabs: tabs, active: source.active || target.active };
}

function baseName(p) {
    if (p === "/")
        return "/";
    var parts = String(p).split("/").filter(function (s) { return s.length > 0; });
    return parts.length ? parts[parts.length - 1] : "/";
}

function parentName(p) {
    var parts = String(p).split("/").filter(function (s) { return s.length > 0; });
    return parts.length > 1 ? parts[parts.length - 2] : "/";
}

// Tab titles for [{ id, path }]: the folder name ("Home" for $HOME), with the parent folder added
// when two tabs would otherwise read the same ("src — project").
function labels(entries, home) {
    var base = entries.map(function (e) {
        return e.path === home ? "Home" : baseName(e.path);
    });
    return entries.map(function (e, i) {
        var dup = base.some(function (b, j) { return j !== i && b === base[i]; });
        var label = base[i];
        if (dup && e.path !== home && e.path !== "/")
            label += " — " + parentName(e.path);
        return { id: e.id, label: label };
    });
}
