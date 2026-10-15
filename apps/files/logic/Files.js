.pragma library

// Pure helpers for the file manager (no Qt/Quickshell dependency, unit-testable).

// --- Paths & URLs -----------------------------------------------------------

function toUrl(path) {
    return "file://" + path.split("/").map(encodeURIComponent).join("/");
}

function toPath(url) {
    return decodeURIComponent(String(url).replace(/^file:\/\//, ""));
}

function parentOf(path) {
    if (path === "/" || path === "")
        return "/";
    const p = path.replace(/\/+$/, "");
    const i = p.lastIndexOf("/");
    return i <= 0 ? "/" : p.slice(0, i);
}

function baseName(path) {
    if (path === "/")
        return "/";
    const p = path.replace(/\/+$/, "");
    return p.slice(p.lastIndexOf("/") + 1);
}

function join(dir, name) {
    return dir === "/" ? "/" + name : dir.replace(/\/+$/, "") + "/" + name;
}

// Breadcrumb segments for `path`. Inside `home` the first crumb is "Home".
function breadcrumb(path, home) {
    const crumbs = [];
    let base, rest;
    if (home && (path === home || path.startsWith(home + "/"))) {
        crumbs.push({ label: "Home", path: home });
        base = home;
        rest = path.slice(home.length);
    } else {
        crumbs.push({ label: "/", path: "/" });
        base = "";
        rest = path === "/" ? "" : path;
    }
    let acc = base;
    for (const part of rest.split("/").filter(s => s.length > 0)) {
        acc = acc + "/" + part;
        crumbs.push({ label: part, path: acc });
    }
    return crumbs;
}

// --- Kinds ------------------------------------------------------------------

const IMAGE = ["png", "jpg", "jpeg", "gif", "webp", "bmp", "svg", "avif"];
const KINDS = {
    image: { icon: "image", label: "Image", exts: IMAGE },
    video: { icon: "movie", label: "Video", exts: ["mp4", "mkv", "webm", "mov", "avi"] },
    audio: { icon: "music_note", label: "Audio", exts: ["mp3", "flac", "ogg", "opus", "wav", "m4a"] },
    pdf: { icon: "picture_as_pdf", label: "PDF", exts: ["pdf"] },
    archive: { icon: "folder_zip", label: "Archive", exts: ["zip", "tar", "gz", "xz", "zst", "7z", "rar", "bz2"] },
    code: { icon: "code", label: "Source", exts: ["js", "ts", "qml", "py", "rs", "c", "cpp", "h", "hpp", "go", "java", "sh", "json", "toml", "yaml", "yml", "html", "css", "lua", "nix"] },
    text: { icon: "description", label: "Text", exts: ["txt", "md", "log", "rst", "conf", "ini"] },
    doc: { icon: "article", label: "Document", exts: ["doc", "docx", "odt", "ppt", "pptx", "odp", "xls", "xlsx", "ods", "csv"] }
};

function extOf(name) {
    const i = name.lastIndexOf(".");
    return i <= 0 ? "" : name.slice(i + 1).toLowerCase();
}

function kindOf(name, isDir) {
    if (isDir)
        return { key: "folder", icon: "folder", label: "Folder" };
    const ext = extOf(name);
    for (const key of Object.keys(KINDS)) {
        if (KINDS[key].exts.includes(ext))
            return { key, icon: KINDS[key].icon, label: KINDS[key].label };
    }
    return { key: "file", icon: "draft", label: ext ? ext.toUpperCase() + " file" : "File" };
}

function isImage(name) {
    return IMAGE.includes(extOf(name));
}

// --- Formatting ---------------------------------------------------------------

function humanSize(bytes) {
    if (bytes < 1000)
        return `${bytes} B`;
    const units = ["kB", "MB", "GB", "TB"];
    let v = bytes, i = -1;
    do {
        v /= 1000;
        i++;
    } while (v >= 1000 && i < units.length - 1);
    return `${v >= 100 ? Math.round(v) : v.toFixed(1)} ${units[i]}`;
}

function plural(n, one, many) {
    return `${n} ${n === 1 ? one : many}`;
}

// --- Places -------------------------------------------------------------------

const PLACES = [
    { label: "Home", dir: "", icon: "home" },
    { label: "Desktop", dir: "Desktop", icon: "desktop_windows" },
    { label: "Documents", dir: "Documents", icon: "description" },
    { label: "Downloads", dir: "Downloads", icon: "download" },
    { label: "Pictures", dir: "Pictures", icon: "image" },
    { label: "Music", dir: "Music", icon: "music_note" },
    { label: "Videos", dir: "Videos", icon: "movie" }
];

// Standard places that exist, given the directory names found in `home`.
function places(home, homeDirNames) {
    return PLACES.filter(p => p.dir === "" || homeDirNames.includes(p.dir))
        .map(p => ({ label: p.label, icon: p.icon, path: p.dir === "" ? home : join(home, p.dir) }));
}
