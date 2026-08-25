#!/usr/bin/env node
// encrypt-pwd.mjs —— 用 material 组件把明文密码加密成 hvigor DecipherUtil 可解的密文
// 用法: node scripts/encrypt-pwd.mjs <materialDir> <明文密码>
import { readFileSync, readdirSync, existsSync, statSync } from 'node:fs';
import { createCipheriv, pbkdf2Sync, createDecipheriv, randomBytes } from 'node:crypto';
import path from 'node:path';

const materialDir = process.argv[2];
const plain = process.argv[3];
if (!materialDir || !plain) { console.error('用法: encrypt-pwd.mjs <materialDir含material/> <明文>'); process.exit(1); }
const COMPONENT = Buffer.from([49,243,9,115,214,175,91,184,211,190,177,88,101,131,192,119]);

function readOne(p) {
  const files = readdirSync(p).filter((f) => f !== '.DS_Store');
  if (files.length !== 1) throw new Error('expected 1 file in ' + p);
  return readFileSync(path.join(p, files[0]));
}
function xorAll(bufs, targetLen) {
  let acc = Buffer.alloc(targetLen);
  for (const b of bufs) {
    if (b.length !== targetLen) throw new Error('component length mismatch');
    for (let i = 0; i < targetLen; i++) acc[i] ^= b[i];
  }
  return acc;
}
function gcmDecrypt(key, data) {
  const len = data.readUInt32BE(0);
  const ivLen = data.length - 4 - len;
  const iv = data.subarray(4, 4 + ivLen);
  const tag = data.subarray(data.length - 16);
  const d = createDecipheriv('aes-128-gcm', key, iv);
  d.setAuthTag(tag);
  return Buffer.concat([d.update(data.subarray(4 + ivLen, data.length - 16)), d.final()]);
}
function gcmEncrypt(key, iv, plaintext) {
  const c = createCipheriv('aes-128-gcm', key, iv);
  const enc = c.update(plaintext, 'utf8');
  c.final();
  const tag = c.getAuthTag();
  const out = Buffer.alloc(4 + iv.length + enc.length + 16);
  out.writeUInt32BE(out.length - 4 - iv.length, 0);
  iv.copy(out, 4);
  enc.copy(out, 4 + iv.length);
  tag.copy(out, 4 + iv.length + enc.length);
  return out;
}

const mroot = path.join(materialDir, 'material');
const fdDir = path.join(mroot, 'fd');
const acFile = path.join(mroot, 'ac');
const ceFile = path.join(mroot, 'ce');
const fdFiles = readdirSync(fdDir).filter((f) => f !== '.DS_Store');
const fdParts = fdFiles.map((f) => readOne(path.join(fdDir, f)));
const salt = readOne(acFile);
// rootKey = pbkdf2(xor(fd组件 + COMPONENT), salt, 10000, 16)
const xorBuf = xorAll([...fdParts, COMPONENT], fdParts[0].length);
const rootKey = pbkdf2Sync(xorBuf.toString(), salt, 10000, 16, 'sha256');
// workKey = gcm-decrypt(rootKey, workMaterial)
const workMaterial = readOne(ceFile);
const workKey = gcmDecrypt(rootKey, workMaterial);
// 加密明文
const iv = randomBytes(12);
const hex = gcmEncrypt(workKey, iv, plain).toString('hex');
console.log(hex);
