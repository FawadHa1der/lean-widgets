#!/usr/bin/env node
// fake-s3.mjs — a tiny LOCAL S3-compatible endpoint that records what an uploader sends (no account, no network
// beyond 127.0.0.1). Used by the deploy rehearsal to see which Content-Type rclone's s3 backend (provider=Cloudflare)
// actually puts on each object, for both single-part PutObject and multipart CreateMultipartUpload.
//
//   node scripts/deploy-rehearsal/fake-s3.mjs <port> <log.jsonl>
//
// Implements just enough of the API for `rclone copy/copyto`: ListObjects(V2) (empty or what was stored),
// HeadObject, PutObject, CreateMultipartUpload, UploadPart, CompleteMultipartUpload, AbortMultipartUpload.
// Bodies are counted and discarded; each object's recorded metadata is {key, size, contentType, multipart, meta}.
import http from 'node:http';
import fs from 'node:fs';
import { createHash, randomUUID } from 'node:crypto';

const [port = '9799', logPath = 'fake-s3.jsonl'] = process.argv.slice(2);
const objects = new Map(); const uploads = new Map();
const log = (o) => fs.appendFileSync(logPath, JSON.stringify(o) + '\n');
const xml = (res, body, status = 200) => { res.writeHead(status, { 'content-type': 'application/xml' }); res.end(`<?xml version="1.0" encoding="UTF-8"?>${body}`); };
const esc = (s) => s.replace(/&/g, '&amp;').replace(/</g, '&lt;');
const metaOf = (h) => Object.fromEntries(Object.entries(h).filter(([k]) => k.startsWith('x-amz-meta-')));

http.createServer((req, res) => {
  const u = new URL(req.url, 'http://x'); const parts = u.pathname.slice(1).split('/');
  const bucket = decodeURIComponent(parts.shift() || ''); const key = parts.map(decodeURIComponent).join('/');
  const chunks = []; let n = 0; const h = createHash('md5');
  req.on('data', (c) => { n += c.length; h.update(c); if (req.method === 'POST') chunks.push(c); });
  req.on('end', () => {
    const q = u.searchParams;
    if (req.method === 'GET' && !key) {   // ListObjects / ListObjectsV2
      const prefix = q.get('prefix') || ''; const delim = q.get('delimiter') || '';
      const all = [...objects.values()].filter((o) => o.bucket === bucket && o.key.startsWith(prefix));
      const items = delim ? all.filter((o) => !o.key.slice(prefix.length).includes(delim)) : all;
      const dirs = delim ? [...new Set(all.map((o) => o.key.slice(prefix.length)).filter((r) => r.includes(delim)).map((r) => prefix + r.slice(0, r.indexOf(delim) + 1)))] : [];
      return xml(res, `<ListBucketResult><Name>${esc(bucket)}</Name><Prefix>${esc(prefix)}</Prefix><KeyCount>${items.length + dirs.length}</KeyCount><MaxKeys>100000</MaxKeys><IsTruncated>false</IsTruncated>${
        items.map((o) => `<Contents><Key>${esc(o.key)}</Key><LastModified>2026-10-01T00:00:00.000Z</LastModified><ETag>"${o.etag}"</ETag><Size>${o.size}</Size><StorageClass>STANDARD</StorageClass></Contents>`).join('')}${
        dirs.map((d) => `<CommonPrefixes><Prefix>${esc(d)}</Prefix></CommonPrefixes>`).join('')}</ListBucketResult>`);
    }
    if (req.method === 'HEAD' && !key) { res.writeHead(200); return res.end(); }
    if (req.method === 'HEAD' || (req.method === 'GET' && key)) {
      const o = objects.get(`${bucket}/${key}`);
      if (!o) { res.writeHead(404); return res.end(); }
      res.writeHead(200, { 'content-length': o.size, 'content-type': o.contentType, etag: `"${o.etag}"`, 'last-modified': 'Wed, 01 Oct 2026 00:00:00 GMT', ...o.meta });
      return res.end();
    }
    if (req.method === 'PUT' && q.has('uploadId')) {   // UploadPart
      const up = uploads.get(q.get('uploadId')); up.size += n; up.parts++;
      res.writeHead(200, { etag: `"${h.digest('hex')}"` }); return res.end();
    }
    if (req.method === 'PUT') {   // PutObject
      const o = { bucket, key, size: n, etag: h.digest('hex'), contentType: req.headers['content-type'] || null, multipart: false, meta: metaOf(req.headers) };
      objects.set(`${bucket}/${key}`, o); log({ op: 'PutObject', key, size: n, contentType: o.contentType, meta: o.meta });
      res.writeHead(200, { etag: `"${o.etag}"` }); return res.end();
    }
    if (req.method === 'POST' && q.has('uploads')) {   // CreateMultipartUpload
      const id = randomUUID();
      uploads.set(id, { bucket, key, size: 0, parts: 0, contentType: req.headers['content-type'] || null, meta: metaOf(req.headers) });
      log({ op: 'CreateMultipartUpload', key, contentType: req.headers['content-type'] || null, meta: metaOf(req.headers) });
      return xml(res, `<InitiateMultipartUploadResult><Bucket>${esc(bucket)}</Bucket><Key>${esc(key)}</Key><UploadId>${id}</UploadId></InitiateMultipartUploadResult>`);
    }
    if (req.method === 'POST' && q.has('uploadId')) {   // CompleteMultipartUpload
      const up = uploads.get(q.get('uploadId'));
      const o = { bucket, key, size: up.size, etag: `${createHash('md5').update(key).digest('hex')}-${up.parts}`, contentType: up.contentType, multipart: true, meta: up.meta };
      objects.set(`${bucket}/${key}`, o); log({ op: 'CompleteMultipartUpload', key, size: up.size, parts: up.parts, contentType: o.contentType });
      return xml(res, `<CompleteMultipartUploadResult><Bucket>${esc(bucket)}</Bucket><Key>${esc(key)}</Key><ETag>"${o.etag}"</ETag></CompleteMultipartUploadResult>`);
    }
    if (req.method === 'DELETE' && q.has('uploadId')) { uploads.delete(q.get('uploadId')); res.writeHead(204); return res.end(); }
    log({ op: 'UNHANDLED', method: req.method, url: req.url }); res.writeHead(501); res.end();
  });
}).listen(Number(port), '127.0.0.1', () => console.log(`fake-s3 listening on http://127.0.0.1:${port}, log ${logPath}`));
