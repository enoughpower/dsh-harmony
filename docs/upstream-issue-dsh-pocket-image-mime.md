# 上游意见 · dsh-pocket 图片拖拽格式不支持 HEIC/空 MIME

- **目标仓库**: https://github.com/deepseek-ai/deepseek-harness (issues 已禁用,走其他渠道)
- **记录日期**: 2026-08-28
- **状态**: 待反馈(issues disabled)
- **标题**: Image attachments reject HEIC / empty MIME on drop (only PNG/JPG/WebP/GIF supported)

## 问题
从手机相册把图片**拖到对话输入框**时,提示"图片格式不对 / Only PNG, JPG, WebP, and GIF images are supported",无法上传。

## 环境
- HarmonyOS 手机(相册原生拖拽)
- dsh-pocket Web 客户端(对话 composer 的附件拖拽)

## 根因
`packages/client/ui-conversation/src/client/service.ts` 的 `imageMediaType()` 只放行:
```ts
case 'image/png': case 'image/jpeg': case 'image/webp': case 'image/gif':
```
其它类型(如 `image/heic`、`image/bmp`,或**原生拖拽时空的 `File.type`**)一律 `throw UnsupportedImageMediaTypeError`,对应提示文案在 `locales.ts` 的 `image.unsupportedType`。

且 `encodeImage()` 只是把原始字节 base64 提交,**没有做格式归一化**——即使把 HEIC 加进白名单,浏览器/模型也解码不了 HEIC。

## 复现
1. 打开对话,拖一张手机相册里 HEIC(或系统给 `type=''` 的 JPEG/PNG)的图片到 composer。
2. 触发 `image.unsupportedType` 提示,附件无法加入。

## 建议
1. **客户端归一化**:在 `encodeImage()` 前,对非白名单文件用 `Image` + `<canvas>.toBlob('image/png')` 解码并转成 PNG。
2. **HEIC**:浏览器 canvas 原生解不了 HEIC;引入 `heic2any` 或至少检测到 HEIC 给明确提示。
3. 平台侧(如 HarmonyOS 套壳 Web)尽可能先转 JPEG 再注入。

## 相关位置
- `packages/client/ui-conversation/src/client/service.ts` → `imageMediaType()` / `encodeImage()`
- `packages/client/ui-conversation/src/client/locales.ts` → `image.unsupportedType`
- `packages/client/ui-attachment/src/client/ComposerAttachments.tsx` → `onDrop`
