import { assertEquals } from "jsr:@std/assert@1";
import {
  parseEmailAllowlist,
  resolvePortalAccess,
  timingSafeEqual,
} from "./access.ts";

Deno.test("allowlisted authenticated account gets passwordless access", () => {
  const allowlist = parseEmailAllowlist(
    " editor@example.com,Second@example.com ",
  );
  assertEquals(
    resolvePortalAccess({
      authenticatedEmail: "EDITOR@EXAMPLE.COM",
      passwordlessEmails: allowlist,
      submittedPassword: "",
      expectedPassword: "server-password",
    }),
    "account",
  );
});

Deno.test("other accounts still need the shared password", () => {
  const allowlist = parseEmailAllowlist("editor@example.com");
  assertEquals(
    resolvePortalAccess({
      authenticatedEmail: "other@example.com",
      passwordlessEmails: allowlist,
      submittedPassword: "server-password",
      expectedPassword: "server-password",
    }),
    "password",
  );
  assertEquals(
    resolvePortalAccess({
      authenticatedEmail: "other@example.com",
      passwordlessEmails: allowlist,
      submittedPassword: "wrong",
      expectedPassword: "server-password",
    }),
    null,
  );
});

Deno.test("anonymous users cannot use the account allowlist", () => {
  assertEquals(
    resolvePortalAccess({
      authenticatedEmail: null,
      passwordlessEmails: parseEmailAllowlist("editor@example.com"),
      submittedPassword: "",
      expectedPassword: "server-password",
    }),
    null,
  );
});

Deno.test("password comparison handles equal, unequal and unicode input", () => {
  assertEquals(timingSafeEqual("abc123", "abc123"), true);
  assertEquals(timingSafeEqual("abc123", "abc124"), false);
  assertEquals(timingSafeEqual("kurz", "deutlich-laenger"), false);
  assertEquals(timingSafeEqual("München", "München"), true);
});
