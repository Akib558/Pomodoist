import { assertEquals, assert } from "jsr:@std/assert@1";
import { collaborationRuntime } from "./pomodoist_collaboration_runtime.ts";
Deno.test("Storage signing keeps internal service traffic but returns public capability URLs", async () => {
  const calls: string[] = [];
  const runtime = collaborationRuntime({ url: "http://gateway:8000", publicUrl: "https://api.example.com",
    key: "fake-service-key", webUrl: "https://app.example.com", env: { get: () => undefined },
    fetcher: async (input) => {
      const url = String(input); calls.push(url);
      return Response.json(url.includes("/upload/sign/") ? { url: "/object/upload/sign/pomodoist-shared/path?token=fake" } :
        { signedURL: "/object/sign/pomodoist-shared/path?token=fake" });
    },
  });
  const upload = await runtime.upload("path");
  const download = await runtime.download("path", "notes.txt");
  assert(upload.signedUrl.startsWith("https://api.example.com/storage/v1/"));
  assert(download.startsWith("https://api.example.com/storage/v1/"));
  assertEquals(calls.every(url => url.startsWith("http://gateway:8000/")), true);
});

Deno.test("inline URLs omit download; forced downloads carry a filename", async () => {
  const runtime = collaborationRuntime({ url: "https://storage.invalid", key: "service-key", webUrl: "", env: { get: () => undefined },
    fetcher: async () => Response.json({ signedURL: "/object/sign/pomodoist-shared/path?token=fake" }),
  });
  assertEquals(new URL(await runtime.download("path", "file.svg")).searchParams.get("download"), "file.svg");
  assertEquals(new URL(await runtime.download("path", "file.png", true)).searchParams.has("download"), false);
});

Deno.test("cleanup retains queue when removal fails and acknowledges only successful retries", async () => {
  const acknowledgements: unknown[] = [];
  let fail = true;
  const runtime = collaborationRuntime({ url: "https://storage.invalid", key: "service-key", webUrl: "", env: { get: () => undefined },
    fetcher: async (input, options) => {
      if (String(input).includes("/rest/v1/rpc/")) {
        const body = JSON.parse(String(options?.body ?? "{}"));
        if (body.p_deleted) acknowledgements.push(body.p_deleted);
        return Response.json({ paths: ["pending/path"] });
      }
      return fail ? Response.json({ message: "Unavailable" }, { status: 503 }) : Response.json([]);
    },
  });
  let rejected = false;
  try { await runtime.cleanup(); } catch { rejected = true; }
  assertEquals(rejected, true);
  assertEquals(acknowledgements, []);
  fail = false;
  await runtime.cleanup();
  assertEquals(acknowledgements, [["pending/path"]]);
});

Deno.test("files runtime uses its RPC and reports disabled storage without signing", async () => {
  const paths: string[] = [];
  const runtime = collaborationRuntime({ url: "https://storage.invalid", key: "service-key", webUrl: "", env: { get: () => undefined },
    rpcName: "pomodoist_files", storageEnabled: false,
    fetcher: async input => { paths.push(String(input)); return Response.json({ canUpload: true, reason: null }); },
  });
  assertEquals(await runtime.rpc("Bearer user", { action: "capabilities", projectId: "p" }), { canUpload: false, reason: "storage_unavailable" });
  assertEquals(paths, ["https://storage.invalid/rest/v1/rpc/pomodoist_files"]);
  let rejected = false;
  try { await runtime.rpc("Bearer user", { action: "reserveUpload" }); } catch { rejected = true; }
  assertEquals(rejected, true);
  assertEquals(paths.length, 1);
});
