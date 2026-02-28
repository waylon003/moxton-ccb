import { createHash } from 'crypto';
import { mapRouteToLockState } from './state-mapper.js';

function routeId(from, task, status, body) {
  return createHash('sha256').update(`${from}|${task}|${status}|${body}`).digest('hex').slice(0, 16);
}

export function registerTools(server, z, store) {
  server.registerTool('report_route', {
    description: 'Report task completion status to Team Lead. Workers MUST call this after finishing a task.',
    inputSchema: z.object({
      from: z.string().describe('Worker name, e.g. backend-dev, shop-fe-qa'),
      task: z.string().describe('Task ID, e.g. BACKEND-008'),
      status: z.enum(['success', 'fail', 'blocked', 'in_progress']).describe('Task status'),
      body: z.string().describe('Result summary: files changed, commands run, test results')
    })
  }, async ({ from, task, status, body }) => {
    const id = routeId(from, task, status, body);

    return store.withLock(store.inboxPath, async () => {
      const inbox = await store.readInbox();
      if (inbox.routes.some(r => r.id === id)) {
        return { content: [{ type: 'text', text: JSON.stringify({ success: true, duplicate: true, routeId: id }) }] };
      }

      inbox.routes.push({
        id, from, to: 'team-lead', type: 'status',
        task, status, body,
        created_at: new Date().toISOString(),
        processed: false, processed_at: null
      });
      await store.writeInbox(inbox);

      // Update TASK-LOCKS.json
      let lockWarning = null;
      await store.withLock(store.locksPath, async () => {
        const locks = await store.readLocks();
        if (locks?.locks?.[task]) {
          const newState = mapRouteToLockState(status, from);
          locks.locks[task].state = newState;
          locks.locks[task].updated_at = new Date().toISOString();
          locks.locks[task].updated_by = 'mcp-route-server/report_route';
          locks.locks[task].routeUpdate = { worker: from, timestamp: new Date().toISOString(), bodyPreview: (body || '').slice(0, 200) };
          await store.writeLocks(locks);
        } else {
          lockWarning = `Task '${task}' not found in TASK-LOCKS.json. Route saved to inbox but lock not updated.`;
        }
      });

      const result = { success: true, routeId: id, timestamp: new Date().toISOString() };
      if (lockWarning) result.warning = lockWarning;
      return { content: [{ type: 'text', text: JSON.stringify(result) }] };
    });
  });

  server.registerTool('check_routes', {
    description: 'Check pending route messages from Workers.',
    inputSchema: z.object({
      filter_task: z.string().optional().describe('Filter by task ID'),
      filter_status: z.enum(['success', 'fail', 'blocked', 'in_progress']).optional().describe('Filter by status'),
      include_processed: z.boolean().optional().default(false).describe('Include processed routes')
    })
  }, async ({ filter_task, filter_status, include_processed }) => {
    const inbox = await store.readInbox();
    let routes = inbox.routes;
    if (!include_processed) routes = routes.filter(r => !r.processed);
    if (filter_task) routes = routes.filter(r => r.task === filter_task);
    if (filter_status) routes = routes.filter(r => r.status === filter_status);
    return { content: [{ type: 'text', text: JSON.stringify({ pending: routes, count: routes.length }) }] };
  });

  server.registerTool('clear_route', {
    description: 'Mark route messages as processed.',
    inputSchema: z.object({
      route_id: z.string().optional().describe('Specific route ID to clear'),
      clear_all: z.boolean().optional().default(false).describe('Clear all pending routes')
    })
  }, async ({ route_id, clear_all }) => {
    return store.withLock(store.inboxPath, async () => {
      const inbox = await store.readInbox();
      let cleared = 0;
      const now = new Date().toISOString();
      for (const r of inbox.routes) {
        if (r.processed) continue;
        if (clear_all || r.id === route_id) {
          r.processed = true;
          r.processed_at = now;
          cleared++;
        }
      }
      await store.writeInbox(inbox);
      return { content: [{ type: 'text', text: JSON.stringify({ cleared }) }] };
    });
  });
}
