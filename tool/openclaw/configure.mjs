import { runCli } from './skills/pomodoist/scripts/configure.mjs';

export { buildConfig, connectionCommands, runCli } from './skills/pomodoist/scripts/configure.mjs';

if (import.meta.main) runCli();
