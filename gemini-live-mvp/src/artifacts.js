import fs from 'fs';
import path from 'path';

export class ArtifactManager {
  constructor(artifactsDir) {
    this.artifactsDir = artifactsDir;
    this.backupsDir = path.join(artifactsDir, 'backups');

    // Ensure directories exist
    if (!fs.existsSync(this.artifactsDir)) {
      fs.mkdirSync(this.artifactsDir);
    }
    if (!fs.existsSync(this.backupsDir)) {
      fs.mkdirSync(this.backupsDir);
    }
  }

  atomicWrite(fileName, content) {
    const filePath = path.join(this.artifactsDir, fileName);
    const timestamp = new Date().toISOString().replace(/[:.]/g, '-');

    // Create backup if file exists
    if (fs.existsSync(filePath)) {
      const backupPath = path.join(this.backupsDir, `${fileName}.${timestamp}.backup`);
      fs.copyFileSync(filePath, backupPath);
      console.log(`   📦 Backup created: ${path.basename(backupPath)}`);
    }

    // Write to temp file first
    const tempPath = `${filePath}.tmp`;
    fs.writeFileSync(tempPath, content);

    // Atomic rename
    fs.renameSync(tempPath, filePath);

    console.log(`   ✅ Wrote ${content.length} chars to ${fileName}`);
    return true;
  }

  read(fileName) {
    const filePath = path.join(this.artifactsDir, fileName);

    if (fs.existsSync(filePath)) {
      return fs.readFileSync(filePath, 'utf-8');
    }

    throw new Error(`File not found: ${fileName}`);
  }

  exists(fileName) {
    const filePath = path.join(this.artifactsDir, fileName);
    return fs.existsSync(filePath);
  }
}