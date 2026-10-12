// Folder handle for music/, remembered in IndexedDB the same way the
// Quake64 and SquareDoom editors remember their project file.

const HANDLE_DB = "wolf64-music-editor";
const HANDLE_STORE = "handles";
const HANDLE_KEY = "music";

function openDb() {
  return new Promise((resolve, reject) => {
    const req = indexedDB.open(HANDLE_DB, 1);
    req.onupgradeneeded = () => {
      const db = req.result;
      if (!db.objectStoreNames.contains(HANDLE_STORE)) db.createObjectStore(HANDLE_STORE);
    };
    req.onsuccess = () => resolve(req.result);
    req.onerror = () => reject(req.error);
  });
}

async function idbPut(key, value) {
  const db = await openDb();
  await new Promise((resolve, reject) => {
    const tx = db.transaction(HANDLE_STORE, "readwrite");
    tx.objectStore(HANDLE_STORE).put(value, key);
    tx.oncomplete = () => resolve();
    tx.onerror = () => reject(tx.error);
  });
  db.close();
}

async function idbGet(key) {
  const db = await openDb();
  const value = await new Promise((resolve, reject) => {
    const tx = db.transaction(HANDLE_STORE, "readonly");
    const req = tx.objectStore(HANDLE_STORE).get(key);
    req.onsuccess = () => resolve(req.result || null);
    req.onerror = () => reject(req.error);
  });
  db.close();
  return value;
}

async function ensurePermission(handle) {
  if (!handle.queryPermission) return true;
  const opts = { mode: "readwrite" };
  if ((await handle.queryPermission(opts)) === "granted") return true;
  return (await handle.requestPermission(opts)) === "granted";
}

async function storeMusicHandle(handle) {
  await idbPut(HANDLE_KEY, handle);
}

async function loadMusicHandle() {
  try {
    return await idbGet(HANDLE_KEY);
  } catch (err) {
    return null;
  }
}

async function readFile(handle) {
  const file = await handle.getFile();
  return new Uint8Array(await file.arrayBuffer());
}

async function writeFile(dir, name, bytes) {
  const handle = await dir.getFileHandle(name, { create: true });
  const writable = await handle.createWritable();
  await writable.write(bytes);
  await writable.close();
}

async function listMusic(dir) {
  const mids = [];
  const sids = [];
  for await (const [name, handle] of dir.entries()) {
    if (handle.kind !== "file") continue;
    if (/\.mid$/i.test(name)) mids.push(name);
    else if (/\.sid$/i.test(name)) sids.push(name);
  }
  mids.sort((a, b) => a.localeCompare(b));
  sids.sort((a, b) => a.localeCompare(b));
  return { mids, sids };
}
