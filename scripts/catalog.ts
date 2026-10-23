import { readFileSync, writeFileSync, existsSync } from 'node:fs';
import { dirname, resolve, relative } from 'node:path';
import { fileURLToPath } from 'node:url';

type Level = 'behavior-observed' | 'behavior-partial' | 'ui-visible' | 'static-only';
type Feature = { id: string; module: string; title: string; evidenceLevel: Level; scope: string; stage: string; staticCandidateId: string | null; observations: string[]; nativeObservations?: string[]; evidence?: string[]; acceptanceStatus: string; implementation?: { status: string; sources: string[] }; remainingExperiment: string };
type Message = { context: string; source: string; comment: string; translation: string; status: string };
type Reference = { file: string; line: number; quote?: string; match?: string; symbol?: string };
const root = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const read = (path: string) => JSON.parse(readFileSync(resolve(root, path), 'utf8'));
const assert = (condition: unknown, text: string): asserts condition => { if (!condition) throw new Error(text); };
function ref(path: string) {
  const p = resolve(root, path);
  assert(!relative(root, p).startsWith('..'), `Reference escapes project: ${path}`);
  assert(existsSync(p), `Missing evidence: ${path}`);
}
const key = (m: { context: string; source: string; comment?: string }) => JSON.stringify([m.context, m.source, m.comment ?? '']);
const xml = (v: string) => v.replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll('>', '&gt;').replaceAll('"', '&quot;').replaceAll("'", '&apos;');
const cell = (v: string) => v.replaceAll('|', '\\|').replaceAll('\n', ' ');
const placeholders = (v: string) => (v.match(/%L?\d+|%L?n/g) ?? []).sort();
const tags = (v: string) => v.match(/<\/?[A-Za-z][^>]*>/g) ?? [];
const urls = (v: string) => (v.match(/https?:\/\/[^\s<>"']+/g) ?? []).sort();

const catalog = read('catalog/features.json');
const features: Feature[] = catalog.features;
const source = read('evidence/static/localization-source-catalog.json');
const draft = read('catalog/zh-CN.draft.json');
const observations = read('catalog/observations.json').observations;
const nativeObservations = read('catalog/native-observations.json').observations;
assert(new Set(nativeObservations.map((o: { id: string }) => o.id)).size === nativeObservations.length, 'Duplicate native observation IDs');
for (const o of nativeObservations) for (const path of o.evidence) ref(path);
const candidates = read('evidence/static/feature-candidates.json').candidates;
const sourceKeys = new Set(source.messages.map(key));
const obsIds = new Set(observations.map((o: { id: string }) => o.id));
const nativeObsIds = new Set(nativeObservations.map((o: { id: string }) => o.id));
const levels: Record<Level, string> = { 'behavior-observed': '局部行为已观察', 'behavior-partial': '部分行为已观察', 'ui-visible': '入口/文案可见', 'static-only': '仅静态证据' };
assert(new Set(features.map(f => f.id)).size === features.length, 'Duplicate feature IDs');
assert(obsIds.size === observations.length, 'Duplicate observation IDs');
assert(source.sourceCount === source.messages.length && sourceKeys.size === source.messages.length, 'Source count or uniqueness mismatch');
assert(draft.messages.length === source.messages.length, 'Translation count mismatch');
assert(new Set(draft.messages.map(key)).size === sourceKeys.size, 'Translation key duplicates');
for (const o of observations) for (const path of o.evidence) ref(path);
for (const f of features) {
  assert(f.evidenceLevel in levels, `Invalid evidence level ${f.id}`);
  assert(['not-accepted', 'accepted'].includes(f.acceptanceStatus), `Invalid acceptance status: ${f.id}`);
  assert(f.acceptanceStatus !== 'accepted', `Feature acceptance requires a linked runtime case before enabling: ${f.id}`);
  for (const path of f.implementation?.sources ?? []) ref(path);
  assert(f.remainingExperiment.length > 0, `Missing remaining experiment ${f.id}`);
  for (const id of f.observations) assert(obsIds.has(id), `Unknown observation ${f.id}/${id}`);
  for (const id of f.nativeObservations ?? []) assert(nativeObsIds.has(id), `Unknown native observation ${f.id}/${id}`);
  if (f.evidenceLevel !== 'static-only') assert(f.observations.length > 0, `Missing UI source ${f.id}`);
  if (f.staticCandidateId) assert(candidates.some((c: { id: string }) => c.id === f.staticCandidateId), `Missing static candidate ${f.id}`);
  for (const path of f.evidence ?? []) ref(path);
}
let quoteCount = 0;
for (const c of candidates) {
  for (const r of [...c.stringEvidence, ...c.symbolEvidence] as Reference[]) {
    ref(r.file);
    const line = readFileSync(resolve(root, r.file), 'utf8').split('\n')[r.line - 1];
    assert(line !== undefined, `Out-of-range evidence line ${c.id}/${r.line}`);
    if (r.quote) { assert(line === r.quote, `Quote drift ${c.id}/${r.line}`); quoteCount++; }
    if (r.symbol) assert(line.includes(r.symbol), `Symbol drift ${c.id}/${r.line}`);
  }
}
for (const m of draft.messages as Message[]) {
  assert(sourceKeys.has(key(m)), `Unknown translation key ${m.context}/${m.source}`);
  assert(typeof m.translation === 'string' && m.translation.trim().length > 0, `Empty translation: ${m.source}`);
  assert(m.status === 'draft', `Premature translation approval: ${m.source}`);
  assert(JSON.stringify(placeholders(m.source)) === JSON.stringify(placeholders(m.translation)), `Placeholder mismatch: ${m.source}`);
  assert(JSON.stringify(tags(m.source)) === JSON.stringify(tags(m.translation)), `HTML drift: ${m.source}`);
  assert(JSON.stringify(urls(m.source)) === JSON.stringify(urls(m.translation)), `URL drift: ${m.source}`);
}

let md = '# 功能与待验证清单\n\n由 `catalog/features.json` 生成，请修改源文件后执行 `npm run generate`。\n\n';
md += `当前 ${features.length} 项，包括可见功能、部分行为、历史/平台候选；实现进度与验收独立记录，当前尚无整项功能完整验收通过。计数不是完整行为覆盖率。\n\n`;
md += '|证据级别|数量|含义|\n|---|---:|---|\n';
for (const [level, label] of Object.entries(levels)) md += `|${label}|${features.filter(f => f.evidenceLevel === level).length}|${level === 'behavior-observed' ? '只证明账本中明确记录的局部前后态' : level === 'behavior-partial' ? '已有操作，终态或其他分支未闭环' : level === 'ui-visible' ? '入口/说明存在，效果未完成验证' : '字符串/符号/资源，不证明当前Mac可达'}|\n`;
for (const mod of [...new Set(features.map(f => f.module))]) {
  md += `\n## ${mod}\n\n|ID|功能|原版证据|范围/阶段|原版体验|新版实测|实现状态|\n|---|---|---|---|---|---|---|\n`;
  for (const f of features.filter(f => f.module === mod)) {
    md += `|${f.id}|${cell(f.title)}|${levels[f.evidenceLevel]}|${f.scope === 'mac-target' ? 'Mac目标' : '延后确认'} / ${f.stage}|${f.observations.join(', ') || '无'}|${f.nativeObservations?.join(', ') || '无'}|${f.implementation?.status ?? 'pending'}|\n`;
  }
  md += `\n待补：${features.find(f => f.module === mod)!.remainingExperiment}\n`;
}
md += '\n每项静态英文引文、地址见 `evidence/static/feature-candidates.json`；原版操作见 `catalog/observations.json`，新版实测见 `catalog/native-observations.json`。新版记录含失败和预览路径，须按记录中的状态及范围阅读，不等于整项功能已准出。S066来自QM更新器上下文。所有候选的详细边界见 `evidence/static/symbol-findings.md`。\n';
const contexts = [...new Set((draft.messages as Message[]).map(m => m.context))];
let ts = '<?xml version="1.0" encoding="utf-8"?>\n<!DOCTYPE TS>\n<TS version="2.1" language="zh_CN" sourcelanguage="en_US">\n';
for (const context of contexts) {
  ts += `  <context>\n    <name>${xml(context)}</name>\n`;
  for (const m of (draft.messages as Message[]).filter(m => m.context === context)) {
    ts += `    <message>\n      <source xml:space="preserve">${xml(m.source)}</source>\n`;
    if (m.comment) ts += `      <comment>${xml(m.comment)}</comment>\n`;
    ts += `      <translation type="unfinished" xml:space="preserve">${xml(m.translation)}</translation>\n    </message>\n`;
  }
  ts += '  </context>\n';
}
ts += '</TS>\n';
const outputs = { 'docs/features.md': md, 'locales/eyeblink_zh_CN.ts': ts };
const mode = process.argv[2] ?? 'check';
assert(mode === 'check' || mode === 'generate', 'Usage: catalog.ts check|generate');
for (const [path, contents] of Object.entries(outputs)) {
  if (mode === 'generate') writeFileSync(resolve(root, path), contents);
  else assert(readFileSync(resolve(root, path), 'utf8') === contents, `Generated file drift: ${path}; run npm run generate`);
}
console.log(JSON.stringify({ status: 'PASS', scope: 'investigation-data-integrity-only', features: features.length, observations: observations.length, translations: draft.messages.length, contexts: contexts.length, exactQuotesChecked: quoteCount, implementationsAccepted: 0, mode }, null, 2));
