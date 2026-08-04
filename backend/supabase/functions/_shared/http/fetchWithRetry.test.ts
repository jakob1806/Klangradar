import { assertEquals, assertRejects } from "jsr:@std/assert@1";
import { fetchWithRetry } from "./fetchWithRetry.ts";

function withMockedFetch<T>(impl: typeof fetch, fn: () => Promise<T>): Promise<T> {
  const original = globalThis.fetch;
  globalThis.fetch = impl;
  return fn().finally(() => {
    globalThis.fetch = original;
  });
}

Deno.test("returns the response on first success, no retry", async () => {
  let calls = 0;
  await withMockedFetch(
    () => {
      calls++;
      return Promise.resolve(new Response("ok", { status: 200 }));
    },
    async () => {
      const res = await fetchWithRetry("https://example.test", {}, { retries: 1, retryDelayMs: 0 });
      assertEquals(res.status, 200);
    },
  );
  assertEquals(calls, 1);
});

Deno.test("retries once on 5xx then returns the successful retry", async () => {
  let calls = 0;
  await withMockedFetch(
    () => {
      calls++;
      return Promise.resolve(
        calls === 1 ? new Response("err", { status: 503 }) : new Response("ok", { status: 200 }),
      );
    },
    async () => {
      const res = await fetchWithRetry("https://example.test", {}, { retries: 1, retryDelayMs: 0 });
      assertEquals(res.status, 200);
    },
  );
  assertEquals(calls, 2);
});

Deno.test("does not retry on 4xx — returns the response immediately", async () => {
  let calls = 0;
  await withMockedFetch(
    () => {
      calls++;
      return Promise.resolve(new Response("not found", { status: 404 }));
    },
    async () => {
      const res = await fetchWithRetry("https://example.test", {}, { retries: 1, retryDelayMs: 0 });
      assertEquals(res.status, 404);
    },
  );
  assertEquals(calls, 1);
});

Deno.test("retries once on a thrown network error, then throws after exhausting retries", async () => {
  let calls = 0;
  await withMockedFetch(
    () => {
      calls++;
      return Promise.reject(new TypeError("network error"));
    },
    async () => {
      await assertRejects(
        () => fetchWithRetry("https://example.test", {}, { retries: 1, retryDelayMs: 0 }),
        Error,
        "network error",
      );
    },
  );
  assertEquals(calls, 2);
});

Deno.test("passes a 304 through untouched, no retry", async () => {
  let calls = 0;
  await withMockedFetch(
    () => {
      calls++;
      return Promise.resolve(new Response(null, { status: 304 }));
    },
    async () => {
      const res = await fetchWithRetry("https://example.test", {}, { retries: 1, retryDelayMs: 0 });
      assertEquals(res.status, 304);
    },
  );
  assertEquals(calls, 1);
});
