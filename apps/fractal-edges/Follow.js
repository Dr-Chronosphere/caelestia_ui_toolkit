.pragma library

// Keeping icon cards on their windows while Hyprland animates them (zoom, reflow) or slides a
// workspace. Pure helpers, no Quickshell.

// Rects of every window from `hyprctl clients -j`: { address: { x, y, w, h, workspace } }.
// While a window animates, hyprctl reports its CURRENT (animated) position and size.
function rectsByAddress(clientsText) {
    var list;
    try {
        list = JSON.parse(clientsText);
    } catch (e) {
        return {};
    }
    var out = {};
    if (!Array.isArray(list))
        return out;
    list.forEach(function (c) {
        if (c && c.address && c.at && c.size && c.mapped !== false)
            out[c.address] = { x: c.at[0], y: c.at[1], w: c.size[0], h: c.size[1], workspace: c.workspace ? c.workspace.id : 0 };
    });
    return out;
}

// The card that covers a window currently at `live`: the window's rect grown by `pad` px (the
// same relation the card has to a settled window, measured by Seams.measureInsets).
function cardFromLive(live, pad) {
    return { x: live.x - pad, y: live.y - pad, w: Math.max(1, live.w + 2 * pad), h: Math.max(1, live.h + 2 * pad) };
}

function sameRect(a, b, eps) {
    eps = eps === undefined ? 2 : eps;
    return Math.abs(a.x - b.x) <= eps && Math.abs(a.y - b.y) <= eps && Math.abs(a.w - b.w) <= eps && Math.abs(a.h - b.h) <= eps;
}

// Is any card away from where its window is right now (so a transition is under way)?
// cards: [{ address, x, y, w, h }] at their settled geometry; rects: rectsByAddress().
function transitioning(cards, rects, pad, eps) {
    for (var i = 0; i < cards.length; i++) {
        var live = rects[cards[i].address];
        if (live && !sameRect(cardFromLive(live, pad), cards[i], eps === undefined ? 3 : eps))
            return true;
    }
    return false;
}

// Workspace animation from `hyprctl animations -j`: { ms, style } or null if workspace animations
// are off / unreadable. Hyprland's speed is in units of 100 ms.
function parseWorkspaceAnim(text) {
    var o;
    try {
        o = JSON.parse(text);
    } catch (e) {
        return null;
    }
    var list = Array.isArray(o) && Array.isArray(o[0]) ? o[0] : (Array.isArray(o) ? o : []);
    var byName = {};
    list.forEach(function (a) { if (a && a.name) byName[a.name] = a; });
    var a = byName.workspaces || byName.workspacesIn || byName.workspacesOut;
    if (!a || a.enabled === false || !(a.speed > 0))
        return null;
    var g = byName.global;
    if (a.overridden === false && g && g.enabled === false)
        return null;
    return { ms: Math.round(a.speed * 100), style: String(a.style || "slide") };
}

// Slide offset of a workspace's cards at progress t (0..1). `dir` is +1 when going to a higher
// workspace (the old one leaves to the left, the new one enters from the right), -1 the other way.
// `incoming` selects the new workspace's cards (they start offset and arrive at 0), else the old
// one's (they start at 0 and leave). Styles: "slide" (horizontal), "slidevert" (vertical); anything
// else (fade, popin, ...) does not move.
function slideOffset(dir, style, incoming, t, width, height) {
    var s = String(style || "slide");
    var vertical = s.indexOf("vert") >= 0;
    if (s.indexOf("slide") !== 0)
        return { x: 0, y: 0 };
    var span = vertical ? height : width;
    var d = incoming ? dir * span * (1 - t) : -dir * span * t;
    return vertical ? { x: 0, y: d } : { x: d, y: 0 };
}
