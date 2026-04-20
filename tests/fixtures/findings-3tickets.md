---
title: User Authentication Overhaul
findings_version: 1
slug_hint: user-auth-overhaul
---

# Findings: User Authentication Overhaul

## Context

Current login flow uses session cookies with a known session-fixation risk.
Product has asked for migration to short-lived JWT with refresh tokens.

## Investigation Summary

- `src/auth/login.ts` currently issues a session cookie with no rotation.
- `src/auth/middleware.ts` validates cookie on every request.
- No token-refresh endpoint exists today.
- Client SDK `clients/web/auth-client.ts` hardcodes cookie-based auth.

## Required Work Units

### 1. Issue JWT access + refresh tokens on login

Login endpoint returns `{ access_token, refresh_token, expires_in }` instead of setting a session cookie.
Affected: `src/auth/login.ts`, `src/auth/token.ts` (new).
Observable: POST /auth/login with valid credentials returns 200 and response body matches the token schema.

### 2. Validate JWT access token in request middleware

Replace cookie validation with Authorization header Bearer token validation. Reject expired tokens with 401.
Affected: `src/auth/middleware.ts`.
Observable: request with expired JWT returns 401 with body `{"error":"token_expired"}`.

### 3. Refresh-token rotation endpoint

POST /auth/refresh accepts a valid refresh token, returns a new access + refresh pair, and invalidates the old refresh token.
Affected: `src/auth/refresh.ts` (new), `src/auth/token.ts`.
Observable: using a refresh_token twice returns 401 on the second attempt.

## Dependencies

- Unit 2 depends on Unit 1 (middleware needs token-issuance infrastructure).
- Unit 3 depends on Unit 1 (refresh needs token infrastructure).
- Unit 2 and Unit 3 are independent of each other.
