import { readFile, writeFile } from 'fs/promises';
import { existsSync, mkdirSync } from 'fs';
import { dirname } from 'path';
import { lock } from 'proper-lockfile';

export class FileStore {
  constructor(inboxPath, locksPath) {
    this.inboxPath = inboxPath;
    this.locksPath = locksPath;
    this._ensureDir(inboxPath);
  }

  _ensureDir(filePath) {
    const dir = dirname(filePath);
    if (!existsSync(dir)) mkdirSync(dir, { recursive: true });
  }

  async withLock(filePath, fn) {
    this._ensureDir(filePath);
    if (!existsSync(filePath)) {
      await writeFile(filePath, '{}', 'utf8');
    }
    const release = await lock(filePath, { retries: { retries: 5, minTimeout: 200 }, stale: 10000 });
    try {
      return await fn();
    } finally {
      await release();
    }
  }

  async readInbox() {
    if (!existsSync(this.inboxPath)) {
      return { version: '1.0', updated_at: new Date().toISOString(), routes: [] };
    }
    const raw = await readFile(this.inboxPath, 'utf8');
    try {
      return JSON.parse(raw);
    } catch {
      return { version: '1.0', updated_at: new Date().toISOString(), routes: [] };
    }
  }

  async writeInbox(data) {
    data.updated_at = new Date().toISOString();
    await writeFile(this.inboxPath, JSON.stringify(data, null, 2), 'utf8');
  }

  async readLocks() {
    if (!existsSync(this.locksPath)) return null;
    const raw = await readFile(this.locksPath, 'utf8');
    return JSON.parse(raw.replace(/^\uFEFF/, ''));
  }

  async writeLocks(data) {
    data.updated_at = new Date().toISOString();
    const bom = '\uFEFF';
    await writeFile(this.locksPath, bom + JSON.stringify(data, null, 4), 'utf8');
  }
}
