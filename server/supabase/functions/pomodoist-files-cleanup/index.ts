import { handleFilesCleanup } from "../_shared/pomodoist_files.ts";
import { collaborationRuntime } from "../_shared/pomodoist_collaboration_runtime.ts";
const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
const workerSecret = Deno.env.get("POMODOIST_FILES_CLEANUP_SECRET") ?? serviceKey;
const dependencies = collaborationRuntime({
  url: Deno.env.get("SUPABASE_URL") ?? "",
  publicUrl: Deno.env.get("SUPABASE_PUBLIC_URL"),
  key: serviceKey,
  rpcName: "pomodoist_files",
  webUrl: Deno.env.get("POMODOIST_WEB_URL") ?? "",
  env: Deno.env,
});
Deno.serve(request => handleFilesCleanup(request, workerSecret, dependencies.cleanup));
