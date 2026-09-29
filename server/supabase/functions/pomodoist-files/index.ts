import { handleFiles } from "../_shared/pomodoist_files.ts";
import { collaborationRuntime } from "../_shared/pomodoist_collaboration_runtime.ts";
const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
const dependencies = collaborationRuntime({
  url: Deno.env.get("SUPABASE_URL") ?? "",
  publicUrl: Deno.env.get("SUPABASE_PUBLIC_URL"),
  key: serviceKey,
  rpcName: "pomodoist_files",
  storageEnabled: Deno.env.get("POMODOIST_FILES_STORAGE_ENABLED") === "true",
  webUrl: Deno.env.get("POMODOIST_WEB_URL") ?? "",
  env: Deno.env,
});
Deno.serve(request => handleFiles(request, dependencies));
