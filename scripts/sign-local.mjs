#!/usr/bin/env node
// sign-local.mjs —— local product unsigned hap 手动签名(绕开 hvigor SignHap 加密密码体系)
// 用法: node scripts/sign-local.mjs [--install [hdc-target]]
import { readFileSync, readdirSync, existsSync, statSync } from 'node:fs';
import { execFileSync } from 'node:child_process';
import path from 'node:path';
import os from 'node:os';

const ROOT = path.resolve(path.dirname(new URL(import.meta.url).pathname), '..');
const args = process.argv.slice(2);
const installIdx = args.indexOf('--install');
const doInstall = installIdx >= 0;
const target = doInstall && args[installIdx + 1] ? args[installIdx + 1] : '';

const outputs = path.join(ROOT, 'entry/build/local/outputs/default');
const unsigned = (() => {
  const files = readdirSync(outputs).filter((f) => f.includes('unsigned') && f.endsWith('.hap'));
  files.sort((a, b) => statSync(path.join(outputs, b)).mtimeMs - statSync(path.join(outputs, a)).mtimeMs);
  return files[0] ? path.join(outputs, files[0]) : '';
})();
if (!unsigned) { console.error('未见 unsigned hap'); process.exit(1); }
const out = unsigned.replace('unsigned', 'signed');

const bp = readFileSync(path.join(ROOT, 'build-profile.json5'), 'utf8');
const seg = bp.match(/"name":\s*"default",[\s\S]*?"material":\s*\{([\s\S]*?)\}/)?.[1] || '';
const g = (k) => { const m = seg.match(new RegExp('"' + k + '"\\s*:\\s*"([^"]+)"')); return m ? m[1] : ''; };
const conf = {
  certpath: g('certpath'), profile: g('profile'), keyAlias: g('keyAlias'),
  keyPassword: g('keyPassword'), storeFile: g('storeFile'),
  storePassword: g('storePassword'), signAlg: g('signAlg')
};
if (!conf.storeFile) { console.error('build-profile default material 读取失败'); process.exit(1); }

const JBR = process.env.JBR || '/Applications/DevEco-Studio.app/Contents/jbr/Contents/Home/bin/java';
const JAR = process.env.JAR || '/Applications/DevEco-Studio.app/Contents/sdk/default/openharmony/toolchains/lib/hap-sign-tool.jar';
console.log('==> 签名:', path.basename(unsigned));
execFileSync(JBR, ['-jar', JAR, 'sign-app', '-mode', 'localSign',
  '-keyAlias', conf.keyAlias, '-keyPwd', conf.keyPassword,
  '-appCertFile', conf.certpath, '-profileFile', conf.profile, '-profileSigned', '1',
  '-inFile', unsigned, '-signAlg', conf.signAlg,
  '-keystoreFile', conf.storeFile, '-keystorePwd', conf.storePassword,
  '-outFile', out], { stdio: 'inherit' });
console.log('==> 签名产物:', out);

if (doInstall) {
  const hdc = process.env.HDC || path.join(os.homedir(), '.harmony/command-line-tools-mac26/sdk/default/openharmony/toolchains/hdc');
  const base = [hdc];
  if (target) base.push('-t', target);
  console.log('==> 安装到手机');
  execFileSync(hdc, [...(target ? ['-t', target] : []), 'install', '-r', out], { stdio: 'inherit' });
  execFileSync(hdc, [...(target ? ['-t', target] : []), 'shell', 'aa', 'start', '-a', 'EntryAbility', '-b', 'com.dsh.lite'], { stdio: 'inherit' });
}
