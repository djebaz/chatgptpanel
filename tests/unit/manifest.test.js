import { describe, it } from 'node:test';
import assert from 'node:assert';
import fs from 'node:fs';
import path from 'node:path';

describe('Manifest Validation', () => {
  const manifestPath = path.resolve('src/manifest.json');
  const manifest = JSON.parse(fs.readFileSync(manifestPath, 'utf8'));

  it('should have basic metadata', () => {
    assert.strictEqual(manifest.manifest_version, 3, 'Must use Manifest V3');
    assert.ok(manifest.name, 'Manifest must have a name');
    assert.ok(manifest.version, 'Manifest must have a version');
    assert.ok(manifest.description, 'Manifest must have a description');
  });

  it('should have correctly configured background service worker', () => {
    assert.ok(manifest.background, 'Manifest must have a background section');
    assert.ok(manifest.background.service_worker, 'Background must have a service_worker');
    
    const workerPath = path.resolve('src', manifest.background.service_worker);
    assert.ok(fs.existsSync(workerPath), `Service worker file not found: ${workerPath}`);
  });

  it('should not have excessive permissions', () => {
    const allowedPermissions = ['storage', 'sidePanel', 'declarativeNetRequest', 'declarativeNetRequestFeedback', 'tabs']; 
    const permissions = manifest.permissions || [];
    
    permissions.forEach(perm => {
      assert.ok(allowedPermissions.includes(perm), `Unexpected permission found: ${perm}`);
    });
  });

  it('should have valid icons that exist on disk', () => {
    const icons = manifest.icons || {};
    const actionIcons = (manifest.action && manifest.action.default_icon) || {};
    
    const allIcons = { ...icons, ...actionIcons };
    assert.ok(Object.keys(allIcons).length > 0, 'Manifest should define at least one icon');

    Object.entries(allIcons).forEach(([size, iconPath]) => {
      const fullPath = path.resolve('src', iconPath);
      assert.ok(fs.existsSync(fullPath), `Icon file (size ${size}) not found: ${fullPath}`);
    });
  });

  it('should define a default_popup', () => {
    assert.strictEqual(manifest.action.default_popup, 'popup.html', 'Should define popup.html as default_popup');
  });
});
