import { McpServer } from '@modelcontextprotocol/sdk/server/mcp.js';
import { StdioServerTransport } from '@modelcontextprotocol/sdk/server/stdio.js';
import * as z from 'zod/v4';
import { join, dirname } from 'path';
import { fileURLToPath } from 'url';
import { FileStore } from './lib/file-store.js';
import { registerTools } from './lib/tools.js';

const __dirname = dirname(fileURLToPath(import.meta.url));
const dataDir = process.env.ROUTE_DATA_DIR || join(__dirname, 'data');
const locksPath = process.env.TASK_LOCKS_PATH || join(__dirname, '..', '..', '01-tasks', 'TASK-LOCKS.json');

const store = new FileStore(join(dataDir, 'route-inbox.json'), locksPath);

const server = new McpServer({ name: 'moxton-route', version: '1.0.0' });
registerTools(server, z, store);

const transport = new StdioServerTransport();
await server.connect(transport);
console.error('moxton-route MCP server running');
