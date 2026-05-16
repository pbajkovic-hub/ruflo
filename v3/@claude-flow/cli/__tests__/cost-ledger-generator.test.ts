/**
 * P0 regression test for PR #1487 (cross-project cost-ledger).
 *
 * This is the single highest-value test for the feature: it exercises the
 * ONLY code path actually invoked in production — the `session-end` hook
 * runs `node ~/.claude/helpers/cost-ledger.cjs record` and pipes Claude
 * Code's session JSON on stdin.
 *
 * In one test it covers: generated-script syntactic validity (a single
 * escaping bug in the string-templated .cjs makes the subprocess fail),
 * `readStdinSync` (piped, non-TTY), `record()` field mapping + rounding
 * math, and ~/.claude directory auto-creation. HOME/USERPROFILE are
 * redirected to a tmpdir so the real user ledger is never touched.
 *
 * Convention mirrors fs-secure.test.ts (mkdtempSync + rmSync isolation,
 * subprocess execution).
 */

import { describe, it, expect, beforeEach, afterEach } from 'vitest';
import { mkdtempSync, rmSync, writeFileSync, existsSync, readFileSync } from 'node:fs';
import { execFileSync } from 'node:child_process';
import { tmpdir } from 'node:os';
import { join, basename } from 'node:path';

import { generateCostLedger } from '../src/init/helpers-generator.js';

describe('cost-ledger generator (PR #1487, P0)', () => {
  let home: string;
  let ledgerScript: string;

  beforeEach(() => {
    home = mkdtempSync(join(tmpdir(), 'cost-ledger-test-'));
    ledgerScript = join(home, 'cost-ledger.cjs');
    writeFileSync(ledgerScript, generateCostLedger(), 'utf-8');
  });

  afterEach(() => {
    rmSync(home, { recursive: true, force: true });
  });

  it('record writes a correct JSONL entry from a Claude Code stdin payload', () => {
    const payload = {
      cost: {
        total_cost_usd: 1.235,
        total_duration_ms: 120000,
        total_lines_added: 10,
        total_lines_removed: 2,
      },
      model: { model_id: 'claude-opus-4-7' },
      session_id: 's-1',
    };

    // The child resolves the ledger via os.homedir(): HOME on POSIX,
    // USERPROFILE on Windows. Redirect both to the tmpdir.
    execFileSync(process.execPath, [ledgerScript, 'record'], {
      input: JSON.stringify(payload),
      cwd: home,
      env: { ...process.env, HOME: home, USERPROFILE: home },
      timeout: 10000,
      stdio: ['pipe', 'pipe', 'pipe'],
    });

    const ledgerPath = join(home, '.claude', 'cost-ledger.jsonl');
    expect(existsSync(ledgerPath)).toBe(true);

    const lines = readFileSync(ledgerPath, 'utf-8').trim().split('\n');
    expect(lines).toHaveLength(1);

    const entry = JSON.parse(lines[0]);
    // Deterministic fields + rounding contract (Math.round(1.235*100)/100 = 1.24,
    // Math.round(120000/60000*10)/10 = 2).
    expect(entry.cost_usd).toBe(1.24);
    expect(entry.duration_min).toBe(2);
    expect(entry.model).toBe('claude-opus-4-7');
    expect(entry.session_id).toBe('s-1');
    expect(entry.lines_added).toBe(10);
    expect(entry.lines_removed).toBe(2);
    // project falls back to basename(cwd) when not a git repo with an origin.
    expect(entry.project).toBe(basename(home));
    // shape: ISO date + timestamp present
    expect(entry.date).toMatch(/^\d{4}-\d{2}-\d{2}$/);
    expect(typeof entry.timestamp).toBe('string');
  });
});
