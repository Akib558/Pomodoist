import { CollaborationError, type CollaborationDependencies, handleCollaboration, integer, type Json, required, validateFileTarget } from "./pomodoist_collaboration.ts";

export function validateFilesRequest(value: unknown): Json {
  if (!value || typeof value !== "object" || Array.isArray(value)) throw new CollaborationError("Expected request object");
  const input = value as Json;
  const action = required(input, "action");
  if (!["capabilities", "reserveUpload", "finishUpload", "download", "deleteAttachment"].includes(action)) throw new CollaborationError("Unknown files action");
  if (input.scopeId != null) required(input, "scopeId");
  if (["capabilities", "reserveUpload"].includes(action)) validateFileTarget(input);
  if (action === "reserveUpload") {
    for (const key of ["uploadId", "contentType"]) required(input, key);
    required(input, "name", 255);
    if (!integer(input, "bytes", 20_000_000)) throw new CollaborationError("Empty attachment");
  }
  if (action === "finishUpload") required(input, "uploadId");
  if (["download", "deleteAttachment"].includes(action)) required(input, "attachmentId");
  if (input.preview !== undefined && typeof input.preview !== "boolean") throw new CollaborationError("Invalid preview");
  return input;
}

export function handleFiles(request: Request, dependencies: CollaborationDependencies): Promise<Response> {
  return handleCollaboration(request, dependencies, validateFilesRequest);
}

export async function handleFilesCleanup(request: Request, serviceKey: string, cleanup: () => Promise<void>): Promise<Response> {
  const headers = { "Cache-Control": "no-store" };
  if (request.method !== "POST") return Response.json({ error: "POST required" }, { status: 405, headers });
  // Only the configured server credential can dispatch deletion work; user JWTs cannot.
  if (!serviceKey || request.headers.get("Authorization") !== `Bearer ${serviceKey}`) {
    return Response.json({ error: "Authentication required" }, { status: 401, headers });
  }
  try {
    await cleanup();
    return Response.json({ ok: true }, { headers });
  } catch {
    return Response.json({ error: "Storage cleanup unavailable" }, { status: 503, headers });
  }
}
