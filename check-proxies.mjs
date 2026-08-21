#!/usr/bin/env node
// Proxy country checker for a list of proxies.
//
// Usage:  `node check-proxies.mjs [proxies.txt] [--proto auto|http|socks5] [--geo ip-api|ip2location] [--csv file.csv]`
//         without a file it reads proxies.txt (if present), otherwise stdin.
// Lines:  ip:port:user:pass | ip:port | socks5://user:pass@ip:port  (# = comment)
//
// Geo detection goes THROUGH the proxy itself (result = exit node's country):
//   1. ip-api.com/json (default — more accurate exit for hosting IPs)
//   2. api.ip2location.io (1,000 queries/day without a key; key: env IP2LOCATION_KEY)
// Switch with --geo ip2location (useful when databases disagree — compare results).
// --proto auto tries HTTP proxy first, then SOCKS5.

import { execFile } from 'node:child_process';
import { readFileSync, existsSync, writeFileSync } from 'node:fs';
import { promisify } from 'node:util';

const execFileP = promisify(execFile);
const CONCURRENCY = 10;

const CURL_ERRORS = {
  5: 'proxy not found (DNS)',
  7: 'unreachable',
  22: 'HTTP error',
  28: 'timeout',
  56: 'recv/auth error',
  97: 'SOCKS auth failed',
};

function parseProxy(line) {
  const t = line.trim();
  if (!t || t.startsWith('#')) return null;
  let host, port, user = '', pass = '';
  if (t.includes('://')) {
    const u = new URL(t);
    host = u.hostname; port = u.port; user = u.username; pass = u.password;
  } else {
    const parts = t.split(':');
    [host, port, user = '', pass = ''] = parts;
  }
  if (!host || !port) return null;
  return { host, port, user, pass };
}

// curl with proxy auth via --proxy-user (safe even for special chars in passwords)
function curlArgs(p, proto, url) {
  const args = [
    '-s', '--max-time', '12', '--connect-timeout', '8',
    '--proxy', `${proto}://${p.host}:${p.port}`,
  ];
  if (p.user) args.push('--proxy-user', `${p.user}:${p.pass}`);
  args.push(url);
  return args;
}

async function geoIp2location(p, proto) {
  const key = process.env.IP2LOCATION_KEY ? `?key=${process.env.IP2LOCATION_KEY}` : '';
  const r = await execFileP('curl', curlArgs(p, proto, `https://api.ip2location.io/${key}`));
  const j = JSON.parse(r.stdout);
  if (!j.ip) throw new Error('ip2location: bad response');
  return {
    country: j.country_name || j.country_code || '?',
    countryCode: j.country_code || '',
    city: j.city_name || '',
    exitIp: j.ip,
  };
}

async function geoIpApi(p, proto) {
  const r = await execFileP('curl', curlArgs(p, proto, 'http://ip-api.com/json'));
  const j = JSON.parse(r.stdout);
  if (j.status !== 'success' || !j.query) throw new Error('ip-api: bad response');
  return { country: j.country, countryCode: j.countryCode, city: j.city, exitIp: j.query };
}

async function geoLookup(p, protoMode, geoMode) {
  const protos = protoMode === 'auto' ? ['http', 'socks5h'] : [protoMode];
  const apis = geoMode === 'ip2location' ? [geoIp2location, geoIpApi] : [geoIpApi, geoIp2location];
  const start = Date.now();
  let lastErr;
  for (const proto of protos) {
    for (const api of apis) {
      try {
        const geo = await api(p, proto);
        return { status: 'OK', ...geo, proto, latencyMs: Date.now() - start };
      } catch (err) {
        lastErr = err;
      }
    }
  }
  const code = Number(lastErr?.code);
  return { status: 'FAIL', reason: CURL_ERRORS[code] || `curl exit ${code || '?'}` };
}

function getInput() {
  const args = process.argv.slice(2);
  const csvIdx = args.indexOf('--csv');
  const csvPath = csvIdx >= 0 ? (args[csvIdx + 1] ?? 'proxies-results.csv') : null;
  const protoIdx = args.indexOf('--proto');
  const protoMode = protoIdx >= 0 ? args[protoIdx + 1] : 'auto';
  if (protoMode && !['auto', 'http', 'socks5', 'socks5h'].includes(protoMode)) {
    console.error(`Unknown protocol: ${protoMode} (auto|http|socks5)`);
    process.exit(1);
  }
  const geoIdx = args.indexOf('--geo');
  const geoMode = geoIdx >= 0 ? args[geoIdx + 1] : 'ip-api';
  if (geoMode && !['ip-api', 'ip2location'].includes(geoMode)) {
    console.error(`Unknown geo API: ${geoMode} (ip-api|ip2location)`);
    process.exit(1);
  }
  const fileArg = args.find(a => !a.startsWith('--') && a !== args[csvIdx + 1] && a !== args[protoIdx + 1] && a !== args[geoIdx + 1]);

  let text;
  if (fileArg) {
    if (!existsSync(fileArg)) {
      console.error(`File ${fileArg} does not exist.`);
      process.exit(1);
    }
    text = readFileSync(fileArg, 'utf8');
  } else if (existsSync('proxies.txt')) {
    text = readFileSync('proxies.txt', 'utf8');
  } else {
    text = readFileSync(0, 'utf8'); // stdin
  }

  const proxies = text.split('\n').map(parseProxy).filter(Boolean);
  if (!proxies.length) {
    console.error('No proxies in input.');
    process.exit(1);
  }
  return { proxies, csvPath, protoMode: protoMode === 'socks5' ? 'socks5h' : protoMode, geoMode };
}

const pad = (s, n) => String(s).padEnd(n);

async function main() {
  const { proxies, csvPath, protoMode, geoMode } = getInput();
  console.log(`Checking ${proxies.length} proxies (proto: ${protoMode === 'socks5h' ? 'socks5' : protoMode}, geo: ${geoMode})...\n`);

  const results = [];
  for (let i = 0; i < proxies.length; i += CONCURRENCY) {
    const batch = proxies.slice(i, i + CONCURRENCY);
    results.push(...(await Promise.all(batch.map(p => geoLookup(p, protoMode, geoMode)))));
  }

  console.log(pad('proxy', 30) + pad('status', 7) + pad('country', 30) + pad('exit IP', 17) + pad('proto', 7) + 'time');
  proxies.forEach((p, i) => {
    const r = results[i];
    const label = `${p.host}:${p.port}`;
    if (r.status === 'OK') {
      console.log(
        pad(label, 30) + pad('OK', 5) + pad(`${r.country} (${r.countryCode})`, 30) +
        pad(r.exitIp, 17) + pad(r.proto === 'socks5h' ? 'socks5' : r.proto, 7) +
        `${(r.latencyMs / 1000).toFixed(1)}s`
      );
    } else {
      console.log(pad(label, 30) + pad('FAIL', 5) + r.reason);
    }
  });

  const ok = results.filter(r => r.status === 'OK');
  const byCountry = {};
  for (const r of ok) byCountry[r.country] = (byCountry[r.country] || 0) + 1;
  console.log(`\nSummary: OK ${ok.length} | FAIL ${results.length - ok.length}`);
  for (const [c, n] of Object.entries(byCountry).sort((a, b) => b[1] - a[1])) {
    console.log(`  ${c}: ${n}`);
  }

  if (csvPath) {
    const head = 'proxy,country,countryCode,city,exitIp,proto,latencyMs,status';
    const rows = proxies.map((p, i) => {
      const r = results[i];
      const c = v => (v ? `"${String(v).replace(/"/g, '""')}"` : '');
      return `${p.host}:${p.port},${c(r.country)},${c(r.countryCode)},${c(r.city)},${c(r.exitIp)},${c(r.proto)},${r.latencyMs || ''},${r.status === 'OK' ? 'OK' : `"${r.reason}"`}`;
    });
    writeFileSync(csvPath, [head, ...rows].join('\n') + '\n');
    console.log(`\nCSV saved: ${csvPath}`);
  }
}

main().catch(err => {
  console.error('Error:', err.message);
  process.exit(1);
});
