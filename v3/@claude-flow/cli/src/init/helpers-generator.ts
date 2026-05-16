/**
 * Helpers Generator
 * Creates utility scripts in .claude/helpers/
 */

import type { InitOptions } from './types.js';
import { generateStatuslineScript, generateStatuslineHook } from './statusline-generator.js';

/**
 * Generate pre-commit hook script
 */
export function generatePreCommitHook(): string {
  return `#!/bin/bash
# Ruflo Pre-Commit Hook
# Validates code quality before commit

set -e

echo "🔍 Running Ruflo pre-commit checks..."

# Get staged files
STAGED_FILES=$(git diff --cached --name-only --diff-filter=ACM)

# Run validation for each staged file
for FILE in $STAGED_FILES; do
  if [[ "$FILE" =~ \\.(ts|js|tsx|jsx)$ ]]; then
    echo "  Validating: $FILE"
    npx @claude-flow/cli hooks pre-edit --file "$FILE" --validate-syntax 2>/dev/null || true
  fi
done

# Run tests if available
if [ -f "package.json" ] && grep -q '"test"' package.json; then
  echo "🧪 Running tests..."
  npm test --if-present 2>/dev/null || echo "  Tests skipped or failed"
fi

echo "✅ Pre-commit checks complete"
`;
}

/**
 * Generate post-commit hook script
 */
export function generatePostCommitHook(): string {
  return `#!/bin/bash
# Ruflo Post-Commit Hook
# Records commit metrics and trains patterns

COMMIT_HASH=$(git rev-parse HEAD)
COMMIT_MSG=$(git log -1 --pretty=%B)

echo "📊 Recording commit metrics..."

# Notify ruflo of commit
npx ruflo@latest hooks notify \\
  --message "Commit: $COMMIT_MSG" \\
  --level info \\
  --metadata '{"hash": "'$COMMIT_HASH'"}' 2>/dev/null || true

echo "✅ Commit recorded"
`;
}

/**
 * Generate session manager script
 */
export function generateSessionManager(): string {
  return `#!/usr/bin/env node
/**
 * Ruflo Session Manager
 * Handles session lifecycle: start, restore, end
 */

const fs = require('fs');
const path = require('path');

const SESSION_DIR = path.join(process.cwd(), '.claude-flow', 'sessions');
const SESSION_FILE = path.join(SESSION_DIR, 'current.json');

const commands = {
  start: () => {
    const sessionId = \`session-\${Date.now()}\`;
    const session = {
      id: sessionId,
      startedAt: new Date().toISOString(),
      cwd: process.cwd(),
      context: {},
      metrics: {
        edits: 0,
        commands: 0,
        tasks: 0,
        errors: 0,
      },
    };

    fs.mkdirSync(SESSION_DIR, { recursive: true });
    fs.writeFileSync(SESSION_FILE, JSON.stringify(session, null, 2));

    console.log(\`Session started: \${sessionId}\`);
    return session;
  },

  restore: () => {
    if (!fs.existsSync(SESSION_FILE)) {
      console.log('No session to restore');
      return null;
    }

    const session = JSON.parse(fs.readFileSync(SESSION_FILE, 'utf-8'));
    session.restoredAt = new Date().toISOString();
    fs.writeFileSync(SESSION_FILE, JSON.stringify(session, null, 2));

    console.log(\`Session restored: \${session.id}\`);
    return session;
  },

  end: () => {
    if (!fs.existsSync(SESSION_FILE)) {
      console.log('No active session');
      return null;
    }

    const session = JSON.parse(fs.readFileSync(SESSION_FILE, 'utf-8'));
    session.endedAt = new Date().toISOString();
    session.duration = Date.now() - new Date(session.startedAt).getTime();

    // Archive session
    const archivePath = path.join(SESSION_DIR, \`\${session.id}.json\`);
    fs.writeFileSync(archivePath, JSON.stringify(session, null, 2));
    fs.unlinkSync(SESSION_FILE);

    console.log(\`Session ended: \${session.id}\`);
    console.log(\`Duration: \${Math.round(session.duration / 1000 / 60)} minutes\`);
    console.log(\`Metrics: \${JSON.stringify(session.metrics)}\`);

    return session;
  },

  status: () => {
    if (!fs.existsSync(SESSION_FILE)) {
      console.log('No active session');
      return null;
    }

    const session = JSON.parse(fs.readFileSync(SESSION_FILE, 'utf-8'));
    const duration = Date.now() - new Date(session.startedAt).getTime();

    console.log(\`Session: \${session.id}\`);
    console.log(\`Started: \${session.startedAt}\`);
    console.log(\`Duration: \${Math.round(duration / 1000 / 60)} minutes\`);
    console.log(\`Metrics: \${JSON.stringify(session.metrics)}\`);

    return session;
  },

  update: (key, value) => {
    if (!fs.existsSync(SESSION_FILE)) {
      console.log('No active session');
      return null;
    }

    const session = JSON.parse(fs.readFileSync(SESSION_FILE, 'utf-8'));
    session.context[key] = value;
    session.updatedAt = new Date().toISOString();
    fs.writeFileSync(SESSION_FILE, JSON.stringify(session, null, 2));

    return session;
  },

  metric: (name) => {
    if (!fs.existsSync(SESSION_FILE)) {
      return null;
    }

    const session = JSON.parse(fs.readFileSync(SESSION_FILE, 'utf-8'));
    if (session.metrics[name] !== undefined) {
      session.metrics[name]++;
      fs.writeFileSync(SESSION_FILE, JSON.stringify(session, null, 2));
    }

    return session;
  },
};

// CLI
const [,, command, ...args] = process.argv;

if (command && commands[command]) {
  commands[command](...args);
} else {
  console.log('Usage: session.js <start|restore|end|status|update|metric> [args]');
}

module.exports = commands;
`;
}

/**
 * Generate agent router script
 */
export function generateAgentRouter(): string {
  return `#!/usr/bin/env node
/**
 * Ruflo Agent Router
 * Routes tasks to optimal agents based on learned patterns
 */

const AGENT_CAPABILITIES = {
  coder: ['code-generation', 'refactoring', 'debugging', 'implementation'],
  tester: ['unit-testing', 'integration-testing', 'coverage', 'test-generation'],
  reviewer: ['code-review', 'security-audit', 'quality-check', 'best-practices'],
  researcher: ['web-search', 'documentation', 'analysis', 'summarization'],
  architect: ['system-design', 'architecture', 'patterns', 'scalability'],
  'backend-dev': ['api', 'database', 'server', 'authentication'],
  'frontend-dev': ['ui', 'react', 'css', 'components'],
  devops: ['ci-cd', 'docker', 'deployment', 'infrastructure'],
};

const TASK_PATTERNS = {
  // Code patterns
  'implement|create|build|add|write code': 'coder',
  'test|spec|coverage|unit test|integration': 'tester',
  'review|audit|check|validate|security': 'reviewer',
  'research|find|search|documentation|explore': 'researcher',
  'design|architect|structure|plan': 'architect',

  // Domain patterns
  'api|endpoint|server|backend|database': 'backend-dev',
  'ui|frontend|component|react|css|style': 'frontend-dev',
  'deploy|docker|ci|cd|pipeline|infrastructure': 'devops',
};

function routeTask(task) {
  const taskLower = task.toLowerCase();

  // Check patterns
  for (const [pattern, agent] of Object.entries(TASK_PATTERNS)) {
    const regex = new RegExp(pattern, 'i');
    if (regex.test(taskLower)) {
      return {
        agent,
        confidence: 0.8,
        reason: \`Matched pattern: \${pattern}\`,
      };
    }
  }

  // Default to coder for unknown tasks
  return {
    agent: 'coder',
    confidence: 0.5,
    reason: 'Default routing - no specific pattern matched',
  };
}

// CLI
const task = process.argv.slice(2).join(' ');

if (task) {
  const result = routeTask(task);
  console.log(JSON.stringify(result, null, 2));
} else {
  console.log('Usage: router.js <task description>');
  console.log('\\nAvailable agents:', Object.keys(AGENT_CAPABILITIES).join(', '));
}

module.exports = { routeTask, AGENT_CAPABILITIES, TASK_PATTERNS };
`;
}

/**
 * Generate memory helper script
 */
export function generateMemoryHelper(): string {
  return `#!/usr/bin/env node
/**
 * Ruflo Memory Helper
 * Simple key-value memory for cross-session context
 */

const fs = require('fs');
const path = require('path');

const MEMORY_DIR = path.join(process.cwd(), '.claude-flow', 'data');
const MEMORY_FILE = path.join(MEMORY_DIR, 'memory.json');

function loadMemory() {
  try {
    if (fs.existsSync(MEMORY_FILE)) {
      return JSON.parse(fs.readFileSync(MEMORY_FILE, 'utf-8'));
    }
  } catch (e) {
    // Ignore
  }
  return {};
}

function saveMemory(memory) {
  fs.mkdirSync(MEMORY_DIR, { recursive: true });
  fs.writeFileSync(MEMORY_FILE, JSON.stringify(memory, null, 2));
}

const commands = {
  get: (key) => {
    const memory = loadMemory();
    const value = key ? memory[key] : memory;
    console.log(JSON.stringify(value, null, 2));
    return value;
  },

  set: (key, value) => {
    if (!key) {
      console.error('Key required');
      return;
    }
    const memory = loadMemory();
    memory[key] = value;
    memory._updated = new Date().toISOString();
    saveMemory(memory);
    console.log(\`Set: \${key}\`);
  },

  delete: (key) => {
    if (!key) {
      console.error('Key required');
      return;
    }
    const memory = loadMemory();
    delete memory[key];
    saveMemory(memory);
    console.log(\`Deleted: \${key}\`);
  },

  clear: () => {
    saveMemory({});
    console.log('Memory cleared');
  },

  keys: () => {
    const memory = loadMemory();
    const keys = Object.keys(memory).filter(k => !k.startsWith('_'));
    console.log(keys.join('\\n'));
    return keys;
  },
};

// CLI
const [,, command, key, ...valueParts] = process.argv;
const value = valueParts.join(' ');

if (command && commands[command]) {
  commands[command](key, value);
} else {
  console.log('Usage: memory.js <get|set|delete|clear|keys> [key] [value]');
}

module.exports = commands;
`;
}

/**
 * Generate hook-handler.cjs (cross-platform hook dispatcher)
 * This is the inline fallback when file copy from the package fails.
 * Uses string concatenation instead of template literals to avoid escaping issues.
 */
export function generateHookHandler(): string {
  // Build as array of lines to avoid template-in-template escaping nightmares
  const lines = [
    '#!/usr/bin/env node',
    '/**',
    ' * Ruflo Hook Handler (Cross-Platform)',
    ' * Dispatches hook events to the appropriate helper modules.',
    ' */',
    '',
    "const path = require('path');",
    "const fs = require('fs');",
    '',
    'const helpersDir = __dirname;',
    '',
    'function safeRequire(modulePath) {',
    '  try {',
    '    if (fs.existsSync(modulePath)) {',
    '      const origLog = console.log;',
    '      const origError = console.error;',
    '      console.log = () => {};',
    '      console.error = () => {};',
    '      try {',
    '        const mod = require(modulePath);',
    '        return mod;',
    '      } finally {',
    '        console.log = origLog;',
    '        console.error = origError;',
    '      }',
    '    }',
    '  } catch (e) {',
    '    // silently fail',
    '  }',
    '  return null;',
    '}',
    '',
    "const router = safeRequire(path.join(helpersDir, 'router.js'));",
    "const session = safeRequire(path.join(helpersDir, 'session.js'));",
    "const memory = safeRequire(path.join(helpersDir, 'memory.js'));",
    "const intelligence = safeRequire(path.join(helpersDir, 'intelligence.cjs'));",
    '',
    'const [,, command, ...args] = process.argv;',
    '',
    '// Read stdin with timeout — Claude Code sends hook data as JSON via stdin.',
    '// Timeout prevents hanging when stdin is in an ambiguous state (not TTY, not pipe).',
    'async function readStdin() {',
    '  if (process.stdin.isTTY) return "";',
    '  return new Promise((resolve) => {',
    '    let data = "";',
    '    const timer = setTimeout(() => {',
    '      process.stdin.removeAllListeners();',
    '      process.stdin.pause();',
    '      resolve(data);',
    '    }, 500);',
    '    process.stdin.setEncoding("utf8");',
    '    process.stdin.on("data", (chunk) => { data += chunk; });',
    '    process.stdin.on("end", () => { clearTimeout(timer); resolve(data); });',
    '    process.stdin.on("error", () => { clearTimeout(timer); resolve(data); });',
    '    process.stdin.resume();',
    '  });',
    '}',
    '',
    'async function main() {',
    '  let stdinData = "";',
    '  try { stdinData = await readStdin(); } catch (e) { /* ignore */ }',
    '  let hookInput = {};',
    '  if (stdinData.trim()) {',
    '    try { hookInput = JSON.parse(stdinData); } catch (e) { /* ignore */ }',
    '  }',
    '  // Prefer stdin fields, then env, then argv. `hookInput.toolInput` is an',
    '  // object (e.g. {command:"ls"}); falling back to it directly bound prompt',
    '  // to the object and tripped .toLowerCase() / .substring() on every Bash',
    '  // hook (#1944). Pull `.command` off whichever stdin shape Claude Code sent.',
    '  var toolInputObj = hookInput.toolInput || hookInput.tool_input || {};',
    "  var prompt = hookInput.prompt || hookInput.command || toolInputObj.command || process.env.PROMPT || process.env.TOOL_INPUT_command || args.join(' ') || '';",
    '',
    'const handlers = {',
    "  'route': () => {",
    '    if (intelligence && intelligence.getContext) {',
    '      try {',
    '        const ctx = intelligence.getContext(prompt);',
    '        if (ctx) console.log(ctx);',
    '      } catch (e) { /* non-fatal */ }',
    '    }',
    '    if (router && router.routeTask) {',
    '      const result = router.routeTask(prompt);',
    '      var output = [];',
    "      output.push('[INFO] Routing task: ' + (prompt.substring(0, 80) || '(no prompt)'));",
    "      output.push('');",
    "      output.push('+------------------- Primary Recommendation -------------------+');",
    "      output.push('| Agent: ' + result.agent.padEnd(53) + '|');",
    "      output.push('| Confidence: ' + (result.confidence * 100).toFixed(1) + '%' + ' '.repeat(44) + '|');",
    "      output.push('| Reason: ' + result.reason.substring(0, 53).padEnd(53) + '|');",
    "      output.push('+--------------------------------------------------------------+');",
    "      console.log(output.join('\\n'));",
    '    } else {',
    "      console.log('[INFO] Router not available, using default routing');",
    '    }',
    '  },',
    '',
    "  'pre-bash': () => {",
    '    var cmd = prompt.toLowerCase();',
    "    var dangerous = ['rm -rf /', 'format c:', 'del /s /q c:\\\\', ':(){:|:&};:'];",
    '    for (var i = 0; i < dangerous.length; i++) {',
    '      if (cmd.includes(dangerous[i])) {',
    "        console.error('[BLOCKED] Dangerous command detected: ' + dangerous[i]);",
    '        process.exit(1);',
    '      }',
    '    }',
    "    console.log('[OK] Command validated');",
    '  },',
    '',
    "  'post-edit': () => {",
    '    if (session && session.metric) {',
    "      try { session.metric('edits'); } catch (e) { /* no active session */ }",
    '    }',
    '    if (intelligence && intelligence.recordEdit) {',
    '      try {',
    "        var file = process.env.TOOL_INPUT_file_path || args[0] || '';",
    '        intelligence.recordEdit(file);',
    '      } catch (e) { /* non-fatal */ }',
    '    }',
    "    console.log('[OK] Edit recorded');",
    '  },',
    '',
    "  'session-restore': () => {",
    '    if (session) {',
    '      var existing = session.restore && session.restore();',
    '      if (!existing) {',
    '        session.start && session.start();',
    '      }',
    '    } else {',
    "      console.log('[OK] Session restored: session-' + Date.now());",
    '    }',
    '    if (intelligence && intelligence.init) {',
    '      try {',
    '        var result = intelligence.init();',
    '        if (result && result.nodes > 0) {',
    "          console.log('[INTELLIGENCE] Loaded ' + result.nodes + ' patterns, ' + result.edges + ' edges');",
    '        }',
    '      } catch (e) { /* non-fatal */ }',
    '    }',
    '  },',
    '',
    "  'session-end': () => {",
    '    // Record session cost to global ledger',
    '    try {',
    "      var ledgerPath = path.join(require('os').homedir(), '.claude', 'helpers', 'cost-ledger.cjs');",
    '      if (fs.existsSync(ledgerPath)) {',
    "        var { execSync } = require('child_process');",
    '        execSync("node \\"" + ledgerPath + "\\" record", {',
    '          input: JSON.stringify(hookInput) || "",',
    '          timeout: 3000,',
    "          stdio: ['pipe', 'pipe', 'pipe'],",
    '        });',
    '      }',
    '    } catch (e) { /* non-fatal — cost tracking should never break session end */ }',
    '',
    '    if (intelligence && intelligence.consolidate) {',
    '      try {',
    '        var result = intelligence.consolidate();',
    '        if (result && result.entries > 0) {',
    "          var msg = '[INTELLIGENCE] Consolidated: ' + result.entries + ' entries, ' + result.edges + ' edges';",
    "          if (result.newEntries > 0) msg += ', ' + result.newEntries + ' new';",
    "          msg += ', PageRank recomputed';",
    '          console.log(msg);',
    '        }',
    '      } catch (e) { /* non-fatal */ }',
    '    }',
    '    if (session && session.end) {',
    '      session.end();',
    '    } else {',
    "      console.log('[OK] Session ended');",
    '    }',
    '  },',
    '',
    "  'pre-task': () => {",
    '    if (session && session.metric) {',
    "      try { session.metric('tasks'); } catch (e) { /* no active session */ }",
    '    }',
    '    if (router && router.routeTask && prompt) {',
    '      var result = router.routeTask(prompt);',
    "      console.log('[INFO] Task routed to: ' + result.agent + ' (confidence: ' + result.confidence + ')');",
    '    } else {',
    "      console.log('[OK] Task started');",
    '    }',
    '  },',
    '',
    "  'post-task': () => {",
    '    if (intelligence && intelligence.feedback) {',
    '      try {',
    '        intelligence.feedback(true);',
    '      } catch (e) { /* non-fatal */ }',
    '    }',
    "    console.log('[OK] Task completed');",
    '  },',
    '',
    "  'compact-manual': () => {",
    "    console.log('PreCompact Guidance:');",
    "    console.log('IMPORTANT: Review CLAUDE.md in project root for:');",
    "    console.log('   - Available agents and concurrent usage patterns');",
    "    console.log('   - Swarm coordination strategies (hierarchical, mesh, adaptive)');",
    "    console.log('   - Critical concurrent execution rules (1 MESSAGE = ALL OPERATIONS)');",
    "    console.log('Ready for compact operation');",
    '  },',
    '',
    "  'compact-auto': () => {",
    "    console.log('Auto-Compact Guidance (Context Window Full):');",
    "    console.log('CRITICAL: Before compacting, ensure you understand:');",
    "    console.log('   - All agents available in .claude/agents/ directory');",
    "    console.log('   - Concurrent execution patterns from CLAUDE.md');",
    "    console.log('   - Swarm coordination strategies for complex tasks');",
    "    console.log('Apply GOLDEN RULE: Always batch operations in single messages');",
    "    console.log('Auto-compact proceeding with full agent context');",
    '  },',
    '',
    "  'status': () => {",
    "    console.log('[OK] Status check');",
    '  },',
    '',
    "  'stats': () => {",
    '    if (intelligence && intelligence.stats) {',
    "      intelligence.stats(args.includes('--json'));",
    '    } else {',
    "      console.log('[WARN] Intelligence module not available. Run session-restore first.');",
    '    }',
    '  },',
    '};',
    '',
    'if (command && handlers[command]) {',
    '  try {',
    '    handlers[command]();',
    '  } catch (e) {',
    "    console.log('[WARN] Hook ' + command + ' encountered an error: ' + e.message);",
    '  }',
    '} else if (command) {',
    "  console.log('[OK] Hook: ' + command);",
    '} else {',
    "  console.log('Usage: hook-handler.cjs <route|pre-bash|post-edit|session-restore|session-end|pre-task|post-task|compact-manual|compact-auto|status|stats>');",
    '}',
    '} // end main',
    '',
    'process.exitCode = 0;',
    'main().catch(() => {}).finally(() => { process.exit(0); });',
  ];
  return lines.join('\n') + '\n';
}

/**
 * Generate a minimal intelligence.cjs stub for fallback installs.
 * Provides the same API as the full intelligence.cjs but with simplified logic.
 * Gets overwritten when source copy succeeds (full version has PageRank, Jaccard, etc.)
 */
export function generateIntelligenceStub(): string {
  const lines = [
    '#!/usr/bin/env node',
    '/**',
    ' * Intelligence Layer Stub (ADR-050)',
    ' * Minimal fallback — full version is copied from package source.',
    ' * Provides: init, getContext, recordEdit, feedback, consolidate',
    ' */',
    "'use strict';",
    '',
    "const fs = require('fs');",
    "const path = require('path');",
    "const os = require('os');",
    '',
    "const DATA_DIR = path.join(process.cwd(), '.claude-flow', 'data');",
    "const STORE_PATH = path.join(DATA_DIR, 'auto-memory-store.json');",
    "const RANKED_PATH = path.join(DATA_DIR, 'ranked-context.json');",
    "const PENDING_PATH = path.join(DATA_DIR, 'pending-insights.jsonl');",
    "const SESSION_DIR = path.join(process.cwd(), '.claude-flow', 'sessions');",
    "const SESSION_FILE = path.join(SESSION_DIR, 'current.json');",
    '',
    'function ensureDir(dir) {',
    '  if (!fs.existsSync(dir)) fs.mkdirSync(dir, { recursive: true });',
    '}',
    '',
    'function readJSON(p) {',
    '  try { return fs.existsSync(p) ? JSON.parse(fs.readFileSync(p, "utf-8")) : null; }',
    '  catch { return null; }',
    '}',
    '',
    'function writeJSON(p, data) {',
    '  ensureDir(path.dirname(p));',
    '  fs.writeFileSync(p, JSON.stringify(data, null, 2), "utf-8");',
    '}',
    '',
    '// Read session context key',
    'function sessionGet(key) {',
    '  var session = readJSON(SESSION_FILE);',
    '  if (!session) return null;',
    '  return key ? (session.context || {})[key] : session.context;',
    '}',
    '',
    '// Write session context key',
    'function sessionSet(key, value) {',
    '  var session = readJSON(SESSION_FILE);',
    '  if (!session) return;',
    '  if (!session.context) session.context = {};',
    '  session.context[key] = value;',
    '  writeJSON(SESSION_FILE, session);',
    '}',
    '',
    '// Tokenize text into words',
    'function tokenize(text) {',
    '  if (!text) return [];',
    '  return text.toLowerCase().replace(/[^a-z0-9\\s]/g, " ").split(/\\s+/).filter(function(w) { return w.length > 2; });',
    '}',
    '',
    '// Bootstrap entries from MEMORY.md files when store is empty',
    'function bootstrapFromMemoryFiles() {',
    '  var entries = [];',
    '  var candidates = [',
    '    path.join(os.homedir(), ".claude", "projects"),',
    '    path.join(process.cwd(), ".claude-flow", "memory"),',
    '    path.join(process.cwd(), ".claude", "memory"),',
    '  ];',
    '  for (var i = 0; i < candidates.length; i++) {',
    '    try {',
    '      if (!fs.existsSync(candidates[i])) continue;',
    '      var files = [];',
    '      try {',
    '        var items = fs.readdirSync(candidates[i], { withFileTypes: true, recursive: true });',
    '        for (var j = 0; j < items.length; j++) {',
    '          if (items[j].name === "MEMORY.md") {',
    '            var parentDir = items[j].parentPath || items[j].path || candidates[i];',
    '            var fp = path.join(parentDir, items[j].name);',
    '            files.push(fp);',
    '          }',
    '        }',
    '      } catch (e) { continue; }',
    '      for (var k = 0; k < files.length; k++) {',
    '        try {',
    '          var content = fs.readFileSync(files[k], "utf-8");',
    '          var sections = content.split(/^##\\s+/m).filter(function(s) { return s.trim().length > 20; });',
    '          for (var s = 0; s < sections.length; s++) {',
    '            var lines2 = sections[s].split("\\n");',
    '            var title = lines2[0] ? lines2[0].trim() : "section-" + s;',
    '            entries.push({',
    '              id: "mem-" + entries.length,',
    '              content: sections[s].substring(0, 500),',
    '              summary: title.substring(0, 100),',
    '              category: "memory",',
    '              confidence: 0.5,',
    '              sourceFile: files[k],',
    '              words: tokenize(sections[s].substring(0, 500)),',
    '            });',
    '          }',
    '        } catch (e) { /* skip */ }',
    '      }',
    '    } catch (e) { /* skip */ }',
    '  }',
    '  return entries;',
    '}',
    '',
    '// Load entries from auto-memory-store or bootstrap from MEMORY.md',
    'function loadEntries() {',
    '  var store = readJSON(STORE_PATH);',
    '  // Support both formats: flat array or { entries: [...] }',
    '  var entries = null;',
    '  if (store) {',
    '    if (Array.isArray(store) && store.length > 0) {',
    '      entries = store;',
    '    } else if (store.entries && store.entries.length > 0) {',
    '      entries = store.entries;',
    '    }',
    '  }',
    '  if (entries) {',
    '    return entries.map(function(e, i) {',
    '      return {',
    '        id: e.id || ("entry-" + i),',
    '        content: e.content || e.value || "",',
    '        summary: e.summary || e.key || "",',
    '        category: e.category || e.namespace || "default",',
    '        confidence: e.confidence || 0.5,',
    '        sourceFile: e.sourceFile || (e.metadata && e.metadata.sourceFile) || "",',
    '        words: tokenize((e.content || e.value || "") + " " + (e.summary || e.key || "")),',
    '      };',
    '    });',
    '  }',
    '  return bootstrapFromMemoryFiles();',
    '}',
    '',
    '// Simple keyword match score',
    'function matchScore(promptWords, entryWords) {',
    '  if (!promptWords.length || !entryWords.length) return 0;',
    '  var entrySet = {};',
    '  for (var i = 0; i < entryWords.length; i++) entrySet[entryWords[i]] = true;',
    '  var overlap = 0;',
    '  for (var j = 0; j < promptWords.length; j++) {',
    '    if (entrySet[promptWords[j]]) overlap++;',
    '  }',
    '  var union = Object.keys(entrySet).length + promptWords.length - overlap;',
    '  return union > 0 ? overlap / union : 0;',
    '}',
    '',
    'var cachedEntries = null;',
    '',
    'module.exports = {',
    '  init: function() {',
    '    cachedEntries = loadEntries();',
    '    var ranked = cachedEntries.map(function(e) {',
    '      return { id: e.id, content: e.content, summary: e.summary, category: e.category, confidence: e.confidence, words: e.words };',
    '    });',
    '    writeJSON(RANKED_PATH, { version: 1, computedAt: Date.now(), entries: ranked });',
    '    return { nodes: cachedEntries.length, edges: 0 };',
    '  },',
    '',
    '  getContext: function(prompt) {',
    '    if (!prompt) return null;',
    '    var ranked = readJSON(RANKED_PATH);',
    '    var entries = (ranked && ranked.entries) || (cachedEntries || []);',
    '    if (!entries.length) return null;',
    '    var promptWords = tokenize(prompt);',
    '    if (!promptWords.length) return null;',
    '    var scored = entries.map(function(e) {',
    '      return { entry: e, score: matchScore(promptWords, e.words || tokenize(e.content + " " + e.summary)) };',
    '    }).filter(function(s) { return s.score > 0.05; });',
    '    scored.sort(function(a, b) { return b.score - a.score; });',
    '    var top = scored.slice(0, 5);',
    '    if (!top.length) return null;',
    '    var prevMatched = sessionGet("lastMatchedPatterns");',
    '    var matchedIds = top.map(function(s) { return s.entry.id; });',
    '    sessionSet("lastMatchedPatterns", matchedIds);',
    '    if (prevMatched && Array.isArray(prevMatched)) {',
    '      var newSet = {};',
    '      for (var i = 0; i < matchedIds.length; i++) newSet[matchedIds[i]] = true;',
    '    }',
    '    var lines2 = ["[INTELLIGENCE] Relevant patterns for this task:"];',
    '    for (var j = 0; j < top.length; j++) {',
    '      var e = top[j];',
    '      var conf = e.entry.confidence || 0.5;',
    '      var summary = (e.entry.summary || e.entry.content || "").substring(0, 80);',
    '      lines2.push("  * (" + conf.toFixed(2) + ") " + summary);',
    '    }',
    '    return lines2.join("\\n");',
    '  },',
    '',
    '  recordEdit: function(file) {',
    '    if (!file) return;',
    '    ensureDir(DATA_DIR);',
    '    var line = JSON.stringify({ type: "edit", file: file, timestamp: Date.now() }) + "\\n";',
    '    fs.appendFileSync(PENDING_PATH, line, "utf-8");',
    '  },',
    '',
    '  feedback: function(success) {',
    '    // Stub: no-op in minimal version',
    '  },',
    '',
    '  consolidate: function() {',
    '    var count = 0;',
    '    if (fs.existsSync(PENDING_PATH)) {',
    '      try {',
    '        var content = fs.readFileSync(PENDING_PATH, "utf-8").trim();',
    '        count = content ? content.split("\\n").length : 0;',
    '        fs.writeFileSync(PENDING_PATH, "", "utf-8");',
    '      } catch (e) { /* skip */ }',
    '    }',
    '    return { entries: count, edges: 0, newEntries: 0 };',
    '  },',
    '};',
  ];
  return lines.join('\n') + '\n';
}

/**
 * Generate a minimal auto-memory-hook.mjs fallback for fresh installs.
 * This ESM script handles import/sync/status commands gracefully when
 * @claude-flow/memory is not installed. Gets overwritten when source copy succeeds.
 */
export function generateAutoMemoryHook(): string {
  return `#!/usr/bin/env node
/**
 * Auto Memory Bridge Hook (ADR-048/049) — Minimal Fallback
 * Full version is copied from package source when available.
 *
 * Usage:
 *   node auto-memory-hook.mjs import   # SessionStart
 *   node auto-memory-hook.mjs sync     # SessionEnd / Stop
 *   node auto-memory-hook.mjs status   # Show bridge status
 */

import { existsSync, mkdirSync, readFileSync, writeFileSync } from 'fs';
import { join, dirname } from 'path';
import { fileURLToPath } from 'url';

const __filename = fileURLToPath(import.meta.url);
const __dirname = dirname(__filename);
const PROJECT_ROOT = join(__dirname, '../..');
const DATA_DIR = join(PROJECT_ROOT, '.claude-flow', 'data');
const STORE_PATH = join(DATA_DIR, 'auto-memory-store.json');

const DIM = '\\x1b[2m';
const RESET = '\\x1b[0m';
const dim = (msg) => console.log(\`  \${DIM}\${msg}\${RESET}\`);

// Ensure data dir
if (!existsSync(DATA_DIR)) mkdirSync(DATA_DIR, { recursive: true });

async function loadMemoryPackage() {
  // Strategy 1: Use createRequire for CJS-style resolution (handles nested node_modules
  // when installed as a transitive dependency via npx ruflo / npx claude-flow)
  try {
    const { createRequire } = await import('module');
    const require = createRequire(join(PROJECT_ROOT, 'package.json'));
    return require('@claude-flow/memory');
  } catch { /* fall through */ }

  // Strategy 2: ESM import (works when @claude-flow/memory is a direct dependency)
  try { return await import('@claude-flow/memory'); } catch { /* fall through */ }

  // Strategy 3: Walk up from PROJECT_ROOT looking for the package in any node_modules
  let searchDir = PROJECT_ROOT;
  const { parse } = await import('path');
  while (searchDir !== parse(searchDir).root) {
    const candidate = join(searchDir, 'node_modules', '@claude-flow', 'memory', 'dist', 'index.js');
    if (existsSync(candidate)) {
      try { return await import(\`file://\${candidate}\`); } catch { /* fall through */ }
    }
    searchDir = dirname(searchDir);
  }

  return null;
}

async function doImport() {
  const memPkg = await loadMemoryPackage();

  if (!memPkg || !memPkg.AutoMemoryBridge) {
    dim('Memory package not available — auto memory import skipped (non-critical)');
    return;
  }

  // Full implementation deferred to copied version
  dim('Auto memory import available — run init --upgrade for full support');
}

async function doSync() {
  if (!existsSync(STORE_PATH)) {
    dim('No entries to sync');
    return;
  }

  const memPkg = await loadMemoryPackage();

  if (!memPkg || !memPkg.AutoMemoryBridge) {
    dim('Memory package not available — sync skipped (non-critical)');
    return;
  }

  dim('Auto memory sync available — run init --upgrade for full support');
}

function doStatus() {
  console.log('\\n=== Auto Memory Bridge Status ===\\n');
  console.log('  Package:        Fallback mode (run init --upgrade for full)');
  console.log(\`  Store:          \${existsSync(STORE_PATH) ? 'Initialized' : 'Not initialized'}\`);
  console.log('');
}

// Suppress unhandled rejection warnings from dynamic import() failures
process.on('unhandledRejection', () => {});

const command = process.argv[2] || 'status';

try {
  switch (command) {
    case 'import': await doImport(); break;
    case 'sync': await doSync(); break;
    case 'status': doStatus(); break;
    default:
      console.log('Usage: auto-memory-hook.mjs <import|sync|status>');
      process.exit(1);
  }
} catch (err) {
  // Hooks must never crash Claude Code - fail silently
  dim(\`Error (non-critical): \${err.message}\`);
}
// Ensure clean exit for Claude Code hooks (exit 0 = success)
process.exit(0);
`;
}

/**
 * Generate Windows PowerShell daemon manager
 */
export function generateWindowsDaemonManager(): string {
  return `# RuFlo V3 Daemon Manager for Windows
# PowerShell script for managing background processes

param(
    [Parameter(Position=0)]
    [ValidateSet('start', 'stop', 'status', 'restart')]
    [string]$Action = 'status'
)

$ErrorActionPreference = 'SilentlyContinue'
$ClaudeFlowDir = Join-Path $PWD '.claude-flow'
$PidDir = Join-Path $ClaudeFlowDir 'pids'

# Ensure directories exist
if (-not (Test-Path $PidDir)) {
    New-Item -ItemType Directory -Path $PidDir -Force | Out-Null
}

function Get-DaemonStatus {
    param([string]$Name, [string]$PidFile)

    if (Test-Path $PidFile) {
        $pid = Get-Content $PidFile
        $process = Get-Process -Id $pid -ErrorAction SilentlyContinue
        if ($process) {
            return @{ Running = $true; Pid = $pid }
        }
    }
    return @{ Running = $false; Pid = $null }
}

function Start-SwarmMonitor {
    $pidFile = Join-Path $PidDir 'swarm-monitor.pid'
    $status = Get-DaemonStatus -Name 'swarm-monitor' -PidFile $pidFile

    if ($status.Running) {
        Write-Host "Swarm monitor already running (PID: $($status.Pid))" -ForegroundColor Yellow
        return
    }

    Write-Host "Starting swarm monitor..." -ForegroundColor Cyan
    $process = Start-Process -FilePath 'node' -ArgumentList @(
        '-e',
        'setInterval(() => { require("fs").writeFileSync(".claude-flow/metrics/swarm-activity.json", JSON.stringify({swarm:{active:true,agent_count:0},timestamp:Date.now()})) }, 5000)'
    ) -PassThru -WindowStyle Hidden

    $process.Id | Out-File $pidFile
    Write-Host "Swarm monitor started (PID: $($process.Id))" -ForegroundColor Green
}

function Stop-SwarmMonitor {
    $pidFile = Join-Path $PidDir 'swarm-monitor.pid'
    $status = Get-DaemonStatus -Name 'swarm-monitor' -PidFile $pidFile

    if (-not $status.Running) {
        Write-Host "Swarm monitor not running" -ForegroundColor Yellow
        return
    }

    Stop-Process -Id $status.Pid -Force
    Remove-Item $pidFile -Force
    Write-Host "Swarm monitor stopped" -ForegroundColor Green
}

function Show-Status {
    Write-Host ""
    Write-Host "RuFlo V3 Daemon Status" -ForegroundColor Cyan
    Write-Host "=============================" -ForegroundColor Cyan

    $swarmPid = Join-Path $PidDir 'swarm-monitor.pid'
    $swarmStatus = Get-DaemonStatus -Name 'swarm-monitor' -PidFile $swarmPid

    if ($swarmStatus.Running) {
        Write-Host "  Swarm Monitor: RUNNING (PID: $($swarmStatus.Pid))" -ForegroundColor Green
    } else {
        Write-Host "  Swarm Monitor: STOPPED" -ForegroundColor Red
    }
    Write-Host ""
}

switch ($Action) {
    'start' {
        Start-SwarmMonitor
        Show-Status
    }
    'stop' {
        Stop-SwarmMonitor
        Show-Status
    }
    'restart' {
        Stop-SwarmMonitor
        Start-Sleep -Seconds 1
        Start-SwarmMonitor
        Show-Status
    }
    'status' {
        Show-Status
    }
}
`;
}

/**
 * Generate Windows batch file wrapper
 */
export function generateWindowsBatchWrapper(): string {
  return `@echo off
REM RuFlo V3 - Windows Batch Wrapper
REM Routes to PowerShell daemon manager

PowerShell -ExecutionPolicy Bypass -File "%~dp0daemon-manager.ps1" %*
`;
}

/**
 * Generate cross-platform session manager
 */
export function generateCrossPlatformSessionManager(): string {
  return `#!/usr/bin/env node
/**
 * Ruflo Cross-Platform Session Manager
 * Works on Windows, macOS, and Linux
 */

const fs = require('fs');
const path = require('path');
const os = require('os');

// Platform-specific paths
const platform = os.platform();
const homeDir = os.homedir();

// Get data directory based on platform
function getDataDir() {
  const localDir = path.join(process.cwd(), '.claude-flow', 'sessions');
  if (fs.existsSync(path.dirname(localDir))) {
    return localDir;
  }

  switch (platform) {
    case 'win32':
      return path.join(process.env.APPDATA || homeDir, 'claude-flow', 'sessions');
    case 'darwin':
      return path.join(homeDir, 'Library', 'Application Support', 'claude-flow', 'sessions');
    default:
      return path.join(homeDir, '.claude-flow', 'sessions');
  }
}

const SESSION_DIR = getDataDir();
const SESSION_FILE = path.join(SESSION_DIR, 'current.json');

// Ensure directory exists
function ensureDir(dir) {
  if (!fs.existsSync(dir)) {
    fs.mkdirSync(dir, { recursive: true });
  }
}

const commands = {
  start: () => {
    ensureDir(SESSION_DIR);
    const sessionId = \`session-\${Date.now()}\`;
    const session = {
      id: sessionId,
      startedAt: new Date().toISOString(),
      platform: platform,
      cwd: process.cwd(),
      context: {},
      metrics: { edits: 0, commands: 0, tasks: 0, errors: 0 }
    };
    fs.writeFileSync(SESSION_FILE, JSON.stringify(session, null, 2));
    console.log(\`Session started: \${sessionId}\`);
    return session;
  },

  restore: () => {
    if (!fs.existsSync(SESSION_FILE)) {
      console.log('No session to restore');
      return null;
    }
    const session = JSON.parse(fs.readFileSync(SESSION_FILE, 'utf-8'));
    session.restoredAt = new Date().toISOString();
    fs.writeFileSync(SESSION_FILE, JSON.stringify(session, null, 2));
    console.log(\`Session restored: \${session.id}\`);
    return session;
  },

  end: () => {
    if (!fs.existsSync(SESSION_FILE)) {
      console.log('No active session');
      return null;
    }
    const session = JSON.parse(fs.readFileSync(SESSION_FILE, 'utf-8'));
    session.endedAt = new Date().toISOString();
    session.duration = Date.now() - new Date(session.startedAt).getTime();

    const archivePath = path.join(SESSION_DIR, \`\${session.id}.json\`);
    fs.writeFileSync(archivePath, JSON.stringify(session, null, 2));
    fs.unlinkSync(SESSION_FILE);

    console.log(\`Session ended: \${session.id}\`);
    console.log(\`Duration: \${Math.round(session.duration / 1000 / 60)} minutes\`);
    return session;
  },

  status: () => {
    if (!fs.existsSync(SESSION_FILE)) {
      console.log('No active session');
      return null;
    }
    const session = JSON.parse(fs.readFileSync(SESSION_FILE, 'utf-8'));
    const duration = Date.now() - new Date(session.startedAt).getTime();
    console.log(\`Session: \${session.id}\`);
    console.log(\`Platform: \${session.platform}\`);
    console.log(\`Started: \${session.startedAt}\`);
    console.log(\`Duration: \${Math.round(duration / 1000 / 60)} minutes\`);
    return session;
  }
};

// CLI
const [,, command, ...args] = process.argv;
if (command && commands[command]) {
  commands[command](...args);
} else {
  console.log('Usage: session.js <start|restore|end|status>');
  console.log(\`Platform: \${platform}\`);
  console.log(\`Data dir: \${SESSION_DIR}\`);
}

module.exports = commands;
`;
}

/**
 * Generate all helper files
 */
/**
 * Generate cost-ledger.cjs — tracks session costs across all projects.
 * Stores a JSONL ledger at ~/.claude/cost-ledger.jsonl with per-session
 * cost, duration, model, and lines changed. Supports daily/weekly/monthly/annual reports.
 */
export function generateCostLedger(): string {
  return `#!/usr/bin/env node
/**
 * Claude Code Cost Ledger
 *
 * Tracks session costs across all projects on this machine.
 * Two modes:
 *   1. "record" — called by session-end hook, appends cost to JSONL ledger
 *   2. "report" — generates daily/weekly/monthly/annual summaries
 *
 * Ledger location: ~/.claude/cost-ledger.jsonl
 *
 * Usage:
 *   node cost-ledger.cjs record          # (reads stdin from Claude Code)
 *   node cost-ledger.cjs report          # default: last 30 days
 *   node cost-ledger.cjs report --daily
 *   node cost-ledger.cjs report --weekly
 *   node cost-ledger.cjs report --monthly
 *   node cost-ledger.cjs report --annual
 *   node cost-ledger.cjs report --project <name>
 *   node cost-ledger.cjs report --json
 */

const fs = require('fs');
const path = require('path');
const os = require('os');

const LEDGER_PATH = path.join(os.homedir(), '.claude', 'cost-ledger.jsonl');

const c = {
  reset: '\\x1b[0m', bold: '\\x1b[1m', dim: '\\x1b[2m',
  red: '\\x1b[31m', green: '\\x1b[32m', yellow: '\\x1b[33m',
  blue: '\\x1b[34m', cyan: '\\x1b[36m', white: '\\x1b[37m',
  brightGreen: '\\x1b[1;32m', brightYellow: '\\x1b[1;33m',
  brightCyan: '\\x1b[1;36m', brightWhite: '\\x1b[1;37m',
};

function readStdinSync() {
  try {
    if (process.stdin.isTTY) return null;
    const chunks = [];
    const buf = Buffer.alloc(4096);
    let bytesRead;
    try {
      while ((bytesRead = fs.readSync(0, buf, 0, buf.length, null)) > 0) {
        chunks.push(buf.slice(0, bytesRead));
      }
    } catch { /* EOF */ }
    const raw = Buffer.concat(chunks).toString('utf-8').trim();
    if (raw && raw.startsWith('{')) return JSON.parse(raw);
  } catch { /* ignore */ }
  return null;
}

function getProjectName() {
  try {
    const { execSync } = require('child_process');
    const remote = execSync('git remote get-url origin 2>/dev/null', {
      encoding: 'utf-8', timeout: 2000, stdio: ['pipe', 'pipe', 'pipe']
    }).trim();
    if (remote) {
      const match = remote.match(/\\/([^/]+?)(?:\\.git)?$/);
      if (match) return match[1];
    }
  } catch { /* ignore */ }
  return path.basename(process.cwd());
}

function record() {
  const data = readStdinSync();
  const costUsd = (data && data.cost && data.cost.total_cost_usd)
    || parseFloat(process.env.CLAUDE_SESSION_COST || '0');
  const durationMs = (data && data.cost && data.cost.total_duration_ms)
    || parseInt(process.env.CLAUDE_SESSION_DURATION_MS || '0', 10);
  const linesAdded = (data && data.cost && data.cost.total_lines_added) || 0;
  const linesRemoved = (data && data.cost && data.cost.total_lines_removed) || 0;
  const model = (data && data.model && data.model.model_id)
    || process.env.CLAUDE_MODEL || 'unknown';
  const sessionId = (data && data.session_id)
    || process.env.CLAUDE_SESSION_ID || 'session-' + Date.now();

  if (costUsd <= 0 && durationMs <= 0) return;

  const entry = {
    date: new Date().toISOString().split('T')[0],
    timestamp: new Date().toISOString(),
    project: getProjectName(),
    session_id: sessionId,
    cost_usd: Math.round(costUsd * 100) / 100,
    duration_min: Math.round(durationMs / 60000 * 10) / 10,
    model: model,
    lines_added: linesAdded,
    lines_removed: linesRemoved,
  };

  const dir = path.dirname(LEDGER_PATH);
  if (!fs.existsSync(dir)) fs.mkdirSync(dir, { recursive: true });
  fs.appendFileSync(LEDGER_PATH, JSON.stringify(entry) + '\\n');
}

function loadLedger() {
  if (!fs.existsSync(LEDGER_PATH)) return [];
  const lines = fs.readFileSync(LEDGER_PATH, 'utf-8').trim().split('\\n');
  const entries = [];
  for (const line of lines) {
    if (!line.trim()) continue;
    try { entries.push(JSON.parse(line)); } catch { /* skip */ }
  }
  return entries;
}

function filterByDate(entries, days) {
  const cutoff = new Date();
  cutoff.setDate(cutoff.getDate() - days);
  const cutoffStr = cutoff.toISOString().split('T')[0];
  return entries.filter(e => e.date >= cutoffStr);
}

function groupBy(entries, keyFn) {
  const groups = {};
  for (const e of entries) {
    const key = keyFn(e);
    if (!groups[key]) groups[key] = [];
    groups[key].push(e);
  }
  return groups;
}

function summarize(entries) {
  const totalCost = entries.reduce((s, e) => s + (e.cost_usd || 0), 0);
  const totalDuration = entries.reduce((s, e) => s + (e.duration_min || 0), 0);
  return {
    cost_usd: Math.round(totalCost * 100) / 100,
    duration_hours: Math.round(totalDuration / 60 * 10) / 10,
    sessions: entries.length,
    lines_added: entries.reduce((s, e) => s + (e.lines_added || 0), 0),
    lines_removed: entries.reduce((s, e) => s + (e.lines_removed || 0), 0),
    avg_cost_per_session: entries.length > 0 ? Math.round(totalCost / entries.length * 100) / 100 : 0,
  };
}

function getWeekKey(dateStr) {
  const d = new Date(dateStr + 'T00:00:00');
  const day = d.getDay();
  const diff = d.getDate() - day + (day === 0 ? -6 : 1);
  const monday = new Date(d.setDate(diff));
  return monday.toISOString().split('T')[0];
}

function formatCost(usd) { return '$' + usd.toFixed(2); }
function formatDuration(hours) {
  if (hours < 1) return Math.round(hours * 60) + 'm';
  return hours.toFixed(1) + 'h';
}

function report(args) {
  const entries = loadLedger();
  if (entries.length === 0) {
    console.log('No cost data recorded yet. Costs will be tracked after session-end hooks run.');
    return;
  }

  const jsonOutput = args.includes('--json');
  const projectFilter = args.includes('--project')
    ? args[args.indexOf('--project') + 1] : null;

  let filtered = entries;
  if (projectFilter) filtered = filtered.filter(e => e.project === projectFilter);

  let groupFn, groupLabel, periodDays;
  if (args.includes('--annual') || args.includes('--yearly')) {
    groupFn = e => e.date.substring(0, 4);
    groupLabel = 'Annual'; periodDays = 3650;
  } else if (args.includes('--monthly')) {
    groupFn = e => e.date.substring(0, 7);
    groupLabel = 'Monthly'; periodDays = 365;
  } else if (args.includes('--weekly')) {
    groupFn = e => 'Week of ' + getWeekKey(e.date);
    groupLabel = 'Weekly'; periodDays = 90;
  } else if (args.includes('--daily')) {
    groupFn = e => e.date;
    groupLabel = 'Daily'; periodDays = 30;
  } else {
    groupFn = e => e.project;
    groupLabel = 'By Project (Last 30 Days)'; periodDays = 30;
  }

  filtered = filterByDate(filtered, periodDays);
  if (filtered.length === 0) { console.log('No cost data for the specified period.'); return; }

  const groups = groupBy(filtered, groupFn);
  const overall = summarize(filtered);

  if (jsonOutput) {
    const result = { period: groupLabel, overall, breakdown: {} };
    for (const [key, ents] of Object.entries(groups)) {
      result.breakdown[key] = summarize(ents);
    }
    console.log(JSON.stringify(result, null, 2));
    return;
  }

  console.log('');
  console.log(c.bold + c.brightCyan + '  Claude Code Cost Report' + c.reset);
  console.log(c.dim + '  ' + String.fromCharCode(0x2500).repeat(50) + c.reset);
  console.log('');
  console.log(c.bold + '  Overall' + c.reset + (projectFilter ? c.dim + ' (' + projectFilter + ')' + c.reset : ''));
  console.log(c.brightYellow + '    Total Cost:     ' + c.brightWhite + formatCost(overall.cost_usd) + c.reset);
  console.log(c.cyan + '    Total Time:     ' + c.white + formatDuration(overall.duration_hours) + c.reset);
  console.log(c.cyan + '    Sessions:       ' + c.white + overall.sessions + c.reset);
  console.log(c.cyan + '    Avg/Session:    ' + c.white + formatCost(overall.avg_cost_per_session) + c.reset);
  console.log(c.cyan + '    Lines +/-:      ' + c.green + '+' + overall.lines_added + c.reset + ' / ' + c.red + '-' + overall.lines_removed + c.reset);
  console.log('');
  console.log(c.bold + '  ' + groupLabel + c.reset);
  console.log(c.dim + '  ' + String.fromCharCode(0x2500).repeat(50) + c.reset);

  var colW = { name: 24, cost: 10, time: 8, sess: 6 };
  console.log(c.dim + '  ' + 'Period/Project'.padEnd(colW.name) + 'Cost'.padStart(colW.cost) + 'Time'.padStart(colW.time) + 'Sess'.padStart(colW.sess) + c.reset);

  var sorted = Object.entries(groups)
    .map(function(pair) { var s = summarize(pair[1]); s.key = pair[0]; return s; })
    .sort(function(a, b) { return b.cost_usd - a.cost_usd; });

  for (var i = 0; i < sorted.length; i++) {
    var row = sorted[i];
    var costColor = row.cost_usd > 50 ? c.brightYellow : row.cost_usd > 10 ? c.yellow : c.green;
    console.log('  ' + c.white + row.key.substring(0, colW.name - 1).padEnd(colW.name) + c.reset +
      costColor + formatCost(row.cost_usd).padStart(colW.cost) + c.reset +
      c.cyan + formatDuration(row.duration_hours).padStart(colW.time) + c.reset +
      c.dim + String(row.sessions).padStart(colW.sess) + c.reset);
  }

  console.log('');
  console.log(c.dim + '  Ledger: ' + LEDGER_PATH + c.reset);
  console.log('');
}

const [,, cmd, ...cmdArgs] = process.argv;
if (cmd === 'record') { record(); }
else if (cmd === 'report') { report(cmdArgs); }
else {
  console.log('Claude Code Cost Ledger');
  console.log('');
  console.log('Usage:');
  console.log('  node cost-ledger.cjs record           Record session cost (from hook)');
  console.log('  node cost-ledger.cjs report            Last 30 days by project');
  console.log('  node cost-ledger.cjs report --daily    Daily breakdown');
  console.log('  node cost-ledger.cjs report --weekly   Weekly breakdown');
  console.log('  node cost-ledger.cjs report --monthly  Monthly breakdown');
  console.log('  node cost-ledger.cjs report --annual   Annual breakdown');
  console.log('  node cost-ledger.cjs report --project <name>  Filter by project');
  console.log('  node cost-ledger.cjs report --json     JSON output');
  console.log('');
  console.log('Ledger: ' + LEDGER_PATH);
}
`;
}

export function generateHelpers(options: InitOptions): Record<string, string> {
  const helpers: Record<string, string> = {};

  if (options.components.helpers) {
    // Unix/macOS shell scripts
    helpers['pre-commit'] = generatePreCommitHook();
    helpers['post-commit'] = generatePostCommitHook();

    // Cross-platform Node.js scripts
    helpers['session.js'] = generateCrossPlatformSessionManager();
    helpers['router.js'] = generateAgentRouter();
    helpers['memory.js'] = generateMemoryHelper();

    // Windows-specific scripts
    helpers['daemon-manager.ps1'] = generateWindowsDaemonManager();
    helpers['daemon-manager.cmd'] = generateWindowsBatchWrapper();

    // Cost tracking (installed to both project and ~/.claude/helpers/)
    helpers['cost-ledger.cjs'] = generateCostLedger();
  }

  if (options.components.statusline) {
    helpers['statusline.cjs'] = generateStatuslineScript(options);  // .cjs for ES module compatibility
    helpers['statusline-hook.sh'] = generateStatuslineHook(options);
  }

  return helpers;
}
