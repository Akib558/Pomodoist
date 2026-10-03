import { assertEquals, assertThrows } from "jsr:@std/assert@1";
import { type CollaborationDependencies, CollaborationError, validateCollaborationRequest } from "./pomodoist_collaboration.ts";
import { handleFiles, handleFilesCleanup, validateFilesRequest } from "./pomodoist_files.ts";

Deno.test("file targets accept personal/shared tasks/projects and reject ambiguity and invalid sizes", () => {
  for (const target of [{ taskId: "t" }, { projectId: "p" }, { scopeId: "s", projectId: "p" }]) {
    for (const action of ["capabilities", "reserveUpload"]) {
      const input = { action, ...target, uploadId: "u", name: "file", contentType: "text/plain", bytes: 20_000_000 };
      assertEquals(validateFilesRequest(input), input);
      if (action === "reserveUpload") assertEquals(validateCollaborationRequest({ ...input, scopeId: "s" }).projectId, input.projectId);
    }
  }
  for (const input of [null, [], { action: "state" }, { action: "capabilities" }, { action: "capabilities", taskId: "t", projectId: "p" },
    { action: "reserveUpload", taskId: "t", uploadId: "u", name: "f", contentType: "image/png", bytes: 20_000_001 },
    { action: "reserveUpload", taskId: "t", uploadId: "u", name: "f", contentType: "image/png", bytes: 0 },
    { action: "download", attachmentId: "a", preview: "true" }]) assertThrows(() => validateFilesRequest(input));
});

Deno.test("file signing follows SQL authorization and permits inline only for confirmed raster MIME", async () => {
  const downloads: unknown[] = [];
  let contentType = "image/png";
  let forbidden = false;
  const dependencies: CollaborationDependencies = {
    authenticate: async () => "user", rpc: async () => {
      if (forbidden) throw new CollaborationError("Forbidden", "42501", 403);
      return { objectPath: "authorized/path", name: "f", contentType };
    }, upload: async () => ({ signedUrl: "upload", token: "token" }),
    download: async (...args) => { downloads.push(args); return "signed"; },
    cleanup: async () => {}, inviteEmail: async () => {}, webUrl: "",
  };
  const request = (authorized = true) => new Request("https://files.invalid", { method: "POST", headers: authorized ? { Authorization: "Bearer jwt" } : {}, body: JSON.stringify({ action: "download", attachmentId: "a", preview: true, objectPath: "untrusted", contentType: "image/png" }) });
  assertEquals((await handleFiles(request(false), dependencies)).status, 401);
  assertEquals(downloads.length, 0);
  for (const mime of ["image/png", "image/svg+xml", "text/html", "application/pdf", "image/jpeg", "image/avif"]) {
    contentType = mime;
    const response = await handleFiles(request(), dependencies);
    assertEquals(response.status, 200);
    assertEquals(await response.json(), { name: "f", contentType: mime, url: "signed" });
  }
  assertEquals(downloads.map((call) => (call as unknown[])[2]), [true, false, false, false, true, true]);
  assertEquals((downloads[0] as unknown[])[0], "authorized/path");
  forbidden = true;
  assertEquals((await handleFiles(request(), dependencies)).status, 403);
  assertEquals(downloads.length, 6);
});

Deno.test("scheduled cleanup rejects users and retries failed storage work", async () => {
  let calls = 0;
  const cleanup = async () => { calls++; if (calls === 1) throw new Error("Storage down"); };
  for (const bearer of [null, "Bearer user", "Bearer "]) {
    const request = new Request("https://files.invalid", { method: "POST", headers: bearer ? { Authorization: bearer } : {} });
    assertEquals((await handleFilesCleanup(request, "service-secret", cleanup)).status, 401);
  }
  assertEquals(calls, 0);
  for (const secret of ["", "user", "service-secret-wrong"]) {
    const request = new Request("https://files.invalid", { method: "POST", headers: { "X-Pomodoist-Cleanup-Secret": secret } });
    assertEquals((await handleFilesCleanup(request, "service-secret", cleanup)).status, 401);
  }
  const request = () => new Request("https://files.invalid", { method: "POST", headers: { "X-Pomodoist-Cleanup-Secret": "service-secret", Authorization: "Bearer gateway-rewritten-token" } });
  assertEquals((await handleFilesCleanup(request(), "", cleanup)).status, 401);
  assertEquals(calls, 0);
  assertEquals((await handleFilesCleanup(request(), "service-secret", cleanup)).status, 503);
  assertEquals((await handleFilesCleanup(request(), "service-secret", cleanup)).status, 200);
  assertEquals(calls, 2);
});
