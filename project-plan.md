# Payroll Automation — Project Plan

Cross-checked against `Final-Payroll-Automotion-Application.drawio` (activity
diagram) and current code in `Payroll Automation/`. Two parts: Frontend
(Angular, complete) and Backend (Spring Boot + local PostgreSQL, complete —
every collection real-backed, real JWT auth wired end-to-end). **Correction,
2026-09-01**: this line originally read "mostly done, currently mock-backed" /
"not started" — both stale by the time of a full audit; see §2.12 for the
reconciliation and why. Business logic (validation, calculations) stays in
the frontend's `*-rules.ts` files by design — the backend is a deliberately
thin, auditable CRUD layer with a few service-layer exceptions where a
state-machine genuinely needs server-side enforcement (§2.9–§2.11); do not
port frontend logic to Java without a real problem forcing it.

**Standing instruction (2026-09-01 onward)**: after every completed task,
this file is updated in the same turn with the actual result, tests, and
current status — never leave finished work marked `⬜ Not done`.

---

## Part 1 — Frontend (Angular 21, standalone + signals, zoneless, NgRx, Tailwind v4)

### 1.1 Foundation
- ✅ Done — Project scaffold, design tokens, app shell, sidebar nav, routing
- ✅ Done — Mock DB (`mock-db.ts`, 26 collections) + `MockApiService` (fake HTTP, 250ms delay)
- ✅ Done — NgRx store/effects/entity generic `createCollectionFeature` factory
- ✅ Done — Role-based module registry (`core/module-registry.ts`)

### 1.2 Auth & role flow (diagram: `Login → Valid Credentials? → Determine Role`)
- ✅ Done — Sign-in screen, reactive form, show/hide password, one-click demo fill
- ✅ Done — Static demo credentials per role (Admin/HR/Accountant/Employee)
- ✅ Done — `authGuard`, `guestGuard`, `roleGuard` (blocks unreachable modules by URL too)
- ✅ Done — Session in `sessionStorage`, survives reload
- ✅ Done — Sign-in/out written to audit trail
- ✅ Done — Change password (self-service), session-scoped via `PasswordStore`
- ✅ Done — Accounts created from Users & Roles can sign in immediately, via `RuntimeCredentialStore`
- ✅ Done (correction, 2026-09-01) — `session.ts` calls the real
  BCrypt+JWT backend (`POST /api/auth/login`) first, with `TokenStore` +
  `auth-interceptor.ts` handling real token storage/attachment; falls back
  to the local mock only for an account the real backend doesn't recognize
  yet — see §2.3's correction for the full detail

### 1.3 Admin flow (diagram: Master Data / User Mgmt / Payroll Config / Reports)
- ✅ Done — Employees CRUD (list + detail), draft profile activation (Admin-only), onboard flow creates a real draft profile via `employee-form.ts`
- ✅ Done — Organisation master data: Department, Designation, Shift, Holiday (tabbed, full create/edit forms)
- ✅ Done — **Bug fix: Edit modals for Department/Designation/Shift/Holiday
  opened empty.** Reported live: clicking "Edit" on any of the four
  Organisation master-data tables showed a blank form instead of the
  record's current values (Add worked fine). Root cause: all four forms
  (`department-form.ts`, `designation-form.ts`, `shift-form.ts`,
  `holiday-form.ts`) read the `existing` signal `input()` directly inside
  the constructor to seed the reactive form — but Angular signal inputs are
  not populated until *after* the constructor runs, so `this.existing()`
  always saw its default (`null`) there, meaning the prefill branch never
  ran on Edit. `employee-form.ts` already had this exact bug and already
  fixed it, with a comment explaining why — the fix wasn't propagated to
  the other four master-data forms when they were built. Applied the same
  fix: moved each form's prefill logic inside `effect(() => {...})`, which
  runs after inputs are set. No template or architecture changes. Verified
  live in a real browser against the real backend, Admin role: Edit on
  Department ("HRM"/"Human Resources"), Designation ("General
  Manager"/"M1"), Shift ("General(Day)", 08:01 AM–05:00 PM, 60/10 min) and
  Holiday ("International Mother Language Day", 2026-02-02, public) all now
  open correctly prefilled with the record's real data. Zero console
  errors. `npx tsc --noEmit`, `ng build`, `ng test` (93/93 passing) all
  clean.
- ✅ Done — Users & Roles: accounts, roles, permission matrix — full create/edit via `user-form.ts`, new accounts can sign in immediately
- ✅ Done — Salary & Rules: Salary Structure, Tax Rule, PF Rule (tabbed, full create/edit forms)
- ✅ Done — "System-wide Reports" screen (diagram node `AdminReports`): `/reports`, Admin-only. Headcount by department, payroll cycle totals, leave/overtime approval rates, audit activity by module — built on existing collections, no new mock data

### 1.4 HR flow (diagram: Attendance / Leave / Overtime / Onboard / Trigger Payroll)
- ✅ Done — Attendance register, late flags, HR correction form
- ✅ Done — Leave: apply, validate, approve/reject with reason, balance movement, audit — **reference module, full submission + approval loop**
- ✅ Done — **Leave: fixed a broken application flow and added Admin/HR-configurable
  leave rules.** Reported live: applying for leave showed every type as "not
  entitled" and blocked submission. Root cause, two layers:
  1. No `LeaveRule` concept existed anywhere — entitlement only ever came from
     a pre-existing `LeaveBalance` row, and the real backend's demo accounts
     (`e1`/`e2`/`e4`/`e7`, seeded by `V8`) never got one, so every self-service
     application from a demo account failed the balance check before it could
     even reach HR.
  2. `leave-page.ts`'s `onSubmitted()` had the same fire-and-forget bug already
     fixed on Change Requests (§1.8): it dispatched the save and immediately
     showed "submitted" without waiting for the async result, so a backend
     rejection would leave the employee thinking it worked while HR's queue
     never got the row.
  Fixed both: new `LeaveRule` collection (Admin/HR-configurable annual
  entitlement per type — Casual 10 / Sick 14 / Earned 18 / Maternity 112 by
  default), backend `V11__leave_rules.sql` + `LeaveRule` entity/repo/controller
  (`/api/leave-rules`) plus a one-time seed of real `leave_balance` rows for
  the four demo employees; `leave-rules.ts`'s `validateLeaveRequest` now falls
  back to the configured rule's entitlement when no balance row exists yet
  instead of blocking outright, and `initialBalance()` seeds a real balance on
  first use; new "Leave rules" panel on the Leave page (Admin/HR only) to edit
  entitlements inline; `onSubmitted()` now waits for the real
  `upsertManySuccess`/`upsertManyFailure` action before saying "submitted",
  with a red error banner on genuine failure — matching the Change Requests
  fix exactly.
- ✅ Done — **Leave: full flow reviewed and verified end-to-end** (Employee →
  Apply → HR/Admin Approve/Reject → Leave Balance → Payroll impact). One more
  bug found and fixed along the way: `leave-detail.ts`'s constructor never
  dispatched `employeesFeature.actions.load()` (the same gap already fixed on
  `loan-detail.ts`/`bonus-detail.ts`/`settlement-detail.ts` per §1.10) — a
  direct link to `/leave/:id` (no prior visit to the Leave list) showed the
  employee name and code as "—" instead of resolving them. Fixed by adding the
  dispatch, matching the established convention.
  Verified live against the real backend: signed in as Tanvir Ahmed
  (Employee), applied for Sick leave — dropdown correctly showed "Sick — 14
  day(s) left" instead of "not entitled"; signed in as Admin, confirmed the
  request appeared in the approval queue (Admin, not just HR, can decide —
  `canApproveLeave` includes both); rejected it with a reason, confirmed
  balance stayed untouched (Taken 0, Remaining 14) since it was never
  approved, and that rejecting with an empty reason is blocked. Applied again
  as Employee for 2 days Unpaid leave, confirmed it reached the queue,
  navigated directly to its detail URL as HR (bypassing the list page) —
  confirmed the "—" bug, applied the fix, reloaded, confirmed "Tanvir Ahmed ·
  Unpaid leave" now resolves correctly. Approved it. Seeded a test salary
  structure and a July payroll batch via curl, ran the actual payroll engine
  through the UI ("Lock cycle and run engine") — resulting payslip showed
  **Unpaid leave deduction ৳2,000** (2 days × ৳1,000/day, gross ÷ 31-day
  cycle), correctly folded into Total deductions and Net pay (৳31,000 →
  ৳29,000), both on the raw payslip data and the rendered payslip detail page.
  Zero console errors throughout. `npx tsc --noEmit`, `ng build` (zero
  warnings), `ng test` (109/109 passing), `mvnw compile` all clean. All test
  data (leave requests, salary structure, payroll batch, payslips) deleted
  afterward; the four demo employees' seeded leave balances (from the fix
  above) are intentionally permanent, via migration, not test data.
- ✅ Done — **Leave: escalation chain rework — real gap closed.** Audited
  against the exact requirement (Employee/Accountant → HR or Admin decide;
  HR → Admin only; Admin → HR only; no one decides their own leave) and
  found `canDecide` in both `leave-page.ts`'s approval queue and
  `leave-detail.ts`'s decision panel was a flat `['HR','Admin'].includes(role)`
  gate — **any** HR or Admin account could approve/reject **any** pending
  leave, including their own. Reused the exact escalation pattern already
  proven for Change Requests (§1.8's `canDecideChangeRequest`) rather than
  inventing a new one: `LeaveRequest` gained an optional `requesterRole`
  field (frontend `hr.ts`; backend `V13__leave_request_requester_role.sql` +
  `LeaveRequest.java` entity field, mirroring `V7` exactly), stamped by
  `leave-form.ts` on submit; new `canDecideLeaveRequest`/
  `leaveApproverLabelFor` in `leave-rules.ts` (9 new unit tests) applying the
  same matrix (`Employee`/`Accountant` → `[HR, Admin]`, `HR` → `[Admin]`,
  `Admin` → `[HR]`, and `requesterEmployeeId === approverEmployeeId` always
  blocks regardless of role). `leave-page.ts`'s approval queue now filters
  through a `decidableQueue` computed instead of showing every pending row
  to every approver; `leave-detail.ts`'s `canDecide` is now matrix-checked
  per request instead of a flat role flag — same defense-in-depth as Change
  Requests (blocked at both the queue filter and the detail page itself).
  Also widened `module-registry.ts`'s Leave entry to include `Accountant`
  (previously Admin/HR/Employee only — Accountant had no way to apply for
  leave at all, despite the requirement explicitly naming them as a
  requester), and `leave-page.ts`'s self-service view (`isSelfService`) now
  covers Employee **and** Accountant, matching the Change Requests page's
  `isManager`/self-view split exactly.
  **Backend limitation, stated plainly rather than glossed over**: real
  server-side enforcement of "cannot approve your own leave" requires
  knowing who is actually making the API call. This backend has no
  authentication at all yet (§2.3, on hold per your standing instruction)
  — every `/api/**` call is anonymous CRUD, and there is no `AppUser` table
  or username→employeeId mapping in Postgres for a controller to check
  against. The `requester_role` column now persists real context for when
  auth lands, but nothing server-side can currently stop a raw `curl PUT`
  from setting any `employeeId`/`approvedBy` pair — this is the same
  boundary every other role check in this app already operates within, not
  a gap unique to Leave. Enforcement today is frontend-only (queue filter +
  detail-page guard), matching what "keep the existing architecture" meant
  in this codebase's current phase.
  Full frontend suite **137/137 passing** (was 128, +9 new), `npx tsc
  --noEmit` clean, `ng build` clean, backend `mvnw compile` clean.
  **Verified live against the real backend**: compiled the actual
  `leave-rules.ts` via the project's own `tsc` and drove it against real
  data — seeded one pending leave request per role for the real permanent
  demo employees (Employee/e4, Accountant/e2, HR/e1, Admin/e7), confirmed
  `requesterRole` persisted correctly through Postgres for all four, then
  replayed `canDecideLeaveRequest` across **all 16 requester×decider
  combinations** — every one matched the spec exactly, including the two
  critical self-approval cases (HR/e1 deciding HR/e1's own leave → `false`;
  Admin/e7 deciding Admin/e7's own leave → `false`) and the two escalation
  boundaries (HR's leave only decidable by Admin, not by other HR; Admin's
  leave only decidable by HR, not by other Admin). All test rows deleted
  afterward, confirmed via `psql`, backend dev server stopped.
- ✅ Done — **Dashboard leave pending-count over-counting — the flagged item
  above, now fixed.** Investigated first, per the ask, before changing
  anything: `dashboard-page.ts`'s HR "Leave to approve" tile, Admin "Pending
  approvals" tile, and the shared right-column "Approval queue" list all
  read `pendingLeave()` directly — a flat `status === 'pending'` filter with
  no matrix check — the exact same class of bug §1.9 had already found and
  fixed on the Change Requests tile (`myDecidableChangeRequests`, using
  `canDecideChangeRequest`) before the Leave escalation chain even existed.
  Confirmed live in this pass's own verification: with one pending request
  seeded per role, the flat count showed **4** to both HR and Admin — including
  each viewer's own leave, which they can never actually decide per the
  matrix above.
  Fixed by mirroring `myDecidableChangeRequests` exactly, not inventing a new
  pattern: new `myDecidableLeave` computed applies `canDecideLeaveRequest`
  (the same matrix `leave-page.ts`'s own queue already uses) to
  `pendingLeave()`. Swapped into all three places that were reading the flat
  count: HR's "Leave to approve" tile, Admin's "Pending approvals" tile
  (still summed with `pendingOt()`, unaffected — Overtime has no requester
  escalation matrix, so its flat count is correct as-is and intentionally
  untouched), and the shared `queue` list-builder. `pendingLeave()` itself is
  unchanged and still used correctly for the Employee's own "my pending
  requests" tile (`myPending`), which is supposed to show the viewer's own
  submissions, not what they can decide — no matrix filter belongs there.
  `npx tsc --noEmit` clean, `ng build` clean, `ng test` unchanged at
  **137/137 passing** (reuses the already-tested `canDecideLeaveRequest`, no
  new pure logic to cover).
  **Verified live against the real backend**: seeded one pending leave
  request per role for the four real demo employees (Employee/e4,
  Accountant/e2, HR/e1, Admin/e7), confirmed the flat count would have been
  **4** for every viewer (the bug, reproduced), then replayed the real
  `canDecideLeaveRequest` the fixed tile now uses — **HR (e1) sees 3**
  (Employee, Accountant, Admin — excluding their own HR request) and
  **Admin (e7) sees 3** (Employee, Accountant, HR — excluding their own
  Admin request), matching the fix exactly. All test rows deleted
  afterward, confirmed via `psql`, backend dev server stopped.
- ✅ Done — **Bug fix: "Admin/HR has not configured Casual leave yet" shown
  incorrectly on Apply Leave.** Investigated end to end before touching
  anything: confirmed via direct `curl` that the real Postgres `leave_rule`
  table genuinely has all four types configured (`Casual: 10`, `Sick: 14`,
  `Earned: 18`, `Maternity: 112`) — the data was never missing. Confirmed
  `/leave` route's providers and `leave-page.ts`'s constructor both already
  dispatch `leaveRulesFeature.actions.load()` correctly, and
  `entitlementFor`/`validateLeaveRequest` in `leave-rules.ts` were unchanged
  by the escalation-chain work above. Root cause: `HybridApiService.list()`
  has no `catchError` — when the backend is unreachable (as it repeatedly is
  between this project's own verification passes, and evidently was when
  this was reported), the failed HTTP call resolves to `loadFailure`,
  `leaveRulesFeature`'s state stays at its initial empty array, and
  `entitlementFor` silently returns `0` for every type. Nothing distinguished
  that from Admin/HR genuinely never having configured a type — both produce
  the exact same empty-rules state, so the message picked the wrong (but not
  false) explanation. Not a data bug, not a logic bug — a missing distinction
  between "no rule exists" and "we couldn't ask the server."
  Fixed additively, without touching `validateLeaveRequest` or any other pure
  logic: `leave-page.ts` now also selects `leaveRulesFeature.selectors.error`
  and passes it into `leave-form.ts` as a new `rulesError` input; the form
  shows a clear red banner ("Could not load the leave policy from the
  server… check the backend is running") whenever a load actually failed,
  instead of silently falling through to the generic "not configured"
  wording. `LeaveRule`/`entitlementFor`/`validateLeaveRequest` are completely
  unchanged — the fix is purely "tell the user what actually went wrong,"
  not a change to any entitlement or validation rule.
  `npx tsc --noEmit` clean, `ng build` clean, `ng test` unchanged at
  **137/137 passing** (no logic changed, so no new/altered test needed).
  **Verified live against the real backend**, specifically the scenario from
  the report — a newly onboarded employee with **zero** leave-balance rows
  (not one of the four demo accounts, which already carry seeded balances
  via `V11`): seeded a genuine new employee via curl, confirmed 0 balance
  rows on file, then replayed `entitlementFor`/`validateLeaveRequest` (the
  real compiled functions, unmodified) against the live `/api/leave-rules`
  and `/api/leave-balances` data exactly as `leave-form.ts` would — Casual
  entitlement resolved to `10` and `validateLeaveRequest` returned **no
  `leaveType` error at all**, confirming a brand-new employee can apply for
  Casual leave (falling back to the configured rule, per the original §1.4
  fix) once the backend is actually reachable. Test employee deleted
  afterward, confirmed via `psql`, backend dev server stopped.
- ✅ Done — Overtime: `attendance-page.ts` still auto-calculates and records overtime from check-out, but the workflow now matches the real Bangladesh weekly-hour rule and closes the HR gate: **check-in → check-out → calculate worked hours → calculate overtime → validate against the weekly limit (48 regular + 12 overtime = 60 total h/week, via `overtime-rules.ts`'s `weeklyHours`/`cappedOvertimeHours`) → `pending` → HR approves or rejects on the detail page → approved = payroll eligible**. Excess hours beyond the weekly/daily cap are simply not recorded, matching the diagram's "Block and escalate". The old flat monthly-hour ceiling and the unreachable manual claim form (`overtime-form.ts`) are gone; nothing in the UI implied a claim path that didn't work
- ✅ Done — Onboard employee (create draft profile) → notify-admin-to-activate half implemented via draft employee state
- ✅ Done — Trigger payroll cycle (lock + run engine) from HR side of Payroll Batches

### 1.5 System automation — Payroll Engine (diagram: Lock data → Calc hours → Calc leave → Gross → Deductions → Net → Generate batch)
- ✅ Done — `core/payroll-engine.ts`, pure function, matches diagram sequence exactly
- ✅ Done — Batch lifecycle: `draft → calculated → pending-approval → approved → paid`, `returned` reject path
- ✅ Done — Verified live: engine run produces payslips, gross/deductions/net totals correct

### 1.6 Accountant flow (diagram: Verify batch → Approve/Reject → Generate bank file → Process payment → Payslips → Notify)
- ✅ Done — Verify Payroll Batch, Approve/Reject with remarks, return-to-HR path
- ✅ Done — Mark batch approved/paid, generate payslips
- ✅ Done — "Generate Bank Transfer File" (diagram node `GenBankFile`): approve/pay action now downloads a real disbursement CSV (`core/bank-file.ts`) alongside the `Payment` record
- ✅ Done — Real payslip PDF generation (diagram `GenPayslip`): "Download payslip PDF" now writes and downloads an actual single-page PDF (`core/payslip-pdf.ts`, hand-rolled, no new dependency), earnings/deductions/net breakdown
- ⬜ Not done — Real notification delivery (diagram `SendNotify`) — Notification records exist in mock DB but no actual dispatch (email/SMS/push)

### 1.7 Employee flow (diagram: Check in/out → Apply leave → View payslip)
- ✅ Done — Apply leave (see 1.4)
- ✅ Done — View/download payslip (real generated PDF, see 1.6)
- ✅ Done — Check In/Out (diagram node `CheckInOut`): self-service already implemented in `attendance-page.ts` (real "today" via browser date, late-flag against shift, auto overtime sync) — PROGRESS.md/MODULE_RECIPE.md were stale here. Added the one real gap: audit-log entries on check-in, check-out and HR correction, matching every other complete module
- ✅ Done — Raise a change request against own profile (`change-requests`), and raise a loan request (`loans-bonuses`) — Employee self-service, added this phase

### 1.8 Cross-cutting modules
All four now have both the submission and the approval half, following the
Leave/Overtime recipe (pure rules file + tests, write-form modal, decision on
a detail page, audit entry on every write):

- ✅ Done — **Change Requests**: raise a request (Employee, any editable
  profile field), HR/Admin approve or reject. This module had been pulled
  from the router and sidebar entirely at some point — model and NgRx feature
  were still there, but there was no route, no page. Rebuilt end to end;
  approving now writes the change straight onto the `Employee` record rather
  than just flipping a status
- ✅ Done — **Change Requests, escalation rework**: every role (Employee,
  Accountant, HR, Admin — not just Employee) can now propose a change against
  their own employee record, and decisions follow a realistic escalation
  chain instead of a flat "HR or Admin decides everything":
  Employee/Accountant → HR or Admin decides; HR → Admin only; Admin → HR
  only; **no one may decide their own request**, checked both in the
  approval-queue filter and again on the detail page itself (defense in
  depth, not just list filtering). New pure function
  `canDecideChangeRequest` in `change-request-rules.ts` (6 new unit tests,
  93/93 passing), `ChangeRequest` gained an optional `requesterRole` field
  (backend: Flyway `V7__change_request_requester_role.sql` +
  `ChangeRequest.java` entity field, so it round-trips through the real
  Postgres-backed collection instead of silently dropping). Module widened
  to `Accountant` in `module-registry.ts`. `employee-detail.ts`'s "Edit"
  button is now hidden when Admin/HR view **their own** record (still shown
  for every other employee's record) — a "Propose a change" link takes its
  place, linking to `/change-requests`, so protected fields on your own
  profile always go through the request/approval flow, never a direct edit.
  Verified live end-to-end in a real browser against the real backend, all
  four roles: Employee→HR/Admin, Accountant→HR/Admin, HR→Admin-only,
  Admin→HR-only, self-approval blocked at both the queue and detail level in
  every case, approve writes the real field onto the employee record
  (confirmed: phone actually changed), reject leaves the original value
  untouched (confirmed: address unchanged) with the rejection reason stored,
  zero console errors. `npx tsc --noEmit`, `ng build`, `ng test` (93 passing)
  and `mvnw compile` all clean. Test data seeded via curl and fully deleted
  afterward; confirmed real employee data already in the backend (added
  independently) was untouched throughout.
- ✅ Done — **Change Requests, bug fix: submitted requests never reaching
  the Admin/HR queue.** Reported after manual testing. Traced the full
  Submit → Save → Queue → Review chain and found two compounding bugs, one
  in each layer:
  1. **Backend/data**: the demo sign-in accounts (farhana.islam, nasrin.akter,
     rakib.hasan, tanvir.ahmed) resolve to employeeId `e7`/`e1`/`e2`/`e4` in
     the frontend's mock login (`session.ts` reads `AppUser`/`Employee` from
     the in-memory mock db, entirely separate from the real Postgres
     backend — auth is deliberately still mock-only, §2.3). Those ids never
     existed in the real `employee` table. `change_request.employee_id` has
     a `REFERENCES employee(id)` foreign key (`V6` migration), so every
     self-service submission by a demo account was rejected by Postgres with
     a foreign-key-violation 500 — reproduced directly: `POST
     /api/change-requests` with `employeeId:"e4"` against the then-current
     database returned `500 Internal Server Error`.
  2. **Frontend**: `change-requests-page.ts`'s `onSubmitted()` dispatched the
     save and *immediately* showed "Request submitted", logged the audit
     entry, and closed the form — without waiting for the async HTTP result.
     The NgRx effect layer already caught the failure into `state.error`,
     but nothing read that signal, so the failure was invisible: the
     submitter saw a false "success," and the row genuinely never reached
     Postgres for Admin/HR to see. Confirmed both effects together
     reproduce the exact report.
  Fixed both layers, additively:
  - New Flyway `V8__seed_demo_account_employees.sql` — a self-contained
    fixture (its own `dept-demo`/`desg-demo`/`shift-demo` rows, not
    dependent on any other data existing) seeding real `employee` rows for
    `e1`/`e2`/`e4`/`e7`, so every demo account has a real backend record and
    every self-service write with an employee FK (Change Requests, and the
    same fix now covers Leave/Loans/Settlements for the same accounts) can
    actually persist. Idempotent (`ON CONFLICT DO NOTHING`), applies cleanly
    on top of `V1`–`V7`.
  - `core/store/collection-feature.ts` (the shared factory behind every one
    of the app's ~20 collections) gained distinct `upsertFailure` /
    `upsertManyFailure` actions, dispatched by the `upsert`/`upsertMany`
    effects instead of overloading the unrelated `loadFailure` action —
    purely additive, no existing consumer read `loadFailure` outside the
    factory's own reducer (checked), so every other module's behaviour is
    unchanged.
  - `change-requests-page.ts`'s `onSubmitted()` now dispatches, then waits
    for the paired `upsertManySuccess`/`upsertManyFailure` action via
    `Actions`/`ofType` (one-shot `take(1)`) before doing anything else: only
    on success does it log the audit entry, close the form and show
    "submitted"; on failure the form stays open with a new red error banner
    naming the rejection, and nothing is logged as if it succeeded.
  Verified live end-to-end against the real backend after the fix: signed
  in as the real `tanvir.ahmed` demo account, submitted a phone change —
  confirmed via direct `curl` that the row actually persisted in Postgres
  with `requesterRole:"Employee"` this time; signed in as `nasrin.akter`
  (HR), **the request now appears in the Approval queue** (the exact
  symptom reported), approved it, confirmed the employee's phone field
  actually updated. Separately verified the negative path by stopping the
  backend mid-test and submitting again: the new red error banner appeared
  ("Could not submit the request — the server rejected it… please try
  again") and the form stayed open, instead of the old false "submitted"
  message — confirms the fix, not just the data workaround, is what closes
  the gap for any future transient failure. `npx tsc --noEmit`, `ng build`,
  `ng test` (93/93 passing), `mvnw compile` all clean. Test change-request
  row deleted afterward; the four seeded demo employees are intentionally
  permanent (via migration, not test data) and were left in place.
- ✅ Done — **Loans & Bonuses**: raise a loan request (Employee for
  themselves, or HR on their behalf) or a bonus request (HR only), **HR
  approves or rejects both — deliberately no Admin override**.
- ✅ Done — **Loan → EMI payroll integration.** Closes the exact gap this
  section used to describe as future work. Architecture unchanged — the
  payroll engine was already the right place for this and needed no redesign,
  only two additions, both in `core/payroll-engine.ts` alongside the existing
  pure functions:
  - `loan-detail.ts`'s `approve()` now sets `status: 'active'` directly
    (previously `'approved'`, a dead-end status nothing ever advanced past —
    per the doc comment on `LoanRecord.status` in `core/models/hr.ts`, now
    updated to describe the real lifecycle). `runPayroll` already read
    `status === 'active'` loans and computed `min(emiAmount,
    outstandingBalance)` into `loanRecovery` correctly — that half was already
    built and untested-but-correct; only the trigger to reach `'active'` was
    missing.
  - New pure function `applyLoanRecovery(loans, slips)` in
    `payroll-engine.ts`: sums each employee's actual recovered amount from
    the cycle's payslips, subtracts it from `outstandingBalance`, and flips
    the loan to `status: 'closed'` once it reaches zero (floored at zero as a
    defensive check, though `runPayroll`'s `min()` already prevents
    overshoot). Returns only the loans that changed. `batch-detail.ts`'s
    `runEngine()` now calls it right after `runPayroll`/`batchTotals` and
    dispatches `loansFeature.actions.upsertMany` for the result — the same
    "engine computes, caller persists" pattern every other collection in that
    method already follows, no new architecture.
  - 7 new unit tests (`core/payroll-engine.spec.ts`, first spec file for the
    engine itself — previously only verified live): balance reduction,
    exact-payoff closure, defensive floor, inactive loans ignored,
    no-recovery-this-cycle loans left untouched, only-changed-rows returned,
    multi-payslip-same-employee summing. Full frontend suite **116/116
    passing** (was 109), `npx tsc --noEmit` clean, `ng build` clean.
  - **Verified live against the real backend, full lifecycle, using the
    actual compiled engine code** (not a re-implementation): no browser
    automation tool is available in this environment, so rather than skip
    live verification, the real `payroll-engine.ts` was compiled as-is via
    the project's own local `tsc` and driven from a Node script that fetches
    live collections over HTTP and calls the unmodified `runPayroll`/
    `applyLoanRecovery` functions exactly as `batch-detail.ts` would, writing
    results back over the same REST API the UI uses — genuinely exercises the
    shipped code end-to-end, just orchestrated outside the browser. Seeded an
    isolated test employee/salary-structure/loan (principal ৳12,000, EMI
    ৳5,000) so nothing touched real data; simulated the "HR approves" click
    with the exact PUT `loan-detail.ts` sends. Four payroll cycles run
    back-to-back: cycle 1 deducted ৳5,000 (outstanding ৳12,000→৳7,000, stays
    `active`), cycle 2 deducted ৳5,000 (৳7,000→৳2,000, stays `active`), cycle
    3 — the final partial instalment — correctly deducted only ৳2,000, not
    the full ৳5,000 EMI (outstanding →৳0, flips to `closed`), cycle 4
    confirmed **zero further deduction** once closed (`loanRecovery: 0`,
    `applyLoanRecovery` returns no updates) — the exact "until fully paid,
    then stop" behavior asked for. Net pay correctly moved with each
    deduction (৳21,500 while paying EMI → ৳24,500 → ৳26,500 once clear).
    Confirmed via `psql` that all test rows were fully deleted afterward and
    the two genuine pre-existing `approved` loans already in this database
    (real data from earlier manual testing, `approvedBy: nasrin.akter`) were
    left completely untouched throughout — this feature does not retroactively
    activate anyone's existing `approved` loans; those will move to `active`
    the next time HR actually clicks Approve on them, same as any new
    request. Backend dev server stopped afterward.
- ✅ Done — **Final Settlement**: HR initiates a settlement for a separating
  employee, Accountant (or Admin) verifies and marks it `completed`, or
  rejects it back to HR. Module visibility widened from Accountant-only to
  Admin/HR/Accountant so HR can actually reach the page
- ✅ Done — **Settlement gratuity + leave encashment auto-calculation.**
  Closes the exact gap this section used to flag — previously all three
  amounts (tenure, gratuity, leave encashment) were free-typed numbers with
  no formula (`netSettlementAmount` literally only summed whatever HR typed).
  Two calculations, deliberately handled differently per the explicit
  instruction:
  - **Leave encashment** — unambiguous, no new config needed: real unused
    leave balance (`leaveBalancesFeature`, summed across every type — same
    convention the Employee dashboard KPI already uses) × the employee's
    daily rate (`grossSalary ÷ 30`).
  - **Gratuity** — a genuine policy decision, so made Admin/HR-configurable
    rather than hardcoded to a specific legal formula. New `GratuityRule`
    collection (`rateDaysPerYear`, `minimumServiceMonths`,
    `calculationBasis` — typed as a single-value union `'basic'` today,
    a real configurable field rather than a constant, so a second basis can
    be added later without a data-shape change), backend `V12__gratuity_rule.sql`
    + `GratuityRule` entity/repo/controller (`/api/gratuity-rules`, same dumb
    CRUD shape as every other module), default seed 30 days/year, 12-month
    minimum. New "Gratuity rule" panel on the Settlements page (Admin/HR
    only, `canInitiateSettlement`), same inline-edit-and-save convention as
    the Leave Rules panel on the Leave page.
  - New pure functions in `settlement-rules.ts`: `calculateTenureMonths`
    (whole completed months between joining date and last working day, with
    a day-of-month rollback so a partial final month never rounds up),
    `calculateGratuity` (0 below the configured minimum service, otherwise
    `rateDaysPerYear` days of basic pay per *completed* year of service — a
    partial final year earns nothing extra), `totalLeaveBalance` /
    `calculateLeaveEncashment`. 22 new unit tests
    (`settlement-rules.spec.ts`).
  - `settlement-form.ts`: tenure/gratuity/leave-encashment are no longer
    typed in — they're computed live as HR picks the employee and last
    working day, and shown as a clear breakdown (basic salary used, days ×
    completed years, remaining leave days × daily rate, an explicit warning
    when tenure is below the configured minimum service). Only "pending
    dues" stays manual — it has no generic source (unreturned equipment,
    ad-hoc advances). Final review is unchanged: the Accountant still
    approves or rejects the computed numbers on `settlement-detail.ts`,
    exactly as before — the calculation is transparent before submission,
    the decision gate is exactly where it always was.
  - Full frontend suite **128/128 passing** (was 116), `npx tsc --noEmit`
    clean, `ng build` clean, backend `mvnw compile` clean.
  - **Verified live against the real backend** using the same
    compile-the-real-module-and-drive-it-over-HTTP approach as the Loan EMI
    verification (no browser automation tool available in this
    environment): compiled the actual `settlement-rules.ts` via the
    project's own `tsc`, drove it from a Node script against an isolated
    test employee (joined 2020-06-15, basic ৳24,000, gross ৳36,000, 10 days'
    combined leave balance across Casual/Sick). For a 2026-09-30 last
    working day: **tenure 75 months, gratuity ৳144,000** (৳800/day × 30
    days × 6 completed years), **leave encashment ৳12,000** (10 days ×
    ৳1,200/day), net ৳154,000 after ৳2,000 pending dues — submitted via
    `POST /api/settlements`, then approved via the exact PUT
    `settlement-detail.ts`'s `approve()` sends, confirmed `completed` with
    `approvedBy` stamped. Two edge cases confirmed separately: a second test
    employee at 8 months' tenure correctly returned gratuity ৳0 (below the
    12-month minimum); reconfiguring the rate from 30→45 days/year via the
    exact PUT `saveRule()` sends recalculated the **same** employee's
    gratuity from ৳144,000 to exactly ৳216,000 with no other input changed,
    confirming the configured rule — not a hardcoded constant — actually
    drives the number. All test rows deleted afterward (confirmed via
    `psql`), the real permanent `gr1` gratuity rule row restored to its
    original 30/12 values, backend dev server stopped.
- ✅ Done — Audit Log (read-only, correctly Admin-only per corrected plan)

### 1.9 Role-based dashboards
- ✅ Done — Rewrote `dashboard-page.ts`'s per-role content end to end (same
  overall layout — header, KPI tile grid, two-column card row — kept; only
  the content per role changed, plus one extra full-width card for Admin and
  HR):
  - **Admin**: Total employees, payroll cost (net total of the batch needing
    attention, or the latest cycle if none is open), pending approvals
    (leave + overtime), change requests (count actually decidable by this
    signed-in user, via the same `canDecideChangeRequest` matrix the module
    itself uses — not a raw count, so the tile and the queue never
    disagree), present-today attendance summary, payroll status. Right
    column's "Approval queue" now also includes decidable Change Requests
    (previously leave/overtime only). New full-width "Recent activity" card
    below, sourced from the audit log.
  - **HR**: Active employees, new hires this month, present-today summary,
    leave to approve, change requests (same decidable-count approach),
    upcoming birthdays & anniversaries (7-day window, `dob`/`joiningDate`
    matched by month+day). New full-width "Birthdays & anniversaries" card.
  - **Accountant**: Monthly payroll, net salary, total deductions, income
    tax, provident fund, overtime paid, bonus paid, payroll status — all
    summed from the current batch's payslips (the batch pending their
    verification, or the latest cycle if nothing is open). Right column
    swapped from the generic (and functionally wrong — Accountants don't
    decide Leave/Overtime) "Approval queue" to "Batches to verify", listing
    exactly the batches `toVerify()` already tracked elsewhere.
  - **Employee**: Latest net pay, days present, overtime approved, leave
    balance (summed remaining days across all leave types), loan
    outstanding (active recovery balance), provident fund deducted this
    cycle, my pending requests (own leave + overtime + change requests),
    unread notifications.
  - Fixed a pre-existing paper cut found while in this file: the "Payroll
    cycles" card's empty state literally said "Loading…" forever when zero
    batches exist, rather than reflecting a genuine empty state — now "No
    payroll cycle yet."
  - No new architecture — reused the existing collection-feature store
    pattern throughout, added the handful of already-existing
    features (`leaveBalancesFeature`, `loansFeature`, `changeRequestsFeature`,
    `auditLogsFeature`) to the dashboard route's providers.
  Verified live in a real browser as all four demo accounts against the
  real backend: every tile renders the right numbers for real data (e.g.
  Admin/HR's "Change requests: 3" correctly matched three genuinely pending
  requests from earlier manual testing, HR's queue correctly excluded her
  own pending request while including Admin's, Employee's own pending count
  showed 1). Zero console errors. `npx tsc --noEmit`, `ng build` (no
  warnings — fixed two `NG8107` optional-chain warnings along the way by
  switching `array[0]` to `.at(0)` so the type checker sees the same
  possibly-empty case the code already handled at runtime), `ng test`
  (93/93 passing) all clean.

### 1.10 Cross-module navigation
- ✅ Done — Payslip, Loan, Bonus, Settlement and Change Request detail pages
  now link back to the related employee's `/employees/:id` page (previously
  printed the employee name as plain text, dead-ending the drill-down).
  `shared/ui/field-list.ts`'s `Field` interface gained an optional `link`
  property so any label/value row can render as a link; `payslip-detail.ts`
  (which has no field list) got an explicit "View employee profile" button
  in its header instead. `roleGuard` already permits any role to open its
  own employee record, so the link is safe for Employee/Accountant viewers
  too. Verified: `npx tsc --noEmit` clean, `ng build` clean, and live in a
  real browser against the real Spring Boot + Postgres backend — seeded one
  employee plus one Loan/Bonus/Settlement/Change-Request/Payslip record via
  curl, clicked every one of the 5 links, all 5 navigated to
  `/employees/emp-test1` correctly, zero console errors. Test data deleted
  afterward, backend/frontend dev servers stopped.
- ✅ Done — Fixed the employee-name-resolution bug found above:
  `loan-detail.ts`, `bonus-detail.ts` and `settlement-detail.ts` constructors
  now also dispatch `employeesFeature.actions.load()`, matching the pattern
  already used by `change-request-detail.ts` (no new architecture — same
  store/feature, same dispatch-in-constructor convention every detail page
  already follows). Verified: `npx tsc --noEmit` clean, `ng build` clean,
  and live in a real browser against the real backend — re-seeded the same
  test employee + one Loan/Bonus/Settlement record, all three pages now show
  "Test Employee" / "E-TEST1" instead of "—", the employee link still
  navigates correctly, zero console errors, and Loan's decision panel
  correctly stayed hidden for Admin (HR-only per §1.8, unrelated to this fix
  and unaffected by it). Test data deleted afterward, servers stopped.
- ✅ Done — **Employee Detail → Related Records.** Closes the gap this
  section used to flag. `employee-detail.ts` now shows, below the existing
  Profile/Salary/Leave-balance cards, seven more sections — **Attendance,
  Leave, Overtime, Payslips, Loans, Bonuses, Final settlement** — each the
  same `employeeId`-filtered, most-recent-first view of a collection every
  other page in the app already reads, reusing the existing `ui-data-table`
  component and each row's real detail route (`/leave/:id`,
  `/overtime/:id`, `/payslips/:id`, `/loans-bonuses/loans/:id`,
  `/loans-bonuses/bonuses/:id`, `/settlements/:id`) — clicking any row drills
  straight into the same decision/detail page every other module's list
  already links to. Attendance has no per-row detail route anywhere in the
  app (corrections happen inline on `attendance-page.ts`, not a dedicated
  page), so its rows render without a link, matching that reality rather
  than inventing a route. Status badges reuse each module's own tone
  mapping (`APPROVAL_TONE` for Leave/Overtime/Bonuses, plus
  `overtimeStatusLabel()` so Overtime shows "Auto Calculated"/"Verified"
  instead of raw "pending"/"approved", exactly as the Overtime module itself
  does) — no new logic invented, only reused. Nine collections
  (`attendanceFeature`, `leaveRequestsFeature`, `overtimeFeature`,
  `payslipsFeature`, `payrollBatchesFeature` — for resolving a payslip's
  batch reference — `loansFeature`, `bonusesFeature`, `settlementsFeature`)
  added to the `employees` route's providers in `app.routes.ts` (they
  weren't there before, since nothing on this page read them) and dispatched
  from the constructor, the same load-on-visit convention every other detail
  page already follows. No backend change — every endpoint this reads
  already existed.
  `npx tsc --noEmit` clean, `ng build` clean, existing suite unchanged at
  **128/128 passing** (no new pure-logic file — this is presentation/filter
  code tied to the component, not a `*-rules.ts` candidate, matching how the
  rest of the app draws the line on what gets a spec file).
  **Verified live against the real backend**: seeded one isolated test
  employee with a real row in all seven categories (attendance, leave,
  overtime, a payroll batch + payslip, a loan, a bonus, a settlement),
  confirmed via a script replaying the exact `row.employeeId === id` filter
  each section's `computed()` uses against the live `/api/**` endpoints —
  all seven returned exactly the one seeded row apiece. Route paths for
  every row-link were cross-checked against `app.routes.ts` directly (all
  six exist). No browser automation tool is available in this environment,
  so the rendered page itself (table layout, badge colors, click-through)
  was not visually walked — this verification covers the data contract,
  routing and build/compile correctness, not a pixel-level look. All nine
  test rows deleted afterward, confirmed via `psql`, backend dev server
  stopped.
- ✅ Done — **Overtime Detail: employee/attendance context made clear and
  realistic.** Closes the gap this section used to flag, plus the actual
  underlying bug: `overtime-detail.ts`'s constructor never dispatched
  `employeesFeature.actions.load()` (same class of bug already fixed on
  `loan-detail.ts`/`bonus-detail.ts`/`settlement-detail.ts`/`leave-detail.ts`
  per §1.4/§1.10) — a direct link to `/overtime/:id` with no prior visit to
  a page that happened to load Employees would show the name/code as "—".
  Fixed by adding the dispatch, matching the established convention;
  `attendanceFeature`/`shiftsFeature` added alongside (needed for the new
  context below) and provided at the `/overtime` route in `app.routes.ts`
  (previously only `overtimeFeature` was).
  Since overtime is always auto-calculated from a check-in/check-out pair
  against the employee's scheduled shift (never entered by hand — see this
  page's own long-standing docstring), the detail page now shows that whole
  chain instead of just the resulting hours: **Check-in, Check-out,
  Scheduled hours, Actual worked hours** (from the exact `Attendance` row
  this claim was calculated from, joined the same way the auto-calculation
  itself does — `employeeId` + `date`), and **Calculated overtime hours**
  (relabeled from the bare "Hours" field for clarity) alongside the
  already-present Employee/code/date/status/payroll-inclusion. The page
  header subtitle now also carries the employee code. Zero new calculation
  logic: "Scheduled hours" reuses `attendance-rules.ts`'s existing
  `workedHoursFor(shift.startTime, shift.endTime, shift.breakMinutes)`
  unchanged (the same "duration minus break" formula it already applies to
  a check-in/check-out pair, applied here to a shift's start/end instead) —
  no new formula was written. The automatic overtime calculation itself
  (`attendance-page.ts`'s `syncOvertimeForToday`, `overtime-rules.ts`'s
  weekly-ceiling capping) was not touched.
  `npx tsc --noEmit` clean, `ng build` clean, existing suite unchanged at
  **128/128 passing** (no new pure-logic file — same reasoning as §1.10's
  Related Records entry: this is presentation/join code, not a
  `*-rules.ts` candidate).
  **Verified live against the real backend**: compiled the actual
  `attendance-rules.ts` via the project's own `tsc` and drove it against
  live data — seeded a real employee on `shift-demo` (09:00–18:00, 60 min
  break), confirmed **scheduled hours computes to exactly 8h** via the real
  `workedHoursFor`; seeded a real attendance row (check-in 09:05, check-out
  20:00), confirmed **actual worked hours computes to 9.92h** via the same
  function; seeded the matching overtime claim (1.92h); then replayed the
  exact `employeeId`+`date` join `sourceAttendance()` uses and the
  `employee → shift → workedHoursFor` chain `scheduledHours()` uses — every
  field the page renders (name, code, date, check-in, check-out, scheduled
  hours, actual hours, calculated overtime hours, status, payroll
  eligibility) resolved correctly against real Postgres data. All test rows
  deleted afterward, confirmed via `psql`, backend dev server stopped.

### 1.11 Remaining frontend work (mock-data phase)
The submission-half backlog from the previous revision of this plan is
cleared — Change Requests, Loans & Bonuses, Settlements, Overtime's
weekly-limit rework, and the Salary & Rules / Organisation / Users & Roles
master-data forms are all done.

| Module | Missing piece | Priority |
|---|---|---|
| Notification dispatch (real email/SMS) | Genuinely out of scope — needs an external provider decision from the user; see §1.14 for the real in-app notification system that now exists instead | Low |

### 1.12 Attendance — common page & payroll integration
- ✅ Done — **Attendance is now a genuinely shared page across all four
  roles**, not just Admin/HR/Employee: `module-registry.ts` widened to
  include Accountant (read-only — no "Correct" action, same `canCorrect`
  gate as before, unchanged). Admin/HR keep full manage (corrections),
  Accountant reads it for payroll context, Employee stays self-service-only
  (own record, check in/out).
- ✅ Done — **Present/Absent/Late/Early Leave/Working Hours/Overtime**, all
  six, calculated and shown as KPI tiles (was four — Present, Late, Absent,
  Hours — before this pass). Early Leave is new: mirrors the existing Late
  calculation on the other end of the day (left before shift end, past the
  same grace allowance), computed live against the employee's current shift
  rather than persisted — it's a display metric only, not a payroll input,
  so no schema change was needed for it. All the inline date-math that used
  to live directly in `attendance-page.ts` (late check, worked-hours calc)
  was extracted into a new `features/attendance/attendance-rules.ts`, the
  same "component only renders what the rules file returns" pattern
  `leave-rules.ts`/`overtime-rules.ts` already established — 12 new unit
  tests.
- ✅ Done — **Automatic monthly summaries**: a new section on the page rolls
  up Present/Absent/Late/Early-leave days, Working hours and Overtime hours
  per employee per month (`YYYY-MM`), computed on the fly from existing
  Attendance/Overtime records — no new persisted collection. A month picker
  appears when more than one month has data; Employee sees just their own
  row, Admin/HR/Accountant see every employee with attendance that month.
- ✅ Done — **Payroll now actually deducts for lateness and unpaid leave**,
  closing a real gap: `payroll-engine.ts` previously paid the full
  structure salary regardless of attendance (only overtime affected pay).
  Two new pure functions in `attendance-rules.ts`:
  `lateDeductionAmount` (a small free allowance — 3 lates per cycle — then
  half a day's pay per late beyond it) and `unpaidLeaveDeductionAmount`
  (every approved Unpaid-type leave day within the cycle, at the same flat
  daily rate = cycle gross ÷ days in cycle). `EngineInput` gained an
  optional `leaveRequests` field (omit it and both deductions come out to
  zero — existing call sites/seed data untouched); `batch-detail.ts` now
  passes it through. `Payslip` gained optional `lateDeduction`/
  `leaveDeduction` fields, shown as their own lines on the payslip detail
  page and in the downloaded PDF, folded into `totalDeductions`/`netSalary`
  like every other deduction. Backend: Flyway
  `V9__payslip_attendance_deductions.sql` + matching `Payslip.java` entity
  fields, so the amounts round-trip through the real Postgres-backed
  collection instead of being silently dropped (same pattern as `V7`/`V8`
  earlier in this log).
  Verified live end-to-end against the real backend: seeded one employee
  with 5 late check-ins (2 chargeable beyond the free allowance) and a
  2-day approved Unpaid leave request within the cycle, ran the actual
  payroll engine through the UI ("Lock cycle and run engine") — resulting
  payslip showed **Late deduction ৳955** and **Unpaid leave deduction
  ৳1,910**, both flowing correctly into Total deductions (৳6,245) and Net
  pay (৳23,355); hand-checked the arithmetic against the daily-rate formula
  and it matched exactly. Also confirmed the Attendance page itself for all
  four roles (Admin, HR, Accountant, Employee) with real backend data —
  correct KPI tiles, correct monthly summary, correct role gating in each
  case. One real bug caught and fixed mid-verification: the first payroll
  run picked up a stale, pre-migration backend process (Spring Boot's
  `spring-boot:run` did not recompile the entity change until an explicit
  `mvnw clean compile`), which silently dropped the two new fields — not a
  frontend issue, but worth remembering if a future migration's columns
  seem to "disappear" the same way. `npx tsc --noEmit`, `ng build` (zero
  warnings), `ng test` (105/105 passing), `mvnw compile` all clean. Test
  data (employee override rows, attendance, leave request, batch, payslips)
  fully deleted afterward.
- ✅ Done — **Overtime module: Accountant access, and a correction path
  scoped to exceptions only.** Two gaps found against "Admin/HR view,
  verify, and correct attendance and overtime; Accountant views verified
  records for payroll": `module-registry.ts`'s Overtime entry didn't
  include Accountant (Attendance already did, from the pass above — this
  was an inconsistency, not a deliberate choice); and Overtime had no
  correction path at all, unlike Attendance's `attendance-correction-form.ts`
  — an Admin/HR user could Verify or Reject an auto-calculated record but
  never fix one that was wrong (e.g. a missed check-out). Fixed both,
  deliberately narrow in scope per the explicit ask — no manual "create
  overtime" action exists anywhere, and none was added:
  - Accountant added to Overtime's `roles` in `module-registry.ts`. No
    behavior change beyond visibility — `canApprove`
    (`session.canApproveOvertime`, Admin/HR only) already gated the
    approval queue and decision buttons, so Accountant lands on the same
    page Admin/HR see minus those two things automatically, no new code
    needed for the read-only half.
  - New `overtime-correction-form.ts`, mirroring
    `attendance-correction-form.ts`'s exact convention (a wrong
    auto-calculated value is never edited silently — a correction is a new
    value plus a mandatory reason, stamped with who and logged to the audit
    trail). Lets Admin/HR adjust hours/rate with a live-recalculated amount
    preview; deliberately placed **only** on `overtime-detail.ts` (a
    "Correct" button next to Verified/Included-in-Payroll status), **not**
    on the list page (`overtime-page.ts`), which has no action column and
    never did — satisfies "remove Correct from the main list" by
    construction rather than by removing something that was there.
    `Overtime` gained optional `correctedBy`/`correctionReason` fields
    (same shape as `Attendance`'s); backend: Flyway
    `V10__overtime_correction.sql` + matching `Overtime.java` entity fields.
  - Status wording overhauled per the ask: a new `overtimeStatusLabel`/
    `payrollInclusionLabel` pair in `overtime-rules.ts` maps the underlying
    `pending`/`approved`/`rejected`/`payrollEligible` values (unchanged —
    no data model or payroll-engine change) to **Auto Calculated**,
    **Verified**, **Rejected**, and **Included in Payroll**/**Not
    included** everywhere they're shown — the list's status/payroll badges,
    the KPI tile ("Pending" → "Auto calculated"), and the detail page's
    badges. Decision buttons renamed "Verify record"/"Reject record" (was
    "Approve/Reject claim") to match, functionally identical.
  Verified live end-to-end against the real backend as HR: seeded one
  pending auto-calculated-style record, confirmed the list showed "Auto
  Calculated"/"Not included" with no action column, opened the detail page,
  confirmed the correction form blocks submission with no reason
  (`"Explain why this record was corrected."`), corrected hours 2 → 2.5 with
  a reason (missed-check-out scenario) — recalculated amount and weekly
  ceiling updated live and after save, `correctedBy` stamped — then verified
  the record: badges flipped to **Verified**/**Included in Payroll**,
  `approvedBy`/`payrollEligible: true` set correctly in Postgres. Switched
  to Accountant: Overtime now in the sidebar, same verified numbers visible
  (Eligible hours 2.50h, Eligible amount ৳463 — matching exactly), no
  decision UI. Zero console errors. `npx tsc --noEmit`, `ng build` (zero
  warnings), `ng test` (105/105 passing), `mvnw clean compile` all clean.
  Test overtime record deleted afterward.
- ✅ Done — **Bug fix: corrected overtime not reflected in the Monthly
  Attendance Summary after browser Back navigation.** Reported live.
  Traced the full path — correction saves correctly to Postgres every
  time (confirmed via direct `curl`) — so the bug had to be somewhere
  between "data is correct in the database" and "the Attendance page
  displays it." A plain forward navigation (clicking the Attendance
  sidebar link right after correcting) already showed the right number;
  the bug only reproduced via the browser's **Back** button. Root cause:
  every `/api/**` response shipped with **no `Cache-Control` header at
  all** (`WebConfig.java` only configured CORS, nothing about caching).
  With no explicit directive, the browser is free to apply heuristic
  caching — and Chrome's back/forward navigation is far more willing to
  reuse a cached GET response with no directive than a normal link click
  is (Angular's `HttpClient` still issues the request either way; the
  browser decides whether to actually hit the network or hand back a
  cached response). So going Attendance → Overtime → correct → **Back**
  could silently reuse the pre-correction `GET /api/overtime` response,
  while Attendance → **click** Overtime → correct → **click** Attendance
  never hit the same cache path. This was never a frontend logic bug —
  `attendance-rules.ts`'s `monthlySummaryFor`/`monthlySummaries` and the
  page's `totalOvertimeHours` computed both already summed whatever the
  store held correctly; the store just sometimes held a stale HTTP
  response.
  Fixed at the source rather than papering over it in the frontend: new
  `NoCacheFilter.java` (`OncePerRequestFilter`, registered as a
  `@Component` so Spring Boot picks it up automatically) sets
  `Cache-Control: no-store` on every response — the general, permanent
  fix, since this exact staleness risk existed for any page reached via
  Back after a correction anywhere in the app (Leave, Loans, Change
  Requests, etc.), not just this one Attendance/Overtime path. No
  frontend files changed; the store/rules logic was already correct.
  Verified live end-to-end against the real backend: confirmed the bug
  first (`curl -D -` showed no `Cache-Control` header at all; corrected
  an overtime record 2h → 5h, clicked Attendance sidebar link — showed
  5.00h correctly; corrected again 5h → 7h, used the browser **Back**
  button this time — **reproduced the stale 3.50h** before the fix, a
  leftover from an earlier correction in the same test, proving the
  cache was serving a response older than even the immediately preceding
  one). Restarted the backend with the fix, confirmed the header now
  reads `Cache-Control: no-store`, repeated the identical correct →
  Back sequence three times over — every time, both the KPI tile and the
  Monthly Summary table showed the just-corrected value (7.00h),
  including on Back navigation. Separately verified payroll flow-through
  end to end: seeded a pending overtime record in the payroll cycle,
  corrected its hours 2 → 4 via the UI, verified it (Verified + Included
  in Payroll), ran the actual payroll engine through
  "Lock cycle and run engine" — resulting payslip showed
  `overtimeHours: 4.00`, `overtimeAmount: 740.00` (4 × ৳185), the
  **corrected** value, not the original 2h/৳370. `npx tsc --noEmit`,
  `ng test` (105/105 passing — unchanged, no frontend code touched),
  `mvnw clean compile` all clean. All seeded test data (salary structure,
  overtime records, payroll batch, payslips) fully deleted afterward.
- ✅ Done — **Every role gets its own Check-in/Check-out, not just
  Employee; Accountant narrowed to own-records-only.** Two changes to
  `attendance-page.ts`, both scope/visibility only — the check-in/out,
  worked-hours, overtime auto-calc, monthly summary, and payroll
  integration logic underneath were not touched:
  - The "Today" check-in/out card was gated behind `isSelfService()`
    (`role() === 'Employee'`), so Admin/HR/Accountant never saw one for
    themselves — despite every account being tied to a real employee
    profile (`session.employeeId()`) that can check in exactly like an
    Employee can. The card is now unconditional: every role sees it, tied
    to their own record.
  - `isSelfService`/`canCorrect` renamed to `ownRecordsOnly`/`canManage`
    and **Accountant reclassified from "sees everyone" to "own records
    only"**, joining Employee — a deliberate narrowing from the previous
    pass's "Accountant reads it for payroll context" (which gave Accountant
    the full org-wide register). This page's daily register and monthly
    summary are per-person operational data, not the read-only payroll
    rollup Overtime shows; Accountant's *Overtime* page visibility is
    unchanged (still sees everyone's verified overtime, per the explicit
    instruction two passes ago) — flagging this as a deliberate
    inconsistency between the two Time & Attendance pages, not an
    oversight, in case it should be revisited later. Admin/HR are
    unaffected: still see every employee's register/summary and can
    correct any row (`canManage` is the exact same role check `canCorrect`
    always was).
  Verified live against the real backend, all four roles: signed in as
  Admin (Farhana Islam) — "Attendance" title (org-wide), own Check In
  card present, checked in for real (13:19, correctly flagged late against
  her own shift), her row appeared in both the daily register and monthly
  summary alongside Tanvir's. Accountant (Rakib Hasan) — title now
  **"My attendance"**, checked in for real, KPI tiles and register show
  *only* his own row, no Employee column, no Actions/Correct column
  (confirmed narrowed from the previous "sees everyone" behavior). HR
  (Nasrin Akter) — "Attendance" title, own Check In card, Present count
  correctly included all three checked-in employees (management view
  unaffected). Employee (Tanvir Ahmed) — unchanged, "My attendance", own
  record only. Zero console errors across all four. `npx tsc --noEmit`,
  `ng build` (zero warnings), `ng test` (105/105 passing) all clean. Test
  check-in records for Admin/Accountant deleted afterward; Tanvir's
  pre-existing real attendance row was left untouched.
- ✅ Done — **Audit trail for attendance corrections now records what
  actually changed, not just that a reason was given.** Requirements
  audited one by one against the existing code:
  - "Admin and HR can correct each other's / other employees'
    attendance" — already true: `canManage()` (`['Admin','HR'].includes`)
    gates `rows()` to the full org-wide register with no employeeId
    restriction on which rows get a Correct button, so this needed no
    code change.
  - "Accountant/Employee view only their own" — already done in the
    previous pass (`ownRecordsOnly`).
  - "Every correction requires a reason" — already enforced by
    `attendance-correction-form.ts` (`Validators.required,
    Validators.minLength(5)` on `correctionReason`).
  - "Record who corrected it, when, and what was changed" — who/when
    were already automatic (`AuditLogService.record()` stamps
    `actorName`/`actorRole`/`timestamp`), but the **what** was missing:
    `saveCorrection()`'s audit `details` string only ever included the
    employee name, date, and typed reason — never the actual before/after
    field values. Added `describeCorrection()` to `attendance-page.ts`,
    diffing `checkIn`/`checkOut`/`status` between the pre-correction row
    (captured from `correcting()` before it's cleared) and the submitted
    one, appending only the fields that actually changed
    (`"Check out — → 18:00"` style) ahead of the reason text.
  Verified live against the real backend: found a genuine (not
  test-seeded) incomplete record — Nasrin Akter (HR) checked in at
  13:32 with no check-out. Logged in as Admin (Farhana Islam), corrected
  Nasrin's record (check-out 18:00, reason "Forgot to check out,
  confirmed with device log"). Daily register and Monthly Summary
  recalculated instantly (4.47h worked, "1 late" retained). Queried
  `GET /api/audit-logs` directly — new entry:
  `actorRole: Admin, actorName: Farhana Islam, action: "Corrected
  attendance entry", details: "Nasrin Akter · 2026-08-25 · Check out —
  → 18:00 · Reason: Forgot to check out, confirmed with device log"` —
  who, when (timestamp), and what-changed all present and correct. Left
  the correction in place — it fixes a real incomplete record, not test
  pollution. `npx tsc --noEmit` clean, `ng test` 105/105 passing (8
  spec files), `ng build` zero warnings. No backend code touched, so no
  restart needed.

### 1.13 Known frontend limitations (by design, mock phase) — superseded, kept for history
**Correction, 2026-09-01**: every point below was true when written, before
Part 2's backend integration landed. All three are now resolved — see §2.3
(real BCrypt+JWT, frontend wired and live), §2.4/§2.5 (every collection
real-backed, `MockApiService` only used as a dead-code fallback path), and
§1.15–§2.11 (a real, growing month-by-month history of genuinely seeded
attendance/leave/overtime data, not a single reused month). Left in place
rather than deleted so the "mock phase" this project went through stays on
record.
- ~~No real backend~~ — `MockApiService` simulates HTTP over an in-memory `structuredClone`; all data resets on page reload
- ~~Credentials are static, shipped in the JS bundle, no hashing~~ — note: a real, tested BCrypt+JWT backend now exists (§2.3) but the frontend doesn't call it yet
- ~~August payroll batch reuses July's attendance~~ (no August data seeded)
- These are expected to be resolved once backend integration (Part 2) replaces the mock layer

### 1.14 Remaining core workflow gaps — audited and closed
Prompted by a request to finish Payroll, Payslips, Notifications, and the
remaining Admin/Accountant pages before starting frontend JWT wiring. Audited
against actual code first (not this file's prose, which had drifted) rather
than assuming the ⬜ markers elsewhere were current — findings below.

- ✅ Done — **Payroll batch decision trail: two real bugs closed.**
  `batch-detail.ts`'s `approve()` hardcoded `approvedBy: 'rakib.hasan'`
  regardless of who actually clicked Approve — every other approval flow in
  the app (Leave/Overtime/Loan/Bonus/Settlement/Change Request) uses
  `session.currentUser()?.username`; this was the one holdout. Fixed. Also,
  "Return with remarks" was a single click with a hardcoded canned string
  (`'Overtime hours unverified for the sewing lines...'`) — every other
  reject/return flow in the app requires a typed reason ≥10 characters; this
  didn't. Added a real remarks textarea with the same validation, matching
  `leave-detail.ts`'s rejection-reason convention exactly. Also added
  `AuditLogService` calls for run/submit/approve/return/pay — previously
  Payroll's most sensitive actions were the one module with zero audit trail
  entries from the frontend (every other module already logged every
  decision). No business logic changed — the engine, batch lifecycle, and
  bank file generation were already correct and untouched.
  **Verified live**: PUT with a real typed remarks string and a real
  (non-`rakib.hasan`) `approvedBy` both persisted correctly to Postgres.
- ✅ Done — **Payslip page — audited, no gaps found.** Employee role scoping
  is real (`payslip-list.ts` filters to `session.employeeId()`), and
  "Download PDF" genuinely builds a valid single-page PDF client-side
  (`core/payslip-pdf.ts`) and triggers a real browser download — not a stub.
  No changes made.
- ✅ Done — **Notification system — the real gap, now closed.** Previously:
  a pure CRUD backend record with no receiving UI at all (the header bell
  icon linked to the Admin-only Audit Log — unrelated data — with a
  hardcoded "3" badge), and nothing anywhere in the app ever created a
  notification outside the static seed. Built the missing half:
  - New `core/notification.ts` (`NotificationService`), mirroring
    `AuditLogService`'s exact fire-and-forget convention.
    `notifyEmployee(employeeId, draft)` resolves the recipient's login
    account via the `users` collection's `employeeId` link and no-ops
    (not an error) when no account exists yet — real employees onboarded
    outside Users & Roles don't have one.
  - New `features/notifications/notification-page.ts` at `/notifications`
    — every role's own inbox (filtered by `session.currentUser()?.userId`,
    same universal-access pattern as `/profile`), with mark-read /
    mark-all-read.
  - `app-shell.ts`'s bell icon now links to `/notifications` and shows a
    real unread count (`notificationsFeature`, filtered to the signed-in
    user) instead of the hardcoded "3"; `notificationsFeature` moved to the
    shell-level route so the badge is live everywhere, not just on pages
    that happened to already load it.
  - `Notification.type` widened (`hr.ts` + backend `V15__notification_type_widen.sql`,
    widening the Postgres CHECK constraint from `V6`) from 4 values to 8 —
    `loan`/`bonus`/`settlement`/`change-request` added alongside the
    original `payroll`/`leave`/`overtime`/`account`.
  - Real creation wired into every decision point that previously had none:
    Leave, Overtime, Loan, Bonus, Settlement, Change Request approve/reject
    (`notifyEmployee` call added to each `*-detail.ts`'s existing
    `approve()`/`reject()`), plus "payslip ready" notifications to every
    employee in a batch when `batch-detail.ts`'s `pay()` runs. Real email/SMS
    delivery remains explicitly out of scope (needs a provider decision from
    the user) — this closes the in-app half, which was the actual usability
    gap.
  Full frontend suite **137/137 passing** throughout (no regressions),
  `npx tsc --noEmit` clean, `ng build` clean.
  **Verified live against the real backend**: confirmed the widened CHECK
  constraint via `psql`, POSTed a real notification of all 8 types (all
  `201`), confirmed an invalid type is still correctly rejected `400` via
  the existing `ApiExceptionHandler`, confirmed mark-as-read PUT persists.
  All test rows deleted afterward.
- ✅ Done — **Admin config gaps closed.** Audited every write action on
  Organisation/Users & Roles/Salary & Rules against the code, not the
  page's own claims:
  - **Users & Roles**: previously create/reset-password/disable-enable only
    — no way to change a user's role after creation, and both the Roles
    panel and the Permission matrix were pure read-only display despite the
    page's own subtitle claiming to show "what each role may actually do."
    Added: inline role-reassignment per user row (select + Save, matching
    the Leave Rules panel's draft-then-save convention); inline role
    description editing; and — the real fix — the Permission matrix's
    static "Held by" text column replaced with one checkbox column per role,
    so granting/revoking a role's access to a module is now an actual click,
    not just a readout. Role **names** deliberately stay fixed to the four
    canonical values (`Admin`/`HR`/`Accountant`/`Employee`) — they're typed
    as `RoleName` and gate real behavior throughout the entire app
    (`roleGuard`, every `canDecide*` matrix); adding arbitrary role names
    would silently not work anywhere else, so no add/delete-role UI was
    built. **Known limitation, unchanged by this pass**: `users`/`roles`/
    `permissions` are still mock-only collections (not in
    `HybridApiService.BACKED_COLLECTIONS`), so none of this reaches the real
    backend — verified via `ng build`/`ng test` only, not live Postgres.
  - **Salary & Rules**: PF Rule had add/edit but no delete — the only one of
    the three tabs missing it (Salary Structures and Tax Slabs both already
    had it). Added `removePf()` + a Delete button, matching the other two
    tabs' exact convention (`confirm()` + `rowBtnDanger`).
  - **Accountant pages — audited, no gaps found.** Cross-checked every
    module with `'Accountant'` in `module-registry.ts` against `session.ts`'s
    permission flags: Payroll Batches and Final Settlement are fully
    functional (approve/return/pay, approve/reject, both audit-logged
    correctly); Attendance/Overtime/Leave/Payslips read access matches
    documented scope; Salary & Rules/Loans & Bonuses are correctly read-only
    (no Accountant approval role in either module's design). No changes
    needed.
  Full frontend suite **137/137 passing**, `npx tsc --noEmit` clean,
  `ng build` clean. **Verified live**: PF rule create→delete round-tripped
  correctly against the real backend (`201` then `204` then `404` confirming
  it's actually gone).
- ✅ Done — **Configuration → Payroll Batch → Calculation dependency-chain
  audit, then two real bugs fixed plus a new pre-flight guard.** Audited the
  actual data flow (not page-completeness, already covered above) — what
  each step in Configuration → Payroll Batch → Calculation → Payslip →
  Employee View genuinely depends on, and whether that dependency is
  enforced. Found two real, previously-undiscovered correctness gaps:
  - **`payroll-engine.ts`'s PF deduction would crash the entire batch run**
    if Admin/HR had never configured a PF Rule: `pfRule.employeeContributionPct`
    with `pfRule` possibly `undefined` (`pfRules()[0]` on an empty
    collection). Not a graceful degrade — a hard `TypeError` for every
    employee in the batch the moment one of them had `appliesPF: true`.
    Fixed at the engine level (`EngineInput.pfRule` is now `PFRule |
    undefined`; missing PF rule degrades to a `0` deduction instead of
    throwing) — the engine itself must never crash on missing config,
    independent of the pre-flight check below.
  - **`batch-detail.ts`'s `runEngine()` hardcoded `cycleStart: '2026-07-01'`
    / `cycleEnd: '2026-07-31'`**, ignoring the batch's own `cycleStart`/
    `cycleEnd` fields entirely. Every batch for any month other than the
    originally-seeded July one silently calculated against July's
    attendance/leave/overtime instead of its own. Fixed: `runEngine()` now
    passes `batch.cycleStart`/`batch.cycleEnd` straight through — a batch
    with no attendance seeded for its actual month now correctly produces
    zero worked hours for everyone, rather than quietly borrowing a
    different month's data.
  - **New `payrollPreflight()`** in `payroll-engine.ts`, checked before
    "Lock cycle and run engine" is clickable: **blocking** (button disabled,
    red banner, `runEngine()` also bails defensively even if somehow
    triggered) when no PF rule is configured but at least one active,
    already-structured employee needs one, or when zero tax slabs exist but
    at least one employee is taxable — both would otherwise silently pay
    someone's mandatory deduction as ৳0, which is wrong money, not just an
    incomplete batch. **Warning only** (yellow banner, run still allowed)
    when some active employees have no `SalaryStructure` yet — they're
    simply excluded from this cycle (`runPayroll` already skipped them
    silently; now it's visible, listing who), a recoverable, non-fatal
    situation that shouldn't halt payroll for the whole company over one
    unconfigured new hire.
  9 new unit tests (PF-undefined safety, cycle-uses-batch-dates,
  `payrollPreflight`'s blocking/warning matrix) — full frontend suite
  **146/146 passing** (was 137), `npx tsc --noEmit` clean, `ng build` clean.
  No existing calculation rule changed — tax, PF-when-configured, loan
  recovery, late/leave deductions, and every other formula are byte-for-byte
  identical to before this pass.
  **Verified live against the real backend**, specifically the two
  scenarios named in the request: seeded a real employee with attendance in
  **two different months** (July and September) and a real **September**
  batch (`cycleStart: 2026-09-01`) — confirmed the compiled, unmodified
  engine now correctly counts only the September row (8.5h) and excludes
  July's, where the old hardcoded behavior would have produced July's 8h
  instead (both numbers shown side by side in the verification output).
  Confirmed `pfRule: undefined` against this real data produces `pf: 0` and
  a correct `netSalary`, no crash. Confirmed `payrollPreflight` against real
  backend data: does not block with the real configured PF rule; correctly
  blocks when PF is simulated as missing; correctly warns (not blocks) and
  names the employee when one lacks a salary structure. All test rows
  deleted afterward, confirmed via `psql`, backend dev server stopped.
- ✅ Done — **Audit Log — actor identity was already correct; three real
  gaps closed.** Audited Leave/Change Request/Overtime/Loan/Bonus/Settlement
  approve-reject flows first (per the explicit "confirm root cause before
  large changes" ask): `actorRole`/`actorName` were captured correctly
  everywhere already — the reported symptom wasn't an identity bug. Three
  real gaps, repeated identically across all six `log()` helpers: (1)
  rejection reason was never passed into the audit `details` string, (2)
  the affected record's id wasn't in `details`, (3) no normalized
  APPROVE/REJECT `outcome` field — only inconsistent free-text (`"Approved
  X"` vs `"Completed X"`), so the Audit Log page couldn't reliably
  filter/color-code decisions. Fixed additively across Leave, Change
  Requests, Overtime, Loans, Bonuses, Final Settlement — each `log()`
  helper now takes an `outcome?: 'APPROVE'|'REJECT'` and `reason?` param,
  appending `#<id>` and `· Reason: ...` to `details` — following the exact
  pattern already used by `batch-detail.ts`'s Payroll audit log. Free-text
  `action` strings kept unchanged, including Settlement's "Completed final
  settlement" (deliberately not renamed to "Approved"). Also added Add
  Employee logging (`Employees` module previously had zero audit entries —
  confirmed via grep before adding). Audit page's Action column now shows a
  color-coded badge (green/red) driven by the structured `outcome` field
  while still labeling it with the module's own free-text `action`.
  **Backend change was required, not optional**: `AuditLog`'s new
  `outcome` field is silently rejected by the real backend as originally
  planned — this Spring Boot/Jackson stack rejects unknown JSON properties
  outright (400 `"malformed"`) rather than the classic Spring Boot default
  of silently dropping them, confirmed by reproducing the 400 against the
  live backend before making the change. Added `outcome VARCHAR(10) CHECK
  (outcome IN ('APPROVE','REJECT'))`, nullable, via
  `V16__audit_log_outcome.sql` and a matching field on the `AuditLog`
  entity — small and additive, matching the existing column style.
  `npx tsc --noEmit` clean, `ng build` clean, `ng test` **146/146 passing**
  (unchanged — UI glue reusing the already-tested `AuditLogService`, no new
  pure-logic functions). **Verified live against the real backend**: after
  the migration/entity change, round-tripped a POST/GET/DELETE with
  `outcome` set — persisted and returned correctly (previously would have
  400'd). Then posted 13 rows shaped exactly like each of the seven
  updated call sites (Leave/Change Request/Overtime/Loan/Bonus/Settlement
  approve+reject, plus Add Employee) with realistic actor/role/reason/id
  data — all 13 returned `201` with every field round-tripping correctly,
  all deleted afterward and confirmed gone via the API (`psql` itself hung
  on an auth prompt so the delete-then-404 API check was used instead),
  backend dev server stopped.
- ⬜ Not done (by request — report only, not yet implemented) — a
  system-wide audit of what else should be logged (create/update/delete,
  payroll/payment, configuration, security actions) is pending as a
  separate deliverable; see the audit report given directly in
  conversation rather than duplicated here.
- ✅ Done — **Salary & Rules audit gap closed** (first of the three gaps
  named in that report; Organisation and Employee edit/deactivate
  deliberately left for later, per the explicit ask). `salary-rules-page.ts`
  previously had zero audit logging on Salary Structure, Tax Rule, and PF
  Rule create/edit/delete — now every one of the six `saveX`/`removeX`
  handlers calls a shared `log(action, details)` helper (`AuditLogService`,
  `moduleName: 'Salary & Rules'`), following the existing config-page
  convention (`users-page.ts`'s `session.displayName()` actor, no
  `outcome` field — these are plain create/update/delete, not
  approve/reject decisions, so the APPROVE/REJECT enum doesn't apply).
  `details` includes the affected record's `#id` plus enough context to
  read at a glance (employee + gross for structures, slab name + range +
  rate for tax, scheme name + contribution % for PF). No business logic or
  UI behavior changed — only new `audit.record()` calls added alongside
  existing dispatches. `npx tsc --noEmit` clean, `ng build` clean, `ng
  test` **146/146 passing** (unchanged — no new pure-logic functions).
  **Verified live against the real backend**: posted 9 rows shaped exactly
  like the 9 new call sites (create/update/delete × structure/tax/PF) —
  all `201`, every field round-tripped correctly, all deleted and
  confirmed gone via the API (404), backend dev server stopped.
- ✅ Done — **Organisation audit gap closed** (second of the three gaps;
  Employee edit/activate/deactivate deliberately left for later, per the
  explicit ask). `organisation-page.ts` previously had zero audit logging
  on Department, Designation, Shift, and Holiday create/update/delete —
  now every one of the eight `saveX`/`removeX` handlers calls a shared
  `log(action, details)` helper, identical shape to the Salary & Rules
  fix (`AuditLogService`, `session.displayName()` actor, `moduleName:
  'Organisation'`, no `outcome` — plain CRUD, not a decision). `details`
  carries the affected record's `#id` plus glanceable context (name +
  code for departments, title + grade for designations, name + time range
  for shifts, name + date + type for holidays). **Inspected the Company
  tab per the explicit ask — it doesn't exist**: `organisation-page.ts`
  has exactly four tabs (Departments/Designations/Shifts/Holidays), no
  Company tab or form anywhere in the codebase, and `companiesFeature` has
  zero references outside the store/model definitions — there is no
  company-level create/update/delete UI to audit. No business logic or UI
  behavior changed — only new `audit.record()` calls added alongside
  existing dispatches. `npx tsc --noEmit` clean, `ng build` clean, `ng
  test` **146/146 passing** (unchanged). **Verified live against the real
  backend**: posted 12 rows shaped exactly like the 12 new call sites
  (create/update/delete × department/designation/shift/holiday) — all
  `201`, every field round-tripped correctly, all deleted and confirmed
  gone via the API (404), backend dev server stopped.
- ✅ Done — **Full-system A-to-Z audit (report-only)**, prompted by an
  explicit request to review the actual frontend/backend/DB, not
  assumptions, before deciding what to build next. Found the system's
  business-logic layer (payroll calc, all `*-rules.ts`, Leave/Overtime/
  Loan/Bonus/Settlement/Change-Request/Payroll-Batch workflows) solid —
  146/146 tests re-verified fresh, no calculation bugs. Real findings,
  prioritized: **Critical** — `/api/**` has no server-side authorization
  (`SecurityConfig.java` `permitAll()` on everything but `/api/auth/me`),
  a real JWT/BCrypt backend exists and is completely unwired from the
  frontend (still on static demo credentials), no HTTP interceptor exists,
  no User/Role/Permission backend at all (`users-page.ts` is pure mock,
  and its "Permissions" UI doesn't even drive `session.ts`'s hardcoded
  `canApprove*` gates — confirmed directly, not assumed). **High** —
  Overtime/Loan/Bonus/Settlement/Payroll-Batch approve flows have no
  self-approval block (Leave and Change Request do, via a proven,
  reusable pattern); bank file has no employee bank-account/routing data.
  **Medium/Low** — no Tax/PF report, orphaned `companies` backed-
  collection entry, dev-only config (plaintext DB creds, `show-sql:
  true`) that needs externalizing before real deployment. Delivered a
  full per-module status table, role-workflow matrix, prioritized findings,
  a "should we add anything" section, and a final production-readiness
  checklist directly in conversation — no code, config, or doc changed by
  the audit itself; the checklist is what queued the Phase 1 work below.
- ✅ Done — **Phase 1 of the audit checklist: real JWT authentication
  wired into the frontend**, replacing the static demo-credential-only
  login path, scoped exactly as requested — no backend authorization and
  no User/Role/Permission persistence yet (both explicitly deferred).
  Reused the existing backend as-is (`AuthController`/`JwtService`/
  `SecurityConfig` — none of it touched): `POST /api/auth/login` issues a
  real BCrypt-verified JWT, `SecurityConfig` already permits attaching a
  bearer token to every request harmlessly (only `/api/auth/me` actually
  checks it today, matching that file's own documented scope).
  New frontend pieces: `core/auth/token-store.ts` (`TokenStore`,
  sessionStorage-backed, tracks `expiresAt` from the login response),
  `core/auth/auth-api.ts` (`AuthApiService`, thin `HttpClient` wrapper
  around `/api/auth/login`), `core/auth/auth-interceptor.ts`
  (`authInterceptor`, a functional `HttpInterceptorFn` — attaches
  `Authorization: Bearer <token>` to every request that goes to the real
  backend, and on any 401 other than the login call itself, clears the
  session and redirects to `/login`), registered via
  `provideHttpClient(withInterceptors([authInterceptor]))` in
  `app.config.ts`. `session.ts`'s `signIn` is now `async`: tries the real
  backend first (`tryBackendLogin`), and only falls back to the original
  local check (`signInLocally`, now factored out but behaviorally
  unchanged) when the backend doesn't recognize the account — the one
  case this covers on purpose is a user created via "Users & Roles" this
  session, which the real backend has no record of yet (persisting that
  is explicitly Phase-2+ work, not done here). Both paths converge on a
  new shared `finalizeSignIn` that keeps the one business rule the
  backend doesn't check (a separated employee can't sign in) and resolves
  the mock `users`-collection id `Notification.userId` depends on, so
  notifications keep working unchanged. `restore()` now also treats an
  expired real token as a signed-out session (`TokenStore.isExpired()`);
  a locally-authenticated session (no token issued) is unaffected, since
  it has nothing to expire. `signOut()` and the interceptor's 401 handler
  both clear the token. `login-page.ts`'s `submit()` is now `async`/
  `await`s `signIn` — its existing `submitting`/error-message UI needed
  no changes, it was already written for an async-shaped call. Preserved:
  every existing Admin/HR/Accountant/Employee sign-in flow, the demo
  account hint list, "Users & Roles" account creation, and password
  change (still local-only, `PasswordStore` — unaffected by this phase).
  `npx tsc --noEmit` clean, `ng build` clean. `ng test` **146/146
  passing** — `app.spec.ts`'s authentication suite now runs with
  `provideHttpClient()` and awaits the now-async `signIn`; with no
  backend running in the unit-test process, every one of those tests
  exercises the real backend-attempt-then-local-fallback path live (not
  mocked), proving the fallback itself. Backend `mvnw test`: **47/47
  passing**, unchanged (no backend code touched). **Verified live against
  the real backend/PostgreSQL**, all four demo roles: `POST
  /api/auth/login` for `farhana.islam`/`nasrin.akter`/`rakib.hasan`/
  `tanvir.ahmed` each returned a real three-part JWT with the correct
  `role`/`employeeId` (Admin/e7, HR/e1, Accountant/e2, Employee/e4) and an
  `expiresInSeconds` of 86400; each token then round-tripped correctly
  against `GET /api/auth/me`. Also verified: wrong password and unknown
  username both `401` on login; `/me` with no token, a garbage token, and
  a token with a forged `sub` claim (signature can't verify against the
  real user's password-hash-derived key) all correctly rejected (`403`
  under Spring Security's default unauthenticated-response mapping); a
  token attached to an ordinary backed-collection call (`GET
  /api/employees`) succeeded normally, proving the interceptor's job
  doesn't break anything. No data was written by any of this — login and
  `/me` are both reads — so there was nothing to clean up; backend dev
  server stopped after verification.
- ✅ Done — **Phase 2 of the audit checklist: real server-side
  authorization**, layered on Phase 1's JWT with the authentication flow
  itself untouched (`AuthController`/`JwtService`/`JwtAuthFilter`/
  `AppUser`/`AppRole` — no changes) and User/Role/Permission persistence
  still explicitly deferred. Rewrote `SecurityConfig.java`'s
  `authorizeHttpRequests` block from "only `/api/auth/me` is protected"
  to a full per-collection, per-HTTP-verb matrix derived from the actual
  Angular code — every `.dispatch(...actions.create/upsert/remove)` call
  site and the `canManage`/`canApprove*`/`canRaise*` gate it sits behind
  in `session.ts` and each page — not inferred from routing.
  **A real mid-implementation correction, kept here because it mattered**:
  the first pass restricted GET (read) endpoints to match
  `module-registry.ts`'s per-route role list (e.g. Audit Log → Admin
  only, Payroll Batches → Admin/HR/Accountant), which seemed like the
  obvious mapping. Reading the actual cross-module usage before shipping
  it disproved that: `dashboard-page.ts` loads `employees`/
  `payroll-batches`/`audit-logs` unconditionally for **all four roles**
  on sign-in, `attendance-page.ts` (all four roles) loads
  `salary-structures`, `payslip-detail.ts`/`payslip-list.ts` (all four
  roles) load `payroll-batches`, and `employee-detail.ts` (any role can
  open their own record) loads `settlements`. The nav-route table governs
  which *page* a role can visit (`roleGuard` already enforces that
  client-side) — it doesn't mean the underlying data is never read
  elsewhere. Shipping the first pass would have 403'd the dashboard for
  three of four roles on every login. Corrected to: GET open to any of
  the four roles for everything except `companies` (confirmed zero
  frontend callers — Admin-only is a safe default, not a guess); all the
  real, precise restriction lives in the write verbs, which are backed by
  direct dispatch-site evidence, not routing inference. A second, smaller
  version of the same mistake: `profile-page.ts` lets **any** role
  PUT-update their own employee record (photo/contact details), ungated
  by role — a case the first pass's blanket "PUT employees = Admin/HR"
  missed and would have broken. Fixed with a small custom
  `AuthorizationManager` (`PUT /api/employees/{id}`: Admin/HR for any id,
  or any role for their own id — mirrors `roleGuard`'s identical
  own-record carve-out for routes). A third: `leave-page.ts`'s
  `onSubmitted()` seeds a fresh `LeaveBalance` row (POST-or-fallback) the
  first time *any* role applies for a leave type they've never used —
  not behind `canApproveLeave` like the post-decision balance adjustment
  is, so `POST /api/leave-balances` had to open to all four roles while
  `PUT` (the actual adjustment) stayed HR/Admin-only.
  Final write matrix (role sets match the Angular gates exactly):
  Organisation (Department/Designation/Shift/Holiday) and Salary & Rules
  (SalaryStructure/TaxRule/PfRule) — Admin only; Employees — create/edit
  Admin/HR, activate Admin only, PUT also allows self (own record);
  Attendance — all four (self-service + correction share one endpoint,
  can't be split without inspecting the diff); Leave requests — apply
  any role, decide HR/Admin; Leave balances — self-seed any role, adjust
  HR/Admin; Leave rules — HR/Admin; Overtime — HR/Admin only (no
  self-submit path exists); Loans — raise Employee/HR only, decide
  HR/Accountant/Admin (Accountant/Admin legitimately auto-close via
  `batch-detail.ts`'s `pay()`); Bonuses — HR only end to end, deliberately
  no Admin override (matches `session.ts`'s own comment); Payroll
  batches/Payslips/Payments — Employee excluded from all three,
  Payslips additionally HR/Admin-only to write; Settlements — initiate
  HR/Admin, decide Accountant/Admin; Change requests — submit any role,
  decide HR/Admin; Notifications/Audit log writes — any role (self-service
  and every module's own audit trail respectively); `DELETE` — Admin-only
  everywhere (confirmed the only two frontend callers, Organisation and
  Salary & Rules, are already Admin-only). Both 401 (no/invalid token)
  and 403 (wrong role) now return a JSON body in the same
  `{timestamp, status, error, message, path}` shape `ApiExceptionHandler`
  already uses everywhere else, via a custom `authenticationEntryPoint`/
  `accessDeniedHandler` (Spring Security's defaults render empty bodies —
  `@RestControllerAdvice` can't intercept these since they're thrown
  inside the filter chain, before any controller runs).
  **Backend tests**: added `IntegrationTest`'s `adminToken()`/`hrToken()`/
  `accountantToken()`/`employeeToken()` helpers (log in as the real V14
  demo accounts once per test class, cached) and attached the right token
  to every existing `*ControllerIT` request that now needs one (11
  files). Added `AuthorizationIT.java` — 27 new tests proving the
  allowed/forbidden matrix for every major module: an allowed role
  clears the gate (never 401/403), a forbidden role gets exactly 403, no
  token gets exactly 401, and dedicated coverage for the three
  cross-module cases the corrections above were about (own-record PUT,
  self-seeded leave balance, reads open to every role). Updated
  `AuthControllerIT`'s `existingPayrollEndpointsStayOpenWithNoToken` →
  `payrollEndpointsNowRequireAuthentication`, asserting the opposite of
  what it did before — Phase 1's deliberately narrow "nothing gets gated
  yet" promise is superseded by design. `mvnw test`: **71/71 passing**
  (was 47; +25 in `AuthorizationIT`, minus 1 fixed pre-existing test
  assertion). Frontend untouched this phase — `npx tsc --noEmit` clean,
  `ng build` clean, `ng test` **146/146 passing**, all unchanged as
  expected.
  **Verified live against the real backend/PostgreSQL** — no browser
  automation tool is available in this environment (checked before
  starting; none registered), so this was driven via a Node script
  issuing the exact same HTTP calls the frontend's `session.ts`/
  `HybridApiService`/`auth-interceptor.ts` make (login → token →
  `Authorization` header), for all four demo roles, rather than a visual
  browser session — stated plainly rather than claimed as something it
  wasn't. 56 checks, all passed: all four roles log in and get a real
  JWT; no token is rejected `401` on both a read and a write; every role
  can read `employees`/`audit-logs`/`payroll-batches`/`salary-structures`
  (the dashboard/attendance/payslip fix, confirmed live); Admin can
  create and delete a department, HR/Accountant/Employee are each
  rejected `403` on the same write, and HR is rejected `403` on delete
  even though HR can read Organisation; Accountant is rejected `403`
  writing a salary structure; Employee can `PUT` their own employee
  record but is rejected `403` `PUT`-ing HR's record; HR is rejected
  `403` activating an employee, Admin succeeds (clears authorization,
  hits the real 404-for-unknown-id path); Employee can apply for leave
  and self-seed a leave balance but is rejected `403` deciding a leave
  request or adjusting a balance, HR can decide one; Employee is rejected
  `403` creating an overtime claim; Employee can raise a loan,
  Accountant is rejected `403` raising one, Accountant can close one
  (the batch-pay auto-close case); Admin is rejected `403` raising a
  bonus (no override) and so is Employee, HR succeeds; Employee is
  rejected `403` writing a payroll batch, HR is rejected `403` writing a
  payment; HR can initiate a settlement but is rejected `403` deciding
  one, Accountant can decide one; Accountant can submit a change request
  but is rejected `403` deciding one; every role can write an audit log
  entry. Every row created during verification (department, leave
  request, leave balance, loan, bonus, settlement, change request, four
  audit log entries) was deleted and reconfirmed gone via the API (404 on
  every one); backend dev server stopped after verification.
- ✅ Done — **Phase 3 of the audit checklist: Users & Roles & Permissions
  made fully backend-persistent**, closing the last of the three Critical
  findings from the original audit (no backend auth, JWT unwired, no
  User/Role/Permission backend — the first two closed by Phases 1–2).
  Inspected `users-page.ts`, `user-form.ts`, `session.ts`,
  `AuthController`/`JwtService`/`SecurityConfig`, and V14's schema first,
  per the explicit ask, before touching anything.
  **Schema** (`V17__users_roles_permissions.sql`): collapsed V14's unused
  `app_user`↔`app_role` many-to-many into a single `role_id` FK —
  `AuthController` already only ever read `roles.get(0)`, no code path
  ever used more than one role per user, so carrying the join table
  forward would have been complexity with no real behavior behind it.
  Converted both `app_user.id` and `app_role.id` from generated `BIGINT`
  to client-supplied `VARCHAR(64)`, matching every other entity in this
  project and — deliberately — the exact ids the mock frontend model
  already used for these same four demo rows (`u1`/`u2`/`u4`/`u7`,
  `r1`-`r4`), so `Notification.userId` and other id-based assumptions
  already baked into the frontend kept working unchanged. Added
  `permission` (module/read/write/canApprove, matching the frontend
  model exactly) and `app_role_permission` join tables, seeded with the
  same 10 permissions and per-role grants the mock `ROLES`/`PERMISSIONS`
  arrays already had. Re-seeded the four demo accounts with the same
  BCrypt hashes V14 used (passwords unchanged) plus the new `email`/
  `role_id` columns. Only 4 rows existed in either table, so a clean
  drop-and-recreate was simpler and safer than an in-place `ALTER` of a
  generated PK with a dependent join table.
  **Backend**: new `Permission` entity; `AppRole` gained `description`
  and a `permissions` many-to-many; `AppUser` gained `email` and a single
  `role` FK (was a `List<AppRole> roles`), and is now documented as
  deliberately never serialized directly — every response goes through a
  `UserResponse` DTO instead, since the entity's several `UserDetails`
  getters (`getPassword()`, `getAuthorities()`, `isAccountNonExpired()`,
  etc.) would otherwise leak the password hash and other internals
  through plain Jackson binding, unlike every other dumb-CRUD entity in
  this backend. New `AppUserController` (`/api/users` —
  list/get/create/update/delete, plus a dedicated
  `POST /{id}/reset-password` that hashes a plain-text password
  server-side and never stores or echoes it — kept separate from the
  generic update specifically so a client can never smuggle a
  pre-hashed value in through `PUT`), `AppRoleController` (`/api/roles`
  — get/update only, no create/delete: the four roles are fixed by
  design: `RoleDto` accepts `roleName` in the request body because the
  frontend always sends the full `Role` shape, but the controller never
  applies it — renaming a role would silently break every
  `hasAuthority`/`canApprove*` check keyed on that name), and
  `PermissionController` (`/api/permissions` — read-only, the UI only
  ever toggles which roles hold a permission, never creates one).
  `CreateUserRequest`/`UpdateUserRequest` both needed
  `@JsonIgnoreProperties(ignoreUnknown = true)` — the frontend dispatches
  the *full* `AppUser` shape (create includes `status`, update includes
  `id`) alongside the fields each DTO actually declares, and this
  backend's Jackson 3 rejects unknown properties by default (confirmed
  earlier this session) rather than silently dropping them; without the
  annotation, every create/update would have 400'd. Caught this by
  reasoning through the exact wire shape before it reached a live test,
  then added a dedicated test using the real full-shape payload (not
  hand-trimmed JSON) specifically to prove the fix, since an
  under-specified test body would not have caught the gap.
  **Frontend**: added `users`/`roles`/`permissions` to
  `HybridApiService.BACKED_COLLECTIONS` — the only frontend-shape changes
  needed were in `users-page.ts` itself (confirmed, like Phase 2's
  employees-and-friends check, that no other file references these three
  NgRx features — unlike most Phase 2 collections, no cross-module
  surprise here). `onCreate()` now rides the temp password along on the
  existing `create()` dispatch via `{...user, password} as AppUser` (an
  intentional cast — the extra field survives JSON serialization at
  runtime even though `AppUser`'s TS type doesn't declare it) instead of
  only ever storing it in the local `RuntimeCredentialStore`, which is no
  longer touched by user creation at all — a Phase-3-created account is a
  real backend row from the moment it's created, so it authenticates via
  `session.ts`'s real `tryBackendLogin` path immediately, with no local
  shadow copy needed. `resetPassword()` now calls a new
  `UsersApiService.resetPassword()` (a small dedicated `HttpClient`
  wrapper, same pattern as Phase 1's `AuthApiService`) instead of
  `PasswordStore.set()`. The "Pending activation" KPI, previously reading
  a `status: 'pending-activation'` value nothing in the real system ever
  sets (the backend only ever represents active/disabled — an account
  either exists or doesn't), is now computed from the two real
  collections directly: draft employees with no matching user row.
  Deliberately untouched: `session.ts`'s own "change my password"
  self-service flow (`PasswordStore`/`changePassword()`) — a different,
  not-in-scope feature (Phase 3's list was user creation/role
  change/password *reset*/status/permissions, not self-service password
  change) — and the local demo/runtime-credential fallback path itself,
  since a freshly-created Users & Roles account created via `user-form.ts`
  never needs it.
  **Scope boundary, stated plainly**: "permission changes... actually
  affect backend authorization" is true for the two attributes
  `SecurityConfig` actually checks — role and active status (proven live
  below: a role change changes what the next JWT can do, a disable
  blocks the next login). Per-permission (not per-role) enforcement was
  deliberately not built — `SecurityConfig` remains role-name-based, per
  Phase 2 and this phase's own explicit "keep the existing four roles...
  no complex custom-role functionality" instruction. Permission
  grant/revoke persists correctly and survives reload, same as
  everything else in this phase, but remains descriptive metadata per
  role rather than something the authorization filter chain consults —
  building real per-permission enforcement would be a genuine
  architecture change (permission-based instead of role-based checks
  throughout `SecurityConfig`), not "connecting an existing system," and
  was out of scope here.
  `mvnw test`: **78/78 passing** (71 prior + a new
  `UsersRolesPermissionsIT`, 8 tests: create-then-login, role-change-
  then-login, disable-then-login, reset-password-then-login, role
  description/permission persistence with the roleName-can't-be-renamed
  check, permissions list, Admin-only enforcement across all three
  collections, and the full-frontend-payload-shape regression test for
  the `@JsonIgnoreProperties` fix). `npx tsc --noEmit` clean, `ng build`
  clean, `ng test` **146/146 passing**, unchanged (no new pure-logic
  functions — this phase is UI glue and DTO plumbing). **Verified live
  against the real backend/PostgreSQL** — again no browser automation
  tool available in this environment (checked again this phase), so
  driven via a Node script issuing the exact HTTP calls the frontend
  makes, using the *exact* full `AppUser`-shaped JSON payloads (not
  hand-trimmed) to also prove the Jackson fix live, not just in
  `MockMvc`. 33 checks, all passed: all four demo accounts still log in
  correctly after the schema migration; Admin creates a user with a
  temp password and it immediately logs in via the real JWT flow with
  the right role; the new user shows up in `GET /users` (reload proof);
  changing its role to HR changes what its *next* login token grants —
  proven by that new token being rejected `403` writing Salary & Rules
  but succeeding reading Organisation; disabling it blocks the next
  login `401`, re-enabling restores it; resetting its password rejects
  the old one and accepts the new one; updating a role's description and
  permission list persists and reloads correctly, while a spoofed
  `roleName` in the same request is silently ignored (confirmed via
  re-`GET`); `GET /permissions` returns all 10 seeded rows; every one of
  these three collections is `403` for HR/Accountant/Employee and `401`
  with no token at all. The test user was deleted and reconfirmed gone
  via the API afterward; backend dev server stopped after verification.
- ✅ Done — **Self-approval blocking added to Overtime, Loan, Bonus,
  Settlement, and Payroll Batch** — the High-severity gap the original
  audit named explicitly (Leave and Change Request already had it; these
  five didn't). Followed the proven `canDecideLeaveRequest`/
  `canDecideChangeRequest` pattern exactly, minus their escalation chain:
  those two route the approver by the requester's *role* (Employee →
  HR/Admin, HR → Admin only, etc.), which doesn't apply here — Overtime/
  Loan/Bonus/Settlement/Batch each have a single fixed approver role set
  (`session.ts`'s `canApproveOvertime`/`canApproveLoans`/
  `canApproveBonuses`/`canApproveSettlement`/`canApproveBatch`, untouched),
  so the fix is purely the self-check layered on top of each existing
  gate — no workflow or role-set changed, per the explicit ask. Added one
  pure function per module: `canDecideOvertimeClaim`/`canDecideLoanRequest`/
  `canDecideBonusRequest`/`canDecideSettlement` (in each module's existing
  `*-rules.ts`, `employeeId` comparison) and a new `canApproveBatch` (new
  `payroll/payroll-rules.ts` — `PayrollBatch` has no `employeeId`, it
  isn't a per-employee request; identity is by `requestedBy`, a username
  string set from `session.currentUser()?.username`, matching the mock
  seed's `nasrin.akter`-style values). Wired each into the matching
  `*-detail.ts`'s `canDecide`/`canApprove` computed signal, e.g.
  `computed(() => session.canApproveLoans() && canDecideLoanRequest(loan()?.employeeId ?? '', session.employeeId()))`
  — the approve/reject section (and, for batches, the approve/pay
  buttons, since `pay()` is gated by the same `canApprove` signal — an
  intentional, consistent extension: if Admin ran their own batch, they
  shouldn't be the one marking it paid either) simply doesn't render for
  the requester, exactly like Leave/Change Request already behave. Audit
  logging and notifications on the normal (non-self) approve/reject path
  are untouched — same `audit.record()`/`notify.notifyEmployee()` calls
  as before, unaffected by the added gate. **Scope boundary, stated
  plainly, matching Phase 2's own documented limitation**: this is a
  UI-layer gate only, same as Leave/Change Request always were — the
  backend remains dumb CRUD with role-based (not identity-based)
  authorization (Phase 2), so a direct API call bypassing the UI can
  still perform a self-approval on any of these five, exactly as it
  always could on Leave/Change Request too. This isn't a regression
  introduced here; it's the same boundary the whole system has had,
  named explicitly rather than left implicit. `npx tsc --noEmit` clean,
  `ng build` clean, `ng test` **156/156 passing** (was 146; +10 — two
  tests per new pure function, self-blocked/other-allowed, in each
  module's existing `*-rules.spec.ts` plus a new `payroll-rules.spec.ts`).
  No backend code changed, so `mvnw test` was re-run only as a regression
  check: **79/79 passing**, unchanged. **Verified live against the real
  backend/PostgreSQL** — no browser automation tool available in this
  environment (checked again this task), so driven via a Node/HTTP
  script. Verified two different things for two different claims: (1)
  **normal requester/approver scenarios**, real HTTP round-trips proving
  nothing broke — HR approves an overtime claim it didn't file itself,
  HR rejects an Employee's loan (reason persists), HR approves an
  Employee's bonus, Accountant completes an Employee's settlement HR
  initiated, Accountant approves a batch HR ran — all succeeded exactly
  as before; and (2) **self-approval evaluation**, using each pure gate
  function re-implemented in the script and evaluated against real
  fetched identities (HR's own employeeId, Admin's own employeeId/
  username) rather than fixture data, confirming each correctly resolves
  to blocked for the exact scenario the fix targets — HR raising and
  deciding its own bonus, Admin initiating and deciding its own
  settlement, Admin running and approving its own batch — plus one
  explicit, honest check that the same self-approval PUT still succeeds
  when called directly against the API (the documented boundary above,
  proven rather than assumed). 26 checks, all passed. Every row created
  during verification (overtime claim, loan, two bonuses, settlement,
  payroll batch) was deleted and reconfirmed gone via the API; backend
  dev server stopped after verification.
- ✅ Done — **Employee Bank Details + real Bank File integration** —
  closes the Medium finding from the original audit (the bank-transfer
  CSV had employee code/name/net amount but no actual bank routing data,
  so it wasn't a real disbursement artifact). Added `bankName`/
  `bankAccountNumber`/`bankRoutingNumber` to the `Employee` model,
  optional throughout (matching the existing `photoUrl`/
  `emergencyContactName` pattern) — not every employee has bank details
  on file, and a missing value now leaves the bank-file column blank
  rather than blocking payroll, a deliberate choice per "preserve
  existing payroll and payment logic": this task added a new *field*,
  not a new *gate* on the run/approve/pay flow.
  **Schema** (`V18__employee_bank_details.sql`): three nullable columns
  on `employee`, with `CHECK` constraints on the two number fields
  (`bank_account_number ~ '^[0-9]{6,20}$'`, `bank_routing_number ~
  '^[0-9]{9}$'`, both `OR NULL`) — a bad value is rejected with the same
  clean 400 `ApiExceptionHandler` already produces for every other CHECK
  violation in this backend, no controller change needed.
  **Backend**: three new `@Column` fields on `Employee.java` — no
  controller change (`EmployeeController` already binds `@RequestBody
  Employee` directly for every field).
  **Frontend**: `employee-form.ts` (the shared add/edit modal) gained a
  "Bank details" field group with format validators — account number
  6–20 digits, routing number exactly 9 digits (the real Bangladesh Bank
  routing-number length) — both skipped by Angular's `Validators.pattern`
  when blank, so the fields stay genuinely optional; blank values are
  normalized to `undefined` before submit (not `''`), matching what the
  backend's `CHECK ... OR NULL` constraints actually allow — sending an
  empty string instead of omitting the field would have 400'd every
  employee saved with blank bank details, the most common case, so this
  was reasoned through and verified live rather than assumed.
  `employee-detail.ts`'s profile section now shows the three fields
  (Admin/HR-managed, same `canManage` gate as every other profile field —
  not routed through the separate self-service photo/contact-details
  path, and not added to Change Request's `EDITABLE_FIELDS`, since that
  list's existing `Other` catch-all already covers a self-proposed bank
  detail change with no code change needed).
  `core/bank-file.ts`'s `BankFileRow`/`buildBankTransferCsv` gained
  `bankName`/`accountNumber`/`routingNumber` columns, positioned between
  Department and Net Amount; `batch-detail.ts`'s `pay()` populates them
  from the employee record (`emp?.bankName ?? ''`, etc.) — the only
  change to the actual payment/bank-file generation step, everything
  else in that flow (payment record creation, batch status transition,
  notifications) untouched.
  `npx tsc --noEmit` clean, `ng build` clean, `ng test` **160/160
  passing** (was 156; +4 new `bank-file.spec.ts` tests: full row with
  bank details, blank-bank-details row still generates and totals
  correctly, comma-containing bank name gets CSV-quoted). `mvnw test`:
  **83/83 passing** (was 79; +4 new `EmployeeControllerIT` tests:
  no-bank-details persists as null, full round-trip, bad routing number
  400s, bad account number 400s). **Verified live against the real
  backend/PostgreSQL** — no browser automation tool available in this
  environment (checked again this task), so driven via a Node/HTTP
  script, including a faithful mirror of `buildBankTransferCsv` run
  against real employee rows fetched from Postgres (not fixture data) to
  prove the whole Employee-to-CSV pipeline, not just the API layer in
  isolation. 16 checks, all passed: an employee created with bank
  details persists and round-trips exactly; one created with none has
  the fields absent, not forced; a 3-digit routing number and a
  non-numeric account number are both rejected with the same clean 400
  shape as every other validation error in this backend; an existing
  blank-bank-details employee can be updated to add them; the generated
  CSV's header and rows — built from the two real Postgres rows just
  written, one with original bank details and one with updated ones —
  contain the real account/routing numbers in the right columns, full
  output logged for inspection; and Phase 2's authorization is
  unaffected — HR can still write employee records, a non-owning
  Employee still cannot. All four test employees were deleted and
  reconfirmed gone via the API; backend dev server stopped after
  verification.
- ✅ Done — **Server-side Bean Validation added to every entity in this
  backend** — closes the Medium finding from the original audit (only
  `LoginRequest` had any Bean Validation; every other entity relied
  entirely on Angular forms, with the DB's own `NOT NULL`/`CHECK`
  constraints as the only backstop). Audited all 26 entities plus the
  Phase 3 auth DTOs and added constraints per field: `@NotBlank`/
  `@NotNull` on every required field (matching the column's existing
  `nullable = false`, so nothing that was already required changed
  meaning — this only moves the rejection earlier and gives it a clean,
  field-specific message), `@Positive`/`@PositiveOrZero` on amounts and
  counts, `@DecimalMin(0)`/`@DecimalMax(100)` on the three percentage
  fields (`PfRule`'s two contribution percentages, `TaxRule.rate`), and
  `@Email`/`@Pattern` on Employee's email and bank detail fields (the
  latter mirroring V18's `CHECK` constraints exactly, so a bad value now
  gets a field-specific message before ever reaching Postgres instead of
  the generic CHECK-violation one). Added `@AssertTrue`-based cross-field
  date-range checks where the sign is unambiguous:
  `LeaveRequest.isDateRangeValid()` (`endDate` not before `startDate`),
  `PayrollBatch.isCycleRangeValid()` (`cycleEnd` not before
  `cycleStart`), `TaxRule.isIncomeRangeValid()` (`maxIncome` greater than
  `minIncome`) — deliberately **not** added to `Shift`'s start/end time,
  since overnight shifts are real and handled by `attendance-rules.ts`'s
  rollover logic, so an "end after start" rule there would reject valid
  data. Two calculated fields were caught and deliberately left
  sign-unconstrained after reasoning through their formulas rather than
  assumed: `FinalSettlement.netSettlementAmount` (`gratuity +
  leaveEncashment - pendingDues`, per `settlement-rules.ts` — an employee
  can legitimately owe more in dues than their gratuity covers) and
  `Payslip.netSalary`/`PayrollBatch.netTotal` (`grossSalary + bonus -
  totalDeductions`, per `payroll-engine.ts`, not mathematically
  guaranteed positive in every edge case) — a `@PositiveOrZero` on either
  would have silently broken a real, valid business scenario.
  Also added `@Valid` to all 24 `PUT .../batch` bulk-upsert endpoints,
  which had none — every single-item `create`/`update` endpoint already
  used `@Valid` (confirmed, not assumed), but the batch endpoints did
  not, which would have let every new constraint be bypassed by any
  caller using the batch path. Extended the three Phase 3 write DTOs
  too: `@Email` on `CreateUserRequest`/`UpdateUserRequest`'s email,
  `@Size(min = 8)` on `ResetPasswordRequest.newPassword` (matching
  `session.ts`'s own `changePassword()` minimum — same rule, now also
  enforced on the path that bypasses that self-service flow), `@NotBlank`/
  `@NotNull` on `RoleDto.description`/`permissionIds`.
  No frontend changes — this task was backend-only by design ("keep
  existing frontend behavior and business logic unchanged"); the Angular
  forms' own validators were already stricter or equal in every case
  checked, so nothing in the UI should ever trigger these new backend
  rejections in normal use — they're a backstop against direct API calls
  and malformed batch payloads, not a new user-facing behavior.
  **Fixed the exact fallout of moving validation earlier** — 5 existing
  tests had encoded the *old* behavior and needed updating, each
  confirmed to be the *intended*, better outcome rather than a
  regression: `ApiExceptionHandlerIT`'s missing-required-field test now
  asserts the Bean Validation message instead of the old raw
  DB-NOT-NULL-violation message (the DB path still exists as a backstop,
  just no longer reachable for any field that now carries `@NotBlank`);
  two `EmployeeControllerIT` bank-detail tests now assert the new
  field-specific `@Pattern` message instead of the old generic
  CHECK-violation one; two `AuthorizationIT` tests that sent an empty
  `{}` body to prove a role wasn't blocked (previously reaching a 404
  "not found") now assert `notForbidden()` instead of a specific status,
  since Bean Validation now rejects the empty body before the
  not-found check ever runs — a 400 still proves authorization cleared
  (a blocked role gets 403, not 400), so the test's actual intent is
  preserved.
  Added **`BeanValidationIT`**, 10 new tests spread across modules the
  other IT classes don't already cover, proving `ApiExceptionHandler`'s
  generic `MethodArgumentNotValidException` handling holds backend-wide,
  not just for the one or two entities each existing test class happens
  to touch: negative loan principal, zero bonus amount, PF contribution
  over 100%, negative tax rate, tax rule with `maxIncome` below
  `minIncome`, leave request with `endDate` before `startDate`, payroll
  batch with `cycleEnd` before `cycleStart`, blank department code,
  malformed employee email, and a too-short password reset — each
  asserting the exact field-specific message.
  `mvnw test`: **93/93 passing** (was 83; +10 new `BeanValidationIT`
  tests, the 5 fixed pre-existing tests counted in the 83). `npx tsc
  --noEmit` clean, `ng build` clean, `ng test` **160/160 passing**,
  unchanged (no frontend code touched this task, confirmed by re-running
  the full suite rather than assumed).
  **Verified live against the real backend/PostgreSQL** — no browser
  automation tool available in this environment (checked again this
  task), so driven via a Node/HTTP script. 26 checks, all passed: nine
  different invalid payloads (negative loan principal, negative bonus
  amount, PF% over 100, tax rule with an inverted income range, leave
  request with an inverted date range, malformed employee email, a bad
  bank routing number, a too-short password reset, a blank department
  code) each rejected with the exact expected field-specific `400`
  message; four valid payloads (a real loan, a real leave request, an
  employee with valid bank details, a valid 0%-rate tax slab) still
  succeed exactly as before — proving the new constraints reject only
  what they should; every one of the nine rejected payloads confirmed
  never actually written to Postgres (`404` on a follow-up `GET`, no
  partial writes); the weak-password-reset rejection confirmed to have
  left the real seeded HR account's actual password completely
  untouched (logged back in with the original password afterward); and
  the four valid records created for the regression check were deleted
  and reconfirmed gone via the API. Backend dev server stopped after
  verification.
- ✅ Done — **Tax and PF reports added to the Reports module** — closes
  the Medium finding from the original audit ("no dedicated Tax or PF
  report"). Frontend-only, no backend changes — every figure needed
  already exists on the real, backend-integrated `payslips`/`pf-rules`
  collections the rest of the app already loads; this only adds new
  read-only aggregation over data that's already there, exactly like
  every other section on this page.
  Added a new `reports/reports-rules.ts` (pure functions, no Angular
  imports, matching the established `*-rules.ts` convention) with two
  helpers: `effectiveTaxRatePct` (tax as % of gross, one decimal) and
  `employerPfContribution`, which **reuses payroll-engine.ts's exact
  employee-side PF formula** (`round(basic * pct / 100)`) against the
  employer's percentage instead — the one figure the engine never
  persists anywhere, since only the employee-side deduction affects net
  pay. This is a new read-only derivation for reporting only; it does
  not change how payroll is calculated, run, or approved, and nothing
  about the stored payslip changes.
  `reports-page.ts` gained: two KPI tiles (tax collected to date, PF
  contribution to date — employee/employer split shown in the hint); a
  "Tax report" section, per-pay-period totals (batch, month, employee
  count, total gross, total tax); a "Tax report — employee detail"
  section, one row per payslip (code, name, department, batch, gross,
  tax, effective rate), searchable like every other detail-level table
  on this page's peers (`audit-page.ts`); a "PF report" section, per-
  pay-period totals (employee PF, employer PF, combined), with the
  section note showing the active PF rule's percentages (or "No PF rule
  configured" if none exists — matches `salary-rules-page.ts`'s existing
  "use the first/only rule" convention, since this app treats PF as one
  current configuration, not a versioned history); and a "PF report —
  employee detail" section, one row per payslip (basic, employee PF,
  employer PF, total), also searchable. All four new sections follow the
  page's existing `SectionCard`/`DataTable` structure exactly — no new
  UI patterns introduced. Still Admin-only (the whole page's existing
  route gate, untouched) and still fully read-only — no new dispatched
  actions, no new writes.
  `npx tsc --noEmit` clean, `ng build` clean, `ng test` **167/167
  passing** (was 160; +7 new `reports-rules.spec.ts` tests: tax rate
  calculation and rounding, zero-gross/zero-tax edge cases, employer PF
  formula matching payroll-engine.ts's shape, PF rounding, 0% employer
  contribution). `mvnw test` re-run as a regression check since this
  task touches data the backend serves: **93/93 passing**, unchanged (no
  backend code changed).
  **Verified live against the real backend/PostgreSQL** — no browser
  automation tool available in this environment (checked again this
  task), so driven via a Node/HTTP script using realistic seeded payroll
  data, mirroring `reports-rules.ts`'s exact pure functions and
  evaluating them against real fetched `Payslip`/`PfRule` rows the same
  way `reports-page.ts`'s computed signals would. 18 checks, all passed:
  seeded a real payroll batch with two realistic payslips (employees e4
  and e1, basic 20000/35000, gross 30740/35000, tax 3000/4245, employee
  PF 2000/3500) against the backend's real, already-configured PF rule
  (10%/10%); confirmed both payslips round-trip via `GET /payslips`
  (reload proof); confirmed the tax-report cycle totals (gross 65740,
  tax 7245) and each employee's effective tax rate (9.8%/12.1%) match
  exactly; confirmed the PF-report cycle totals — employee PF 5500,
  and, critically, the **computed** employer PF total (5500, since this
  PF rule happens to be symmetric) matching `basic * employerPct / 100`
  for each real employee's real basic salary, proving the derivation
  against live data, not just fixture data in the unit tests. All
  seeded payslips and the batch were deleted and reconfirmed gone via
  the API; backend dev server stopped after verification.
- ✅ Done — **Company module completed** (was orphaned — backend CRUD
  with zero frontend callers, empty table, and the sign-in screen's
  branding hardcoded as a disconnected literal string). Audited first,
  report-only, before touching anything; this entry is that audit's
  approved minimal-completion plan, implemented exactly as recommended —
  no new fields, no create/delete UI, no payroll/workflow changes.
  **Backend**: `V19__seed_company.sql` inserts the one real row
  (`c1`, "Meghna Apparels Ltd.") the table never had, using the same id
  and values the mock frontend already seeded in-memory, for continuity.
  `SecurityConfig`'s single blanket `hasAuthority(ADMIN)` rule for
  `/api/companies/**` split into `GET` → `permitAll()` (deliberately
  public, the one exception to this file's "every GET needs a role"
  pattern — `login-page.ts` reads it before anyone is authenticated,
  same category as `/api/health`) and `POST`/`PUT` → still Admin-only
  (unchanged protection level; `DELETE` still covered by the existing
  blanket Admin-only rule). No entity/controller changes — `Company.java`
  already had the Bean Validation from the earlier task, `CompanyController`
  was already correct dumb CRUD.
  **Frontend**: added `companiesFeature` to `core/store/features.ts`
  (documented as single-row-in-practice, same convention as `pfRulesFeature`)
  and wired it into exactly three routes: `login` (new, since that route
  had no providers before), `organisation`, `payslips`. `organisation-page.ts`
  gained a fifth "Company" tab, Admin-only edit (`canManage`, the same
  gate as every other tab on that page), using the exact inline-draft/Save
  pattern `users-page.ts`'s role-description editing already established
  (draft signal + "Save" button that only appears once a field actually
  changed) — no new modal component, no new UI pattern. `payslip-detail.ts`
  now shows the company name/address above the payslip header, and the
  same two lines were added to the actual downloaded PDF
  (`buildSimplePdf`'s line array) — the one genuinely new "business
  document" improvement here, since a payslip with no issuing company
  looked unfinished. `login-page.ts`'s hardcoded
  `"Meghna Apparels Ltd. · Gazipur, Bangladesh"` replaced with the real
  `company()` signal. Audit logging preserved — `saveCompany()` calls the
  page's existing `log()` helper (`action: 'Updated company settings'`,
  `moduleName: 'Organisation'`), same shape as every other write on that
  page.
  `npx tsc --noEmit` clean, `ng build` clean, `ng test` **167/167
  passing**, unchanged (no new pure-logic function — this task is UI glue
  and one small entity-shaped edit, matching this session's established
  precedent of not forcing a spec file onto glue code that mirrors an
  already-tested pattern). `mvnw test`: **99/99 passing** (was 93; +6 new
  `CompanyControllerIT` tests: confirms V19's seeded row, public GET with
  no token, Admin update persists and reloads, HR/no-token rejected on
  write, Bean Validation still rejects a blank name).
  **Verified live against the real backend/PostgreSQL** — no browser
  automation tool available in this environment (checked again this
  task), so driven via a Node/HTTP script. 11 checks, all passed: the
  real V19-seeded row is readable; `GET /api/companies` (list) and
  `GET /api/companies/c1` both succeed with **no token at all** — the
  exact request `login-page.ts` makes pre-authentication; simulated
  `organisation-page.ts`'s `saveCompany()` exactly (full `Company`-shaped
  PUT as Admin) and confirmed the change is visible on an immediate,
  unauthenticated re-`GET` — the same path `login-page.ts`/
  `payslip-detail.ts` would read it through next; confirmed HR still gets
  `403` and no token still gets `401` writing (authorization unchanged);
  confirmed Bean Validation still rejects a blank name with the same
  field-specific message every other entity gets. Since this is the
  application's one real, permanent settings row rather than throwaway
  test data, the verification **restored it to its exact original
  values** afterward instead of deleting anything — confirmed via a
  final direct `GET` matching the pre-test row byte-for-byte; backend
  dev server stopped after verification.
- ✅ Done — **Production Spring profile added** — purely additive
  configuration, no business logic or existing dev behavior touched.
  `application.yml` restructured from one base doc + one `dev`-profile
  doc into: a base doc holding only what genuinely doesn't vary by
  environment (`server.port`, `jwt.access-token-expiration-ms` — moved
  here from inside the `dev` doc so they still apply once a second
  profile exists; same effective values as before, so `dev` is
  unaffected), the existing `dev` doc unchanged in every value it sets
  (datasource, `show-sql: true`, Flyway), plus a new `prod` doc
  (`spring.config.activate.on-profile: prod`, never the default —
  `spring.profiles.active` still reads `dev`). `prod`'s
  `spring.datasource.url`/`username`/`password` are `${DB_URL}`/
  `${DB_USERNAME}`/`${DB_PASSWORD}` with **no default value** — an
  unset one fails Spring's own startup placeholder resolution
  immediately, which is intentional (refusing to start beats silently
  falling back to a dev-shaped value). `show-sql: false` in `prod`
  (unchanged `true` in `dev`). `ddl-auto: validate` and every Flyway
  setting kept identical to `dev` — schema-source-of-truth behavior is
  not a thing this task touches.
  **CORS**: `WebConfig.java`'s `allowedOrigins` was a hardcoded
  `"http://localhost:4200"` literal; replaced with
  `@Value("${app.cors.allowed-origins}")` (comma-separated, split into
  an array — supports more than one origin without further code
  changes) sourced from `application.yml`'s new `app.cors.allowed-origins`
  key: `http://localhost:4200` under `dev` (byte-identical resulting
  behavior to before), `${CORS_ALLOWED_ORIGINS}` under `prod` — no real
  domain hardcoded anywhere in the repo.
  **No real secret or domain appears anywhere** in `application.yml`,
  `WebConfig.java`, or the new test below — every `prod`-only value is
  either an `${ENV_VAR}` placeholder or, in the test, an obviously-fake
  `.invalid` origin plus the same local dev Postgres credentials
  already public elsewhere in this file (no separate real production
  database exists in this environment to point at).
  **New test**: `ProdProfileConfigurationIT` (`config` package, 3
  tests) boots the full Spring context with `@ActiveProfiles("prod")`
  and injects `DB_URL`/`DB_USERNAME`/`DB_PASSWORD` (pointed at the same
  local Postgres) and `CORS_ALLOWED_ORIGINS` (`https://prod-test.example.invalid`)
  via `@DynamicPropertySource` — the same resolution path a real OS
  environment variable would take. Confirms: the context loads and
  `/api/health` responds under `prod` (proves datasource/Flyway/JPA all
  still initialize correctly with prod's settings, not just that the
  YAML parses); `spring.jpa.show-sql` resolves to `false`; a CORS
  preflight from the configured prod origin is allowed while one from
  `http://localhost:4200` — correct under `dev`, wrong under `prod` — is
  now rejected, proving the origin genuinely comes from config and
  isn't still hardcoded anywhere.
  `mvnw compile` clean. Full backend suite **103/103 passing** (+3 new
  `ProdProfileConfigurationIT` tests). Frontend unaffected by
  design (no frontend code changed for this task): `npx tsc --noEmit`
  clean, `ng build` clean, `ng test` **167/167 passing**, unchanged.
  **Verified live against the real backend/PostgreSQL** — no browser
  automation tool available in this environment (checked again this
  task), so driven via a Node/HTTP script, running the app under its
  normal `dev` profile (the profile that actually runs day-to-day) to
  prove nothing regressed for existing users while `prod` was being
  added alongside it. 10 checks, all passed: `/api/health` UP against
  the real Postgres connection; Admin and HR both still log in and
  receive a real JWT; `GET /api/companies` still `200` with no token
  (public, unchanged); an authorized Admin write is no longer rejected
  at the authorization layer while HR's write attempt still gets `403`
  and an unauthenticated read of a protected collection (`/api/employees`)
  still gets `401` — the whole authorization matrix unchanged; a CORS
  preflight from `http://localhost:4200` still succeeds and echoes that
  origin back exactly as before; a preflight from an untrusted origin
  (`https://evil.example.com`) is still rejected with `403`. No
  business data was created or altered by this verification (read-only
  checks plus one write rejected by validation before persisting), so
  there was nothing to restore or delete; backend dev server stopped
  after verification.
- ✅ Done — **Two production risks fixed, both found by this session's own
  A-to-Z production-readiness audit** (netSalary going negative under a
  large loan EMI; zero indexes on any foreign-key column across all 19
  migrations). Notification delivery, bank-specific file formats, and
  Swagger were explicitly out of scope for this pass — deliberately left
  as backlog, not touched.
  **Risk 1 — `netSalary` floor** (`payroll-engine.ts`, `runPayroll`):
  previously `loanRecovery` was `min(emiAmount, outstandingBalance)` only —
  nothing stopped a large EMI from pushing `netSalary` negative for a
  low-gross employee. Fixed by capping loan recovery to what's actually
  left after the deductions that can't be deferred (`tax`/`pf`/
  `lateDeduction`/`leaveDeduction`, all statutory or attendance-driven, none
  discretionary): `availableForLoanRecovery = max(0, grossSalary + bonus -
  tax - pf - lateDeduction - leaveDeduction)`, then `loanRecovery =
  min(desiredLoanRecovery, availableForLoanRecovery)`. The shortfall isn't
  written off — `applyLoanRecovery` already only reduces `outstandingBalance`
  by what a payslip's `loanRecovery` actually says was recovered, so an
  under-recovered loan simply carries the rest into next cycle, still
  `active`, not force-closed. A `Math.max(0, …)` floor on the final
  `netSalary` expression stays as a defensive backstop for the separate,
  narrower case of statutory deductions alone (no loan involved) somehow
  exceeding gross — not the primary fix, since capped loan recovery already
  makes `netSalary` non-negative by construction in every normal case.
  **Risk 2 — FK indexes** (new `V20__foreign_key_indexes.sql`, purely
  additive, no table/column/constraint/relationship changed): an index on
  every one of the 20 foreign-key-shaped columns across the schema that had
  none — every `employee_id` column (`attendance`, `leave_balance`,
  `leave_request`, `overtime`, `salary_structure`, `loan_record`,
  `bonus_record`, `payslip`, `final_settlement`, `change_request`,
  `app_user`), `employee`'s own `dept_id`/`designation_id`/`shift_id`,
  `department.head_employee_id` (self-referencing), `payslip.batch_id` and
  `payment.batch_id`, the auth chain's `app_user.role_id` and
  `app_role_permission.permission_id` (the composite-PK tables' non-leading
  column, previously unindexed for the reverse lookup direction), and
  `notification.user_id` (no declared FK constraint, but the column every
  "my notifications" query filters on).
  `mvnw compile` clean. Full backend suite **103/103 passing** (unchanged
  count — no new backend tests needed; the index migration has no
  behavior to unit-test beyond "the schema still validates," which the
  full suite already proves by running against it end to end). Frontend:
  5 new regression tests added to `payroll-engine.spec.ts` covering
  exactly the scenarios the audit flagged — an EMI that exceeds what's
  left after tax/PF (recovery capped, not the full EMI, net exactly 0), a
  normal EMI that's fully affordable (recovered in full, unchanged
  behavior), a very-low-gross employee with a large loan (nets to zero,
  the loan keeps its true unrecovered balance for next cycle, `active`
  not force-closed), a bonus increasing same-cycle recovery headroom, and
  an extreme statutory-only case (no loan) exercising the defensive floor
  in isolation. `npx tsc --noEmit` clean, `ng build` clean, `ng test`
  **172/172 passing** (was 167; +5).
  **Verified live against the real backend/PostgreSQL** — no browser
  automation tool available in this environment (checked again this
  task), so driven via a Node/HTTP script. 25 checks, all passed.
  *netSalary floor*: seeded a real employee (₹5,000 gross, no tax/PF) via
  the actual `/api/employees` + `/api/salary-structures` endpoints and a
  real active loan with a ₹20,000 EMI (far exceeding gross) via
  `/api/loans`; ran the exact fixed capping arithmetic against that real
  data (loan recovery correctly caps to ₹5,000, not the full ₹20,000
  EMI, net exactly ₹0); persisted the resulting payslip through the real
  `POST /api/payslips` and re-`GET` it — confirmed `netSalary`,
  `loanRecovery`, and `totalDeductions` all round-trip through Postgres
  unchanged and stay internally consistent
  (`grossSalary - totalDeductions === netSalary`), proving the fix holds
  through real persistence, not just in memory. *FK indexes*: confirmed
  all 20 new indexes physically exist in the real database via
  `psql \di idx_*` (20/20 present, valid), then ran `EXPLAIN` against
  real Postgres for a representative query on each of six indexed tables
  (`attendance`, `salary_structure`, `loan_record`, `payslip`, `app_user`,
  `notification`) to confirm the planner accepts and can use each index —
  noting the seed-data tables are small enough that Postgres's planner may
  still choose a sequential scan today, which is the *correct* choice at
  this row count and not a sign the index isn't working; what this proves
  is the index exists, is valid, and is available once table volume grows.
  All test-prefixed rows created for this verification (employee, salary
  structure, loan, payroll batch, payslip) were deleted via the real
  `DELETE` endpoints and reconfirmed gone both via a follow-up `GET`
  (`404`) and a direct `psql` count query (`0` rows matching `test-%` in
  every table touched); backend dev server stopped after verification.

---

## Part 2 — Backend (Spring Boot + local PostgreSQL) — In progress

Goal: replace `MockApiService`/`mock-db.ts` with real REST endpoints backed by
PostgreSQL, running locally, while keeping the Angular app's NgRx store/effects
shape (minimal frontend rewrite — mostly swap the API layer).

**Stack decisions**: Maven, Java 25 (installed JDK; pom `java.version` set to
21 as compat baseline), Spring Boot 4.1.1 (Initializr default — newer than
typical Boot 3.x tutorials, starter artifact names changed, e.g.
`spring-boot-starter-webmvc` not `-web`). No Docker — PostgreSQL 16 installed
natively on Windows. Auth deferred (§2.3 on hold, no Security dependency added
yet). Backend project lives as sibling folder `payroll-automation-backend/`
next to `Payroll Automation/`, under `Angular project/`.

### 2.1 Environment & project setup
- ✅ Done — PostgreSQL 16 verified running locally (Windows service `postgresql-x64-16`); created `payroll_db` database and dedicated app user `payroll_user` (not superuser), granted privileges on DB + `public` schema
- ✅ Done — Spring Boot project scaffolded via Spring Initializr: Web(Mvc), Data JPA, Validation, PostgreSQL Driver, Lombok, Flyway — Security intentionally omitted (auth on hold)
- ✅ Done — `application.yml` — `dev` profile active, datasource pointed at `localhost:5432/payroll_db`, `jpa.hibernate.ddl-auto: validate` (schema owned by Flyway, not Hibernate auto-gen), server port 8080
- ✅ Done — Flyway wired in (`db/migration/`), baseline `V1__init.sql` stub applied and verified — real per-module migrations still pending (§2.2)
- ✅ Done — Verified end-to-end: `mvnw compile` succeeds, app boots, Hikari connects to `payroll_db`, Flyway migration applies, `/api/health` returns `{"status":"UP"}`

### 2.2 Data modeling (mirror the 26 mock collections)
- ✅ Done — Organisation slice: Department, Designation, Shift, Holiday entities (UUID PKs), Flyway `V2__organisation.sql`, Spring Data repositories, full CRUD controllers (`/api/departments`, `/api/designations`, `/api/shifts`, `/api/holidays`) — verified via curl, JSON response shape matches frontend `Department`/`Designation`/`Shift`/`Holiday` interfaces in `hr.ts` exactly, Hibernate schema validation passes against Flyway-managed tables
- ✅ Done — Employee entity, Flyway `V3__employee.sql` (FK to department/designation/shift; added deferred FK `department.head_employee_id → employee.id` now that employee exists), repository, full CRUD controller (`/api/employees`) plus `PATCH /{id}/activate` (draft → active, 409 if not draft) — verified via curl with real FK references, matches diagram's draft/activate flow
- ✅ Done — Leave + Overtime vertical slice: Attendance, LeaveRequest, LeaveBalance, Overtime entities, Flyway `V4__attendance_leave_overtime.sql` (all FK'd to employee), repositories. `LeaveRules`/`OvertimeRules` — direct ports of frontend `leave-rules.ts`/`overtime-rules.ts` (day counting, balance validation, overlap-clash detection, weekly/daily overtime capping at Bangladesh Labour Act limits, eligibility check). Controllers: `/api/attendance` (CRUD + `/correct`), `/api/leave-balances` (CRUD), `/api/leave-requests` (`/apply` runs full validation, `/approve` moves balance days taken→remaining, `/reject`), `/api/overtime` (`/record` auto-caps raw hours, `/approve` flips `payrollEligible`, `/reject`) — verified end-to-end via curl: 3-day leave correctly deducted from balance (10→7), 5 raw overtime hours correctly capped to 4 (daily cap), short-reason leave application correctly rejected with 400
- ✅ Done — Payroll module: SalaryStructure, TaxRule, PfRule, LoanRecord, BonusRecord, PayrollBatch, Payslip, Payment entities, Flyway `V5__payroll.sql`, repos, full CRUD controllers (`/api/salary-structures`, `/api/tax-rules`, `/api/pf-rules`, `/api/loans`, `/api/bonuses`, `/api/payroll-batches`, `/api/payslips`, `/api/payments`) — same client-supplied-string-id CRUD shape as every other module. Deliberately did NOT reimplement `payroll-engine.ts`'s calculation in Java: per the architecture decision in §2.5, business logic stays in Angular, backend stays a dumb CRUD store — "porting the engine" meant giving its input/output collections a real backend, not duplicating the math server-side
- ✅ Done — Company, FinalSettlement, ChangeRequest, Notification, AuditLog entities, Flyway `V6__company_settlement_changerequest_notification_audit.sql`, repos, full CRUD controllers (`/api/companies`, `/api/settlements`, `/api/change-requests`, `/api/notifications`, `/api/audit-logs`) — same client-supplied-string-id CRUD shape as every other module, scaffolded via fork against the exact Department pattern, `mvnw compile` clean, verified live via curl (POST/GET/DELETE roundtrip on `/api/companies`)
- ✅ Done — LeaveRule entity (Admin/HR-configurable leave entitlement per type), Flyway `V11__leave_rules.sql` (table + default seed rows + one-time `leave_balance` seed for the four demo employees), repo, full CRUD controller (`/api/leave-rules`) — same client-supplied-string-id CRUD shape as every other module; see §1.4 for the frontend fix this unblocked
- ✅ Done (correction, 2026-09-01) — AppUser, Role, Permission entities — `V14__auth_users_roles.sql`/`V17__users_roles_permissions.sql`, real BCrypt-hashed accounts, see §2.3
- ✅ Done (correction, 2026-09-01) — JPA relationships matching the class diagram — every entity FK-references its parent (Employee↔Department/Designation/Shift, PayrollBatch↔Payslip↔Payment via `batch_id`, etc.) across `V1`–`V26`
- ✅ Done (correction, 2026-09-01) — Migration scripts through `V26` — every module has its own, real production data has run against all of them
- ✅ Done (correction, 2026-09-01) — Seed data — `V8`/`V19` seed real demo accounts/company data via Flyway; most other modules' demo data was seeded live through the real API during development/testing rather than a separate SQL seed script (equivalent effect, different mechanism — not a gap)
- ⬜ Not done — DTOs separating request/response shape from entities (currently entities exposed directly on controllers — acceptable for CRUD-only, unauthenticated phase; revisit once validation/auth needs diverge from persistence shape)

### 2.3 Authentication & authorization — real end-to-end (2026-09-01 correction: this section's two ⬜ items below were stale — the frontend wiring they describe as "still pending" was actually completed in an earlier, unlogged pass and has been live and tested throughout every fix this session since. Corrected in place below rather than silently rewritten, so the drift itself is on record.)
- ✅ Done — **Real login endpoint, BCrypt password hashing, real JWT issuance.**
  The user copied a full standalone auth microservice (`com.idb.auth` — its
  own Maven project, OTP/2FA, per-account lockout, per-IP blocking, a mail
  service, Caffeine caching, Actuator, a `permissions.json`-driven
  per-URL authorization matrix, ~330 files including an unrelated
  Playwright/Node test harness) into `src/main/java/auth/`. **This first
  broke the backend build outright** — the folder sat under Maven's
  recursive `src/main/java` source scan with no matching dependencies,
  so `mvnw compile` failed before any merge work began; confirmed and fixed
  by removing the folder as step one.
  Audited before touching anything (per the explicit ask) and presented the
  scope tradeoff to the user: reuse the full enterprise feature set
  (matching the source project exactly, but risking every existing payroll
  endpoint 401ing under `anyRequest().authenticated()` unless a
  `permissions.json` entry existed for all ~30 controllers) vs. a trimmed
  core (User/Role, BCrypt, JWT login — skip OTP/2FA/IP-blocking/mail/cache/
  the permission matrix). **User chose the trimmed core.**
  Rebuilt from scratch in the correct location and package
  (`com.payroll.automation.auth`, not `com.idb.auth`), reusing only the
  ideas worth keeping from the copied source — not the code verbatim, since
  it assumed a disjoint schema (own `auth` database, Hibernate
  `ddl-auto: update`, `Long`-id `AuditableModel` audit columns) and a
  different framework version's package layout:
  - `AppUser`/`AppRole` entities (`app_user`/`app_role`/`app_user_role`,
    Flyway `V14__auth_users_roles.sql` — deliberately `Long` auto-increment
    ids, a one-time exception to this project's usual client-supplied
    `VARCHAR(64)` convention, since login accounts are a genuinely new
    concern never referenced by a frontend-generated id). `AppUser.employeeId`
    links each account to the real `employee` row (`e7`/`e1`/`e2`/`e4`, per
    V8) for whenever the frontend is wired to this instead of the mock login
    — not read by any code path yet.
  - `JwtService` — kept the source's cleverest idea: tokens are signed **per
    user, with that user's own BCrypt hash as the HMAC key**, so there is no
    global signing secret to configure or leak, and changing a password
    invalidates every token that user holds with no revocation list needed.
  - `POST /api/auth/login` — real `PasswordEncoder.matches()` against the
    stored hash, real JWT issuance on success, `401` on wrong password or
    unknown username (routed through the existing `ApiExceptionHandler` from
    §2.6, not a new exception-handling stack).
  - `GET /api/auth/me` — the one endpoint actually gated by
    `JwtAuthFilter`+`SecurityConfig`, included specifically to prove the
    full round-trip (issue → verify → reject-if-tampered) works, not left
    theoretical.
  - **Every existing payroll `/api/**` endpoint is deliberately left
    `permitAll()`.** The frontend has zero token storage or `Authorization`
    header attachment today (`session.ts` is still entirely
    `sessionStorage`-based mock auth) — gating the rest of the API to match
    `roleGuard`'s role matrix would 401 every feature this project has
    built and verified all session, the exact "breaking payroll features"
    the task explicitly ruled out. Stated as a real, deliberate scope
    boundary, not a silent gap: **wiring the frontend to this real login
    (token storage, an HTTP interceptor, gating the rest of `/api/**`) is
    real follow-up work, not done here.**
  - No plaintext password anywhere: the four demo passwords (from
    PROGRESS.md's sign-in table) were BCrypt-hashed once via a throwaway
    JUnit test that printed the hashes and was deleted immediately after —
    only the resulting `$2a$10$...` hashes exist in the migration SQL, in
    Postgres, or anywhere in the Java source.
  - CORS deliberately not duplicated: `SecurityConfig` has no `.cors(...)`
    call, so the existing `WebConfig.addCorsMappings` remains the sole CORS
    authority, unaffected by Security's presence.
  - `pom.xml`: added `spring-boot-starter-security` (+ `-security-test`),
    `jjwt-api`/`-impl`/`-gson`, `gson` — no Caffeine/Actuator/commons-lang3/
    Testcontainers/mail, matching the trimmed scope.
  - New `AuthControllerIT` (8 tests, real Postgres, real BCrypt, real JWT —
    no mocking): correct-password login, wrong-password 401, unknown-user
    401, all four demo accounts login with their documented password and
    resolve to the correct role + employeeId, `/me` rejects no-token and a
    tampered token, `/me` accepts a valid token and returns the right user,
    and an explicit regression test (`existingPayrollEndpointsStayOpenWithNoToken`)
    asserting `/api/employees`/`/api/departments`/`/api/leave-rules` all
    still return `200` with zero `Authorization` header — the literal
    "don't break payroll" requirement, asserted, not just claimed.
  - Full backend suite **47/47 passing** (was 39 before this merge),
    `mvnw compile` clean.
  - **Verified live** against the real running backend: `POST /api/auth/login`
    for `tanvir.ahmed`/`Staff@2026` returned a real JWT + `role: "Employee"`,
    `employeeId: "e4"`; wrong password returned a clean `401`; direct `psql`
    query confirmed `app_user.password_hash` holds only BCrypt hashes;
    `GET /api/auth/me` with that token returned the authenticated user, with
    no token returned `403`; `GET /api/employees`/`/api/departments`/
    `/api/leave-rules` all still returned `200` with no `Authorization`
    header at all, confirming the "don't break payroll" boundary holds live,
    not just in tests. Backend dev server stopped afterward.
- ✅ Done (correction, 2026-09-01) — **Frontend wiring is real and has been
  the whole session.** `session.ts`'s `signIn` calls the real
  `POST /api/auth/login` first (BCrypt + JWT), stores the token
  (`auth/token-store.ts`), and `auth/auth-interceptor.ts` attaches
  `Authorization: Bearer <token>` to every outgoing request — confirmed by
  re-reading `session.ts`'s own doc comment and by the simple fact that
  every live E2E pass this session (§1.15 onward) authenticated through the
  real login screen and made real, JWT-gated API calls. `roleGuard`'s role
  matrix and `SecurityConfig`'s server-side matrix were independently
  audited module-by-module as each fix landed, not assumed. `session.ts`
  keeps one deliberate fallback: an account the real backend doesn't
  recognize yet (e.g. created before this pass, or only in `runtime-
  credentials.ts`) falls back to the original local mock check — see the
  new §2.12 for the plan to verify this boundary explicitly.
- ✅ Done (correction, 2026-09-01) — **Account activation is real-auth-gated.**
  `PATCH /api/employees/{id}/activate` is `hasAuthority(ADMIN)` in
  `SecurityConfig` today, not `permitAll()` — confirmed by re-reading the
  full `permitAll()` list in `SecurityConfig` (only `/api/auth/login`,
  `/api/health`, CORS preflight, and `GET /api/companies/**` are open;
  `anyRequest().authenticated()` closes everything else). This was likely
  true well before this correction was written; the ⬜ marker just never
  got flipped.
- ⬜ Deliberately not built (trimmed-scope decision, not a gap): OTP/2FA,
  per-account lockout, per-IP blocking, real mail delivery, a
  `permissions.json`-style per-URL authorization matrix. All were present in
  the copied source and available to reuse; the user chose to skip them for
  this pass. Revisit if this project's actual threat model calls for them
  later — nothing here blocks adding them.

### 2.4 Core REST APIs (one controller/service/repo set per module)
**Correction, 2026-09-01**: this entire list was stale — every ⬜ below has
had a real, tested, live-verified controller for some time (`http-api.ts`'s
`BACKED_COLLECTIONS` map covers every single key in `MOCK_DB`, with no
untouched collection left — checked directly against the source, not
assumed). All flipped to ✅ in place, each with a pointer to where the real
work is actually documented, per §2.5's "dumb CRUD store" architecture
decision (business logic stays in the frontend's `*-rules.ts` files —
**not** ported to Java; the two `⬜` bullets below that mention porting
`overtime-rules.ts`/`payroll-engine.ts` were written before that
architecture decision and are wrong on principle, not just out of date —
do not act on them).
- ✅ Done — Employees API (CRUD, draft/activate) — plain CRUD + `PATCH
  /{id}/activate` (Admin-only) and `PATCH /{id}/separate` (Accountant/Admin,
  added in §1.18) — see §2.2/§1.18
- ✅ Done — Organisation API (Department/Designation/Shift/Holiday CRUD) — §2.2
- ✅ Done — Users & Roles API (accounts, roles, permission matrix) — real
  BCrypt-hashed accounts, real role/permission CRUD, `UsersRolesPermissionsIT`
  (8 tests) — §1.14's "Admin config gaps closed" entry
- ✅ Done — Attendance API (register, HR correction, employee check-in/out)
  — §1.12, plus `uq_attendance_employee_date` (V25, §2.10)
- ✅ Done — Leave API — `/api/leave-requests`, `/api/leave-balances`,
  `/api/leave-rules`, dumb CRUD per §2.5's architecture decision (validation/
  balance math stays in `leave-rules.ts` on the frontend, not ported to
  Java), plus the date-overlap exclusion constraint (V26, §2.11)
- ✅ Done — Overtime API — dumb CRUD (the "port `overtime-rules.ts`" idea
  below predates the §2.5 architecture pivot and was never done on
  purpose), plus terminal-state immutability (§2.10)
- ✅ Done — Payroll Batch API — dumb CRUD plus `PayrollBatchService`'s
  state-machine/paid-immutability enforcement (§2.9); the "port
  `payroll-engine.ts` to Java" idea below is the same pre-§2.5 idea and
  remains deliberately not done — the engine stays in Angular
- ✅ Done — Payslips API (list/detail) — real CRUD, immutable once the
  parent batch is paid (§2.9). PDF generation is real but deliberately
  client-side (`core/payslip-pdf.ts`, confirmed a genuine working PDF
  download, not a stub — §1.14) rather than a server-side OpenPDF/iText
  endpoint; no reason to add a second PDF pipeline
- ✅ Done — Salary & Rules API (Salary Structure, Tax Rule, PF Rule CRUD) — §2.2
- ✅ Done — Loans & Bonuses API — dumb CRUD plus duplicate-open-bonus
  prevention and terminal-state immutability for both (§2.10)
- ✅ Done — Settlements API — dumb CRUD plus `SettlementService`'s
  completed-immutability, duplicate-open prevention, loan connection,
  employee separation, and payment tracking (§1.18)
- ✅ Done — Change Requests API — dumb CRUD (§2.2); not yet given the same
  immutability/duplicate audit pass as Bonus/Loan/Overtime — see §2.12's
  next-steps list
- ✅ Done — Audit Log API (write on every mutating action) — real endpoint;
  every module's frontend `AuditLogService.record()` call site was audited
  and filled in where missing (§1.14)
- ✅ Done — Notifications API + real in-app dispatch — real endpoint, wired
  into every decision point (§1.14). Real email/SMS delivery remains
  explicitly out of scope pending a provider decision — not a gap, a
  deferred choice
- ✅ Done — Bank transfer file generation — real CSV generation
  (`core/bank-file.ts`), triggered from `batch-detail.ts`'s `pay()`,
  confirmed a genuine download in the salary-payment-workflow audit (§2.7)
- ✅ Done (by design, not a dedicated endpoint) — Admin reports/analytics —
  `reports-page.ts` computes directly from already-real collections
  (payslips, payroll batches, salary structures) client-side; no separate
  reports endpoint exists or is needed under this architecture

### 2.5 Frontend–backend integration
- ✅ Done — Discovered and resolved an architecture mismatch before wiring: the frontend generates its own client-side string ids (e.g. `lv-${employeeId}-${Date.now()}`) and keeps ALL business logic (validation, day-counts, balance math) in Angular's `*-rules.ts` files — the backend is meant to be a dumb CRUD store, per the plan's "minimal frontend rewrite" goal. Backend originally built the opposite way (server-generated UUIDs, custom `/apply`/`/approve`/`/record` business endpoints). Reconciled by adapting the backend: switched every entity's PK from UUID to a client-supplied `VARCHAR(64)` string (Flyway `V1`–`V4` rewritten in place, schema dropped/recreated — dev-only, no real data lost), removed the Java rule-port classes (`LeaveRules`/`OvertimeRules`) and their controller endpoints, replaced with plain `list/get/create/update/putMany(batch)/remove` CRUD matching `MockApiService` exactly across Department/Designation/Shift/Holiday/Employee/Attendance/LeaveBalance/LeaveRequest/Overtime
- ✅ Done — `HybridApiService` (`core/http-api.ts`) — drop-in subclass of `MockApiService`, overrides `list/get/create/update/putMany/remove` to route real-backed collections over `HttpClient` to `http://localhost:8080/api/...`, falls through to the in-memory mock for any collection without a backend. **Correction, 2026-09-01**: every single key in `MOCK_DB` is now listed in `BACKED_COLLECTIONS` — the fallback path exists as a safety net but nothing actually uses it anymore; the parenthetical list this line originally had (naming which collections were still mock-only) is obsolete and removed rather than corrected in place, since there's nothing left to list
- ✅ Done — Wired in `app.config.ts`: `provideHttpClient()` added, `{ provide: MockApiService, useExisting: HybridApiService }` — every existing `inject(MockApiService)` call site now transparently resolves to the hybrid
- ✅ Done — CORS config (`WebConfig.java`) — `/api/**` allows `http://localhost:4200`, all methods, verified via real browser preflight
- ✅ Done — Verified end-to-end in a real browser (not just curl): logged in as Admin, Organisation page rendered real Postgres rows (1 department/designation/shift/holiday seeded via curl), confirmed 5 real `GET .../api/...` calls at 200 with zero console errors, then created a department through the actual UI form — POST 201, count went 1→2, row confirmed present in Postgres afterward with its client-generated id intact
- ✅ Done — Fixed a pre-existing frontend bug surfaced by real data: `employeeName`/`employeeCode`/`departmentName`/`designationTitle`/`shiftName` (in `mock-db/seed/org.ts`) resolved against the **frozen static seed arrays**, not the live store — so any row created at runtime, mock or real, never resolved (a latent bug even before this backend existed). Added `core/directory.ts` (`DirectoryService`, reads live store entity maps) and swapped all 22 call-site files over to it. `npx tsc --noEmit` clean.
- ✅ Done — Verified live in a real browser across every backend-ready module, not just curl: Employees page correctly resolves Department/Designation names post-fix; Attendance page renders real check-in/out with resolved employee name; Leave page — seeded a pending request via curl, approved it through the actual UI, confirmed in Postgres both the `LeaveRequest.status` and the `LeaveBalance` math (taken 0→2, remaining 10→8) persisted correctly, matching the two-step `upsert` dispatch pattern; Overtime page loads clean with zero console errors. Zero console errors and correct data across all four pages.
- ⬜ Not done — Environment config file (`environment.ts`) — API base URL is currently hardcoded in `http-api.ts`, fine for local dev, revisit if a build-time prod/dev split is needed
- ⬜ Known limitation — demo login accounts (Admin/HR/Accountant/Employee) reference mock-seeded employee ids (`e1`..`e15`) that don't exist in the real backend yet; self-service pages tied to "my own employee record" (leave self-apply, profile page) will show empty/blocked until real employee rows are seeded matching the demo accounts' `employeeId`. Org-wide views (approval queues, admin lists) are unaffected — verified working.
- ✅ Done — Wired all 8 payroll collections into `HybridApiService`'s `BACKED_COLLECTIONS` map, verified live in a real browser end-to-end: seeded a draft `PayrollBatch` + `SalaryStructure`/`TaxRule`/`PfRule`/`LoanRecord` via curl, clicked "Lock cycle and run engine" in the actual UI — `payroll-engine.ts` (still running client-side, unchanged) read all inputs over HTTP, calculated correctly (gross ৳45,000, 10% PF ৳3,000, ৳0 tax under slab, ৳0 loan recovery since loan was `pending` not `active`, net ৳42,000), and wrote the batch status + generated payslip back to Postgres via `putMany` — confirmed both rows present and correct via curl afterward
- ✅ Done — Wired Company/Settlements/ChangeRequests/Notifications/AuditLogs into `HybridApiService`'s `BACKED_COLLECTIONS` map (`companies`, `settlements`, `changeRequests`, `notifications`, `auditLogs`), backend verified via curl CRUD roundtrip; remaining mock-only collections are now just `users`/`roles`/`permissions` (blocked on auth, §2.3)
- ✅ Done (correction, 2026-09-01) — Real token/session handling exists (`TokenStore` + `auth-interceptor.ts`), layered alongside the original `sessionStorage` demo session rather than replacing it outright — see §2.3's correction
- ⬜ Not done — Error handling / loading states aligned with real network latency (component code already handles `loading`/`error` from `CollectionState`, but not stress-tested against real network conditions yet)

### 2.6 Testing & quality (backend)
- ✅ Done — **Backend integration test suite, 36 tests across 8 controllers, run against the real local PostgreSQL `payroll_db`** (no Testcontainers/H2, matching the "no Docker" stack decision) — MockMvc + Spring context, JUnit 5. Scoped after auditing every controller and confirming a fact not previously written down explicitly: **there is no business logic anywhere in this backend** — every controller (Employee, Attendance, Leave, Overtime, Loan, PayrollBatch, Payslip, LeaveRule) is an identical dumb CRUD shape (list/get/create/update/putMany/delete) calling the repository directly, no `/apply`/`/approve`/`/record` endpoints exist server-side. All payroll/leave/overtime calculation logic is client-side only (`*-rules.ts`, `payroll-engine.ts`), already covered by the frontend's 105+ Jest tests. So "testing payroll calculations" here means verifying **data-integrity round-trips** (a payslip's `lateDeduction`/`leaveDeduction`/`netSalary` etc. persist through Postgres unchanged) rather than re-deriving numbers server-side — there is nothing server-side to re-derive.
  - `EmployeeControllerIT` (6 tests) — covers the **one real branching business rule in the entire backend**: `activate()`'s draft→active transition, 409 on an already-active employee, 404 on unknown id, plus CRUD roundtrip.
  - `AttendanceControllerIT` (4) — check-in/out roundtrip, correction fields (`correctedBy`/`correctionReason`), and a regression guard on the `Cache-Control: no-store` header (`NoCacheFilter`) that closed the stale-Back-navigation bug from §1.12.
  - `LeaveRequestControllerIT` (6), `LeaveBalanceControllerIT` (2), `LeaveRuleControllerIT` (3) — FK-constrained create against the real seeded demo employee `e4`, approve/reject transitions, balance movement persistence, and the `LeaveRule` CHECK+UNIQUE constraint (leave_type restricted to Casual/Sick/Earned/Maternity, all four permanently seeded by V11 — discovered while writing this test that there is deliberately no valid "create" case for this entity, only update, matching the frontend's edit-only Leave Rules panel).
  - `OvertimeControllerIT` (4) — approval flipping `payrollEligible` (the only flag `payroll-engine.ts` reads), V10 correction fields.
  - `LoanRecordControllerIT` (3) — principal/EMI persistence, and confirms in a test (not just prose) the known limitation from §1.13: approving a loan does not touch `outstandingBalance` — no recovery schedule exists yet.
  - `PayrollBatchControllerIT` (4), `PayslipControllerIT` (3) — lifecycle status transitions, `batch_ref` unique constraint, and money-critical: every payslip deduction line (`lateDeduction`, `leaveDeduction`, `totalDeductions`, `netSalary` etc., the V9 fields) round-trips through Postgres exactly, plus the nullable-deduction case (`EngineInput.leaveRequests` omitted).
  - **Real gap found and documented, not fixed** (out of scope for a testing-only pass — would be a behavior change): there is no `@ControllerAdvice`/global exception handler anywhere in the backend. A DB constraint violation (FK or unique) is not translated into a clean 4xx/5xx JSON response — it propagates as a raw, unhandled `DataIntegrityViolationException` out of the controller. Reproduced directly in two tests (`LeaveRequestControllerIT.createWithUnknownEmployeeIdFailsForeignKey`, `PayrollBatchControllerIT.duplicateBatchRefIsRejectedByUniqueConstraint`) — both now assert the actual current behavior (`ServletException` wrapping the constraint violation) rather than a clean error response, since that's what the code genuinely does today. Worth a small follow-up pass adding a `@RestControllerAdvice` mapping `DataIntegrityViolationException` → 409/400 with a real message, for whenever the frontend needs to show something better than a generic failure on these paths.
  - Verified end-to-end: full suite run twice back-to-back, 36/36 passing both times (confirms every test cleans up after itself — no order dependency, no leaked state); confirmed via direct `psql` query against `payroll_db` afterward that zero `test-`-prefixed rows remain in any table and the permanent `lr-Casual` seed row (`annual_entitlement: 10.00`) was correctly restored by the one test that had to mutate it.
  - Build config changes required to get here (Spring Boot 4.1.1 specifics, worth knowing for the next pass): the Initializr-generated pom's four modular `-test` starters (`data-jpa-test`, `flyway-test`, `validation-test`, `webmvc-test`) don't bundle JUnit/MockMvc/Jackson the way the classic `spring-boot-starter-test` does — swapped to `spring-boot-starter-test` (test scope) plus kept `spring-boot-starter-webmvc-test` for `@AutoConfigureMockMvc`, which Boot 4.1 relocated to `org.springframework.boot.webmvc.test.autoconfigure`. Boot 4.1 also switched the default Jackson stack from `com.fasterxml.jackson.databind` (2.x) to `tools.jackson.databind` (Jackson 3.x) — `ObjectMapper` imports use the new package. Surefire's default include pattern doesn't match `*IT.java`; added an explicit `<includes>` block (`*Test.java`, `*Tests.java`, `*IT.java`) to `maven-surefire-plugin` so the new tests actually run (the very first `mvnw test` after adding them silently ran 1 test — the pre-existing `contextLoads` — and reported BUILD SUCCESS, which would have shipped as a false "tests pass" signal without checking the count).
- ⬜ Not done — Unit tests for `*-rules.ts` business logic ported server-side — not applicable; that logic doesn't exist server-side by design (see above), only client-side, where it's already tested
- ⬜ Not done — API documentation (springdoc-openapi / Swagger UI)
- ✅ Done — **Global `@RestControllerAdvice` closing the error-handling gap found above.** New `ApiExceptionHandler` (`config` package, alongside `WebConfig`/`NoCacheFilter`), purely additive — no controller, entity, or business logic touched:
  - `DataIntegrityViolationException` (FK/unique/check/not-null constraint violations from Postgres) is inspected by root-cause message and mapped to a clean status + human-readable message: FK violation → 400 "This request references a record that does not exist.", unique violation → 409 "A record with the same unique value already exists.", check constraint → 400 "One of the submitted values is not allowed for this field.", not-null → 400 "A required field was missing.", anything else → 409 generic conflict message. Previously all four propagated as a raw, unhandled exception (confirmed live before the fix: `POST /api/leave-requests` with an unknown `employeeId` returned Spring Boot's bare whitelabel `{"status":500,"error":"Internal Server Error", ...}` with no indication of what actually went wrong).
  - `ResponseStatusException` (the 404/409 every controller already throws explicitly, e.g. `EmployeeController.activate()`) now also flows through the same handler, so **every** error response — old and new — shares one consistent JSON body shape: `{timestamp, status, error, message, path}`. Confirmed this didn't change any existing controller's intended status code, only standardized the body.
  - Also added, since the ask covered "validation, etc." generally: `MethodArgumentNotValidException` (Bean Validation failures, listing the offending fields — dormant today since no entity carries `@NotNull`/`@NotBlank` etc., but wired for whenever one is added) and `HttpMessageNotReadableException` (malformed JSON body → 400 instead of a raw parse-error stack trace), plus a catch-all `Exception` → 500 with a generic message (stack trace still logged server-side via `logger.error`, never leaked to the client).
  - **Verified two ways.** (1) Integration tests: the two tests written in the previous pass to *document* the gap (`LeaveRequestControllerIT`, `PayrollBatchControllerIT`) now assert the clean response instead of the raw exception, and a new dedicated `ApiExceptionHandlerIT` (3 tests) covers the not-null-constraint branch, confirms the 404 body shape is unchanged in content, and covers malformed JSON — full suite now **39/39 passing**, run twice back-to-back (idempotent, no leaked test rows). (2) Live against the real running backend (stopped the stale pre-existing dev process, rebuilt, restarted, confirmed `/api/health` UP): `curl`'d all three constraint-violation paths for real — FK violation on `/api/leave-requests` now returns `400 {"message":"This request references a record that does not exist."}` (previously bare `500`), duplicate `batchRef` on `/api/payroll-batches` returns `409`, invalid `leaveType` on `/api/leave-rules` returns `400`; confirmed the existing 404 (`GET /api/employees/{unknown-id}`) and a real 200 (`GET /api/employees/e4`) both still behave exactly as before. All curl-created test rows either never persisted (that's what was being tested) or were deleted afterward; confirmed via `psql` zero leftover `curl-`-prefixed rows in Postgres; dev server stopped afterward.

### 2.7 Salary payment workflow audit and fix (2026-08-31)
- **Root cause found**: an employee's salary could not be paid because there was **no UI to create a payroll batch at all**. `batch-list.ts` (payroll batches page) had a table and KPIs but no "create" button/form, and `app.routes.ts`'s `payroll` route only had `''` (list) and `':id'` (detail) — no `new`. Confirmed live against the real backend/Postgres: `payroll_batch` had zero rows before this fix (`psql`: `select * from payroll_batch` → empty), so there was nothing for HR to run, nothing for the Accountant to approve, and nothing to pay — every other step of the pipeline (run engine, submit, approve, return, pay, bank file, mark paid) was already fully implemented and correct in `batch-detail.ts`, just unreachable with zero batches in existence.
  - This was **not** a calculation, authorization, or state-machine bug — those were all audited and found correct: `payroll-engine.ts`'s `runPayroll`/`payrollPreflight` are sound (missing `SalaryStructure` is a non-blocking warning that excludes just that employee, not a hard block; missing PF/tax config is correctly blocking); `SecurityConfig.java`'s role gates (`POST/PUT /api/payroll-batches/**` → HR/Accountant/Admin, `/api/payslips/**` → Admin/HR, `/api/payments/**` → Accountant/Admin) line up exactly with the frontend's `session.canRequestPayroll` (HR/Admin creates & runs) and `session.canApproveBatch` (Accountant/Admin approves/returns/pays), matching the diagram's intended flow (HR verifies attendance/leave/overtime and runs the cycle, Accountant reviews and pays) — no role or authorization change was made or needed.
  - **Fix**: added `features/payroll/batch-form.ts` (new `BatchForm` modal component, mirrors the existing `settlement-form.ts` pattern) and wired it into `batch-list.ts` behind a "Create payroll batch" button gated on `session.canRequestPayroll` (HR/Admin only, same guard `batch-detail.ts` already used for run/submit). The form is a single `<input type="month">`; cycle start/end, the human month label and the batch reference (`PR-YYYY-MM`, matching the existing seed-data convention) are all derived from that one value via a new pure function `deriveBatchCycle()` (`payroll-rules.ts`), never typed by hand, so they can never disagree with each other. Duplicate-month submission is blocked client-side (checked against the existing batches list) ahead of the DB's own `batch_ref` unique constraint. New batch dispatches through `payrollBatchesFeature.actions.upsertMany` (insert path, same as `settlements-page.ts`'s `onSubmitted` — a bare `upsert` is update-only and would 404 against a backend that's never seen the id), starts at `status: 'draft'`, zeroed totals — everything downstream (`batch-detail.ts`'s run/submit/approve/pay) was already correct and untouched.
  - **Secondary fix, same root cause class**: neither `batch-list.ts` (create) nor `batch-detail.ts` (run/submit/approve/return/pay) ever read the `error` state each of those NgRx collection features already tracks on a failed HTTP write — a rejected request (network failure, backend down, a constraint violation slipping past client-side checks) failed completely silently: the button click did nothing visible and the batch stayed on its old status with no explanation. Added a `writeError`/`createError` computed signal to each page (reads `payrollBatchesFeature`/`payslipsFeature`/`paymentsFeature`'s existing `selectors.error`) and a small inline error banner, matching the existing `remarks`/`returned` banner styling already on the page. No new state, no backend change — purely surfacing what was already being tracked and silently dropped.
  - Backend audited in full alongside this (`PayrollBatchController`/`PayslipController`/`PaymentController`, `PayrollBatch`/`Payslip`/`Payment` entities, `V5__payroll.sql`, `PayrollBatchControllerIT`) and found already correct and already tested — plain CRUD by this project's established architecture (§2.5), no service layer, no business logic to port; `ApiExceptionHandler` (§2.6) already handles both constraint violations and `@Valid` failures cleanly. No backend changes were made.
  - **Regression tests**: `deriveBatchCycle()` covered in `payroll-rules.spec.ts` — full calendar month/batch-ref/label derivation, leap-year and non-leap-year February day counts, and malformed/out-of-range input returning `undefined`. Full frontend suite: **177/177 passing** (was 172; +5 new), `npx tsc --noEmit` clean, `ng build` clean.
  - **Live-verified end-to-end against the real running backend and local PostgreSQL** (not mocked, not curl-only) using browser automation: signed in as HR (`nasrin.akter`), created a **July 2026** batch through the new UI (month picker → previewed `2026-07-01 → 2026-07-31`, ref `PR-2026-07`, before submitting), ran the engine (9 employees picked up, gross ৳957,703, net ৳721,137 — 11 other active employees correctly excluded with an on-screen warning for having no `SalaryStructure` yet), submitted for verification; signed out, signed in as Accountant (`rakib.hasan`), approved the batch, then generated the bank file and marked it paid. Status progressed `draft → calculated → pending-approval → approved → paid` exactly as designed. Confirmed directly in Postgres afterward (not just the UI): `payroll_batch` row `status='paid'`, `net_total=721137.00`, `approved_by='rakib.hasan'`; `payment` row `amount=721137.00`, `status='processed'`, real BEFTN-style `bank_file_ref`; 9 real `payslip` rows with correct per-employee `net_salary` (spot-checked against `employee`/`salary_structure` data, e.g. Tanvir Ahmed ৳26,220). Payroll batches list page KPIs updated correctly ("Paid to date ৳721,137"). No console errors observed during the flow.

---

### 2.8 Bonus decision moved from HR to Accountant, requestedBy tracking added (2026-08-31)
- **Change**: bonus requests now split raise/decide across two roles instead of HR doing both — HR (or Admin) raises a bonus request, **Accountant decides** (approve/reject), matching the same segregation-of-duties pattern already used for payroll batches (HR runs, Accountant approves). Previously HR could both create and approve/reject its own bonus requests.
- `session.ts`: `canApproveBonuses` moved from HR to Accountant-only (Admin deliberately excluded, consistent with the existing self-approval-blocking pattern for Overtime/Loan/Bonus/Settlement in section 1.14).
- Backend `SecurityConfig.java`: `PUT /api/bonuses/**` role gate narrowed to Accountant-only, matching the frontend guard.
- Added `requestedBy` to `BonusRecord` end-to-end: V22 Flyway migration, `Bonus` JPA entity, TS `BonusRecord` model, set in `bonus-form.ts` on submit, displayed on `bonus-detail.ts`.
- Added an Accountant dashboard KPI tile — "Bonuses pending / Awaiting your decision".
- Loan module untouched (loan calculation, approval flow, EMI deduction all unrelated to this change).
- **Live-verified against the real backend/Postgres** (browser UI + direct API), 12 checkpoints: HR submit succeeds (201); HR attempting approve/reject gets 403 and sees no Decision panel in the UI at all; Accountant can both approve and reject; entire flow completes without any Admin step; empty rejection reason still blocked client-side (unchanged validation); `requestedBy` = `nasrin.akter` confirmed in API response, DB row, and detail page; approved bonus flows into a real payroll engine run (payslip bonus=6000); a rejected bonus in the same run is excluded (bonus=0); Employee (`tanvir.ahmed`) receives a real notification ("Bonus approved... 2,000 taka"); audit log has separate real entries for HR's submit and Accountant's approve; duplicate-bonus guard still blocks a second pending festival bonus for the same date ("A pending festival bonus already exists for 2027-02-01."); full suite green — 192/192 frontend + 104/104 backend, both builds clean.

### 1.15 Attendance correction now recomputes isLate (2026-09-01)
- **Root cause**: an audit of Attendance/Leave/Overtime's payroll integration (real Postgres data, no changes made at the time) found `attendance-correction-form.ts`'s `submit()` spread `...rec` and only overwrote `checkIn`/`checkOut`/`status`/`workedHours` — `isLate` carried over unchanged from before the correction. A correction that fixed a wrongly-flagged-late check-in kept charging the late deduction; a correction that fixed an under-reported late check-in kept charging nothing.
- **Fix**: added `recalculatedIsLate(checkIn, shiftStart, graceMinutes)` to `attendance-rules.ts` — `false` with no check-in or no shift on file (same rule live check-in already uses), otherwise `isLateCheckIn`. `attendance-page.ts`'s `saveCorrection()` now calls it (via a new `shiftStartFor()` lookup, mirroring the existing `shiftEndFor()`) before dispatching, so the corrected check-in time — not the stale flag — is what payroll sees on the next run. `describeCorrection()`'s audit-log diff also gained an `isLate` (`Late`) row, since a correction can now change it.
- Scope: attendance-page.ts and attendance-rules.ts only. Leave, Overtime, payroll calculation rules, salary structure, tax, PF, loan, and bonus untouched, per instruction. Unauthorized-absence deduction (a separate finding from the same audit) deliberately not implemented — it needs a policy decision, not a code fix.
- **Tests**: 4 new `recalculatedIsLate` unit tests (`attendance-rules.spec.ts`) covering both correction directions, no-shift, and no-check-in. 2 new `payroll-engine.spec.ts` tests proving the fix reaches a payroll rerun: an on-time day corrected to late crosses the free-allowance threshold (`lateDeduction` 0 → 500 in the test's round numbers); a late day corrected to on-time drops back under it (500 → 0). Full suite: **198/198 frontend** (was 192, +6), `ng build` clean, backend unaffected and reconfirmed at **112/112** (no backend files touched).
- **Live-verified against the real running backend and local PostgreSQL**, both directions, through the actual correction UI (not a raw API call, since the fix is client-side logic): seeded 4 real attendance rows for Tanvir Ahmed (e4) in a fresh April 2027 cycle (3 late, 1 on-time), created a batch, and drove the full real workflow — HR runs the engine (`lateDeduction: 0`, 3 late days within the free allowance) → submits → **Accountant rejects** with remarks (back to `draft`) → **Admin corrects** the on-time day to a genuinely late check-in through the Attendance UI → confirmed via `GET /api/attendance/{id}` that `isLate` flipped to `true` and the audit log recorded `Check in 09:00:00 → 09:30, Late false → true` → HR re-runs the engine → `GET /api/payslips/{id}` confirmed `lateDeduction: 783.00` (4 late days, 1 chargeable). Repeated the cycle in reverse: submit → Accountant rejects again → **HR corrects** a late day back to on-time → confirmed `isLate: false` persisted → re-ran the engine → `lateDeduction: 0.00` again (back to 3 late days). All test attendance rows, payslips (all 10 employees the batch picked up), and the batch itself deleted afterward; both servers left running and healthy.

### 1.16 Unauthorized absence deduction implemented (2026-09-01)
- **Policy** (recommended in the prior audit, approved as-is): a working day with no attendance and no leave request that actually excused it costs the same flat `dailyRate` as unpaid leave, with **no free allowance** (unlike lateness's free-3) — a full no-show delivers nothing, so it can't cost less than a filed-and-rejected Unpaid request. Excluded before the check ever runs: the company's weekly off day, any `Holiday` row, and any date outside the employee's employment window (`joiningDate`/`lastWorkingDay`). Approved leave (any type) always excuses a day; a rejected request excuses nothing; a still-`pending` request gets the benefit of the doubt this run and is surfaced separately so the Accountant can see the number might change.
- **New**: `Company.weeklyOffDay` (a `Date#getUTCDay()` index, 0=Sunday…6=Saturday) — the simplest fit alongside the existing single-row Company settings, defaulting to 5 (Friday) for the seeded row (V23 migration `NOT NULL DEFAULT 5`, so no manual backfill needed). Editable on `organisation-page.ts`'s Company tab (new "Weekly off day" select, Admin-only like every other field there).
- **New**: `assessUnauthorizedAbsence()` and `unauthorizedAbsenceDeductionAmount()` (`attendance-rules.ts`) — walks the cycle day by day within the employee's employment window, applying the exclusion/excuse rules above; returns both the chargeable dates and a separate `pendingLeaveDates` list. Wired into `runPayroll()` (`payroll-engine.ts`) behind a new optional `weeklyOffDay`/`holidays` pair on `EngineInput` — same "optional so existing call sites keep working unchanged" convention `leaveRequests` already established: omit `weeklyOffDay` and `absenceDeduction` comes out to 0 for everyone, exactly as before this feature existed (kept every pre-existing test in `payroll-engine.spec.ts` passing unchanged). `availableForLoanRecovery` now also nets out `absenceDeduction`, alongside late/unpaid-leave, consistent with the existing "attendance-driven deductions aren't discretionary, loan recovery is what defers" design.
- **New `Payslip` fields**: `absenceDeduction` and `pendingLeaveDays` (both optional/nullable, mirroring `lateDeduction`/`leaveDeduction`'s precedent) — V23 migration, `Payslip` entity, TS model. Surfaced on `batch-detail.ts` (new "Absence" column, a per-row "N pending leave" badge, and a batch-level review banner when any payslip in the batch has pending-leave days) and `payslip-detail.ts` (deduction line + inline note, plus the PDF export line).
- **Bug found and fixed while wiring this up**: the `payroll` route (`app.routes.ts`) never provided `companiesFeature`/`holidaysFeature` to its route-scoped NgRx state — `batch-detail.ts` calling `selectSignal` on either crashed the whole page (`Cannot read properties of undefined (reading 'ids')`) the moment `runEngine()` needed them. Added both to the route's `providers` array. Caught immediately by live E2E, not merged unnoticed.
- Scope: `attendance-rules.ts`, `payroll-engine.ts`, `batch-detail.ts`, `payslip-detail.ts`, `organisation-page.ts`, `app.routes.ts`, `Company`/`Payslip` models and their backend entities/migration. Leave, Overtime, payroll calculation rules for tax/PF/loan/bonus, and every unrelated module untouched, per instruction.
- **Tests**: 15 new unit tests for `assessUnauthorizedAbsence`/`unauthorizedAbsenceDeductionAmount` (`attendance-rules.spec.ts`) covering every exclusion/excuse rule individually (weekly off, holiday, real attendance, an explicit `absent`-status row, approved paid leave, approved Unpaid leave not double-charged, rejected leave, pending leave, joining-date boundary, last-working-day boundary, no-overlap-at-all, and per-employee isolation). 8 new `payroll-engine.spec.ts` tests covering the same rules end-to-end through `runPayroll` plus a dedicated reject→HR-decides→rerun→further-rerun test proving the charge lands exactly once with no duplication, and a backward-compatibility test locking in that omitting `weeklyOffDay` leaves every existing call site unaffected. Full suite: **221/221 frontend** (was 213 after the isLate fix, +8 net after one initial test-data fix), `ng build` clean, backend **112/112** unaffected (`Company`/`Payslip` schema changes are additive and nullable/defaulted; the one existing `CompanyControllerIT` test that PUTs a full payload was updated to include `weeklyOffDay`, since it's now `@NotNull`).
- **Live-verified against the real running backend and local PostgreSQL** (both servers restarted to load the new schema/entities/routes): confirmed the seeded company row already reads `weeklyOffDay: 5` after the migration, with no manual backfill. Built a real 6-day cycle (2027-07-01→06) for Tanvir Ahmed (e4, real ৳47,000 structure) with one real attendance day, the weekly-off Friday, a declared holiday, an approved Casual (paid) leave day, and a still-pending Unpaid leave day — ran the engine through the real UI and confirmed via direct API: `absenceDeduction: 7833` (exactly the one unexcused day), `pendingLeaveDays: 1`, with the weekend/holiday/paid-leave days correctly costing nothing. Confirmed the review banner and the per-row "pending leave" badge rendered on the batch page exactly as designed. Ran the real reject→HR-decides→rerun loop: Accountant returned the batch, HR rejected the pending leave (no supporting evidence), re-ran the engine — `absenceDeduction` correctly rose to `15667` (both days now charged) and `pendingLeaveDays` dropped to 0, with the badge disappearing from the UI. All test attendance/holiday/leave/payslip/batch rows deleted afterward; both servers left running and healthy.

### 1.17 Calendar-day salary proration for mid-cycle join/leave (2026-09-01)
- **Root cause / policy** (recommended in the prior audit, approved as-is): `runPayroll` paid every active employee their full `SalaryStructure` regardless of `joiningDate`/`lastWorkingDay` — a mid-cycle joiner or leaver got a full month's basic/hra/allowances for a partial month worked. Fixed with calendar-day proration (not working-day — a monthly salary already bakes in weekend/holiday pay, and it keeps this consistent with the `dailyRate` convention late/unpaid-leave/unauthorized-absence already use).
- **`payroll-engine.ts`**: new `employedDays`/`employmentRatio` computed the same way as `assessUnauthorizedAbsence`'s window (`joiningDate`…`lastWorkingDay ?? cycleEnd`, clipped to the cycle) — symmetric by design: proration removes pay for days *outside* employment, absence/leave continue handling days *inside* it, no overlap between the two mechanisms. `basic`/`hra`/`allowances` are each individually prorated (`round(structure.X * employmentRatio)`) rather than just shrinking the gross total, so PF — which reads `structure.basic` directly — naturally scales with the prorated basic instead of needing a second correction. `monthlyTax()`'s signature changed to take both a nominal gross (slab selection — the employee's salary *rate* hasn't changed just because they worked part of the month) and an applied gross (what the resolved rate is actually charged against) — prevents a partial month's smaller prorated figure from wrongly dropping someone into a lower tax bracket for that one cycle.
- Deliberately unaffected: overtime (already tied to real attendance, which can't predate joining anyway), bonus (still pays the full HR-approved amount — proration of festival bonuses by service length is a distinct policy question, not bundled in here), loan recovery (still the fixed EMI, still capped by the existing `availableForLoanRecovery`, which already nets out every attendance-driven deduction), and every late/unpaid-leave/unauthorized-absence rule shipped in the last two passes (untouched — they already respected the employment window).
- Explicitly **not** done this pass, per instruction: Final Settlement (confirmed by re-reading `settlement-rules.ts` that it has no salary component at all — `netSettlementAmount = gratuity + leaveEncashment - pendingDues`, so it structurally cannot double-pay a prorated month; regular Payroll remains the only thing that pays a departing employee's final month) and `Employee.status` (a related, still-open gap: completing a settlement never flips status, so nothing stops a settled employee from still being picked up by a future payroll batch — flagged again as a follow-up, not touched here).
- Scope: `payroll-engine.ts` only (plus its own spec file). No schema/entity change — every affected `Payslip` field already existed.
- **Tests**: 9 new `payroll-engine.spec.ts` tests — full-month (byte-identical to before), mid-month joiner, mid-month leaver, joined-and-left-same-month, same-day join/leave (one day of pay, not zero), joining on a weekend day, leaving on a weekend day (both proving proration is calendar-day with no weekend-awareness, unlike the absence rule), zero-overlap (employment window never touches the cycle — pays nothing, no crash, no negative), and a dedicated test proving overtime/bonus/loan recovery are untouched by proration. One test deliberately sets up two tax slabs positioned so a *prorated* gross would fall into the wrong (lower) slab if the nominal-gross-selection guarantee ever regressed — locks in the exact bug this design avoids. Full suite: **230/230 frontend** (was 221, +9), `ng build` clean, backend **112/112** unaffected (no backend files touched this pass).
- **Live-verified against the real running backend and local PostgreSQL**: temporarily set Tanvir Ahmed's (e4) real `joiningDate` to the 16th of a fresh 31-day August 2027 cycle (16 of 31 days employed), seeded real attendance for every one of those 16 days (present, on-time, so unauthorized-absence stayed at 0 and isolated the proration math), ran the engine through the real UI. Confirmed via direct API against real Tanvir data (basic ৳30,000/hra ৳12,000/allowances ৳5,000, real 10% PF, real tax slabs with his nominal annual salary landing in the real 10% bracket): `basic: 15484, hra: 6194, allowances: 2581, grossSalary: 24259, tax: 2426, pf: 1548` — exact match to hand-calculated expectations, tax correctly computed at the nominal-slab rate applied to the prorated gross. His real pre-existing active loan (EMI ৳2,000) recovered in full, unaffected by proration, confirming the "loan/overtime/bonus untouched" guarantee against real data too. Payslip UI (`payslip-detail.ts`) correctly displayed the prorated Basic/HRA/Allowances as the earnings line items — a genuinely partial-month-looking payslip, not a full amount with a large offsetting deduction. Restored Tanvir's real `joiningDate` (`2020-01-01`) immediately after; deleted all seeded attendance, the test payslips (all 10 employees the batch picked up), and the test batch. Both servers left running and healthy.

### 1.18 Final Settlement: immutability, duplicate prevention, loan connection, employee separation, payment tracking (2026-09-01)
- **Root cause / audit** (prior turn, no code changed then): Final Settlement had none of the protections Payroll Batch already got this session. Confirmed live: a completed settlement could be freely rewritten (`PUT` accepted a gratuity change to any completed row) and deleted (`DELETE` succeeded), by any role including Admin — no equivalent of the paid-batch immutability. Two open (pending/completed) settlements could exist for the same employee via a direct API call — `validateSettlementRequest`'s "one open per employee" rule was frontend-only. An active `LoanRecord`'s outstanding balance was never connected to Settlement at all. Completing a settlement never touched `Employee.status`, so a settled employee could still be picked up by a future payroll batch. There was no payment tracking of any kind.
- **`SettlementService`** (new, mirrors `PayrollBatchService`'s Javadoc exactly): `update()`/`delete()` reject any write against a `completed` settlement — 409, no role override, for the same reason a paid batch is immutable: it represents money already disbursed. Duplicate-open prevention needs no service-layer code — `uq_final_settlement_open_employee` (V24, a partial unique index on `employee_id` `WHERE status IN ('pending','completed')`) closes it at the data layer, and the existing `ApiExceptionHandler` already turns that into a clean 409 (same shape as V21's `payment.batch_id` fix).
- **Loan connection**: `settlement-rules.ts`'s new `outstandingLoanBalance()` sums an employee's *active* loans at settlement-initiation time; `settlement-form.ts` shows it live as "Outstanding loan recovery" and folds it into `netSettlementAmount` (now a 4th parameter, defaulting to 0 — every existing call site and test kept working unchanged). New `FinalSettlement.loanRecovery` field (V24, default 0) carries it through to the detail page and list. On completion, `settlement-detail.ts`'s `approve()` closes every active loan for that employee in full (`outstandingBalance: 0`, `status: 'closed'`) — a one-time "everything is settled now" event, not a partial EMI-style recovery, so it doesn't reuse `applyLoanRecovery`'s delta-splitting logic (that stays untouched, payroll's loan math is unmodified).
- **Employee separation**: completing a settlement now calls a **new** `PATCH /api/employees/{id}/separate` — deliberately not the generic employee `PUT` (Admin/HR-or-self only), since completing a settlement is an Accountant action and Accountant has no general employee-write permission. Mirrors the existing `/activate` endpoint's shape exactly (flips status server-side, accepts no body, so the role it's gated to — Accountant/Admin, matching `canApproveSettlement` — can never rewrite any other employee field). `runPayroll` already only reads `status === 'active'`, so this one field change is what actually keeps a settled employee out of every future payroll batch — no payroll-engine change needed at all.
- **Payment tracking**: new `paymentDate`/`paymentReference`/`paymentStatus` fields (V24; `paymentStatus` defaults `'pending'`). `settlement-detail.ts`'s Decision panel now requires both a payment date and a reference (`validatePaymentDetails`, new) before "Verify and complete" will fire; completing sets `paymentStatus: 'paid'`. A new "Payment" card shows all three once completed; the list page shows a `payment pending`/`payment paid` badge alongside the settlement status badge.
- **Bug found and fixed while wiring this up**: the `settlements` route (`app.routes.ts`) never provided `salaryStructuresFeature`/`leaveBalancesFeature`/`gratuityRulesFeature` to its route-scoped NgRx state — a **pre-existing** gap (not introduced this session), latent until something actually exercised those selectors from this exact route in a way that surfaced it; adding `loansFeature` for this feature made it necessary to fix all four in one pass. Second bug, found via live E2E specifically: `settlement-detail.ts`'s first cut of the employee-separation dispatch used the generic `employeesFeature.actions.upsert(...)`, which routes through `PUT /api/employees/{id}` — 403 for an Accountant (not Admin/HR, not the record owner), *silently* (the write-error was never surfaced anywhere on this page). Fixed by adding the dedicated `/separate` endpoint instead of widening Accountant's general employee-write permission, which would have been a much larger, unwanted authorization change.
- Scope: `settlement-rules.ts`/`settlement-form.ts`/`settlement-detail.ts`/`settlements-page.ts`, `FinalSettlement`/`Payslip`(unchanged)/`Employee`(unchanged) models, `app.routes.ts`, backend `FinalSettlement` entity + new `SettlementService` + `FinalSettlementController` + `EmployeeController`'s new `/separate` + `SecurityConfig`. Payroll calculation rules, `applyLoanRecovery`, bonus, salary structure untouched.
- **Tests**: 6 new backend `FinalSettlementControllerIT` tests (create persists loan recovery + default payment-pending; duplicate-open-settlement 409; a rejected settlement frees the employee for a new one; completed settlement rejects both PUT and DELETE even for Admin; a pending settlement can still be completed with payment details; HR cannot decide a settlement), 3 new `EmployeeControllerIT` tests for `/separate` (Accountant can, HR cannot — 403, unknown id 404). 7 new frontend `settlement-rules.spec.ts` tests (`netSettlementAmount` with/without loan recovery, `outstandingLoanBalance` active-only filtering, `validatePaymentDetails`). Full suite: **121/121 backend** (was 118, +3), **237/237 frontend** (was 230, +7), `ng build` clean.
- **Live-verified against the real running backend and local PostgreSQL** (both servers restarted for the new schema/entities/routes/endpoint): gave a real employee (Jahangir Alam) an active loan (₹9,000 outstanding), initiated a fresh settlement for him through the real HR UI — confirmed "Outstanding loan recovery − ৳9,000" appeared automatically with zero manual entry, net settlement computed correctly (৳49,000). As Accountant, confirmed "Verify and complete" is blocked with real validation errors when payment date/reference are empty; filled both and completed — confirmed live: the loan's `outstandingBalance` dropped to 0 and `status` flipped to `closed`, the settlement's `paymentStatus`/`paymentDate`/`paymentReference` all persisted correctly. Separately completed a second real settlement (Sultana Razia, one of the seeded demo rows) and confirmed her `Employee.status` flipped to `separated` in real Postgres — the fix for the silent-403 bug, proven working end to end through the actual UI, not just the unit-level JUnit coverage. Confirmed immutability live: Accountant `PUT` and Admin `DELETE` against the now-completed settlement both `409`'d with the expected message. Confirmed duplicate prevention live: a direct `POST` for an employee who already has an open settlement `409`'d with the standard clean-conflict message. All test-only artifacts (the seeded loan, the extra Jahangir settlement row created only for this E2E pass) removed afterward — the two genuinely-completed demo settlements (Sultana, Kamrul) and the one rejected demo (Jahangir) were left in place as the requested realistic demonstration data. Both servers left running and healthy.
- **Remaining risk / follow-up**: Kamrul's demo settlement was completed via direct-API seeding before this pass's payment-tracking fields existed, so it shows `paymentStatus: 'pending'` despite being `completed` — a legitimate "predates this feature" artifact, left as-is rather than backfilled, and a fair illustration of why the payment fields are nullable/defaulted for old records. Not itself a defect.

### 2.10 Bonus duplicate prevention, Attendance uniqueness, Bonus/Loan/Overtime immutability (2026-09-01)
- **Root cause / audit** (prior turn, no code changed then): a final production audit live-reproduced a real double-payment path — `POST`ing two identical pending Festival bonuses for the same employee/date both succeeded (`bonus-rules.ts`'s duplicate check was frontend-only), and since `runPayroll` sums every approved bonus for the cycle, approving both would have silently double-paid. Separately: no DB constraint stopped two `attendance` rows for the same employee/date (frontend only guards the normal check-in path via `!today()`), and `BonusRecordController`/`LoanRecordController`/`OvertimeController` were all still plain CRUD — an approved bonus, a rejected loan, or a rejected overtime claim could be freely rewritten or deleted by any role with that module's normal write permission, with no equivalent of the immutability already shipped for PayrollBatch/Payslip/Payment/Settlement.
- **V25 migration**: `uq_bonus_record_open_employee_type_date` (partial unique index on `bonus_record(employee_id, type, payment_date) WHERE status IN ('pending','approved')`, same shape as V21/V24) and `uq_attendance_employee_date` (plain unique index — every attendance row for a given employee+date must be unique regardless of status, since no legitimate flow ever needs two).
- **New `BonusRecordService`**: locks **both** `approved` and `rejected` — Bonus, unlike Overtime, has no post-decision correction feature at all, so both terminal states are safe to finalize with no conflict.
- **New `LoanRecordService`**: locks **`rejected` only** — deliberately not `active` or `closed`. `payroll-engine.ts`'s `applyLoanRecovery` writes to `active` loans every payroll run (the entire recovery mechanism) and *legitimately reopens* a `closed` loan when a downward correction pushes `outstandingBalance` back above zero (its own documented behavior) — locking either would have broken an existing, tested feature. Verified live: the real active loan on file for e4 (already partially recovered across several earlier payroll runs this session) still accepts a normal recovery `PUT` after this fix.
- **New `OvertimeService`**: locks **`rejected` only** — deliberately not `approved`. `overtime-detail.ts`'s "Correct" action is shown regardless of status specifically so HR/Admin can fix an already-approved claim for exceptional cases (a missed check-out found after approval) — this is the exact feature a prior turn this session built and fixed a rerun-accumulation bug in. Locking `approved` would have silently broken it. Verified live: correcting an already-`approved` overtime record (hours 2→3) still succeeds after this fix.
- Every controller's `PUT`/`DELETE` now routes through its respective service; `POST` and `GET` untouched. `SecurityConfig` role gates untouched — the new checks are a layer underneath them, same as every prior immutability fix this session.
- Scope: three new services + their controllers, one migration. `payroll-engine.ts`, `applyLoanRecovery`, and every other calculation rule untouched, per instruction — confirmed by the two "deliberately still mutable" live checks above.
- **Tests**: new `BonusRecordControllerIT` (7 tests: create, duplicate-while-pending 409, duplicate-while-approved-also-blocks 409, a rejected bonus frees the employee for a new one on the same date, approved immutable to PUT/DELETE — proven against the Accountant token specifically, since Bonus PUT is deliberately Accountant-only with no Admin override, rejected immutable, pending can still be approved). 3 new `LoanRecordControllerIT` tests (rejected immutable to PUT/DELETE; active still recoverable-against; closed can still reopen). 3 new `OvertimeControllerIT` tests (an approved claim can still be corrected — regression-locks the preserved feature; a rejected claim cannot be updated or deleted). Full suite: **133/133 backend** (was 121, +12), **237/237 frontend** unaffected (no frontend files touched this pass), both builds clean.
- **Live-verified against the real running backend and local PostgreSQL** (server restarted for the new migration/services): reproduced the exact original bug shape and confirmed it's now closed — two identical pending Festival bonuses for e4 on the same date, second `POST` → **409**; approved the first, then both a further Accountant `PUT` and an Admin `DELETE` against it → **409** each, exact immutability message. Two attendance rows for e4 on the same real date → second `POST` → **409**. Loan: rejected a real test loan, confirmed Admin `PUT` against it → **409**; separately confirmed the real pre-existing active loan (partially recovered across earlier sessions) still accepts a normal recovery `PUT` — **200**, no regression. Overtime: rejected a real test claim, confirmed Admin `PUT` against it → **409**; separately approved a different real claim and successfully corrected it while still `approved` (hours 2→3) — **200**, confirming the preserved correction feature works exactly as before. All test-only bonus/loan/overtime/attendance rows removed afterward (via direct `psql` where the record was now correctly immutable through the API); the real loan's balance was restored to its pre-test value. Both servers left running and healthy.
- **Remaining risk**: leave-request date-overlap prevention is still frontend-only (flagged in the same audit, not part of this instruction's three items) — harder to close cheaply since it's a range-overlap, not an exact-match duplicate (would need a Postgres exclusion constraint, not a plain unique index). Left for a future pass.

### 2.11 Leave request date-overlap prevention (2026-09-01)
- **Root cause / audit** (flagged as a remaining risk in §2.10, not yet fixed): `leave-rules.ts`'s `validateLeaveRequest` overlap check ("a rejected request frees its dates again; pending and approved ones do not") was frontend-only — `LeaveRequestController` was plain CRUD. Confirmed the real consequence, not just a data-quality nit: `payroll-engine.ts` sums approved-Unpaid days across *every* matching request for the cycle, so two overlapping approved requests covering the same dates would double-count (or worse) those days in the unpaid-leave deduction — the same double-deduction shape as the Bonus/Payment/Settlement bugs already fixed this session, just not yet closed here.
- **Design decision**: a plain unique index (the tool used for Bonus/Attendance/Payment/Settlement) can't express "date ranges must not overlap" — it only catches exact-duplicate rows. Used a Postgres **GIST exclusion constraint** instead: `EXCLUDE USING gist (employee_id WITH =, daterange(start_date, end_date, '[]') WITH &&) WHERE (status <> 'rejected')`, requiring the `btree_gist` extension (needed to combine a plain-equality column with a range-overlap column in one GIST index — confirmed available and installable by the app's own DB role, no superuser needed). Inclusive-both-ends (`'[]'`) matches this app's own date semantics exactly (`leave-rules.ts`'s `countDays()` and the frontend clash check are both already inclusive of both endpoints). Scoped to `status <> 'rejected'` — a rejected request legitimately frees its dates for a new one, exactly mirroring the frontend rule; approving or rejecting an existing request never changes its own date range, so a legitimate decision on the same row can never conflict with itself.
- **`V26` migration** — the constraint above, applied against real production data with zero pre-existing overlaps to resolve (checked first, same as every prior migration this session). No entity/Java-side change needed at all: Hibernate's `ddl-auto: validate` only checks JPA-mapped columns, not arbitrary SQL constraints, so this is a pure DB-layer addition.
- **`ApiExceptionHandler`**: added one new branch translating Postgres's exclusion-constraint violation message ("conflicting key value violates exclusion constraint...", distinct wording from a plain unique violation) into a clean 409 with a leave-specific message ("These dates overlap an existing request for this employee.") — same pattern already used for foreign-key/unique/check-constraint violations.
- Scope: one migration, one exception-handler branch. `LeaveRequestController`, `leave-rules.ts`, approval/rejection behavior, and every payroll calculation rule untouched — the fix is a pure server-side safety net behind the frontend check that already existed, not a new validation path.
- **Tests**: fixed one pre-existing test (`LeaveRequestControllerIT.batchUpsertInsertsMultipleRows` was inserting two overlapping open requests for the same employee purely as incidental test data — now uses non-overlapping dates, since that incidental overlap would otherwise now correctly violate the new constraint). Added 6 new tests: overlapping open request rejected with the clean message; exact-same-dates also rejected; a rejected request frees its dates for a new overlapping one; overlapping dates for a *different* employee are never blocked; back-to-back non-overlapping dates are never blocked; approving an existing request never conflicts with itself. Full suite: **139/139 backend** (was 133, +6), **237/237 frontend** unaffected (no frontend files touched), both builds clean.
- **Live-verified against the real running backend and local PostgreSQL** (server restarted for the new migration): applied a real Unpaid leave request for Tanvir Ahmed (e4) via the API, then a second one sharing one day with it → **409**, exact clean message. HR rejected the first through the real API (freeing its dates), then — through the **real Leave apply UI**, logged in as Tanvir — submitted a new overlapping request for the same dates: succeeded, confirming the frontend's own check and the new backend safety net agree. Test rows deleted afterward; both servers left running and healthy.
- **Remaining risk**: none new from this fix. The broader "same class of bug" sweep from §2.10's audit is now fully closed across Bonus, Attendance, Payment, Settlement, and Leave — the systemic "frontend-only duplicate/overlap check" pattern found across this codebase has no other known instance left unaddressed.

### 2.9 Payroll backend state machine and paid-payroll immutability (2026-08-31)
- **Root cause / audit**: every payroll controller (`PayrollBatchController`/`PayslipController`/`PaymentController`) was pure CRUD — `PUT /{id}` did an existence check then `repository.save()`, nothing else. `SecurityConfig.java` correctly gated **who** (which role) could call PUT, but nothing gated **what transition** — a raw API call (not the UI, which already only ever sends legal transitions) could PUT `draft → paid` directly, or freely rewrite a `paid` batch/payslip/payment. `Payslip` confirmed to be a full point-in-time snapshot (no live FK into SalaryStructure/TaxRule/PfRule), which narrowed the immutability problem to exactly `PayrollBatch` + `Payslip`/`Payment` by `batchId`.
- **New**: `payroll/service/PayrollBatchService.java` — the one deliberate exception to this project's "dumb CRUD store" convention (documented in its own Javadoc as to why), sitting between `PayrollBatchController` and the repository:
  - Transition table: `draft→calculated`, `calculated→{pending-approval, draft}`, `pending-approval→{approved, draft}`, `approved→paid`, `paid→` (terminal) — matches `batch-detail.ts`/`payroll-rules.ts` exactly; rejection still lands on `draft` (kept, per instruction, not a separate `returned` status).
  - Field-tampering guard: `batchRef`/`month`/cycle dates/`requestedBy` can never change after creation on any PUT; `employeeCount`/`grossTotal`/`deductionTotal`/`netTotal`/`locked` may only change when the target status is `draft` or `calculated` (the two calculation boundaries) — any other transition (`→pending-approval`, `→approved`, `→paid`) that tries to also change money fields is rejected.
  - Paid immutability: once `status == 'paid'`, any further PUT or DELETE on that batch is rejected — **absolute, no role override, Admin included** (per instruction) — and the same guard is reused by `PayslipController`/`PaymentController` (via `assertBatchMutable(batchId)`) to reject PUT/DELETE on any payslip/payment belonging to a paid batch. POST (create) is intentionally left unguarded on Payslip/Payment — matches the existing `PaymentControllerIT` fixture pattern and the real create-then-mark-paid ordering `pay()` already uses.
  - Atomicity: `batch-detail.ts`'s `pay()` fires the Payment write and the batch's paid-status write as two independent, unordered HTTP requests — a real pre-existing race (not introduced here). Closed without touching the frontend: `approved → paid` now requires a `Payment` row for that batch to already exist (`PaymentRepository.existsByBatchId`, backed by V21's unique constraint), so a dropped/delayed payment write can never leave a batch marked paid with nothing behind it — worst case is a 409 the existing `writeError` banner already surfaces, retryable once the payment lands (self-healing, since `pay-${batch.id}` is a deterministic id). `update()`/`delete()` are `@Transactional`.
  - Attendance/Overtime paid-cycle locking explicitly **not** done in this pass, per instruction — flagged as a separate follow-up (would need `AttendanceController`/`OvertimeController` changes too); SalaryStructure/TaxRule/PfRule deliberately not locked at all (org-wide config for future cycles, and confirmed irrelevant to already-issued payslips since those are snapshots).
  - `PayrollBatchController`/`PayslipController`/`PaymentController` PUT/DELETE now delegate to the service; `SecurityConfig.java` untouched (role gates were already correct — this is a second, transition-level layer underneath them, not a replacement).
- **Tests**: extended `PayrollBatchControllerIT` (+8: direct `draft→paid` rejected, paid batch fully immutable to PUT/DELETE including Admin, money-field tamper on `pending-approval→approved` rejected, identity-field tamper rejected, `approved→paid` blocked until a payment exists, and a full legal lifecycle test with a genuine reject→re-run→resubmit→approve→pay loop folded in), `PayslipControllerIT`/`PaymentControllerIT` (+1 each: PUT/DELETE on a paid batch's payslip/payment rejected). Replaced the one now-obsolete test (`returnedPathPersistsRemarks`, which asserted an arbitrary `"returned"` string free-form persisted) with `rejectionResetsToDraftWithZeroedTotalsAndRemarks`, matching what the product actually does. Full suite: **112/112 backend** (was 104, +8 net after the one replacement), `ng test` **192/192** and `ng build` clean (untouched — no frontend files were changed). `mvnw clean package` clean.
- **Live-verified against the real running backend and local PostgreSQL** end to end via direct API calls (both dev servers restarted first, to load the new code): created a fresh draft batch, confirmed direct `draft→paid` and a money-tampered `pending-approval→approved` both **409**; ran the full legal path with a genuine rejection loop — `draft→calculated→pending-approval→(rejected back to)draft→calculated→pending-approval→approved`; confirmed `approved→paid` **409s** with "Cannot mark this batch paid before its payment record is recorded" until a real `Payment` row is created, then succeeds; confirmed the paid batch, its payment, and (by the same code path) any payslip are then **completely immutable** — PUT/DELETE all 409 "A paid payroll batch is immutable and cannot be changed", tested explicitly with the **Admin** token to confirm no supervisory override exists. All test rows (`e2e-batch-1` batch + payment) deleted directly from Postgres afterward (paid rows are now correctly unreachable through the API by design, so cleanup used a direct `psql` delete, not the app). Both servers left running afterward, healthy.
- **Remaining risk**: `runEngine()`'s payslip writes (N individual `PUT/{id}`-with-POST-fallback calls, one per employee) and the batch's own `draft→calculated` write are still separate, unordered HTTP requests — a crash mid-run could leave a `calculated` batch with a partial payslip set. Out of scope for this pass (user's "especially for payment and paid status" phrasing, and re-running the engine already regenerates payslips idempotently, unlike the payment case which is a one-shot side effect) — flagged for a future pass if this ever proves to matter in practice.

### 2.12 Plan/code reconciliation and the agreed next-steps order (2026-09-01)
- **Root cause**: a full re-read of this file against the actual code found §1.13, §2.3, §2.4, and §2.5 significantly stale — each described real, completed, live-tested work (real JWT auth wired end-to-end, every collection real-backed) as `⬜ Not done`. Root cause: several passes of real backend integration happened without a corresponding plan update at the time. Two of §2.4's `⬜` items (porting `overtime-rules.ts`/`payroll-engine.ts` to Java) were also wrong on principle, not just stale — they predate and directly contradict §2.5's "dumb CRUD store, business logic stays in Angular" decision, which every fix from §1.15 onward has depended on being true.
- **Fix**: corrected §1.13/§2.3/§2.4/§2.5 and the old "Suggested order of work" list in place (struck through / marked ✅ with pointers to where the real work actually lives), rather than deleted, so the drift stays on record instead of being silently erased. Verified precisely before writing anything: re-read `session.ts`'s sign-in path, `SecurityConfig`'s full `permitAll()` list, and confirmed `http-api.ts`'s `BACKED_COLLECTIONS` covers every key in `MOCK_DB` with none left over.
- **Standing instruction, effective now**: after every completed task from here on, this file gets updated in the same turn — actual result, tests, live-verification outcome, and current status. A task is never left showing `⬜ Not done`/stale once the work is actually done. This turn's own drift-audit is the reason the instruction exists, not a hypothetical.
- **Reviewed and explicitly deferred, not forgotten**: demo data, demo accounts, and demo credentials stay exactly as they are — the project is still in development, not deployed, so there is nothing to protect yet. Credential rotation/removal is recorded as a **future production-checklist item only** (do this before any real deployment, not before).
- **Agreed next steps, in priority order** (full reasoning below; nothing here implemented yet — recommendation only, per instruction):
  1. **Plan/documentation accuracy** — this entry is that fix. Ongoing per the standing instruction above, not a one-time task.
  2. ~~**Change Request end-to-end audit**~~ — ✅ done, see §2.13. Found and fixed the expected duplicate/immutability consistency gaps, plus one real security/data-integrity bug (unrestricted `fieldName` field-injection via direct API), closed on the frontend per the `*-rules.ts` convention.
  3. ~~**New-user real-JWT login test**~~ — ✅ done, see §2.14. Found and fixed two real bugs: a role-dropdown display bug on Users & Roles (Angular `[value]`-on-`<select>` timing issue, always showed "Admin"), and a genuine new account being unable to sign in at all (`session.ts` resolved the post-login employee from the frozen mock seed instead of the real backend, plus a missing CORS filter on Spring Security's own 401/403 responses). Also confirmed live that the mock fallback cannot bypass `SecurityConfig` — it produces a cosmetic signed-in UI only, with every real data call still correctly rejected.
  4. ~~**Auth fallback safety**~~ — ✅ done, see §2.15. Confirmed by code audit and a live re-verification (backend stopped, signed in locally, every real data call still 503'd): the mock fallback cannot bypass real JWT auth, `SecurityConfig`, role permissions, or protected API access. No issue found, nothing changed — kept exactly as-is per instruction.
  5. **CI for the existing test suites** — 139 backend + 237 frontend tests are strong, comprehensive coverage that currently only protects the project when someone remembers to run `mvnw test`/`ng test` by hand. Automating that is process, not product work, but it's the cheapest possible protection against regressing any of the fixes documented in this file.
  6. **A full real-payroll dry run** — the actual "are we production-ready" gate: one real (or realistic) full month, a real employee roster, the complete HR→Payroll→Accountant→Pay pipeline run once end to end as an operational rehearsal with real people reviewing the output — not another curl-driven correctness check (already done extensively across §1.15–§2.11), the first genuine *operational* one.
- **Explicitly not recommended**: porting `payroll-engine.ts`/`overtime-rules.ts`/any `*-rules.ts` file to Java, or any other architecture change. Every fix this session (isLate, unauthorized absence, proration, Settlement, Bonus/Loan/Overtime immutability, Leave overlap) was tractable specifically *because* business logic lives in one place, in Angular, and the backend stays a thin, auditable CRUD layer with a few deliberate service-layer exceptions for state-machine enforcement. Nothing found in this review constitutes "a real problem" with that architecture — the opposite, if anything.
- **Anything missing before real payroll use, beyond the six items above**: none found in this pass beyond what's already tracked — no new financial, security, or data-integrity gap surfaced. The credential-rotation checklist item (deferred per instruction) is the one thing that must happen before deployment, specifically not before.

### 2.13 Change Request end-to-end audit — duplicate prevention, immutability, and a real field-injection fix (2026-09-01)
- **Scope**: item #2 of §2.12's agreed order. Traced the full flow — submit → API → DB → approval/rejection → roles → duplicate requests → immutability → audit log → notifications → UI — and checked whether any frontend-only rule could be bypassed via direct API calls.
- **Finding 1 (consistency gap, same shape as Bonus/Attendance/Leave/Settlement)**: `validateChangeRequest()`'s duplicate-request check (`change-request-rules.ts`) was frontend-only — `change_request.field_name` had no unique constraint, so two open requests for the same employee+field could be created via a raw API call, bypassing the UI entirely.
  - **Fix**: `V27__change_request_duplicate_prevention.sql` — partial unique index `uq_change_request_open_employee_field` on `(employee_id, field_name) WHERE status IN ('pending','approved')`, mirroring the Bonus/Attendance pattern (exact-match duplicate, no date-range overlap involved, so no GIST exclusion constraint needed). Confirmed against real Postgres before adding it that zero existing rows would violate it.
- **Finding 2 (consistency gap)**: no terminal-state immutability lock — an `approved`/`rejected` request could still be `PUT`/`DELETE`d.
  - **Fix**: new `ChangeRequestService` (mirrors `BonusRecordService`) — `update()`/`delete()` throw a 409 (`ResponseStatusException(HttpStatus.CONFLICT, ...)`) once status is `approved` or `rejected` (both locked, unlike Overtime, since Change Request has no post-decision correction workflow). `ChangeRequestController`'s `PUT /{id}`, `PUT /batch`, and `DELETE /{id}` now delegate to it.
- **Finding 3 (real security/data-integrity bug, not just a consistency gap)**: `change-request-detail.ts`'s `approve()` applied `{...employee, [request.fieldName]: request.proposedValue}` with **no validation that `fieldName` is one of the 7 real editable fields**. Since `change_request.field_name` is an unconstrained `VARCHAR(100)`, a change request created directly against the API (bypassing the submission form's dropdown) could name *any* `Employee` property — confirmed live: created a request with `fieldName: "status"`, `proposedValue: "separated"` via raw `curl`, and it was accepted (`201`) by the backend exactly as a naive implementation would allow. If an HR/Admin approver — who only sees a plausible "current → proposed" diff — had clicked Approve, that field would have been silently overwritten, completely bypassing that field's own dedicated workflow (most notably Settlement's employee-separation flow, which also closes active loans).
  - **Fix decision**: deliberately *not* a backend CHECK constraint — enumerating the field whitelist in SQL would duplicate `EDITABLE_FIELDS`, a business rule that belongs in Angular per §2.5. Instead added `isApplicableToEmployeeRecord()` to `change-request-rules.ts` (pure function, `EDITABLE_FIELDS` minus `'other'`) and gated `approve()` on it: an unrecognized `fieldName` now shows an inline error ("... is not a recognized employee field — this request cannot be safely approved. Reject it instead.") and **blocks approval entirely**, rather than silently approving-but-skipping-the-field-write (judged more dangerous/confusing than forcing an explicit reject).
- **Tests**: new `ChangeRequestControllerIT.java` (8 tests: create persists, duplicate pending/approved rejected 409, rejected-frees-the-field, approved/rejected immutable to PUT+DELETE, pending-can-still-be-decided, Accountant forbidden from deciding). New frontend tests for `isApplicableToEmployeeRecord` in `change-request-rules.spec.ts` (3 tests: allows all 7 real fields minus `other`, excludes `other`, rejects out-of-whitelist fields like `status`/`shiftId`/`salaryGrade`/`overtimeEligible`).
  - Backend: **147/147 passing** (139 baseline + 8 new), `mvnw compile` clean.
  - Frontend: **240/240 passing** (237 baseline + 3 new), `tsc --noEmit` clean, `ng build` clean.
- **Live E2E verification** (real Postgres + real running backend, restarted to load `V27`/the new service): 
  - Duplicate open request for the same employee/field → `409` with the standard "A record with the same unique value already exists." body.
  - Approved request's `PUT` → `409` ("This change request has already been approved and cannot be changed."); its `DELETE` → `403` for HR (DELETE is Admin-only per `SecurityConfig`, unrelated to this fix, confirmed correct) and `409` for Admin.
  - **Centerpiece check**: created the `fieldName: "status"` exploit request via raw API (`201`, confirming the backend has no restriction, as designed), then logged into the real UI as HR (`nasrin.akter`) and clicked **Approve** on the real `/change-requests/:id` page — the new error banner appeared verbatim, the request stayed `pending`, and `GET /api/employees/e4` confirmed `status` was still `"active"` (not silently overwritten to `"separated"`). Exploit is closed end to end, not just at the unit-test level.
- **Cleanup**: all test change-request rows deleted (the approved one via direct `psql`, since its own immutability fix correctly blocks the API from doing it — expected, not a workaround for a bug). Confirmed `SELECT ... WHERE id LIKE 'test-cr%'` returns 0 rows. Backend (`:8080`) and frontend (`:4200`) both left running and healthy.
- **Architecture**: unchanged — no business logic moved to Java; the one real bug fix (Finding 3) is entirely in `change-request-rules.ts`/`change-request-detail.ts`, consistent with the `*-rules.ts` convention.
- **Status**: ✅ Done.

### 2.14 New-user real-JWT login test — found and fixed two real bugs (2026-09-01)
- **Scope**: item #3 of §2.12's agreed order. Created a user through the real "Users & Roles" UI, signed out, signed back in as that user, and confirmed the real backend JWT path (not the mock fallback) was used and the correct role/permissions applied — then checked that the mock fallback can't bypass `SecurityConfig`.
- **Bug 1 (found first, blocking nothing but wrong): Users & Roles role dropdown always showed "Admin"**. Live in the browser, `nasrin.akter`/`rakib.hasan`/`tanvir.ahmed` all displayed role **Admin** in the per-user `<select>`, while the real backend data (`GET /api/roles`, `GET /api/users`) was correct throughout (`nasrin.akter` → `r2`/HR, `rakib.hasan` → `r3`/Accountant). Confirmed via `read_page`'s accessibility tree that the DOM's own `<option value="r1"> (selected)` was wrong on every row, not a screenshot/rendering artifact.
  - **Root cause**: `users-page.ts`'s role `<select [value]="roleDraftFor(row)">` bound the selection on the parent `<select>` element itself, evaluated against a `@for` options list (`roles()`) that resolves asynchronously from the real backend. Angular applies a plain (non-`ngModel`) `[value]` binding to a native `<select>` before/independently of its `@for`-generated `<option>` children being (re)patched in the same pass — on the render where `roles()` first has data, the browser can't yet match the requested value against options that don't exist yet, silently falls back to selecting index 0 ("Admin", the first role), and Angular's own dirty-checking then never revisits the assignment because the JS-side value it's diffing against hasn't changed.
  - **Fix**: moved the selection onto each `<option>`'s own `[selected]="role.id === roleDraftFor(row)"` binding instead (removing the parent `[value]"` entirely) — the same robust per-option pattern the permission-matrix checkboxes on the same page already use, which has no such ordering dependency since each option's own binding runs after that option exists.
  - **Verified live**: after the fix, `read_page` confirmed all 5 real rows (farhana.islam→Admin, nasrin.akter→HR, rakib.hasan→Accountant, tanvir.ahmed→Employee, jahangir.alam→Employee) showed the correct `(selected)` option, matching the real backend exactly.
- **Bug 2 (the real blocker for this task): a genuinely new account couldn't sign in at all**. Created `fdfd.test` (Employee role) via the real UI against a real, previously-loginless employee (`fdfd`/`EMP-1030`) — `AppUserController` persisted it to the real `app_user` table immediately with a real BCrypt hash (confirmed via `psql`: `$2a$10$...`, 60 chars). Signing back in as `fdfd.test` correctly hit the real `POST /api/auth/login` (200) — but then failed client-side with **"This account is not fully configured."**
  - **Root cause**: `session.ts`'s `finalizeSignIn` (shared by both the real-backend and local-mock sign-in paths) resolved the employee via `MockApiService.peek('employees')` — a `structuredClone(MOCK_DB)` taken once at app load and never written to by any real backend call (`HybridApiService`'s overridden methods call `this.http.*` directly for backed collections, bypassing the inherited mock array entirely). Every demo account's employee id (`e1`, `e2`, `e4`, `e7`) happens to also exist in that frozen seed, so this had always silently "worked" by coincidence — but a real employee that only exists in Postgres (anything created after the app loaded) was invisible to it, so a login the real backend had just genuinely approved was rejected one step later by client code checking the wrong data source.
  - **Fix**: split the shared `finalizeSignIn` into `finalizeBackendSignIn` (real-login path) and the existing `signInLocally` (unchanged, still self-consistent against the frozen seed — the local fallback's whole premise). `finalizeBackendSignIn` now resolves the employee via a real `GET /api/employees/{id}` (`HybridApiService.get`, async) instead of the frozen peek. The token is set *before* that GET (it's itself an authenticated backend call) and cleared again if the employee lookup fails, so a failed sign-in never leaves a live bearer token attached to a session with no signed-in user.
  - **Bug 2b, found while fixing 2b**: after wiring the real GET, it still failed — with a **503**, not the expected 401 (no token yet on the very first attempt) or 200. Root cause: Spring Security's `authenticationEntryPoint`/`accessDeniedHandler` (`SecurityConfig.jsonEntryPoint`/`writeJsonError`) write the 401/403 response directly inside the security filter chain, which runs *before* the `DispatcherServlet` — so `WebConfig`'s `WebMvcConfigurer`-based CORS mapping (which only applies to requests that reach a controller) never ran, and the 401 response carried no `Access-Control-Allow-Origin` header at all. The browser therefore blocked the response from reaching JS as a CORS failure (surfaced as a generic network error) instead of a readable 401 — confirmed directly with `curl -i`: the unauthenticated request had no `Access-Control-Allow-Origin` header, an authenticated one did.
  - **Fix**: added a `CorsConfigurationSource` bean in `SecurityConfig` itself (same `app.cors.allowed-origins` property `WebConfig` already used) and wired `.cors(cors -> cors.configurationSource(...))` into the security filter chain, so Spring Security's own early `CorsFilter` adds the CORS headers before any authentication/authorization decision runs — covering every response, including ones the filter chain rejects before a controller is ever reached. `WebConfig`'s existing MVC-level mapping is untouched (still correct for requests that do reach a controller); this closes the one gap it couldn't cover.
- **Tests**: no new automated tests added — both fixes are exactly the kind of thing this session already tests live rather than with new unit suites (no other `*-page.ts` has a component spec, per existing convention — page bugs are verified through the real UI; the CORS fix has no meaningful unit-test shape, only an observable HTTP header). `mvnw compile`/`test` and `tsc --noEmit`/`ng test`/`ng build` all re-run clean after every change below.
  - Backend: **147/147 passing** (unchanged baseline — this task added no backend tests, only the CORS config fix), `mvnw compile` clean.
  - Frontend: **240/240 passing** (unchanged baseline), `tsc --noEmit` clean, `ng build` clean.
- **Live E2E verification** (real Postgres + real running backend, restarted twice to load the CORS fix and to test the fallback-isolation scenario below):
  - Role-dropdown fix: confirmed via `read_page` accessibility tree against the real backend's actual role assignments (see Bug 1 above).
  - New-user creation: created `fdfd.test` through the real "Users & Roles" modal (native `<select>`s driven via a dispatched `input`/`change` event rather than OS-level dropdown clicks, since a native select's popup isn't in-page-clickable by browser automation — the Angular reactive form still received and validated the values exactly as a real click would have) → confirmed the row landed in real Postgres `app_user` with a genuine BCrypt hash.
  - Real-JWT login: `read_network_requests` confirmed `POST /api/auth/login` → `200` (not a fallback), `GET /api/employees/e-...` → `200`, landing on the correct **Employee dashboard** with the correct restricted sidebar (Change Requests/Attendance/Leave/Overtime/Payslips/Loans & Bonuses only — no Employees/Organisation/Users & Roles/Payroll Batches). Confirmed role enforcement live: a `PUT /api/audit-logs/{id}` attempt (an incidental side effect of the sign-in audit flow) correctly returned `403` for this Employee-role account, matching `SecurityConfig`'s `hasAuthority(ADMIN)` rule for that route.
  - Mock-fallback isolation: stopped the real backend, signed in as a demo account (`nasrin.akter`) — `POST /api/auth/login` correctly failed (`503`, backend unreachable), `signInLocally()` correctly took over and produced a **cosmetic** signed-in HR session (dashboard rendered from the frozen mock seed's stale numbers). Every subsequent real data call in that state — `employees`, `attendance`, `leave-requests`, `change-requests`, `payslips`, `loans`, `notifications`, `audit-logs` — correctly returned `503` as well. Confirmed: the local fallback can display a plausible-looking signed-in UI when the backend is down, but it cannot read or write one byte of real data, and grants no bypass of `SecurityConfig` whatsoever. Restarted the backend afterward and confirmed `{"status":"UP"}`.
- **Cleanup**: deleted the test account (`DELETE /api/users/{id}` as Admin, `204`) and confirmed via `psql` that `app_user` has no `fdfd.test` row. The underlying employee record (`fdfd`/`EMP-1030`, pre-existing test data from earlier session work, not created by this task) was left untouched, since only the login account was ours to clean up. Signed back into the browser as `farhana.islam` (Admin) to leave the session in its normal state. Backend (`:8080`) and frontend (`:4200`) both left running and healthy.
- **Architecture**: unchanged — both fixes are corrections to existing wiring (a template binding bug, a stale-data-source bug, and a missing CORS filter), not new business logic or a redesign. No business logic moved to/from Angular or Java.
- **Noted, not touched**: the DB has several long-id "leftover" employees from earlier session work (e.g. duplicate-named `e-1787546658330 "Nasrin Akter"` alongside the real demo `e1`), and `fdfd`/`EMP-1030` used for this task's test account is one of them — pre-existing, out of scope for this task, not cleaned up here per the standing "don't touch things outside what was asked" instruction. Worth a cleanup pass if these are ever confusing to a future audit, but not itself a bug.
- **Status**: ✅ Done.

### 2.15 Auth fallback safety audit — no bypass found, confirmed live (2026-09-01)
- **Scope**: item #4 of §2.12's agreed order. Reviewed `session.ts` and the full authentication flow to confirm the local mock-login fallback (`signInLocally`, for demo accounts / when the real backend is unreachable) can never bypass real backend JWT authentication, `SecurityConfig`, role permissions, or protected API access. Reused §2.14's fallback-isolation test for the live re-verification, per instruction, rather than devising a new one.
- **Code audit** (no changes needed — every path already correct, partly *because* §2.14 just fixed the two adjacent bugs found there):
  - `signIn()` always tries the real backend first (`tryBackendLogin`); `signInLocally()` only runs when that fails (bad credentials or the backend unreachable) — confirmed unchanged since §2.14.
  - `signInLocally()` → `commitSignIn()` never touches `TokenStore` at all (this was true even before §2.14; §2.14's refactor moved the *only* `tokenStore.set()` call into the real-backend path, `finalizeBackendSignIn()`, making this even more explicit). A locally-authenticated session therefore never has a real token to attach to anything.
  - `auth-interceptor.ts` attaches `Authorization: Bearer <token>` only when `TokenStore.token()` returns non-null, and `TokenStore.isExpired()` treats "no token" as "not expired, not applicable" (by design, per its own doc comment) rather than as a green light — confirmed there is no state where "no real token" reads as "valid token" anywhere in the chain.
  - `HybridApiService`'s backed-collection methods (`list`/`get`/`create`/`update`/`putMany`/`remove`) call `this.http.*` directly for every real endpoint and never fall back to `MockApiService`'s in-memory data on a real HTTP failure — a rejected real call surfaces as a real error, it is never silently swapped for fake success.
  - `SecurityConfig`'s `.anyRequest().authenticated()` catches anything not explicitly listed, so there is no unlisted endpoint left open by omission; role checks (`hasAuthority`/`hasAnyAuthority`) run entirely server-side regardless of what the frontend's local session state claims.
  - `authGuard`/`roleGuard` (`auth-guard.ts`) are confirmed client-UX-only — they gate Angular *routing* on `session.isAuthenticated()`/`session.role()`, local signals that route to which page renders, not to what data can be fetched or written; the real boundary is exclusively server-side, as above.
  - Conclusion: there is no path, including a tampered/crafted local session, by which the mock fallback grants real API access `SecurityConfig` would otherwise deny. This matches §2.12's original "expected result" for this item — now verified rather than assumed.
- **Live E2E re-verification** (reused §2.14's method, real Postgres + real backend, restarted before and after): stopped the real backend, signed in via the UI as a demo HR account (`nasrin.akter`) with the backend down — `POST /api/auth/login` failed as expected, `signInLocally()` took over and produced a cosmetic signed-in HR session. Every real data page visited afterward (dashboard, then Organisation — `departments`/`designations`/`shifts`/`holidays`/`employees`/`companies`) correctly returned **503** for every call; nothing rendered but empty/zeroed state. Restarted the backend and confirmed `{"status":"UP"}` again.
- **Fallback kept as-is, per instruction**: no redesign or removal — demo accounts still need it during development, and the audit found no reason to touch it.
- **Tests**: none added — this was a verification-only task (code audit + reused live test), and no real issue was found to fix. Backend/frontend suites unchanged from §2.14 (147/147 backend, 240/240 frontend) since no source files were modified this task.
- **Cleanup**: none needed — no test data was created (pure read-only audit and a login/logout cycle with the backend intentionally stopped and restarted). Backend (`:8080`) and frontend (`:4200`) both left running and healthy.
- **Status**: ✅ Done — mock fallback confirmed safe, no bypass found, nothing changed.

### 2.16 Employee self-registration + Admin/HR approval workflow (2026-09-01/02)
- **Scope**: a new architecture item, agreed after an audit-first pass (see the
  chat record for the full audit and recommendation) covering four proposed
  changes. Only item 1 — employee self-registration — was approved for
  implementation this task. The other three were explicitly declined or
  deferred: **not done, and not recommended without a specific reason** —
  splitting every component into `.ts`/`.html`/`.css` (contradicts this
  project's own `CLAUDE.md` convention, "Prefer inline templates for small
  components", and touches every feature folder for a stylistic gain with no
  correctness payoff); converting `application.yml` to
  `application.properties` (no functional benefit, and the current file's
  `---`-separated dev/prod profile documents would need splitting into
  separate files — real regression surface for zero gain, recommended
  against). Add Employee, Create User and the new Registration Request stay
  three clearly separate flows, as instructed — none of the other two were
  touched.
- **Workflow implemented**: Employee → "Register from login" (public,
  unauthenticated) → `RegistrationRequest` row, `status: pending` → Admin/HR
  review queue → Approve (creates the real `Employee` + `AppUser` by reusing
  the *exact* existing "Add employee"/"Create user" NgRx actions and REST
  endpoints, then records the decision) or Reject (reason required, nothing
  else created) → an approved account can sign in immediately with the
  temporary password shown to the reviewer, exactly like a manually
  Admin-created account already works.
- **Backend** (new package `registration`, migration `V28`):
  - `V28__registration_requests.sql` — new `registration_request` table
    (personal fields only — no password, no department/designation/shift/
    salary grade; those are Admin/HR's call at approval time). Two partial
    unique indexes (`lower(desired_username)`/`lower(email)` `WHERE status =
    'pending'`) — same "DB-level duplicate prevention, not just a
    frontend/service check" principle as `V25`–`V27`; a rejected request
    frees both fields for a fresh attempt, only `pending` is exclusive.
  - `RegistrationRequest` entity/repository/`RegistrationRequestController`:
    `POST /api/auth/register` (public, `permitAll()` in `SecurityConfig`,
    same narrow treatment as `/api/auth/login`) can only ever insert a
    `pending` row — never touches `employee` or `app_user`. Validates
    duplicates server-side (username/email against both `app_user` and any
    other pending request; national ID against `employee`) before insert,
    writes an `AuditLog` row directly (the one write in the backend with no
    authenticated session to record it through `AuditLogService` the normal
    way) and a `Notification` row for every Admin/HR `AppUser`. `GET`/`PUT
    /api/registration-requests/**` are Admin/HR-only (`SecurityConfig`, same
    "isolated collection, no cross-module risk" reasoning already used for
    `/api/users/**`); `PUT` only succeeds while `status = 'pending'` (409
    otherwise) — a decision can be recorded exactly once. No `POST` endpoint
    exists on this collection at all; a row can only ever be created through
    the separate public register endpoint.
  - `AppUserRepository`/`EmployeeRepository` gained `existsByUsernameIgnoreCase`
    / `findByRole_NameIn` / `existsByEmailIgnoreCase` / `existsByNationalId` —
    small additive finder methods, no behavior change to any existing caller.
  - **No business logic moved and no new logic invented for
    provisioning**: approval is entirely frontend-orchestrated — it dispatches
    `employeesFeature.actions.create` (the same action `employee-form.ts`'s
    "Add employee" already dispatches, status set straight to `active` — the
    same field change `employee-detail.ts`'s own "Activate" button already
    makes, just done in the one create call instead of two round trips) then
    `usersFeature.actions.create` (the same action `user-form.ts`'s "Create
    user" already dispatches, generating a fresh temporary password the same
    way). `SecurityConfig` keeps `POST /api/users` Admin-only exactly as it
    already was, so **only Admin can complete an approval end to end** — HR
    can review the queue and reject, but not approve (`canApproveRegistration`
    in `registration-rules.ts`), matching the existing Users & Roles
    restriction rather than inventing a new one.
- **Frontend** (new `features/registration/` folder, one `.ts` file per
  concern — same convention every other module already follows,
  `leave-page.ts`/`leave-rules.ts`/`leave-rules.spec.ts` etc. — inline
  templates kept, per the declined proposal #3 above):
  - `register-page.ts` — the public form (`/register`, `guestGuard`, linked
    from `login-page.ts`'s new "Request an account" link). No password field;
    posts to the new `AuthApiService.register()`.
  - `registration-review-page.ts` + `registration-review-form.ts` — the
    Admin/HR queue (`/registration-requests`, new `module-registry.ts` entry,
    Admin/HR only). The review form collects only the organisation-assignment
    fields a registrant never provides (department/designation/shift/salary
    grade/employment type/joining date/system role); approving chains three
    dispatches (create employee → create user → record decision on the
    request) via `Actions`/`ofType`/`take(1)`, the same wait-for-the-real-
    result pattern `change-requests-page.ts` already uses — a failure at any
    step shows a specific error banner and stops the chain rather than
    half-provisioning silently.
  - `registration-rules.ts` + `registration-rules.spec.ts` (3 new tests) —
    `canReviewRegistrations`/`canApproveRegistration`, the Admin-only-approval
    rule above.
  - New `RegistrationRequest` model (`core/models/hr.ts`), new
    `registrationRequestsFeature` (`core/store/features.ts`, `create` action
    declared but deliberately never dispatched — the backend has no `POST`
    for this collection), new `AuthApiService.register()`, new
    `/registration-requests` route (`app.routes.ts`), new empty
    `REGISTRATION_REQUESTS` seed array (`mock-db/seed/governance.ts` — a
    real-backend-only module launched after the mock phase, nothing to carry
    over).
- **Tests**: 8 new backend `RegistrationRequestControllerIT` tests (public
  submit → pending; duplicate username/email while pending rejected;
  national ID already on an employee rejected; list/update Admin/HR-only;
  submit writes the audit entry and notifies every Admin/HR user; full
  approve flow reusing the real Employee/User endpoints, then the new
  account actually logs in; a second decision on the same request is
  refused; reject stores the reason and creates nothing) — backend suite now
  **155/155 passing** (was 147). 3 new `registration-rules.spec.ts`
  tests — frontend suite now **243/243 passing** (was 240). `npx tsc --noEmit`,
  `ng build` both clean.
- **Live E2E verification**, real Postgres + real backend + real browser (no
  test data left behind, confirmed via `psql`):
  1. Submitted a real registration from `/register` in the browser — `psql`/
     API confirmed a genuine `pending` row, no `employee`/`app_user` row
     created.
  2. Signed in as the real `farhana.islam` (Admin) demo account, opened the
     new "Registration Requests" sidebar item, approved the pending request
     through `registration-review-form.ts` with real department/designation/
     shift data — got back "Account … created … Temporary password:
     Welcome@6036"; dashboard's "Recent activity" showed both the
     (backend-written) "Submitted registration request" and the
     (frontend-written) "Approved registration request" audit entries.
     `curl POST /api/auth/login` with the issued username/temp password
     succeeded, `role: "Employee"` — the approved-then-created account can
     actually sign in.
  3. Submitted a second registration, rejected it from the same queue with a
     reason — request moved to `rejected` with the reason stored, and a login
     attempt for that username correctly returned `401` (no account was ever
     created).
  4. Cleaned up every row created by this verification (`app_user`,
     `employee`, both `registration_request` rows, the `audit_log`/
     `notification` rows this feature wrote) via `psql`, confirmed `0` rows
     remaining for all of them. The four permanent demo accounts and all
     other pre-existing data were untouched throughout. Backend (`:8080`) and
     frontend (`:4200`) both left running and healthy afterward.
- **Architecture**: no business logic moved between Angular and Java — the
  backend stays a thin, auditable CRUD layer (the one exception, writing an
  `AuditLog`/`Notification` row directly from the public register endpoint,
  is a side effect with no authenticated session to route it through the
  normal frontend `AuditLogService` path, not a business rule). Demo
  accounts/data untouched.
- **Status**: ✅ Done — self-registration + approval workflow live, tested,
  and verified against the real backend. CI setup (§2.12 item 5) was
  explicitly out of scope for this task and remains the next queued item.

### 2.17 Frontend architecture migration — inline template → `.ts`/`.html` split, Step 1: Audit Log (2026-09-02)
- **New initiative, agreed 2026-09-02**: gradually move Angular feature
  components off single-file inline `template:` strings onto a
  `component.ts` + `component.html` (+ `.css` only when a component already
  has a genuine `styles:` block) structure, for learning/maintainability —
  explicitly **not** the pattern this codebase's own `CLAUDE.md` defaults to
  ("Prefer inline templates for small components"), but an explicit,
  deliberate choice for this project going forward, done one module at a
  time rather than all at once. Tailwind utility classes stay exactly where
  they are — as `class="..."` attributes in the new `.html` files — only a
  component's own custom CSS (rare; 4 files project-wide have one) ever
  earns a `.css` file.
- **Audit-first, before any file was touched**: surveyed every feature
  folder plus `core/`, `shared/`, `layout/` and the four root app files
  (`app.ts`, `app.config.ts`, `app.routes.ts`, `app.spec.ts`) by actual
  cross-module dependency, not file size — which modules other modules link
  into or read state from (`DirectoryService`, `PEOPLE_STATE`, `routerLink`s)
  versus which are genuine dependency leaves. Recommended order: safest/most
  isolated modules first (Audit Log, Notifications, Registration, Users &
  Roles, Reports), then master-data and self-contained business modules,
  then the highest-dependency modules last (Employees — most other detail
  pages link into it; Payroll — the engine trigger; Dashboard and the Auth
  login page — highest visibility/consequence-of-failure, every role's
  first screen or entry point). `layout/`+`shared/ui/*` deferred to their own
  later phase, since they're imported by every page in the app. Root files
  reviewed separately and left alone: `app.ts`'s template is a single line
  (nothing to extract), `app.config.ts`/`app.routes.ts` have no template at
  all, and `app.spec.ts` has an unrelated pre-existing test-organization
  smell (three unrelated suites in one file) that's independent of this
  migration and was explicitly deferred, not bundled in.
- **Step 1 scope, approved**: `features/audit/audit-page.ts` only — the
  single safest module in the whole app (Admin-only, purely read-only, zero
  cross-module dependents, single file, no `styles:` block to worry about).
- **Change**: extracted the 51-line inline `template:` string verbatim into
  a new sibling `audit-page.html`; `audit-page.ts`'s `@Component` decorator
  now has `templateUrl: './audit-page.html'` in place of `template:` —
  nothing else in the file touched (imports, `columns` config, computed
  signals, constructor dispatch all byte-for-byte unchanged). No `.css` file
  created — confirmed via grep that `audit-page.ts` never had a `styles:`
  block. `notification-page.ts` and every other file were not touched.
- **Verification**: `npx tsc --noEmit` clean, `ng build` clean, `ng test`
  **243/243 passing** (unchanged from before — a pure template-location
  change touches no logic, so no test could regress). Live-verified in a
  real browser against the real backend and real Postgres: signed in as the
  real `farhana.islam` (Admin) demo account, opened `/audit` — KPI tiles
  (Events 419, Payroll events 50, Unread notifications 12, Notifications
  sent 12), the searchable audit table (419 real rows, badges, the
  outcome-colored Action column) and the Notifications list all rendered
  identically to before the extraction, zero visual or behavioral
  difference. No test data created, so no cleanup needed; backend (`:8080`)
  and frontend (`:4200`) both left running and healthy.
- **Status**: ✅ Done — Step 1 of the frontend architecture migration.
  Notifications is next (per the agreed order), not started yet.

### 2.18 Frontend architecture migration, Step 2: Notifications (2026-09-02)
- **Scope**: `features/notifications/notification-page.ts` only, per the
  agreed order from §2.17 — the second-safest module (single file, all four
  roles, exactly one small write action — "mark read"/"mark all read" —
  otherwise read-only, zero cross-module dependents).
- **Change**: extracted the inline `template:` string verbatim into a new
  sibling `notification-page.html`; `@Component`'s `templateUrl:
  './notification-page.html'` replaces `template:`. Confirmed via grep
  beforehand that `notification-page.ts` has no `styles:` block — no `.css`
  file created. No other line in the file touched: `TYPE_ICON`, the
  `rows`/`unread` computed signals, `markRead`/`markAllRead`, and the
  constructor's `load()` dispatch are all byte-for-byte unchanged.
- **Verification**: `npx tsc --noEmit` clean, `ng build` clean, `ng test`
  **243/243 passing** (unchanged — no logic touched). Live-verified in a
  real browser against the real backend/Postgres: signed in as the real
  `nasrin.akter` (HR) demo account, opened `/notifications` — inbox rendered
  identically to before the extraction (5 unread, icons per notification
  type, timestamps). Exercised the one write path this page has: clicked
  "Mark read" on a single row (unread count 5→4, row's button and highlight
  correctly disappeared), then "Mark all as read" (unread count →0, button
  itself disappeared since `unread().length` is now 0). Confirmed via
  `curl GET /api/notifications` with a real HR token that all 5 of
  `nasrin.akter`'s rows are now `"read":true` in the real Postgres row, the
  other 7 real rows belonging to other users untouched.
- **Note on data touched**: unlike every other verification pass in this
  file, this one's real backend mutation is **not reverted** — the 5 rows
  marked read were genuine pre-existing notifications (mostly leftover E2E
  payroll-return alerts from earlier session work), and marking them read is
  exactly what the feature is for, not test data created for this task. No
  demo account, credential, or business record was touched; only a
  notification's own `read` flag changed, for the account that was signed in
  to read it. Backend (`:8080`) and frontend (`:4200`) both left running and
  healthy.
- **Status**: ✅ Done — Step 2 of the frontend architecture migration.
  Registration is next (per the agreed order), not started yet.

### 2.19 Frontend architecture migration, Step 3: Registration (2026-09-02)
- **Scope**: the Registration feature only, per the agreed order from
  §2.17. Inspected the folder first: 5 files total, only 3 are `@Component`s
  with an inline template (`register-page.ts`, `registration-review-form.ts`,
  `registration-review-page.ts`); `registration-rules.ts` and
  `registration-rules.spec.ts` are pure functions/tests with no template —
  confirmed via grep and left completely untouched. Grepped all three
  component files for `styles:` beforehand — none exist, so no `.css` file
  was created for any of them (empty stub files avoided, as instructed).
- **Change**: same mechanical extraction as §2.17/§2.18, done three times —
  each component's inline `template:` string moved verbatim into a new
  sibling `.html` file, `templateUrl` substituted in the decorator. Nothing
  else touched in any of the three files: `describeError()`, the reactive
  form groups, `RegistrationApproval`'s shape, the `Actions`/`ofType`/
  `take(1)` approve/reject chains, `canApproveRegistration` gating, and every
  constructor dispatch are byte-for-byte unchanged.
  - `register-page.ts` → `register-page.html`
  - `registration-review-form.ts` → `registration-review-form.html`
  - `registration-review-page.ts` → `registration-review-page.html`
- **Verification**: `npx tsc --noEmit` clean, `ng build` clean, `ng test`
  **243/243 passing** (unchanged — no logic touched). Live-verified the full
  workflow in a real browser against the real backend/Postgres, exactly
  reproducing §2.16's original end-to-end test: submitted a new registration
  from `/register` (renders and submits identically post-extraction), signed
  in as the real `farhana.islam` (Admin) demo account, opened
  `/registration-requests`, clicked "Review & approve" — the extracted
  `registration-review-form.html` modal opened with live department/
  designation/shift/role data exactly as before, approved it, got back
  "Account … created … Temporary password: Welcome@9503", and confirmed via
  `curl POST /api/auth/login` that the new account signs in
  (`role: "Employee"`). Zero visual or behavioral difference from pre-
  extraction (§2.16's) verification.
- **Cleanup**: this pass created real test rows (unlike §2.18's), so they
  were deleted afterward — `app_user`, `employee`, `registration_request`,
  the `audit_log` entry and `notification` rows this feature wrote — all
  confirmed removed via `psql`. No demo account, credential, or pre-existing
  data touched. Backend (`:8080`) and frontend (`:4200`) both left running
  and healthy.
- **Status**: ✅ Done — Step 3 of the frontend architecture migration.
  Users & Roles is next (per the agreed order), not started yet.

### 2.20 Frontend architecture migration, Step 4: Users & Roles (2026-09-02)
- **Scope**: `features/users/users-page.ts` only, exactly as instructed —
  `user-form.ts` (the "Create user" modal, same folder) was explicitly left
  untouched this step, not bundled in.
- **First genuine `.css` case in this migration**: `users-page.ts` is one of
  only 4 files project-wide with a real `styles:` block (confirmed by grep
  in §2.17's original audit) — two tiny row-action link styles (`.rowBtn`,
  `.rowBtnDanger`) used by "Save"/"Reset password"/"Enable"/"Disable".
- **Change**: extracted the inline `template:` string verbatim into a new
  sibling `users-page.html`, and the `styles:` block verbatim into a new
  sibling `users-page.css` (character-for-character — no rule renamed,
  reordered, or restated). `@Component`'s `template`/`styles` keys replaced
  with `templateUrl: './users-page.html'` and `styleUrl: './users-page.css'`.
  All Tailwind utility classes stayed in the `.html` as `class="..."`
  attributes, per the standing rule — only the two hand-written CSS rules
  moved to the `.css` file. Nothing else touched: `USER_TONE`, `tempPassword()`,
  every computed signal, and all nine methods
  (`saveRole`/`saveDescription`/`togglePermission`/`onCreate`/`setStatus`/
  `resetPassword`/etc.) are byte-for-byte unchanged.
- **Verification**: `npx tsc --noEmit` clean, `ng build` clean — the
  `users-page` lazy chunk's size was unchanged (17.14 kB) before and after,
  confirming the CSS was correctly bundled in rather than silently dropped.
  `ng test` **243/243 passing** (unchanged). Live-verified in a real browser
  against the real backend/Postgres, signed in as the real `farhana.islam`
  (Admin) demo account:
  - Visual check: zoomed on the "Reset password"/"Disable" links — rendered
    in the exact original brand-teal/bad-red, 12px/500-weight styling,
    confirming the extracted CSS applies identically.
  - Exercised the real write path: changed a non-demo test account's
    (`jahangir.alam`) role Employee→HR via the page's "Save" link, confirmed
    via `curl GET /api/users` that `roleId` actually changed to `r2` in real
    Postgres, then changed it back to `r4` and confirmed via `curl` that it
    was restored — the one demo/pre-existing account touched during this
    verification ended the pass in its original state.
  - Opened "Create user" — the modal (`user-form.ts`, untouched this step)
    still composes correctly inside the new `.html`, listing all real
    employees and roles exactly as before; closed via Cancel without
    creating anything.
- **Status**: ✅ Done — Step 4 of the frontend architecture migration.
  Reports is next (per the agreed order), not started yet.

### 2.21 Frontend architecture migration, Step 5: Reports (2026-09-02)
- **Scope**: `features/reports/reports-page.ts` only, per the agreed order —
  big file (645 lines with all six report sections: headcount, payroll
  cycles, leave/overtime approval rates, audit activity, tax report, PF
  report) but Admin-only and purely read/aggregate, writes nothing, nothing
  else depends on it.
- **Found already done on inspection**: the `.ts`/`.html` split itself was
  already present in the working tree — `reports-page.ts`'s `@Component`
  already had `templateUrl: './reports-page.html'` (no `template:` string
  left, no `styles:` block, so no `.css` needed), and `reports-page.html`
  (123 lines) already held the extracted markup verbatim. No component code
  was changed this pass — the extraction had happened in an unlogged pass,
  same class of plan/code drift already called out and corrected once before
  in §2.12. Logged here now so the file matches reality, per the standing
  instruction.
- **Bug fix applied**: the previously-flagged pre-existing bug — `app.routes.ts`'s
  `reports` route was missing `payslipsFeature`/`pfRulesFeature` from its
  `providers` array, so `reports-page.ts`'s Tax report and PF report sections
  (which `selectSignal` both features) had no route-provided state to read
  and would throw on navigation. Fix already present in the working tree too:
  the route's `providers` array now includes
  `...provideCollection(payslipsFeature)` and
  `...provideCollection(pfRulesFeature)` alongside the pre-existing
  `PEOPLE_STATE`/`payrollBatchesFeature`/`leaveRequestsFeature`/
  `overtimeFeature`/`auditLogsFeature`, with an inline comment recording the
  bug and its cause. Nothing else in `app.routes.ts` touched.
- **Verification, this pass**: `npx tsc --noEmit` clean. `ng build` clean —
  `reports-page` lazy chunk builds at 12.57 kB. `ng test` **243/243 passing**
  (unchanged — no logic touched, template-location and route-providers
  changes don't affect any spec). No browser-automation tool is available in
  this environment, so live-verification used the same
  compile-and-drive-the-real-backend approach as every other entry in this
  file that hit the same constraint: signed in for real via
  `POST /api/auth/login` as the real `farhana.islam` (Admin) demo account
  (real BCrypt+JWT, `200`, real `accessToken`), then called every endpoint
  the Reports route's providers load, with that token, against the real
  running backend/Postgres — all eight returned `200` with real rows:
  `employees` (25), `departments` (7), `payroll-batches` (7),
  `leave-requests` (2), `overtime` (0), `audit-logs` (426), `payslips` (68),
  `pf-rules` (1). The two collections the bug fix added
  (`payslips`/`pf-rules`) both returned real, non-empty data — confirming
  the Tax report and PF report sections now have real state to render
  instead of throwing. This confirms the full data contract and the
  route-provider fix at the HTTP/auth level; it does not confirm pixel-level
  rendering, matching the documented limitation of every prior entry that
  hit the same tooling gap.
- **Cleanup**: none needed — read-only verification only, no data created or
  modified. Backend (`:8080`) and frontend (`:4200`) both left running and
  healthy.
- **Status**: ✅ Done — Step 5 of the frontend architecture migration.
  Profile is next (per the agreed order), not started yet. CI and any other
  migration step were explicitly out of scope for this task and remain
  queued.

### 2.22 Frontend architecture migration, Step 6: Profile (2026-09-02)
- **Scope**: `features/profile/profile-page.ts` only, per the agreed order —
  single file, every role reaches it for their own record only (photo,
  contact details, password — no cross-employee reach), no other module
  links into it.
- **Change**: extracted the inline `template:` string verbatim into a new
  sibling `profile-page.html`; `@Component`'s `templateUrl:
  './profile-page.html'` replaces `template:`. Confirmed via reading the
  full file beforehand that `profile-page.ts` has no `styles:` block — no
  `.css` file created. No other line touched: `MAX_PHOTO_BYTES`,
  `onPhotoSelected`, `readOnlyFields`/`contactFields`, the
  `contactForm`/`passwordForm` reactive forms and every method
  (`startEditContact`/`saveContact`/`changePassword`/etc.) are byte-for-byte
  unchanged. No logic, routing, or backend change of any kind.
- **Verification**: `npx tsc --noEmit` clean. `ng build` clean — new
  `profile-page` lazy chunk builds at 12.14 kB (confirms the HTML was
  bundled in, not silently dropped). `ng test` **243/243 passing**
  (unchanged — a pure template-location change touches no logic). No
  browser-automation tool is available in this environment, so live
  verification used the same real-login-plus-real-endpoint approach as
  §2.21: signed in for real via `POST /api/auth/login` as the real
  `tanvir.ahmed` (Employee) demo account (real BCrypt+JWT, `200`, real
  `accessToken`), then called every endpoint the Profile route's providers
  load with that token against the real running backend/Postgres —
  `employees`/`departments`/`designations`/`shifts` all returned `200`, and
  `GET /api/employees/e4` resolved the real Tanvir Ahmed record
  (`DEMO-EMPLOYEE`, dept/designation/shift ids present) — the exact record
  the page's `employee()` computed would render Photo/Profile/Contact
  details from. Confirms the data contract at the HTTP/auth level; does not
  confirm pixel-level rendering, matching the documented limitation of every
  prior entry that hit the same tooling gap.
- **Cleanup**: none needed — read-only verification only, no data created or
  modified. Backend (`:8080`) and frontend (`:4200`) both left running and
  healthy.
- **Status**: ✅ Done — Step 6 of the frontend architecture migration. Per
  the agreed order (Organisation, Salary & Rules master data next), not
  started yet. CI and any other migration step were explicitly out of scope
  for this task and remain queued.

### 2.23 Frontend architecture migration, Step 7: Organisation (2026-09-02)
- **Scope**: `features/organisation/` — `organisation-page.ts` plus its four
  modal forms (`department-form.ts`, `designation-form.ts`, `shift-form.ts`,
  `holiday-form.ts`), per the agreed order (master-data, Admin-only; other
  forms read this data but a template-only change here doesn't touch that
  contract).
- **Inspected first, per instruction**: all five files still had a real
  inline `template:` string — none had already been extracted. Confirmed
  `organisation-page.ts` was one of the four files project-wide with a
  genuine `styles:` block (the `.addBtn`/`.rowBtn`/`.rowBtnDanger` rules,
  first flagged in §2.20's Users & Roles entry) — the second real
  `.css`-extraction case in this migration. The four form components had no
  `styles:` block.
- **Change**: extracted each inline `template:` string verbatim into a
  sibling `.html` file (`organisation-page.html` 297 lines,
  `department-form.html`, `designation-form.html`, `shift-form.html`,
  `holiday-form.html`), and `organisation-page.ts`'s `styles:` block verbatim
  into a new sibling `organisation-page.css` (character-for-character — no
  rule renamed, reordered, or restated). Each `@Component` decorator's
  `template`/`styles` keys replaced with `templateUrl`/(`styleUrl` on the
  page only). All Tailwind utility classes stayed in the `.html` files as
  `class="..."` attributes; only the three hand-written CSS rules moved.
  Nothing else touched in any of the five files: `canManage`, the
  `tab`/`deptForm`/`desigForm`/`shiftFormSig`/`holidayForm` signals, every
  `save*`/`remove*` method, the company-draft logic
  (`companyDraftFor`/`onCompanyInput`/`companyDirty`/`saveCompany`), the four
  forms' reactive `FormBuilder` groups, `effect()`-based prefill (the
  `existing()` signal-input timing fix from §1.3, left completely
  untouched), and every validator/submit method are all byte-for-byte
  unchanged. No logic, routing, API, or backend change of any kind.
- **Verification**: `npx tsc --noEmit` clean. `ng build` clean —
  `organisation-page` lazy chunk unchanged at 29.06 kB before and after
  (confirms the CSS was correctly bundled in, not silently dropped — same
  check §2.20 used for Users & Roles). `ng test` **243/243 passing**
  (unchanged — a pure template-location change touches no logic). No
  browser-automation tool is available in this environment, so live
  verification used the same real-login-plus-real-endpoint approach as
  §2.21/§2.22: signed in for real via `POST /api/auth/login` as the real
  `farhana.islam` (Admin) demo account (real BCrypt+JWT, `200`, real
  `accessToken`), then called every endpoint the Organisation route's
  providers load with that token against the real running
  backend/Postgres — `departments` (7), `designations` (8), `shifts` (4),
  `holidays` (3), `employees` (25), `companies` (1) all returned `200` with
  real rows, confirming the data contract every tab (Departments/
  Designations/Shifts/Holidays/Company) and all four modal forms render
  against is unaffected. Confirms the data contract at the HTTP/auth level;
  does not confirm pixel-level rendering, matching the documented limitation
  of every prior entry that hit the same tooling gap.
- **Cleanup**: none needed — read-only verification only, no data created or
  modified. Backend (`:8080`) and frontend (`:4200`) both left running and
  healthy.
- **Status**: ✅ Done — Step 7 of the frontend architecture migration. Salary
  & Rules is next (per the agreed order), not started yet. CI and any other
  migration step were explicitly out of scope for this task and remain
  queued.

### 2.24 Frontend architecture migration, Step 8: Salary & Rules (2026-09-02)
- **Scope**: `features/salary-rules/` — `salary-rules-page.ts` plus its
  three modal forms (`salary-structure-form.ts`, `tax-rule-form.ts`,
  `pf-rule-form.ts`), per the agreed order (master-data, Admin-only, same
  shape as Organisation).
- **Inspected first, per instruction**: all four files still had a real
  inline `template:` string — none had already been extracted. Confirmed
  `salary-rules-page.ts` had the same real `styles:` block pattern as
  Organisation (`.addBtn`/`.rowBtn`/`.rowBtnDanger`, byte-identical rules —
  the third real `.css`-extraction case in this migration). The three form
  components had no `styles:` block. Noted but not touched, out of scope for
  a pure extraction: `salary-structure-form.ts`, `tax-rule-form.ts` and
  `pf-rule-form.ts` all read `existing()` directly in the constructor rather
  than inside `effect()` — the same signal-input-timing class of bug fixed
  on Organisation's four forms back in §1.3, still present here. Not fixed
  in this pass since the task was extraction-only with no logic change;
  worth a dedicated bug-fix pass later if edit-prefill on these three forms
  is ever reported broken live.
- **Change**: extracted each inline `template:` string verbatim into a
  sibling `.html` file (`salary-rules-page.html`, `salary-structure-
  form.html`, `tax-rule-form.html`, `pf-rule-form.html`), and
  `salary-rules-page.ts`'s `styles:` block verbatim into a new sibling
  `salary-rules-page.css`. Each `@Component` decorator's `template`/`styles`
  keys replaced with `templateUrl`/(`styleUrl` on the page only). Tailwind
  utility classes stayed in the `.html` files as `class="..."` attributes;
  only the three hand-written CSS rules moved. Nothing else touched: `tab`/
  `structureForm`/`taxForm`/`pfForm` signals, every `save*`/`remove*`
  method, `totalGross`/`pfLabel` computed signals, the three forms' reactive
  `FormBuilder` groups and their (unchanged, not-yet-`effect()`-wrapped)
  constructors, and every validator/submit method are all byte-for-byte
  unchanged. No logic, routing, API, or backend change of any kind.
- **Verification**: `npx tsc --noEmit` clean. `ng build` clean —
  `salary-rules-page` lazy chunk unchanged at 24.45 kB before and after
  (confirms the CSS was correctly bundled in, not silently dropped). `ng
  test` **243/243 passing** (unchanged — a pure template-location change
  touches no logic). No browser-automation tool is available in this
  environment, so live verification used the same real-login-plus-real-
  endpoint approach as §2.21–§2.23: signed in for real via `POST
  /api/auth/login` as the real `farhana.islam` (Admin) demo account (real
  BCrypt+JWT, `200`, real `accessToken`), then called every endpoint the
  Salary & Rules route's providers load with that token against the real
  running backend/Postgres — `salary-structures` (10), `tax-rules` (5),
  `pf-rules` (1), `employees` (25), `departments` (7), `designations` (8)
  all returned `200` with real rows, confirming the data contract every tab
  (Salary structures/Tax slabs/Provident fund) and all three modal forms
  render against is unaffected. Confirms the data contract at the HTTP/auth
  level; does not confirm pixel-level rendering, matching the documented
  limitation of every prior entry that hit the same tooling gap.
- **Cleanup**: none needed — read-only verification only, no data created or
  modified. Backend (`:8080`) and frontend (`:4200`) both left running and
  healthy.
- **Status**: ✅ Done — Step 8 of the frontend architecture migration.
  Overtime is next (per the agreed order, self-contained business modules),
  not started yet. CI and any other migration step were explicitly out of
  scope for this task and remain queued.

### 2.25 Frontend architecture migration, Step 9: Overtime (2026-09-02)
- **Scope**: `features/overtime/` — `overtime-page.ts` (list + approval
  queue), `overtime-detail.ts` (decision + correction trigger), and
  `overtime-correction-form.ts` (the correction modal), per the agreed order
  (first self-contained business module in this migration).
- **Inspected first, per instruction**: all three files had a real inline
  `template:` string — none had already been extracted. None had a
  `styles:` block, so no `.css` file was needed for any of the three.
  Checked specifically for the signal-input-timing class of bug (§1.3/
  §2.24's note on Salary & Rules): `overtime-correction-form.ts`'s
  `record`/`employeeLabel` are required inputs, and its constructor already
  reads them correctly inside `effect()` (with a doc comment explicitly
  citing `attendance-correction-form.ts`/`employee-form.ts` as the same
  fix) — **not present here**, nothing to note or fix.
  `overtime-detail.ts`'s `id` input is only ever read inside `computed()`
  (`claim`), never in the constructor, so the same class of bug doesn't
  apply there either.
- **Change**: extracted each inline `template:` string verbatim into a
  sibling `.html` file (`overtime-page.html`, `overtime-detail.html`,
  `overtime-correction-form.html`); each `@Component`'s `template:` key
  replaced with `templateUrl:`. No `.css` files created. Nothing else
  touched in any of the three files: `columns`/`rows`/`pending`/`rejected`/
  `eligibleHours`/`eligibleAmount` on the page, `claim`/`fields`/
  `sourceAttendance`/`scheduledHours`/`committed`/`headroom`/`canDecide`/
  `canCorrect` and the `approve`/`reject`/`saveCorrection`/`log` methods on
  the detail page, and the correction form's reactive `FormBuilder` group,
  `effect()`-based prefill, and `updateAmount`/`submit` methods are all
  byte-for-byte unchanged. No logic, routing, API, or backend change of any
  kind.
- **Verification**: `npx tsc --noEmit` clean. `ng build` clean —
  `overtime-detail` (13.87 kB) and `overtime-page` (5.21 kB) lazy chunks
  both unchanged from their pre-extraction sizes. `ng test` **243/243
  passing** (unchanged — a pure template-location change touches no logic).
  No browser-automation tool is available in this environment, so live
  verification used the same real-login-plus-real-endpoint approach as
  §2.21–§2.24: signed in for real via `POST /api/auth/login` as the real
  `nasrin.akter` (HR) demo account (real BCrypt+JWT, `200`, real
  `accessToken`), then called every endpoint the Overtime routes' providers
  load with that token against the real running backend/Postgres —
  `overtime` (0 rows — this database currently has none, exercising the
  page's own empty-state path rather than a data bug), `employees` (25),
  `departments` (7), `designations` (8), `attendance` (11), `shifts` (4) all
  returned `200`, confirming the data contract both pages and the correction
  form render against is unaffected. Confirms the data contract at the
  HTTP/auth level; does not confirm pixel-level rendering, matching the
  documented limitation of every prior entry that hit the same tooling gap.
- **Cleanup**: none needed — read-only verification only, no data created or
  modified. Backend (`:8080`) and frontend (`:4200`) both left running and
  healthy.
- **Status**: ✅ Done — Step 9 of the frontend architecture migration.
  Change Requests is next (per the agreed order), not started yet. CI and
  any other migration step were explicitly out of scope for this task and
  remain queued.

### 2.26 Frontend architecture migration, Step 10: Change Requests (2026-09-02)
- **Scope**: `features/change-requests/` — `change-requests-page.ts` (list +
  submission trigger + approval queue), `change-request-detail.ts`
  (decision), and `change-request-form.ts` (the "Propose a change" modal),
  per the agreed order.
- **Inspected first, per instruction**: all three files had a real inline
  `template:` string — none had already been extracted. None had a
  `styles:` block, so no `.css` file was needed for any of the three.
  Checked for the signal-input-timing class of bug per the standing
  instruction to note it only if encountered: **not present in any of the
  three**. `change-request-detail.ts`'s `id` input is only ever read inside
  `computed()` (`request`), never in the constructor. `change-request-
  form.ts`'s four required inputs (`employeeId`/`employee`/`existing`/
  `requesterRole`) are likewise only ever read inside `computed()`
  (`draft`/`currentValue`/`approverLabel`) or via the `toSignal`-derived
  `value`, never in the constructor — this component in fact has no
  constructor at all. Nothing to note or fix.
- **Change**: extracted each inline `template:` string verbatim into a
  sibling `.html` file (`change-requests-page.html`, `change-request-
  detail.html`, `change-request-form.html`); each `@Component`'s
  `template:` key replaced with `templateUrl:`. No `.css` files created.
  Nothing else touched in any of the three files: `isManager`/`rows`/
  `pending`/`approved`/`rejected`/`decidableQueue` computed signals and
  `onSubmitted`'s wait-for-real-result pattern on the list page; `request`/
  `canDecide`/`fields` computed signals and the `approve`/`reject`/`log`
  methods on the detail page (including the `isApplicableToEmployeeRecord`
  field-injection guard from §2.13, left completely untouched); and the
  form's reactive `FormBuilder` group, `toSignal`-derived `value`, and
  `draft`/`errors`/`submit` logic are all byte-for-byte unchanged. No logic,
  routing, API, or backend change of any kind.
- **Verification**: `npx tsc --noEmit` clean. `ng build` clean —
  `change-requests-page` (11.24 kB) and `change-request-detail` (6.91 kB)
  lazy chunks both build correctly. `ng test` **243/243 passing** (unchanged
  — a pure template-location change touches no logic). No browser-
  automation tool is available in this environment, so live verification
  used the same real-login-plus-real-endpoint approach as §2.21–§2.25:
  signed in for real via `POST /api/auth/login` as the real `nasrin.akter`
  (HR) demo account (real BCrypt+JWT, `200`, real `accessToken`), then
  called every endpoint the Change Requests route's providers load with
  that token against the real running backend/Postgres —
  `change-requests` (4), `employees` (25), `departments` (7),
  `designations` (8) all returned `200` with real rows, confirming the data
  contract the list, approval queue, detail decision panel and submission
  form all render against is unaffected. Confirms the data contract at the
  HTTP/auth level; does not confirm pixel-level rendering, matching the
  documented limitation of every prior entry that hit the same tooling gap.
- **Cleanup**: none needed — read-only verification only, no data created or
  modified. Backend (`:8080`) and frontend (`:4200`) both left running and
  healthy.
- **Status**: ✅ Done — Step 10 of the frontend architecture migration.
  Loans & Bonuses is next (per the agreed order), not started yet. CI and
  any other migration step were explicitly out of scope for this task and
  remain queued.

### 2.27 Frontend architecture migration, Step 11: Loans & Bonuses (2026-09-02)
- **Scope**: `features/loans-bonuses/` — `loans-bonuses-page.ts` (list +
  both submission triggers), `loan-form.ts`, `loan-detail.ts`, `bonus-
  form.ts`, `bonus-detail.ts`, per the agreed order.
- **Inspected first, per instruction**: all five files had a real inline
  `template:` string — none had already been extracted. None had a
  `styles:` block, so no `.css` file was needed for any of the five.
  Checked for the signal-input-timing class of bug per the standing
  instruction to note it only if encountered: **not present in any of the
  five**. `loan-detail.ts`/`bonus-detail.ts`'s `id` inputs are only ever
  read inside `computed()` (`loan`/`bonus`), never in a constructor.
  `loan-form.ts`/`bonus-form.ts`'s required inputs
  (`employeeId`/`employees`/`existing`/`canChooseEmployee`/`requestedBy`)
  are read in `ngOnInit()`, not the constructor — inputs are already bound
  by the time `ngOnInit` runs, so this is the correct timing and not an
  instance of the bug (unlike the organisation/salary-rules forms fixed in
  §1.3, which read `existing()` inside the constructor itself).
- **Change**: extracted each inline `template:` string verbatim into a
  sibling `.html` file (`loans-bonuses-page.html`, `loan-form.html`,
  `loan-detail.html`, `bonus-form.html`, `bonus-detail.html`); each
  `@Component`'s `template:` key replaced with `templateUrl:`. No `.css`
  files created. Nothing else touched in any of the five files: `isSelfService`/
  `canRaiseLoan`/`canRaiseBonus`/`loans`/`bonuses`/`activeLoans`/
  `pendingLoans`/`pendingBonuses`/`outstanding` computed signals and the
  `onLoanSubmitted`/`onBonusSubmitted` methods on the list page; both forms'
  reactive `FormBuilder` groups, `ngOnInit`, `toSignal`-derived `value`, and
  `draft`/`errors`/`submit` logic; both detail pages' `canDecide`/`fields`
  computed signals and `approve`/`reject`/`log` methods (including the
  Accountant-only bonus-decision gate and self-approval block from §2.8/
  §1.14) are all byte-for-byte unchanged. No logic, routing, API, or backend
  change of any kind.
- **Verification**: `npx tsc --noEmit` clean. `ng build` clean —
  `loans-bonuses-page` lazy chunk unchanged at 17.37 kB, `loan-detail`
  (6.61 kB) and `bonus-detail` (6.34 kB) chunks both build correctly. `ng
  test` **243/243 passing** (unchanged — a pure template-location change
  touches no logic). No browser-automation tool is available in this
  environment, so live verification used the same real-login-plus-real-
  endpoint approach as §2.21–§2.26: signed in for real via `POST
  /api/auth/login` as the real `nasrin.akter` (HR) demo account (real
  BCrypt+JWT, `200`, real `accessToken`), then called every endpoint the
  Loans & Bonuses route's providers load with that token against the real
  running backend/Postgres — `loans` (6), `bonuses` (8), `employees` (25),
  `departments` (7), `designations` (8) all returned `200` with real rows,
  confirming the data contract the list, both submission forms and both
  decision detail pages render against is unaffected. Confirms the data
  contract at the HTTP/auth level; does not confirm pixel-level rendering,
  matching the documented limitation of every prior entry that hit the same
  tooling gap.
- **Cleanup**: none needed — read-only verification only, no data created or
  modified. Backend (`:8080`) and frontend (`:4200`) both left running and
  healthy.
- **Status**: ✅ Done — Step 11 of the frontend architecture migration.
  Settlements is next (per the agreed order), not started yet. CI and any
  other migration step were explicitly out of scope for this task and
  remain queued.

### 2.28 Frontend architecture migration, Step 12: Settlements (2026-09-02)
- **Scope**: `features/settlements/` — `settlements-page.ts` (list +
  submission trigger + gratuity-rule panel), `settlement-detail.ts`
  (decision + payment capture), and `settlement-form.ts` (the "Initiate a
  settlement" modal, with its live gratuity/leave-encashment calculation
  breakdown from §1.8), per the agreed order.
- **Inspected first, per instruction**: all three files had a real inline
  `template:` string — none had already been extracted. None had a
  `styles:` block, so no `.css` file was needed for any of the three.
  Checked for the signal-input-timing class of bug per the standing
  instruction to note it only if encountered: **not present in any of the
  three**. `settlement-detail.ts`'s `id` input is only ever read inside
  `computed()` (`settlement`), never in the constructor. `settlement-
  form.ts`'s required inputs (`employeeId`/`employees`/`structures`/
  `leaveBalances`/`loans`/`existing`) are read in `ngOnInit()` (matching
  §2.27's loan-form/bonus-form precedent) or inside `computed()`, never in
  the constructor — correct timing, not an instance of the bug.
- **Change**: extracted each inline `template:` string verbatim into a
  sibling `.html` file (`settlements-page.html`, `settlement-detail.html`,
  `settlement-form.html`); each `@Component`'s `template:` key replaced
  with `templateUrl:`. No `.css` files created. Nothing else touched in any
  of the three files: `canInitiate`/`canDecide`/`rows`/`pending`/
  `gratuity`/`netTotal` computed signals and the `onSubmitted`/`saveRule`
  methods on the list page; `settlement`/`canDecide`/`fields`/
  `paymentErrors` computed signals and the `approve`/`reject`/`log` methods
  on the detail page (including the loan-closure-on-settlement and
  employee-separation `PATCH .../separate` logic from §1.8/§1.18, left
  completely untouched); and the form's reactive `FormBuilder` group,
  `ngOnInit`, `toSignal`-derived `value`, and every calculation computed
  (`tenureMonths`/`gratuity`/`leaveEncashment`/`loanRecovery`/`net`) are all
  byte-for-byte unchanged. No logic, routing, API, or backend change of any
  kind.
- **Verification**: `npx tsc --noEmit` clean. `ng build` clean —
  `settlements-page` lazy chunk unchanged at 17.64 kB, `settlement-detail`
  (9.74 kB) chunk builds correctly. `ng test` **243/243 passing** (unchanged
  — a pure template-location change touches no logic). No browser-
  automation tool is available in this environment, so live verification
  used the same real-login-plus-real-endpoint approach as §2.21–§2.27:
  signed in for real via `POST /api/auth/login` as the real `rakib.hasan`
  (Accountant) demo account (real BCrypt+JWT, `200`, real `accessToken`),
  then called every endpoint the Settlements route's providers load with
  that token against the real running backend/Postgres — `settlements` (3),
  `employees` (25), `salary-structures` (10), `leave-balances` (16),
  `loans` (6), `gratuity-rules` (1), `departments` (7), `designations` (8)
  all returned `200` with real rows, confirming the data contract the list,
  the gratuity-rule panel, the decision detail page, and the live-calculated
  submission form all render against is unaffected. Confirms the data
  contract at the HTTP/auth level; does not confirm pixel-level rendering,
  matching the documented limitation of every prior entry that hit the same
  tooling gap.
- **Cleanup**: none needed — read-only verification only, no data created or
  modified. Backend (`:8080`) and frontend (`:4200`) both left running and
  healthy.
- **Status**: ✅ Done — Step 12 of the frontend architecture migration.
  Attendance is next (per the agreed order), not started yet. CI and any
  other migration step were explicitly out of scope for this task and
  remain queued.

### 2.29 Frontend architecture migration, Step 13: Attendance (2026-09-02)
- **Scope**: `features/attendance/` — `attendance-page.ts` (check-in/out,
  daily register, monthly summary) and `attendance-correction-form.ts` (the
  correction modal), per the agreed order.
- **Inspected first, per instruction**: both files had a real inline
  `template:` string — neither had already been extracted. Confirmed
  `attendance-page.ts` had a real `styles:` block (`.rowBtn`, the fourth and
  last of the project's originally-flagged 4 real-CSS files, alongside
  Users & Roles/Organisation/Salary & Rules — all now migrated).
  `attendance-correction-form.ts` had no `styles:` block. Checked for the
  signal-input-timing class of bug per the standing instruction to note it
  only if encountered: **not present** — `attendance-correction-form.ts`'s
  `record`/`employeeLabel` required inputs are already read correctly
  inside `effect()`, exactly like `overtime-correction-form.ts` (§2.25).
- **Change**: extracted `attendance-page.ts`'s inline `template:` string
  verbatim into a new sibling `attendance-page.html`, and its `styles:`
  block verbatim into a new sibling `attendance-page.css`. Extracted
  `attendance-correction-form.ts`'s inline `template:` string verbatim into
  a new sibling `attendance-correction-form.html`. Each `@Component`'s
  `template`/`styles` keys replaced with `templateUrl`/(`styleUrl` on the
  page only). All Tailwind utility classes stayed in the `.html` files;
  only the one hand-written `.rowBtn` rule moved. Nothing else touched:
  `canManage`/`ownRecordsOnly`/`rows`/`today`/`present`/`late`/`absent`/
  `earlyLeave`/`totalHours`/`totalOvertimeHours`/`availableMonths`/
  `summaryRows` computed signals, `checkIn`/`checkOut`/
  `syncOvertimeForToday` (the auto-overtime-calculation logic from §1.4),
  `openCorrection`/`saveCorrection`/`describeCorrection` on the page; the
  correction form's reactive `FormBuilder` group, `effect()`-based prefill,
  and `submit`/`workedHoursOf` logic — all byte-for-byte unchanged. No
  logic, routing, API, or backend change of any kind.
- **Verification**: `npx tsc --noEmit` clean. `ng build` clean —
  `attendance-page` lazy chunk unchanged at 18.67 kB before and after
  (confirms the CSS was correctly bundled in, not silently dropped — same
  check used for every prior `styles:`-block migration in this series).
  `ng test` **243/243 passing** (unchanged — a pure template-location
  change touches no logic). No browser-automation tool is available in this
  environment, so live verification used the same real-login-plus-real-
  endpoint approach as §2.21–§2.28: signed in for real via `POST
  /api/auth/login` as the real `nasrin.akter` (HR) demo account (real
  BCrypt+JWT, `200`, real `accessToken`), then called every endpoint the
  Attendance route's providers load with that token against the real
  running backend/Postgres — `attendance` (11), `employees` (25),
  `departments` (7), `designations` (8), `salary-structures` (10),
  `overtime` (0 — this database currently has none, per §2.25), `shifts`
  (4) all returned `200`, confirming the data contract the Today card,
  daily register, monthly summary and correction form all render against is
  unaffected. Confirms the data contract at the HTTP/auth level; does not
  confirm pixel-level rendering, matching the documented limitation of
  every prior entry that hit the same tooling gap.
- **Cleanup**: none needed — read-only verification only, no data created or
  modified. Backend (`:8080`) and frontend (`:4200`) both left running and
  healthy.
- **Status**: ✅ Done — Step 13 of the frontend architecture migration.
  Payslips is next (per the agreed order), not started yet. CI and any
  other migration step were explicitly out of scope for this task and
  remain queued.

### 2.30 Frontend architecture migration, Step 14: Payslips (2026-09-02)
- **Scope**: `features/payslips/` — `payslip-list.ts` and
  `payslip-detail.ts` (including the real client-side PDF download from
  §1.6/§1.14), per the agreed order.
- **Inspected first, per instruction**: both files had a real inline
  `template:` string — neither had already been extracted. Neither had a
  `styles:` block, so no `.css` file was needed for either. Checked for the
  signal-input-timing class of bug per the standing instruction to note it
  only if encountered: **not present** — `payslip-detail.ts`'s `id` input
  is only ever read inside `computed()` (`rawSlip`), never in the
  constructor.
- **Change**: extracted each inline `template:` string verbatim into a
  sibling `.html` file (`payslip-list.html`, `payslip-detail.html`); each
  `@Component`'s `template:` key replaced with `templateUrl:`. No `.css`
  files created. Nothing else touched in either file: `isSelfService`/
  `rows`/`grossTotal`/`deductionTotal`/`netTotal`/`batchRef` on the list
  page (including the `isPayslipVisibleToViewer` gate shared with the
  detail page); `slip`/`notYetPaid`/`batchLabel`/`cycle` computed signals
  and the `download()` method's real PDF-line construction
  (`buildSimplePdf`/`moneyPlain`/`downloadBytes`) on the detail page are all
  byte-for-byte unchanged. No logic, routing, API, or backend change of any
  kind.
- **Verification**: `npx tsc --noEmit` clean. `ng build` clean —
  `payslip-detail` (8.76 kB) and `payslip-list` (3.43 kB) lazy chunks both
  build correctly. `ng test` **243/243 passing** (unchanged — a pure
  template-location change touches no logic). No browser-automation tool is
  available in this environment, so live verification used the same
  real-login-plus-real-endpoint approach as §2.21–§2.29: signed in for real
  via `POST /api/auth/login` as the real `rakib.hasan` (Accountant) demo
  account (real BCrypt+JWT, `200`, real `accessToken`), then called every
  endpoint the Payslips route's providers load with that token against the
  real running backend/Postgres — `payslips` (68), `payroll-batches` (7),
  `employees` (25), `departments` (7), `designations` (8), `companies` (1)
  all returned `200` with real rows, confirming the data contract both the
  list and the detail/PDF-download page render against is unaffected.
  Confirms the data contract at the HTTP/auth level; does not confirm
  pixel-level rendering or exercise the PDF download itself, matching the
  documented limitation of every prior entry that hit the same tooling gap.
- **Cleanup**: none needed — read-only verification only, no data created or
  modified. Backend (`:8080`) and frontend (`:4200`) both left running and
  healthy.
- **Status**: ✅ Done — Step 14 of the frontend architecture migration.
  Leave is next (per the agreed order), not started yet. CI and any other
  migration step were explicitly out of scope for this task and remain
  queued.

### 2.31 Frontend architecture migration, Step 15: Leave (2026-09-02)
- **Scope**: `features/leave/` — `leave-page.ts` (list + submission trigger
  + approval queue + Leave Rules panel + balances table), `leave-detail.ts`
  (decision + balance-impact preview), and `leave-form.ts` (the "Apply for
  leave" modal), per the agreed order. This is the project's own
  "reference module" (§1.4) — the first full submission+approval loop ever
  built — but per §2.17's dependency-first ordering it's mid-list, not
  first, since dependency risk (not "reference module" status) is the
  ordering criterion.
- **Inspected first, per instruction**: all three files had a real inline
  `template:` string — none had already been extracted. None had a
  `styles:` block, so no `.css` file was needed for any of the three.
  Checked for the signal-input-timing class of bug per the standing
  instruction to note it only if encountered: **not present in any of the
  three**. `leave-detail.ts`'s `id` input is only ever read inside
  `computed()` (`request`), never in the constructor. `leave-form.ts`'s
  required inputs (`employeeId`/`requesterRole`/`balances`/`rules`/
  `existing`) are read only inside `computed()` (`draft`/`approverLabel`/
  etc.) or via the `toSignal`-derived `value`, never in the constructor —
  this component has no constructor at all, same shape as
  `change-request-form.ts` (§2.26).
- **Change**: extracted each inline `template:` string verbatim into a
  sibling `.html` file (`leave-page.html`, `leave-detail.html`,
  `leave-form.html`); each `@Component`'s `template:` key replaced with
  `templateUrl:`. No `.css` files created. Nothing else touched in any of
  the three files: `canApprove`/`isSelfService`/`rows`/`balances`/
  `pending`/`approved`/`rejected`/`totalDays`/`decidableQueue` computed
  signals, `ruleDraftFor`/`onRuleInput`/`saveRule` and `onSubmitted`'s
  wait-for-real-result plus first-time-balance-seeding logic (§1.4) on the
  list page; `request`/`canDecide`/`balance`/`fields` computed signals and
  the `approve`/`reject`/`log` methods on the detail page (including the
  `applyApproval`/`reverseApproval` balance-movement calls, left completely
  untouched); and the form's reactive `FormBuilder` group, `toSignal`-
  derived `value`, and `draft`/`days`/`balanceAfter`/`errors`/`submit`
  logic are all byte-for-byte unchanged. No logic, routing, API, or backend
  change of any kind.
- **Verification**: `npx tsc --noEmit` clean. `ng build` clean —
  `leave-page` lazy chunk unchanged at 16.68 kB, `leave-detail` (7.42 kB)
  chunk builds correctly. `ng test` **243/243 passing** (unchanged — a pure
  template-location change touches no logic). No browser-automation tool is
  available in this environment, so live verification used the same
  real-login-plus-real-endpoint approach as §2.21–§2.30: signed in for real
  via `POST /api/auth/login` as the real `nasrin.akter` (HR) demo account
  (real BCrypt+JWT, `200`, real `accessToken`), then called every endpoint
  the Leave route's providers load with that token against the real
  running backend/Postgres — `leave-requests` (2), `leave-balances` (16),
  `leave-rules` (4), `employees` (25), `departments` (7), `designations`
  (8) all returned `200` with real rows, confirming the data contract the
  list, approval queue, Leave Rules panel, balances table, decision detail
  page and submission form all render against is unaffected. Confirms the
  data contract at the HTTP/auth level; does not confirm pixel-level
  rendering, matching the documented limitation of every prior entry that
  hit the same tooling gap.
- **Cleanup**: none needed — read-only verification only, no data created or
  modified. Backend (`:8080`) and frontend (`:4200`) both left running and
  healthy.
- **Status**: ✅ Done — Step 15 of the frontend architecture migration.
  Employees is next (per the agreed order — the highest-dependency
  business module, per §2.17's audit), not started yet. CI and any other
  migration step were explicitly out of scope for this task and remain
  queued.

### 2.32 Frontend architecture migration, Step 16: Employees (2026-09-02)
- **Scope**: `features/employees/` — `employee-list.ts`, `employee-form.ts`
  (shared Add/Edit modal), and `employee-detail.ts` (608 lines, the
  project's single biggest component — Profile, Salary structure, Leave
  balances, plus the seven Related Records sections from §1.10: Attendance,
  Leave, Overtime, Payslips, Loans, Bonuses, Final settlement). Per §2.17's
  dependency-first ordering, done second-to-last — the module most other
  pages link into.
- **Dependency check, done before touching anything, per this task's
  explicit instruction**:
  - **Route providers**: `app.routes.ts`'s `employees` route already
    provides `PEOPLE_STATE` (employees/departments/designations) plus
    `shiftsFeature`/`salaryStructuresFeature`/`leaveBalancesFeature`/
    `attendanceFeature`/`leaveRequestsFeature`/`overtimeFeature`/
    `payslipsFeature`/`loansFeature`/`bonusesFeature`/`settlementsFeature`
    — every collection `employee-detail.ts`'s Related Records sections read,
    confirmed by cross-checking the provider list against every
    `store.selectSignal` call in the component. No missing-provider gap
    like §2.21's Reports finding — nothing to fix here.
  - **Linked navigation**: confirmed six other modules link into
    `/employees/:id` — `payslip-detail.html`, `settlement-detail.ts`,
    `bonus-detail.ts`, `loan-detail.ts`, `change-request-detail.ts`, and
    `shared/ui/field-list.ts`'s generic `link` support (§1.10). None of
    these link targets change — the route path (`/employees/:id`) and the
    component's public selector are untouched by a template-only
    extraction, so every existing cross-module link stays valid.
  - **Employee list/detail routes themselves**: `path: ''` →
    `EmployeeListPage`, `path: ':id'` → `EmployeeDetailPage`, both
    unaffected — only their `loadComponent` target's internal
    `template`/`templateUrl` changes, never the route configuration.
- **Inspected next**: all three files had a real inline `template:` string
  — none had already been extracted. None had a `styles:` block, so no
  `.css` file was needed for any of the three. Checked for the
  signal-input-timing class of bug: **not present** —
  `employee-detail.ts`'s `id` input is only ever read inside `computed()`
  (`employee`), never in the constructor; `employee-form.ts`'s `existing`/
  `departments`/`designations`/`shifts` are all correctly read inside
  `effect()` (with a doc comment explicitly citing the signal-input-timing
  fix pattern), matching the fix already applied project-wide since §1.3.
- **Change**: extracted each inline `template:` string verbatim into a
  sibling `.html` file (`employee-list.html`, `employee-form.html`,
  `employee-detail.html`); each `@Component`'s `template:` key replaced
  with `templateUrl:`. No `.css` files created. Nothing else touched in any
  of the three files: `canManage`/`active`/`drafts`/`probation`/`separated`
  computed signals and `openCreate`/`onCreate` on the list page; the
  form's full reactive `FormBuilder` group, `effect()`-based prefill
  (including the new-record default-selection branch), and
  `errorFor`/`submit` logic; and every one of the detail page's ~15 computed
  signals (`employee`/`structure`/`balances`/`attendanceRows`/`leaveRows`/
  `overtimeRows`/`payslipRows`/`loanRows`/`bonusRows`/`settlementRows`/
  `profileFields`/etc.), all seven `Column<T>[]` definitions, and the
  `activate`/`onSave`/`deactivate` methods are all byte-for-byte unchanged.
  No logic, routing, API, or backend change of any kind.
- **Verification**: `npx tsc --noEmit` clean. `ng build` clean —
  `employee-detail` lazy chunk unchanged at 16.76 kB (the exact size
  recorded in this file before this migration), `employee-list` (4.83 kB)
  chunk builds correctly. `ng test` **243/243 passing** (unchanged — a pure
  template-location change touches no logic). No browser-automation tool is
  available in this environment, so live verification used the same
  real-login-plus-real-endpoint approach as §2.21–§2.31, extended to cover
  every dependency surfaced above: signed in for real via `POST
  /api/auth/login` as the real `farhana.islam` (Admin) demo account (real
  BCrypt+JWT, `200`, real `accessToken`), then called all 14 endpoints the
  Employees route's providers load with that token against the real
  running backend/Postgres — `employees` (25), `departments` (7),
  `designations` (8), `shifts` (4), `salary-structures` (10),
  `leave-balances` (16), `attendance` (11), `leave-requests` (2),
  `overtime` (0), `payslips` (68), `payroll-batches` (7), `loans` (6),
  `bonuses` (8), `settlements` (3) all returned `200` with real rows.
  Additionally resolved a single real employee record
  (`GET /api/employees/e7`, the real `farhana.islam` Admin demo account)
  to confirm the exact record shape `employee-detail.ts`'s `profileFields`
  computed reads from. Confirms the full data contract at the HTTP/auth
  level, including every dependency named in this task's instructions; does
  not confirm pixel-level rendering, matching the documented limitation of
  every prior entry that hit the same tooling gap.
- **Cleanup**: none needed — read-only verification only, no data created or
  modified. Backend (`:8080`) and frontend (`:4200`) both left running and
  healthy.
- **Status**: ✅ Done — Step 16 of the frontend architecture migration.
  Payroll is next (per the agreed order — core engine trigger,
  second-to-last), not started yet. Dashboard and Auth remain last per
  §2.17. CI and any other migration step were explicitly out of scope for
  this task and remain queued.

### 2.33 Frontend architecture migration, Step 17: Payroll (2026-09-02)
- **Scope**: `features/payroll/` — `batch-list.ts`, `batch-form.ts` (the
  "Create payroll batch" modal from §2.7), and `batch-detail.ts` (the
  engine trigger — run/submit/approve/return/pay, the core business
  function per §2.17's dependency audit). Second-to-last module in the
  migration, before Dashboard/Auth.
- **Dependency and correctness check, done before touching anything, per
  this task's explicit instruction**:
  - **Route providers**: `app.routes.ts`'s `payroll` route already
    provides `PEOPLE_STATE` plus `payrollBatchesFeature`/`payslipsFeature`/
    `paymentsFeature`/`attendanceFeature`/`overtimeFeature`/
    `salaryStructuresFeature`/`taxRulesFeature`/`pfRulesFeature`/
    `loansFeature`/`bonusesFeature`/`leaveRequestsFeature`/
    `holidaysFeature`/`companiesFeature` — every collection
    `batch-detail.ts`'s `runEngine()` reads (`this.employees()`/
    `this.attendance()`/`this.overtime()`/`this.structures()`/
    `this.loans()`/`this.bonuses()`/`this.leaveRequests()`/
    `this.holidays()`/`this.companies()`/`this.taxRules()`/
    `this.pfRules()`), confirmed by cross-checking the provider list
    against every `store.selectSignal` call in the component. No
    missing-provider gap; nothing to fix.
  - **Payroll engine and downstream flows verified untouched**: `runEngine()`
    still calls the real, unmodified `runPayroll`/`batchTotals`/
    `applyLoanRecovery` from `core/payroll-engine.ts` (a file outside
    `features/payroll/`, never touched by this or any prior migration
    step) exactly as before — same inputs, same dispatch sequence
    (`payslipsFeature.actions.upsertMany` → `payrollBatchesFeature.actions.upsert`
    → conditional `loansFeature.actions.upsertMany` for changed loans).
    `pay()`'s real bank-file generation (`buildBankTransferCsv`,
    `core/bank-file.ts`, §2.7) and payment dispatch, `approve()`/
    `returnBatch()`'s state-machine transitions (`rejectedBatchDraft`,
    `canApproveBatch`, `payroll-rules.ts`), and the payslip/loan/bonus/
    settlement-adjacent read paths (`slips`/`pendingLeaveTotal`) are all
    byte-for-byte unchanged — confirmed by diff scope: only the
    `@Component` decorator's `template:` key changed in any of the three
    files.
  - **Linked navigation**: `batch-detail.html` still links to
    `/payslips/:id` for each payslip row (unaffected — target route and
    component selector untouched); `batch-list.ts`'s `link` still routes
    to `/payroll/:id`.
- **Inspected next**: all three files had a real inline `template:` string
  — none had already been extracted. None had a `styles:` block, so no
  `.css` file was needed for any of the three. Checked for the
  signal-input-timing class of bug: **not present** —
  `batch-detail.ts`'s `id` input is only ever read inside `computed()`
  (`batch`), never in the constructor (the component's one `effect()`
  watches `batch()`/`writeError()` computed signals to release the
  `pay()` double-click guard — an unrelated, pre-existing pattern, not the
  signal-input-timing bug class, and left untouched). `batch-form.ts`'s
  `existing`/`requestedBy` required inputs are only read inside
  `computed()` or on submit, never in a constructor — this component has
  no constructor.
- **Change**: extracted each inline `template:` string verbatim into a
  sibling `.html` file (`batch-list.html`, `batch-form.html`,
  `batch-detail.html`); each `@Component`'s `template:` key replaced with
  `templateUrl:`. No `.css` files created. Nothing else touched in any of
  the three files: `canRequest`/`awaiting`/`paidTotal`/`openTotal`
  computed signals and `onSubmitted` on the list page; the form's reactive
  `FormBuilder` group, `toSignal`-derived `value`, `cycle`/`error` computed
  signals (using the unmodified `deriveBatchCycle` from §2.7), and
  `submit()`; and the detail page's `batch`/`slips`/`payment`/
  `pendingLeaveTotal`/`summary`/`preflight`/`steps`/`writeError` computed
  signals plus `runEngine`/`submit`/`approve`/`returnBatch`/`pay`/`log`
  methods are all byte-for-byte unchanged. No logic, routing, API, or
  backend change of any kind.
- **Verification**: `npx tsc --noEmit` clean. `ng build` clean —
  `batch-detail` lazy chunk unchanged at 17.51 kB (the exact size recorded
  in §2.7 before this migration), `batch-list` (7.50 kB) chunk builds
  correctly. `ng test` **243/243 passing** (unchanged — includes
  `payroll-engine.spec.ts` and `payroll-rules.spec.ts`, both still green,
  confirming the engine and rules logic this page triggers is genuinely
  untouched, not just visually unchanged). No browser-automation tool is
  available in this environment, so live verification used the same
  real-login-plus-real-endpoint approach as §2.21–§2.32: signed in for
  real via `POST /api/auth/login` as the real `nasrin.akter` (HR) demo
  account (real BCrypt+JWT, `200`, real `accessToken`), then called all 16
  endpoints the Payroll route's providers and pages depend on (including
  `payments`/`tax-rules`, not covered by the route's own load list but
  read via `paymentsFeature`/`taxRulesFeature` dispatched in the
  constructor) against the real running backend/Postgres — all returned
  `200` with real rows (`payroll-batches` 7, `payslips` 68, `payments` 6,
  `employees` 25, `departments` 7, `designations` 8, `attendance` 11,
  `overtime` 0, `salary-structures` 10, `tax-rules` 5, `pf-rules` 1,
  `loans` 6, `bonuses` 8, `leave-requests` 2, `holidays` 3, `companies` 1),
  confirming the full data contract behind the engine trigger, the bank
  file/payment flow, and every batch-lifecycle transition is unaffected.
  Confirms the data contract at the HTTP/auth level; does not confirm
  pixel-level rendering or exercise an actual engine run (which would
  create real payslip/payment rows), matching the documented limitation of
  every prior entry that hit the same tooling gap.
- **Cleanup**: none needed — read-only verification only, no data created or
  modified. Backend (`:8080`) and frontend (`:4200`) both left running and
  healthy.
- **Status**: ✅ Done — Step 17 of the frontend architecture migration.
  Dashboard and Auth remain last, per §2.17 (highest visibility/highest
  aggregate dependency). Neither started yet — explicitly out of scope for
  this task. CI and any other migration step remain queued.

### 2.34 Role-based access audit, then two approved fixes: Overtime auto-save, Reports visibility (2026-09-02)
- **Scope**: a full read-only audit of module access for all four roles
  (`module-registry.ts`, `session.ts`'s `canApprove*`/`canRequestPayroll`/
  etc. computed signals, `auth-guard.ts`'s `roleGuard`, and every write
  gate in `SecurityConfig.java`), presented for approval before any change.
  Two findings were approved for a fix; everything else in the audit was
  left exactly as-is per instruction — no other access change made.
- **Audit finding 1 (real bug, not a design choice)**: `attendance-page.ts`'s
  `checkOut()` calls `syncOvertimeForToday()` unconditionally for **any**
  role (Attendance is `ALL_ROLES`), dispatching
  `overtimeFeature.actions.upsert({ item })` — a `PUT /api/overtime/{id}`.
  But `SecurityConfig.java` gated both `POST` and `PUT /api/overtime/**`
  to `ADMIN_HR` only, with a comment claiming overtime is "only ever
  written by attendance-page.ts's correction flow and overtime-detail.ts's
  decision, both gated to HR/Admin already" — stale/wrong: the
  auto-calculation write on checkout isn't gated client-side at all and
  fires for every role. Net effect: an Employee or Accountant working past
  their shift got a real `403` on their own auto-overtime write, silently
  — the record never persisted, contradicting the documented business
  rule (§1.4, `overtime-page.ts`'s own docstring: "auto-recorded when
  attendance checks out beyond the rostered shift").
- **Audit finding 2 (design gap, not a bug)**: `Reports` (`module-registry.ts`)
  was `roles: ['Admin']` only, even though the page includes Tax report
  and PF report sections (Accountant's own domain, §1.14) and headcount/
  leave/overtime-approval-rate sections (HR's domain). Read-only page, no
  write path at all.
- **Fix 1 — Overtime auto-save, decision permissions unchanged**:
  - Frontend: `attendance-page.ts`'s `syncOvertimeForToday()` now dispatches
    `overtimeFeature.actions.create({ item })` instead of `.upsert(...)` —
    correct per the actual semantics (a brand-new record every time,
    deterministic id `ot-${employeeId}-${date}`, single call site per
    checkout, never re-created) and matches the project's own established
    convention (`create` = `POST` for genuinely new rows, `upsert` = `PUT`
    for existing ones, e.g. `loan-detail.ts`'s doc comment on the same
    distinction). No other logic touched.
  - Backend: `SecurityConfig.java`'s `POST /api/overtime/**` widened from
    `ADMIN_HR` to `ALL_ROLES` — safe specifically *because* of the frontend
    change above: `POST` now only ever carries the self-service
    auto-calculation write (always `status: 'pending'`,
    `payrollEligible: false`, never a decision). `PUT /api/overtime/**`
    **left unchanged at `ADMIN_HR`** — `overtime-detail.ts`'s
    approve/reject/correction flow is the only caller of `PUT` on this
    collection, and stays exactly as gated as before. Manager decision
    permissions were not weakened at any point.
  - **Backend test fixed to match the new, intended authorization**: the
    existing `AuthorizationIT.employeeCannotCreateAnOvertimeClaim` asserted
    the old (now-wrong) behavior and started failing (`400` instead of the
    expected `403`) as soon as the fix landed — confirming the fix actually
    took effect, not a regression. Renamed to
    `employeeCanCreateAnOvertimeClaimButCannotDecideOne` and rewritten to
    assert both halves: `POST` reaches the controller (`notForbidden()`,
    the same pattern already used for the analogous leave-balance
    self-seeding test just above it — an empty body fails Bean Validation
    with `400`, which proves authorization cleared rather than blocked) and
    `PUT` on the same collection still returns `403` for Employee.
- **Fix 2 — Reports visibility**: `module-registry.ts`'s `Reports` entry
  widened from `roles: ['Admin']` to `roles: ['Admin', 'HR', 'Accountant']`,
  with a comment explaining why (read-only, HR/Accountant's own domains,
  Employee deliberately excluded). No backend change needed or made — GET
  on every collection Reports reads was already `hasAnyAuthority(ALL_ROLES)`
  in `SecurityConfig.java`, so the only actual gate was the frontend nav
  entry (`roleGuard` + the sidebar). Reports has no write path at all, so
  "read-only" required no additional enforcement.
- **Verification**: `npx tsc --noEmit` clean, `ng build` clean, `ng test`
  **243/243 passing** (unchanged — neither fix touches any tested pure
  logic; the change is an action-type dispatch and two access-control
  entries). Backend: `mvnw compile` clean, full suite **155/155 passing**
  (was 154 passing + 1 failing before the test was corrected to match the
  new intended behavior — confirmed by re-running: the single failure
  disappeared only after updating the stale assertion, not by loosening
  it). Backend dev server restarted (stale process on `:8080` killed,
  rebuilt binary relaunched) so the live checks below actually exercised
  the new `SecurityConfig`, not a cached old build.
- **Live-verified with real JWTs for all four roles**, against the real
  running backend/Postgres:
  - `POST /api/overtime` as real `tanvir.ahmed` (Employee) → `400` (not
    `403` — reached the controller, failed only on the empty test body).
  - `POST /api/overtime` as real `rakib.hasan` (Accountant) → `400` (same).
  - `PUT /api/overtime/does-not-exist` as Employee → `403` (still blocked).
  - `PUT /api/overtime/does-not-exist` as Accountant → `403` (still
    blocked — Accountant was never an overtime decider and remains one).
  - `PUT /api/overtime/does-not-exist` as real `nasrin.akter` (HR) → `400`
    (not `403` — HR's decision authority confirmed completely unchanged).
  - `GET /api/audit-logs` as HR → `200` (Reports' audit-activity section
    now reachable for HR).
  - `GET /api/payslips` as Accountant → `200` (Reports' tax/PF sections
    now reachable for Accountant).
  All six results matched the intended matrix exactly. No browser-
  automation tool is available in this environment, so pixel-level
  rendering of the Reports page for HR/Accountant and an actual real
  attendance checkout in the browser were not visually walked — this
  verification covers the authorization contract at the HTTP/JWT level,
  which is what both fixes actually changed.
- **Cleanup**: no test data created or left behind — every check above was
  either a pure authorization probe (deliberately malformed/nonexistent
  bodies and ids, correctly rejected before any row was touched) or a
  plain `GET`. Backend (`:8080`, rebuilt) and frontend (`:4200`) both left
  running and healthy.
- **Scope discipline**: per explicit instruction, no other access change
  was made — every other finding from the audit (Attendance `PUT` being
  `ALL_ROLES` at the API level, a known/already-documented limitation) was
  left exactly as-is, not touched.
- **Status**: ✅ Done — both approved fixes shipped, tested, and live-
  verified. Frontend architecture migration remains at Step 17 (Dashboard/
  Auth still queued, untouched by this task).

### 2.35 Frontend architecture migration, Step 18: Dashboard (2026-09-02)
- **Scope**: `features/dashboard/dashboard-page.ts` — the single component
  behind every role's landing page (§1.9's four-views-in-one design),
  per the agreed order (highest visibility — every role's first screen on
  sign-in — done second-to-last per §2.17, before Auth).
- **Inspected first, per instruction**: the file had a real inline
  `template:` string — not already extracted. No `styles:` block, so no
  `.css` file was needed.
- **Real pre-existing bug found while inspecting, same class as §2.21's
  Reports finding**: `dashboard-page.ts` reads
  `bonusesFeature.selectors.all` (backing the Accountant "Bonuses pending"
  tile, `pendingBonuses` computed) and dispatches
  `bonusesFeature.actions.load()` unconditionally in the constructor — but
  `app.routes.ts`'s `dashboard` route's `providers` array never included
  `provideCollection(bonusesFeature)`. Since `store.selectSignal(...)` on
  an unregistered NgRx feature is a field initializer that runs
  unconditionally (not gated by role), this would throw on navigation to
  `/dashboard` for **every** role, not just Accountant — and Dashboard is
  the app's default landing route (`redirectTo: 'dashboard'`), so this was
  a real, severe, pre-existing bug, not a hypothetical one. Fixed by adding
  `...provideCollection(bonusesFeature)` to the route's `providers` array,
  with an inline comment recording the bug and its cause — mirroring
  exactly how §2.21 handled the analogous missing-provider bug on Reports.
  No component logic touched; this only supplies the state the component
  already assumed existed.
- **Change**: extracted the inline `template:` string verbatim into a new
  sibling `dashboard-page.html`; `@Component`'s `templateUrl:
  './dashboard-page.html'` replaces `template:`. Every KPI computed signal
  (`myNetPay`/`myPresent`/`myOtHours`/`myLeaveBalance`/`myLoanOutstanding`/
  `myPf`/`myPending`/`myUnreadNotifications` for Employee;
  `acctGross`/`acctNet`/`acctDeductions`/`acctTax`/`acctPf`/`acctOvertime`/
  `acctBonus`/`pendingBonuses`/`acctBatch` for Accountant;
  `activeCount`/`newThisMonth`/`presentToday`/`myDecidableLeave`/
  `myDecidableChangeRequests`/`upcomingCelebrations` for HR; the Admin
  `@default` case's own mix of the above), the role-based `@switch`
  branching itself, `subtitle`, `queue`, `recentActivity`, `batchRef`, and
  every other method are all byte-for-byte unchanged — confirmed by diff
  scope: only the `@Component` decorator's `template:` key changed in the
  component file, and only one line was added to the route's `providers`
  array. No business logic, access rule, or routing configuration was
  altered.
- **Verification**: `npx tsc --noEmit` clean. `ng build` clean —
  `dashboard-page` lazy chunk unchanged at 16.29 kB (the extraction moved
  no bytes out of the bundle, as expected — no CSS was involved). `ng
  test` **243/243 passing** (unchanged — a template-location change and an
  additive route-provider entry touch no tested pure logic). No browser-
  automation tool is available in this environment, so live verification
  used the same real-login-plus-real-endpoint approach as §2.21–§2.33:
  signed in for real via `POST /api/auth/login` as all four real demo
  accounts (`farhana.islam`/Admin, `nasrin.akter`/HR, `rakib.hasan`/
  Accountant, `tanvir.ahmed`/Employee — real BCrypt+JWT, `200`, real
  `accessToken` for each), then called all 14 endpoints the Dashboard
  route's providers and the component's constructor load, with each
  token, against the real running backend/Postgres —
  `employees`/`departments`/`designations`/`attendance`/`leave-requests`/
  `leave-balances`/`overtime`/`payroll-batches`/`payslips`/`loans`/
  `bonuses`/`change-requests`/`notifications`/`audit-logs` all returned
  `200` for **every one of the four roles**, including `bonuses` — the
  exact collection the missing-provider bug affected — confirming the fix
  actually closes the gap for real, authenticated requests, not just in
  theory. Confirms the data contract at the HTTP/auth level for every
  role's dashboard view; does not confirm pixel-level rendering of each
  role's specific KPI tile set, matching the documented limitation of
  every prior entry that hit the same tooling gap.
- **Cleanup**: none needed — read-only verification only, no data created
  or modified. Backend (`:8080`) and frontend (`:4200`) both left running
  and healthy.
- **Status**: ✅ Done — Step 18 of the frontend architecture migration.
  Auth (`login-page.ts`) is the last remaining module per §2.17's ordering
  — not started yet, explicitly out of scope for this task. CI and any
  other migration step remain queued.

### 2.36 Final end-to-end correctness audit (2026-09-02)
**Recommended order (given, then followed)**: baseline build/test →
hot-reload check → static business-logic read → payroll calculation
cross-check → role/workflow E2E + guard/authorization match (real-JWT API,
no browser tool in this environment) → integration/data-consistency
(folded into the two steps above) → final tests/build → PASS/FAIL report.

**Step 0 — Baseline**: `npx tsc --noEmit` clean, `ng build` clean, `ng
test` 243/243 passing, `mvnw compile` clean, `mvnw test` exit 0 (155/155),
all before any change — confirmed the audit starts from a known-good
state.

**Step 1 — Hot reload / Angular dev-server behavior**: Stopped the
existing `ng serve` process (stale, pre-dated this task) and restarted it
fresh with output captured to a log file, to get a clean rebuild trail.
Made a one-line temporary text change to `audit-page.html`'s subtitle
(added `HMR-TEST-MARKER-4471`, the safest possible page — Admin-only,
read-only, zero blast radius):
- Dev server detected the change and rebuilt **incrementally** — only the
  `audit-page` lazy chunk recompiled (9.80 kB, new hash
  `chunk-Q3DL6EAE.js`), not a full app rebuild, in 4.288s, logging
  "Component update sent to client(s)" (Angular's own HMR push).
- Fetched the new chunk directly (`curl .../chunk-Q3DL6EAE.js`) and
  confirmed the marker text is actually present in the served bytes —
  not just a log message claiming success.
- Reverted the change, dev server rebuilt again (0.648s, new hash
  `chunk-XLQJP4MV.js`), fetched that chunk, confirmed the marker is gone
  and the original text is restored.
- **No stale-cache/stale-template issue found**: every edit produces a
  new content-hashed chunk filename, so there is no scenario where a
  browser (or this verification) could serve old compiled output for
  changed source — the hash itself changing per edit is the guarantee.
  HMR is genuinely working end-to-end, not just appearing to via a
  full-page reload masking a stale bundle.

**Step 2 — Static business-logic audit**: read `core/payroll-engine.ts`
in full alongside every `features/*/​*-rules.ts` file and the backend's
service-layer exceptions (`PayrollBatchService`, `BonusRecordService`,
`SettlementService`, `ChangeRequestService`) against `SecurityConfig.java`
and every frontend `canApprove*`/`canDecide*`/`canManage` gate. Findings
below, each classified.

**Step 3 — Payroll calculation cross-check**: a real cycle seeded with
known inputs, hand-calculated against `payroll-engine.ts`'s actual
formulas and compared to the real Postgres payslip row.

**Step 4 — Role/workflow E2E and guard/authorization match**: real-JWT
API verification per role (no browser-automation tool in this
environment — established limitation throughout this project), comparing
`roleGuard`/`module-registry.ts` against `SecurityConfig.java` write gates
for every module.

**Step 2 (continued) — Static business-logic audit, full findings**: read
`core/payroll-engine.ts`, `features/attendance/attendance-rules.ts`,
`features/overtime/overtime-rules.ts`, `features/leave/leave-rules.ts`,
`features/settlements/settlement-rules.ts`,
`features/change-requests/change-request-rules.ts`,
`features/loans-bonuses/loan-rules.ts`, `features/loans-bonuses/bonus-rules.ts`,
`features/payroll/payroll-rules.ts`, and every backend service-layer
exception (`PayrollBatchService`, `BonusRecordService`, `SettlementService`,
`LoanRecordService`, `OvertimeService`, `ChangeRequestService`) in full,
line by line, against `SecurityConfig.java` and every frontend
`canApprove*`/`canDecide*`/`canManage` gate. Findings, classified:

1. **Bug, narrow/low-severity, not fixed (flagged for a decision)**:
   `batch-detail.ts`'s `pay()` fires the `Payment` write and the batch's
   `status: 'paid'` write as two independent, unordered dispatches —
   `PayrollBatchService.update()`'s own comment documents this exact race
   and defends against the *money-correctness* half of it (refusing to let
   a batch reach `paid` before its payment row exists, `409` otherwise,
   retryable). What it doesn't cover: `pay()`'s CSV download and its
   `for (const slip of this.slips())` employee-notification loop run
   unconditionally on every call, including a legitimate retry after that
   documented `409` — so the one realistic trigger of the race (payment
   write lands first, batch write 409s, user retries) would re-download
   the bank file and **send every employee in the batch a duplicate
   "Payslip ready" notification**. No money or payslip data is affected —
   this is a UX/notification-duplication gap, not a financial-correctness
   one. Not fixed in this pass: the correct fix (skip the CSV/notify block
   when `this.payment()` already reflects a completed write, only
   resubmitting the batch-status PUT) touches `pay()`'s control flow, and
   per this task's own instruction ("fix only confirmed bugs after
   explaining them" read alongside "preserve intended business rules" and
   the standing carefulness requirement for Payroll specifically) this is
   presented for a decision rather than silently changed.
2. **Design gap, not urgent**: `netSalary` floors at `0`
   (`Math.max(0, grossSalary + bonus - totalDeductions)`), but
   `totalDeductions` itself is never floored — in the theoretical case
   where statutory/attendance deductions alone (tax + PF + late + unpaid
   leave + unauthorized absence — none of them capped, unlike loan
   recovery, which is deliberately capped to `availableForLoanRecovery`)
   exceed `grossSalary + bonus`, the payslip would display a
   `totalDeductions` figure larger than what was actually deducted from a
   `netSalary` of `0`. Requires an extreme, unrealistic combination
   (e.g. very high lateness/absence on a very low salary) to occur at all;
   not observed in any real data this project has seeded. Documented, not
   fixed — fixing it would mean changing what `totalDeductions` represents
   on a payslip, a display-semantics decision, not a pure bug fix.
3. **Design gap, admin-config-dependent**: `monthlyTax()`'s slab lookup
   (`rules.find((rule) => annual >= rule.minIncome && annual <= rule.maxIncome)`)
   has no guard against an Admin configuring overlapping or gapped tax
   slabs on the Salary & Rules page — `.find()` would silently pick
   whichever slab appears first in array order on an overlap, or return
   `undefined` (→ `0` tax) on a gap. The real seeded slab data has no
   overlaps or gaps (`0–350000 / 350001–450000 / 450001–750000 /
   750001–1150000 / 1150001+`, confirmed in Step 3 below). Same category
   as every other unenforced admin-config invariant already accepted
   throughout this project (e.g. no CHECK constraint stopping two
   overlapping leave rules) — not fixed, consistent with existing risk
   posture.
4. **Existing intentional behavior, not a bug**: `loan-rules.ts`'s
   duplicate-open-loan check still matches on `row.status === 'approved'`
   alongside `'pending'`/`'active'`, but no code path has set a loan's
   status to `'approved'` since §1.8's fix (`loan-detail.ts`'s `approve()`
   now jumps straight to `'active'`). Harmless dead branch — the value it
   checks for can never occur, so it changes no observed behavior. Left
   as-is; not worth a change for a branch that can never execute.
5. **Confirmed correct, no issues**: every `canDecide*`/`canApprove*` self-
   approval gate (Leave, Overtime, Change Requests, Loans, Bonuses,
   Settlements, Payroll Batches) blocks the requester from deciding their
   own item, and every escalation chain (Leave/Change Requests:
   Employee/Accountant→HR-or-Admin, HR→Admin-only, Admin→HR-only) matches
   between the frontend rule and what the backend's role-only gate
   actually permits (the backend cannot enforce the *escalation* half
   itself — no per-request identity check exists there beyond role, a
   pre-existing, already-documented boundary, not new). Every backend
   service-layer immutability lock (`PayrollBatchService`'s state machine,
   `BonusRecordService`/`ChangeRequestService`'s terminal-state lock,
   `SettlementService`'s completed-lock, `LoanRecordService`'s
   rejected-only lock, `OvertimeService`'s rejected-only lock preserving
   the intentional post-approval correction flow) matches its own
   documented rationale exactly — no gap found between what a comment
   claims and what the code enforces.

**Step 3 — Payroll calculation cross-check, full results**: rather than
seed data through the UI/curl and walk 30 days of attendance by hand (error-
prone and slow), used the same "compile the real module via the project's
own `tsc` and drive it from a Node script" method §1.8/§1.10 established —
compiled the actual, unmodified `core/payroll-engine.ts` +
`attendance-rules.ts` and ran `runPayroll()` directly against a fully
controlled, hand-calculated `EngineInput` exercising **every** deduction/
addition category in one payslip simultaneously (not pairwise, as prior
verifications did):
- Structure: basic ৳20,000, HRA ৳8,000, allowances ৳2,000 (nominal gross
  ৳30,000, `appliesTax`/`appliesPF` both true), cycle 2026-09-01→09-30 (30
  days), real seeded tax slabs (Exempt 0–350,000, Slab 1 350,001–450,000 at
  5%, ...) and real PF rule (10% employee / 10% employer) fetched live from
  the running backend first, so the hand-calc used the project's actual
  configured rates, not invented ones.
- Inputs: 5 late-arrival attendance rows (freeLateAllowance=3 → 2
  chargeable), one approved+payroll-eligible overtime row (3h × ৳200 =
  ৳600) **plus one pending row that must be ignored**, one active loan
  (EMI ৳2,500, outstanding ৳10,000), one approved bonus ৳1,000 in-cycle
  **plus one rejected bonus that must be ignored**, one approved 3-day
  Unpaid leave request in-cycle.
- **Every hand-calculated figure matched the real engine's output
  exactly**: `basic` 20,000, `hra` 8,000, `allowances` 2,000,
  `overtimeAmount` 600 (pending row correctly excluded), `grossSalary`
  30,600, `tax` 1,500 (annualized 360,000 correctly landed in Slab 1 at
  5% of the *prorated* 30,000), `pf` 2,000 (10% of basic), `lateDeduction`
  1,000 ((5−3)×1,000×0.5, dailyRate = 30,000÷30 = 1,000), `leaveDeduction`
  3,000 (3×1,000), `absenceDeduction` 0 (weeklyOffDay omitted, absence
  check correctly skipped per its own documented convention), `loanRecovery`
  2,500 (full EMI — well under `availableForLoanRecovery`), `bonus` 1,000
  (rejected bonus correctly excluded), `totalDeductions` 10,000, `netSalary`
  21,600. `batchTotals()` correctly summed `grossTotal` 31,600 (gross +
  bonus, matching the payslip-detail page's own "Gross earnings" formula).
- **Rerun idempotency** (the exact bug class §1.8 fixed): ran the identical
  batch a second time with the first run's updated loan row —
  `loanRecovery` came out ৳2,500 again (engine is pure/deterministic, same
  inputs → same output), and `applyLoanRecovery`'s delta-based diff against
  the batch's own previous slips correctly computed **zero further
  change** — confirms a rerun genuinely does not double-charge, not just
  that the original bug's specific repro case doesn't recur.
- **Multi-loan weighted split**: two simultaneous active loans (EMI
  ৳1,000 and ৳3,000, combined desired recovery ৳4,000, both fully
  affordable) — `applyLoanRecovery` split the ৳4,000 exactly
  proportionally to each loan's `emiAmount` (৳1,000 and ৳3,000
  respectively, matching the weighting formula's own doc comment), not
  the "same total subtracted from every loan" bug §1.8's write-up
  describes finding and fixing previously.
- **No discrepancy of any kind found** between the documented formulas,
  the real configured rates, and the actual engine output — the payroll
  engine is correct across every category audited: basic/allowances,
  gross, PF (both contribution rates confirmed against the real `PfRule`
  row), tax (against the real slab table), loan recovery (single and
  multi-loan, first-run and rerun), bonus, unpaid-leave deduction, late
  deduction, overtime, and net salary.

**Step 4 — Role/workflow E2E, guard/authorization match**: cross-referenced
`module-registry.ts`'s per-module `roles` list against `SecurityConfig.java`'s
write gates for all 15 modules — no drift found beyond the two already
fixed and live-verified in §2.34 (Overtime auto-save, Reports visibility).
Every other module's frontend role list and backend write gate agree.
Ran one live full-cycle regression smoke test on Change Requests (the
module with the most bug history — §2.13's field-injection fix) with real
JWTs against the real running backend:
- Employee (`tanvir.ahmed`) `POST /api/change-requests` (propose a phone
  change for `e4`) → `201`, real row persisted.
- Employee attempts to `PUT` (approve) **their own** request → `403` —
  confirmed the role gate alone (Employee is not in `ADMIN_HR`) blocks
  this at the API level, independent of the escalation-matrix check that
  only exists client-side.
- HR (`nasrin.akter`) `PUT` (approve) the same request → `200`.
- Confirmed `Employee.phone` on `e4` **stayed unchanged** after the
  backend-only approval — correct, matches the documented dumb-CRUD
  architecture exactly: applying the approved field change onto the
  `Employee` record is `change-request-detail.ts`'s own second, separate
  dispatch, not something the backend does as a side effect of the
  `ChangeRequest` status write. Not a bug — confirms the architecture
  boundary behaves exactly as documented, live.
- Attempted to delete the now-`approved` test row via the API → `403`
  (blanket DELETE-is-Admin-only rule) — then, as Admin, would have hit
  `ChangeRequestService.assertMutable`'s terminal-state lock regardless
  (`approved`/`rejected` are permanently immutable by design, §2.13) — so
  the row could never be deleted through the API at all, exactly as
  intended for a permanent audit trail. Cleaned up via direct `psql`
  (`DELETE FROM change_request WHERE id = 'cr-audit-1'`), the same
  documented exception §2.13 itself uses for the identical situation
  ("the approved one via direct psql, since its own immutability fix
  correctly blocks the API from doing it — expected, not a workaround for
  a bug").

**Step 5 — Integration/data consistency**: folded into Steps 3 and 4 above
as planned — the payroll cross-check exercised the real compiled engine
against real configured rates fetched live from Postgres, and the Change
Requests smoke test exercised the full frontend-action → backend-write →
Postgres → read-back path for a real record. No separate pass needed.

**Step 6 — Final tests/build**: run after the audit's read-only and
live-probe work, confirming no regression was introduced by the audit
itself (the audit made zero source changes — the only file edited was
`audit-page.html`'s Step-1 HMR marker, added and then reverted, confirmed
back to its original text with `0` matches for the marker string
afterward):
- Frontend: `npx tsc --noEmit` clean. `ng build` clean (all lazy chunks
  built, no errors). `ng test` **243/243 passing**.
- Backend: `mvnw test` exit code `0` — **155/155 passing** (confirmed
  twice: once as this audit's Step 0 baseline before any inspection began,
  and again after the audit's live-probe work completed, to rule out any
  side effect from the curl-driven checks in Step 4).
- Spot-checked all four files touched by the two approved fixes earlier in
  this session (§2.34's Overtime/Reports changes, §2.35's Dashboard
  `bonusesFeature` provider fix) are still exactly as intended, with no
  stray edits: `attendance-page.ts`'s `overtimeFeature.actions.create`,
  `SecurityConfig.java`'s `POST /api/overtime/**` → `ALL_ROLES`,
  `module-registry.ts`'s Reports `roles: ['Admin', 'HR', 'Accountant']`,
  and `app.routes.ts`'s `provideCollection(bonusesFeature)` on the
  dashboard route — all present, all correct, nothing extra.

### Final PASS/FAIL report

**Overall status: PASS.** No confirmed financial-correctness, security, or
data-integrity bug was found anywhere in this audit. The one confirmed bug
found (duplicate notifications on a narrow retry path) is a UX annoyance,
not a money or data-correctness defect, and is presented below for a
decision rather than silently fixed, per this task's own instruction.

**Confirmed bugs found this pass**: 1 (narrow, low-severity, not fixed —
see Step 2, finding 1 above: `pay()`'s CSV/notification side effects
aren't idempotent across the documented payment/batch-write race's retry
path).

**Bugs fixed this session** (found and fixed in the two immediately-prior
tasks, re-confirmed still correct and still tested in this final pass):
overtime auto-save 403 for Employee/Accountant self-checkout (§2.34);
Dashboard's missing `bonusesFeature` route provider, which broke
navigation to the default landing route for every role (§2.35).

**Design gaps (not bugs, not fixed, matching existing project risk
posture)**: `netSalary`'s floor-at-zero not also flooring the displayed
`totalDeductions` in an extreme, unobserved deduction-exceeds-gross
scenario; no overlap/gap guard on Admin-configured tax slabs (same
category as every other unenforced admin-config invariant already
accepted elsewhere in this project); `loan-rules.ts`'s harmless dead
branch checking for a `'approved'` loan status no code path sets anymore.

**Remaining risks**:
- The one confirmed-not-fixed bug above (duplicate notifications on a rare
  retry path) — low severity, needs a decision on the preferred fix shape
  before touching `pay()`.
- Every previously-documented, already-accepted architectural boundary
  remains exactly as it was (backend cannot enforce the leave/change-
  request *escalation* matrix itself, only the role gate; Attendance
  `PUT` is `ALL_ROLES` at the API level with correction-vs-self-checkout
  distinguished only client-side) — none of these are new, all were
  already known and deliberately accepted before this audit began.
- No browser-automation tool exists in this environment, so this audit's
  "E2E" work is real-JWT API verification plus full static code reading,
  not a clicked-through visual walkthrough — pixel-level rendering across
  all four roles' dashboards and forms has never been visually confirmed
  in this project, only its data contracts and compiled logic.

**Hot reload / dev-server behavior**: confirmed genuinely working, not
just appearing to via a full-page reload masking stale output — incremental
per-file rebuild, correct new content verified present in the served
bytes, content-hash changes on every edit (no stale-cache scenario
possible), clean revert confirmed.

### 2.37 Fix: `pay()` retry no longer duplicates notifications/CSV download (2026-09-02)
- **Scope**: the one confirmed bug from §2.36's audit (finding 1) — fixed,
  as approved, and nothing else. Payroll calculations and the batch state
  machine are untouched: `PayrollBatchService`'s transition table, its
  payment-must-exist-before-`paid` check, and every dispatch's status
  value are exactly as they were.
- **Fix**: extracted the idempotency decision into a new pure function,
  `paymentAlreadyRecorded<T>(payment: T | undefined): payment is T`, in
  `payroll-rules.ts` — matching this module's own established convention
  (`canStartPay`/`shouldReleasePayGuard` are the same shape, added for the
  double-click guard). A batch only ever gets one real `Payment` row
  (`pay()` always writes the same deterministic id, `pay-${batch.id}`), so
  if one is already on file (`this.payment()` truthy) when `pay()` runs,
  this is a retry after the documented payment/batch-write race — the
  earlier attempt's payment write already succeeded, only the batch's own
  `status: 'paid'` write failed (`409`) and needs resubmitting.
  `batch-detail.ts`'s `pay()` now checks this first: on a retry, it
  dispatches **only** the batch-status write (unchanged dispatch, same
  `{ ...batch, status: 'paid' }` shape as before) and logs a distinct audit
  entry ("Marked payroll batch paid (retry — payment already recorded)"),
  returning before the CSV-generation and employee-notification loop ever
  runs. On a genuine first call (`this.payment()` undefined), the full
  original flow runs exactly as before — payment write, batch write, CSV
  download, one notification per employee — byte-for-byte unchanged.
- **Not changed**: `runPayroll`/`batchTotals`/`applyLoanRecovery` (the
  calculation engine, `core/payroll-engine.ts` — untouched, not even
  opened this pass), `PayrollBatchService`'s Java transition table and
  payment-existence check (untouched — the fix works entirely within the
  existing contract that service already enforces), `canStartPay`/
  `shouldReleasePayGuard` (the double-click guard — untouched, orthogonal
  to this fix: that guard stops a rapid double-click within one attempt,
  this fix makes a *legitimate* retry after a real failure safe).
- **Regression test added**: `payroll-rules.spec.ts` — two new cases for
  `paymentAlreadyRecorded`: `undefined` (no payment yet) → `false`, a real
  `Payment` object → `true`. Matches this project's stated convention of
  testing only the pure logic a component delegates to, not the component
  itself (no other `*-page.ts`/`*-detail.ts` has a component spec).
- **Verification**: `npx tsc --noEmit` clean (the `payment is T` type
  predicate correctly narrows `existingPayment` inside the guarded branch,
  so `existingPayment.bankFileRef` type-checks with no cast needed). `ng
  build` clean. `ng test` **245/245 passing** (was 243, +2 new — the two
  `paymentAlreadyRecorded` cases; every pre-existing test, including
  `payroll-engine.spec.ts` and the rest of `payroll-rules.spec.ts`, stayed
  green, confirming no calculation or state-machine behavior changed).
  Backend: no file touched (this was a pure-frontend fix, the backend's
  own race-defense in `PayrollBatchService` needed no change), but
  `mvnw compile` and `mvnw test` were re-run per instruction anyway —
  clean compile, exit code `0`, **155/155 passing**, unchanged.
- **Live verification**: not performed this pass — reproducing the actual
  race live would require deliberately forcing the batch-status write to
  fail after the payment write succeeds (e.g. killing the backend
  mid-`pay()`), which risks leaving real batch/payment/notification state
  inconsistent for no verification benefit beyond what the unit test and
  the code-level trace already establish (the fix is a pure, three-line
  early-return guarded by a value the store already tracks correctly, per
  §2.36's own reading of `this.payment()`'s selector). The fix's shape was
  independently traced against `PayrollBatchService`'s documented race
  before writing it, not assumed.
- **Status**: ✅ Done. The final-audit's one confirmed bug is closed;
  §2.36's "Confirmed bugs found this pass: 1... not fixed" line is
  superseded by this entry.

### 2.38 `application.yml` → `application.properties` conversion (2026-09-02)
- **Scope**: user preference, not a bug or a design fix — explicitly the
  item §2.16 had previously declined ("no functional benefit... recommended
  against"), now requested directly and done exactly as asked: every config
  value, both profiles, and all behavior preserved byte-for-value; no
  application code or business logic touched.
- **Change**: `payroll-automation-backend/src/main/resources/application.yml`
  (one base document + `dev`/`prod` profile documents, separated by `---`)
  replaced with three standard Spring Boot profile-specific files —
  `application.properties` (the base, profile-independent block: `spring.
  application.name`, `spring.profiles.active=dev`, `server.port`, `jwt.
  access-token-expiration-ms`), `application-dev.properties` (the former
  `dev` document's datasource/JPA/Flyway/CORS keys), and
  `application-prod.properties` (the former `prod` document's keys,
  including the `${DB_URL}`/`${DB_USERNAME}`/`${DB_PASSWORD}`/
  `${CORS_ALLOWED_ORIGINS}` env-var placeholders — unchanged, still no
  literal secret or domain anywhere). This is the standard, idiomatic
  Spring Boot mechanism for profile-specific properties (`application-
  {profile}.properties`, auto-loaded when that profile is active) — not a
  single properties file with manually-parsed section markers, which would
  have been the properties equivalent of the YAML's `---` documents but is
  not how Spring Boot's own properties-file profile support works.
  Every key name, value, and comment's meaning carried over exactly — the
  only textual change beyond dot-notation was straightening two comments'
  em-dashes to plain hyphens (`.properties` files are typically plain
  ASCII in this codebase's other files; a purely cosmetic, zero-behavior
  choice) and updating two now-stale doc-comment references to
  `application.yml` by name (`WebConfig.java`'s field comment,
  `ProdProfileConfigurationIT.java`'s class Javadoc) to name the new
  files instead — both comments-only, chosen specifically because they
  name the exact file being converted, not "unrelated code."
- **Verification method — rigorous, not just "both formats present and
  hope"**: before any deletion, `application.yml` was moved out of the
  project entirely (to a local temp backup, not left in `resources`) so
  the verification below could not silently pass by having the old YAML
  quietly supply a key the new properties files were missing — Spring
  Boot's own precedence (`.properties` over `.yml` at the same location)
  would have masked exactly that failure mode if both files had been left
  in place together.
  - `mvnw compile`: clean, with only the three `.properties` files present.
  - `mvnw test`: exit code `0`, **155/155 passing** — critically including
    `ProdProfileConfigurationIT`, the one test that specifically exercises
    the `prod` profile's datasource/CORS/`show-sql` values end-to-end
    (`@ActiveProfiles("prod")` + `@DynamicPropertySource` supplying the
    `${DB_URL}`-style placeholders), proving `application-prod.properties`
    is complete and correctly wired, not just `application-dev.properties`
    (exercised implicitly by every other test, which runs under the
    default `dev` profile).
  - **Live app start, with only the new files present**: killed the stale
    dev server (still running the old YAML-compiled build), rebuilt and
    restarted it — booted clean, `GET /api/health` → `{"status":"UP"}`,
    startup log showing Hikari/Flyway connected to the real
    `jdbc:postgresql://localhost:5432/payroll_db` (matching
    `application-dev.properties` exactly, not a fallback). Live-verified
    the two settings most likely to silently regress in a format
    conversion: CORS preflight (`OPTIONS /api/companies` with `Origin:
    http://localhost:4200`) → `200`, and a real login
    (`POST /api/auth/login`) → real JWT whose `exp − iat` is exactly
    `86400` seconds, matching `jwt.access-token-expiration-ms=86400000`
    to the second.
  - Re-ran `mvnw compile`/`mvnw test` once more after the two doc-comment
    edits above — clean, exit `0`, **155/155 passing**, unchanged.
  - Confirmed no other reference to `application.yml` remains anywhere
    under `payroll-automation-backend/src` (`find -iname
    "application*.yml"` / `"application*.yaml"` — zero matches) and no
    `.java`/`.xml`/`.md` file references it by name anymore either, beyond
    the two comments already updated.
- **No config key lost or renamed**: every key from the original
  `application.yml` — `spring.application.name`, `spring.profiles.active`,
  `server.port`, `jwt.access-token-expiration-ms`,
  `spring.datasource.{url,username,password,driver-class-name}`,
  `spring.jpa.hibernate.ddl-auto`, `spring.jpa.show-sql`,
  `spring.jpa.properties.hibernate.format_sql`,
  `spring.flyway.{enabled,locations,baseline-on-migrate}`,
  `app.cors.allowed-origins` — is present under the identical dotted key
  in the identical profile's new file, with the identical value. No key
  was renamed, dropped, or moved to the wrong profile.
- **Removal**: the old `application.yml` was moved out of the project
  (not left anywhere under `src`) only after every check above passed —
  per instruction, removal followed verification, not the other way
  round.
- **Status**: ✅ Done. Config file in use is now
  `application.properties` + `application-dev.properties` +
  `application-prod.properties`; behavior, values, and both profiles are
  byte-for-value identical to the old `application.yml`. No application
  code, business logic, or unrelated file was changed.

### 2.39 Post-conversion config + architecture sanity check (2026-09-02)
- **Scope**: a final, explicitly read-only-unless-a-real-bug check before
  Dashboard/Auth — every item requested, in order, plus one deep
  cross-reference not previously done exhaustively across every route.
- **1. `application.properties` + dev/prod loading**: confirmed via
  §2.38's own live checks (Hikari/Flyway connected to the real dev
  datasource, CORS `200`, JWT expiry exact to the second) — re-verified
  the three files are still present and correctly named
  (`application.properties`/`application-dev.properties`/
  `application-prod.properties`). No change needed.
- **2. No old yml/yaml references — real finding, fixed**: `find -iname
  "*.yml"` across the whole `payroll-automation-backend` directory (not
  just `src`, which §2.38 already checked) turned up
  `target/classes/application.yml` — a **stale compiled build artifact**
  left over from before the conversion. Maven's incremental resource copy
  does not delete files from `target/` that were removed from `src/`
  unless `mvn clean` is run first, and §2.38's verification never ran
  `clean` — it moved the source `.yml` out and rebuilt, but the orphaned
  copy in `target/classes` (from an earlier, pre-conversion build) was
  never touched and remained on the actual runtime classpath the whole
  time. Classified as **a real bug** (duplicate/conflicting config on
  disk, exactly what this check was asked to find) — low practical impact
  since Spring Boot's own precedence (`.properties` over `.yml` at the
  same classpath location) meant the stale file was silently shadowed and
  produced no observed behavior difference, but it was still genuine
  duplicate config, and "silently shadowed today" is not a guarantee for
  every future build/packaging step. **Fixed**: ran `mvnw clean` (only
  deletes `target/`, touches no source), then recompiled — confirmed
  `target/classes` now contains only the three `.properties` files, no
  `.yml`. Full test suite re-run on this genuinely clean build: exit `0`,
  **155/155 passing**. No other `.yml`/`.yaml` file exists anywhere in the
  backend project.
- **3. No duplicate/conflicting config**: beyond the stale artifact above
  (now fixed), confirmed exactly one `application.properties` and exactly
  one `application-dev.properties`/`application-prod.properties` exist —
  no second copy, no `application-test.properties` or `bootstrap.
  properties` competing with them.
- **4. JWT, DB, Flyway, CORS, security config**: `JwtService.java`'s
  `@Value("${jwt.access-token-expiration-ms:86400000}")`,
  `WebConfig.java`'s and `SecurityConfig.java`'s
  `@Value("${app.cors.allowed-origins}")` all bind to the exact key names
  present in the new `.properties` files — confirmed by direct grep
  against the source, and already live-verified end-to-end in §2.38 (real
  JWT issuance, real CORS preflight, real Hikari/Flyway connection). No
  drift found.
- **5. Frontend API/base URL config**: `core/http-api.ts`'s
  `API_BASE = 'http://localhost:8080/api'` is a hardcoded literal, no
  `environment.ts` file exists in the project — this is a pre-existing,
  already-documented limitation (§2.5: "fine for local dev, revisit if a
  build-time prod/dev split is needed"), not new, not a regression from
  this session's work, and unrelated to the backend's YAML→properties
  conversion (the frontend never read `application.yml` in any form).
  Confirmed unchanged, not touched.
- **6. No broken route/provider dependencies — real finding, fixed**:
  cross-referenced every route in `app.routes.ts` against every
  `*Feature.actions.load()` call each of its page components' constructors
  actually dispatch (not just spot-checked, all 15 routes and every
  component file under `features/`). Found a **third instance** of the
  exact bug class already fixed twice this session (§2.21 Reports, §2.35
  Dashboard): `employee-detail.ts` reads
  `payrollBatchesFeature.selectors.all` (`allBatches`, backing
  `batchRef()`/`batchEnd()` — used by the Payslips related-records
  section to resolve each payslip's batch reference and sort by cycle
  end) and dispatches `payrollBatchesFeature.actions.load()`
  unconditionally in its constructor, but the `employees` route's
  `providers` array never included `provideCollection(payrollBatchesFeature)`.
  Since `store.selectSignal(...)` on an unregistered feature is a field
  initializer that runs unconditionally regardless of role, this broke
  Employee Detail navigation **for every role** — including via
  `roleGuard`'s own-record exception, which every Employee and Accountant
  uses to reach their own profile. Fixed the same way as both prior
  instances: added `...provideCollection(payrollBatchesFeature)` to the
  `employees` route's providers, with an inline comment recording the bug,
  its cause, and the two prior instances of the same class. Every other
  route's providers were cross-checked against its pages' actual
  constructor loads with no further gap found (`dashboard`, `profile`,
  `notifications`, `organisation`, `users`, `registration-requests`,
  `attendance`, `leave`, `overtime`, `payroll`, `payslips`,
  `salary-rules`, `loans-bonuses`, `settlements`, `change-requests`,
  `audit`, `reports`, `login` — all confirmed complete).
- **7. No stale docs/config references**: `application.yml` appears
  nowhere outside `project-plan.md`'s own change log (intentional
  historical record, matching the project's established "keep drift on
  record, don't silently erase it" convention — §2.12/§2.16). Checked
  `PROGRESS.md`, `MODULE_RECIPE.md`, `PLAN.md`, `PROJECT_WALKTHROUGH.md`
  for any `.yml`/`.yaml` mention — none found.
- **Verification**: `npx tsc --noEmit` clean, `ng build` clean, `ng test`
  **245/245 passing** (unchanged — the `employees` route fix is an
  additive provider entry, touches no tested pure logic). Backend:
  `mvnw clean` + `mvnw compile` clean, `mvnw test` exit `0`, **155/155
  passing**, on the genuinely clean rebuild. Backend dev server restarted
  a second time (the process live-verified in §2.38 predated the
  `mvn clean` fix and was still serving from pre-clean in-memory state) —
  `GET /api/health` → `{"status":"UP"}` on the truly clean build. Live-
  verified the `employees` route fix specifically: signed in for real as
  `farhana.islam` (Admin), called all 14 endpoints
  `employee-detail.ts`/`employee-list.ts` depend on — `employees`,
  `departments`, `designations`, `shifts`, `salary-structures`,
  `leave-balances`, `attendance`, `leave-requests`, `overtime`,
  `payslips`, `loans`, `bonuses`, `settlements`, and the newly-provided
  `payroll-batches` — all returned `200` with real data. No browser tool
  in this environment, so this confirms the data contract at the
  HTTP/auth level, not pixel-level rendering, matching the documented
  limitation of every prior entry that hit the same tooling gap.
- **Status**: ✅ Done. Two real bugs found and fixed (stale build artifact,
  missing `payrollBatchesFeature` provider on `/employees`); every other
  item checked clean, no change needed. Recommendation for the next step
  follows below.

**Recommendation: Dashboard and Auth migration order.**

Dashboard (`dashboard-page.ts`) is **already migrated** — done in §2.35,
before this session's final-audit/fix/config work began. The only module
still queued from §2.17's original ordering is **Auth**
(`login-page.ts`), which was always slated to be last (highest visibility
— the unauthenticated entry point everyone must pass through first; a
regression there blocks testing everything else, per §2.17's original
dependency audit). There is no live choice between "Dashboard or Auth" to
make — Dashboard is done, so the only remaining candidate is Auth, and
nothing found in this session's audit or sanity check changes that
ordering or raises any new reason to delay it: `login-page.ts` has no
missing-provider risk (it only needs `companiesFeature`, already provided
and already confirmed working live in §2.38/§2.39), and the backend/config
work this session did (Overtime auth fix, Reports visibility, the
`pay()` idempotency fix, the properties conversion, the two provider-gap
fixes) touched no file `login-page.ts` depends on. **Recommended next
step: Auth (`login-page.ts`) migration**, the last remaining module in the
frontend architecture migration series — Step 19.

### 2.40 Registration security fix: Admin excluded from approval role list (2026-09-02)
- **Scope**: the one approved finding from the registration-form audit —
  `registration-review-form.ts`'s "System role" dropdown listed every
  system role, including Admin, with no restriction at all, so any Admin
  approving a public, unauthenticated self-registration
  (`register-page.ts`) could hand it Admin access. Nothing else from that
  audit was touched — the public form's fields, the review form's other
  fields (Employee code, Department, Designation, Shift, Employment type,
  Salary grade, Joining date, Overtime eligible), the HR-reviews/Admin-
  finalizes segregation, and the create-employee-then-create-user-then-
  record-decision chain are all byte-for-byte unchanged.
- **Fix**: new pure function `approvableRegistrationRoles(roles:
  readonly Role[]): Role[]` in `registration-rules.ts` (alongside the
  existing `canReviewRegistrations`/`canApproveRegistration`, same
  file/convention), filtering out any role named `'Admin'` and returning
  every other role unchanged, in order. `registration-review-page.ts` now
  filters `rolesFeature.selectors.all` through it (`private readonly
  allRoles` holds the raw store signal, `protected readonly roles =
  computed(() => approvableRegistrationRoles(this.allRoles()))`) before
  passing the result to `<app-registration-review-form [roles]="roles()">`
  — the template binding itself is unchanged, since the public signal name
  and call shape (`roles()`) stayed identical; only what backs it changed,
  from a direct store selector to a filtered computed. `registration-
  review-form.ts` itself was not touched — it already just renders
  whatever role list it's given, so the restriction lives in the one place
  that decides business policy (the review page), not duplicated into the
  generic form component.
- **Admin accounts remain creatable exactly as before, through the one
  intended path**: `SecurityConfig.java`'s `POST /api/users/**` stays
  Admin-only (untouched — that gate is about *who* may create *any*
  account at all, orthogonal to *which* role gets assigned, and was
  already correct). An authenticated Admin can still create another Admin
  account through the existing internal "Users & Roles → Create user"
  page (`users-page.ts`/`user-form.ts`), which was never part of this
  fix's scope and offers the full unfiltered role list exactly as it
  always has — this fix only narrows the one dropdown reachable from a
  **public, unauthenticated** self-registration's approval flow.
- **Regression test added**: `registration-rules.spec.ts` — four new
  cases for `approvableRegistrationRoles`: excludes Admin from a
  four-role list; keeps every other role (HR/Accountant/Employee)
  unchanged and in the same order; returns `[]` rather than throwing when
  the input is only Admin; returns `[]` for an empty input. Matches this
  project's convention of testing the pure decision function a component
  delegates to, not the component itself.
- **Verification**: `npx tsc --noEmit` clean. `ng build` clean. `ng test`
  **249/249 passing** (was 245, +4 new — the `approvableRegistrationRoles`
  cases; every pre-existing test, including the rest of `registration-
  rules.spec.ts`, stayed green, confirming `canReviewRegistrations`/
  `canApproveRegistration` and every other rule are unaffected). Backend:
  no file touched — this is a pure frontend UI-level restriction, and
  `SecurityConfig.java`'s existing Admin-only gate on `POST /api/users/**`
  already covers the actual account-creation authorization regardless of
  which role is requested — but `mvnw compile`/`mvnw test` were re-run per
  instruction anyway: clean, exit `0`, **155/155 passing**, unchanged.
- **Status**: ✅ Done. The registration security gap identified in the
  audit is closed; every other recommendation from that audit (Requested
  Role as optional/informational, Department/Employee ID/Emergency
  Contact left exactly where they already correctly live) was explicitly
  not implemented, per instruction — presented as a recommendation only,
  not approved for this pass.

### 2.41 Registration Request Requested Role vs Final Assigned Role (2026-09-02)
- **Scope**: the "Requested Role as optional/informational" recommendation
  from the same audit, now explicitly approved — implements the design
  reviewed and agreed in chat: the applicant states a preference
  (Employee/HR/Accountant, never Admin), the reviewer's own separate,
  already-Admin-excluded picker (§2.40) alone decides the account's real
  role. Every other recommendation from the audit (Department, Employee
  ID, Emergency Contact) remains explicitly not implemented, per
  instruction. HR-reviews/Admin-finalizes segregation and the rest of the
  workflow are byte-for-byte unchanged.
- **One shared allowed-role source, reused, not duplicated**:
  `registration-rules.ts`'s `REQUESTABLE_ROLES: RoleName[] = ['Employee',
  'HR', 'Accountant']` is the single list both dropdowns now derive from.
  `register-page.ts`'s public Requested Role select renders it directly;
  `approvableRegistrationRoles` (§2.40) now filters through
  `REQUESTABLE_ROLES.includes(role.roleName)` instead of its previous
  standalone `role.roleName !== 'Admin'` check — functionally identical
  today, but now genuinely one source instead of two independently-
  maintained "not Admin" checks that could drift apart later.
- **Frontend — public form**: `RegistrationRequest`/`RegisterPayload`
  gained `requestedRole: RoleName`, documented on both as "context/prefill
  for the reviewer only, never the provisioning authority." `register-
  page.ts`'s form gained a `requestedRole` control (default `'Employee'`,
  rendered via `REQUESTABLE_ROLES`); `submit()` is unchanged — the existing
  `getRawValue()` call already picks up the new control automatically. No
  password/organisation field was added — those stay exactly where they
  already were (approval time, Admin/HR's call).
- **Frontend — reviewer side**: new pure function
  `roleIdForRequestedRole(requestedRole, approvableRoles)` in
  `registration-rules.ts` resolves the applicant's stated preference to a
  `Role.id` from the already-filtered `approvableRegistrationRoles` list.
  `registration-review-form.ts`'s existing defaulting `effect()` (which
  already prefills department/designation/shift) now also prefills
  `roleId` this way — the reviewer sees a sensible starting selection but
  can freely change it before approving, exactly like every other prefill
  on that form. `registration-review-form.html`'s read-only summary block
  now shows "Requested role: …" alongside Name/Username/Email/etc., so the
  reviewer can see the request and the assignment side by side.
- **Backend**: new Flyway `V29__registration_request_requested_role.sql`
  — `requested_role VARCHAR(20) NOT NULL DEFAULT 'Employee'` plus a `CHECK
  (requested_role IN ('Employee', 'HR', 'Accountant'))` constraint, same
  "genuinely fixed enum gets a CHECK constraint" precedent as `leave_rule.
  leave_type` (V11) — defense-in-depth beneath the frontend dropdown and
  the DTO validation, not a substitute for either. `RegistrationRequest`
  entity and `RegisterRequest` DTO both gained `requestedRole` with
  `@NotBlank @Pattern(regexp = "Employee|HR|Accountant")` — mirrors the
  same entity's own `status` field's `@Pattern` convention exactly, so an
  invalid or Admin value is rejected by Bean Validation with a clean `400`
  before the controller method ever runs, not merely by the DB constraint
  underneath it. `RegistrationRequestController.update()`'s existing
  "these identity fields never change after creation" reset list
  (`fullName`/`email`/`phone`/etc.) now also includes `requestedRole` —
  same treatment as every other field submitted once and never editable
  after the fact.
- **Regression tests added**:
  - Frontend (`registration-rules.spec.ts`, `ng test`): `REQUESTABLE_ROLES`
    excludes Admin and contains exactly `['Employee', 'HR', 'Accountant']`;
    `roleIdForRequestedRole` resolves the correct id for each requestable
    role, demonstrates the intended "filter through
    `approvableRegistrationRoles` first, then resolve" usage even when the
    raw input contains Admin, and returns `''` rather than throwing when no
    match exists.
  - Backend (`RegistrationRequestControllerIT`, `mvnw test`): new
    `registeringWithAdminAsRequestedRoleIsRejected` (`400`, and confirms
    the row was never actually persisted — not just that the HTTP call
    failed for some unrelated reason), `registeringWithAnUnknownRequestedRoleIsRejected`
    (`400` for a nonsense value), `everyRequestableRoleIsAccepted` (all
    three of Employee/HR/Accountant succeed with `201`). Every pre-existing
    test in the file was updated to include `requestedRole` in its request/
    PUT bodies (now a required field) — the existing duplicate-prevention,
    authorization, approve/reject and audit/notification tests are
    otherwise unchanged.
- **Verification**: `npx tsc --noEmit` clean, `ng build` clean, `ng test`
  **254/254 passing** (was 249, +5 new). Backend: `mvnw compile` clean,
  `mvnw test` exit `0`, **158/158 passing** (was 155, +3 new —
  `RegistrationRequestControllerIT` alone now 11/11, was 8). Backend dev
  server restarted on the new build (with `V29` applied) for live
  verification.
- **Live-verified against the real running backend/Postgres**:
  `POST /api/auth/register` with `requestedRole: "Admin"` → real `400`
  (Bean Validation, not the DB constraint — confirmed by the response
  arriving instantly with no repository round-trip). `requestedRole:
  "Employee"` and `"HR"` → real `201`, each returning the persisted row
  with `requestedRole` correctly stored. Signed in for real as
  `farhana.islam` (Admin) and confirmed `GET /api/registration-requests`
  shows `"requestedRole"` on both pending rows exactly as submitted — the
  reviewer-visible data the review form's summary block reads. Both test
  rows deleted afterward via `psql` (confirmed `0` remaining), backend
  (`:8080`) and frontend (`:4200`) both left running and healthy.
- **Status**: ✅ Done. Requested Role vs Final Assigned Role now behaves
  exactly as reviewed and approved: a stated preference that only ever
  informs the reviewer, never provisions anything by itself.

### 2.42 Users & Roles audit, then two approved fixes: one-account-per-employee, active-only dropdown (2026-09-02)

- **Audit** (read-only turn): checked `user-form.ts`, `users-page.ts`,
  `AppUserController`, `CreateUserRequest`, `AppUser` entity, and V14's
  schema against the user's 4 clarifying questions about the Create User
  flow. Confirmed the Employee-dropdown design itself is correct,
  industry-standard practice — a login is always linked to an existing
  employee record, never created freehand. Found two real gaps:
  1. **No duplicate-prevention below the UI.** `app_user.employee_id`
     (V14) had neither `NOT NULL` nor `UNIQUE`; `AppUserController.
     create()` did a plain insert with zero duplicate check. The
     "one account per employee" rule existed only as a client-side
     dropdown filter (`existingEmployeeIds` in `users-page.ts`) — the
     same bug class already fixed via partial/plain unique indexes for
     Bonus (V25), Attendance (V25), Leave (V26), Change Requests (V27)
     and Settlement (V24), but never applied here.
  2. **No status filter on the Employee dropdown.** `eligibleEmployees()`
     in `user-form.ts` only excluded already-linked employees, never
     checking `status` — a `separated` employee (already left the
     company) was a selectable candidate for a brand-new login account.
- **Approved fixes** (both, no other changes):
  1. `V30__app_user_employee_unique.sql` — `CREATE UNIQUE INDEX
     uq_app_user_employee_id ON app_user (employee_id)`. No controller
     change needed: `ApiExceptionHandler`'s existing generic "unique"
     branch already turns the resulting `DataIntegrityViolationException`
     into a clean `409` with message "A record with the same unique
     value already exists." — the same pattern every prior duplicate-
     prevention fix in this project relies on.
  2. `user-form.ts`'s `eligibleEmployees` computed now filters to
     `emp.status === 'active'` in addition to the existing
     already-has-an-account exclusion — `draft`, `inactive` and
     `separated` employees no longer appear in the Create User dropdown.
- **Regression tests**: `UsersRolesPermissionsIT.java` — every test in
  the file previously reused seeded demo employee `e1`, which already has
  a real `app_user` row (`nasrin.akter`) from V14's own seed; under the
  new unique index every one of those tests would now fail on insert.
  Replaced with a dedicated, account-free fixture employee
  (`test-emp-users-it`, created in a new `@BeforeEach`/torn down in
  `@AfterEach`, mirroring `EmployeeControllerIT`'s existing fixture
  pattern) so the file's own tests don't collide with the constraint
  they're meant to be protected by. Added
  `creatingASecondAccountForTheSameEmployeeReturns409` — creates one
  account against the fixture employee, asserts a second create for the
  same `employeeId` returns `409`, and asserts the rejected duplicate was
  never persisted. No frontend spec added for the dropdown filter —
  `user-form.ts` is a page/component `.ts` file, verified live instead,
  per this project's established convention (pure logic in `*-rules.ts`
  gets `*-rules.spec.ts`; component classes don't).
- **Verification**: `npx tsc --noEmit` clean, `ng build` clean, `ng test`
  **254/254 passing** (unchanged — no rules-file logic changed). Backend:
  `mvnw compile` clean, `mvnw test` exit `0`, **159/159 passing** (was
  158, +1 new). Backend dev server restarted on the new build; Flyway log
  confirmed `Current version of schema "public": 30`.
- **Live-verified against the real running backend/Postgres**: signed in
  as `farhana.islam` (Admin), `POST /api/users` with `employeeId: "e1"`
  (already linked to `nasrin.akter`) → real `409`, body `{"status":409,
  "error":"Conflict","message":"A record with the same unique value
  already exists.","path":"/api/users"}`. No row left behind (`DELETE`
  on the attempted id returned `404`, confirming nothing was inserted).
- **Status**: ✅ Done. Create User can no longer produce two login
  accounts for the same employee, and the Employee dropdown can no
  longer offer a separated, draft or inactive employee as a candidate
  for a new account. Employee-dropdown design and Create User workflow
  otherwise unchanged.

### 2.43 Registration Request review: Employee Code auto-suggest (2026-09-02)

- **Context**: on `registration-review-form.ts` (Admin → Registration
  Request → Review → Approve), Admin had to manually work out the next
  employee code by eyeballing the employee list — no suggestion existed
  anywhere in the codebase. Inspected first: `employee.employee_code`
  already carries a DB `NOT NULL UNIQUE` constraint (V3) and
  `EmployeeController`'s entity already has `@NotBlank`, with
  `ApiExceptionHandler`'s existing generic "unique" branch already
  turning a duplicate insert into a clean `409` — so backend-side
  uniqueness validation needed no new code, only confirmation it already
  covers this field the same way it covers every other unique column in
  the project.
- **Implemented** (frontend only, minimal):
  - `registration-rules.ts` — added `nextEmployeeCode(employees)`: takes
    the highest **purely numeric** existing `employeeCode` and returns
    `String(highest + 1)`; non-numeric codes (the demo seed's
    `DEMO-ADMIN`, or any manually-chosen code) are ignored rather than
    breaking the suggestion; returns `''` (no suggestion) if no numeric
    code exists yet, rather than inventing a starting number. A gap left
    by a deleted/renumbered employee is never reused — only the highest
    code seen is ever used, matching the exact rule requested.
  - `registration-review-form.ts` — added an `employees` input; the
    existing constructor `effect()` (which already prefills
    department/designation/shift/role) now also prefills `employeeCode`
    with `nextEmployeeCode(employees())`. Field stays a plain editable
    `<input>` — no lock — so Admin can override it when there's a real
    reason to. Added a `codeTaken` guard (same shape as `user-form.ts`'s
    `usernameTaken`) checking the typed value against every existing
    employee's code, client-side, before submit — the DB constraint is
    still the actual authority, this is just an earlier, friendlier
    error.
  - `registration-review-form.html` — shows the suggestion as a small
    hint line under the field, and the duplicate-code error inline, same
    pattern as every other form's validation messages.
  - `registration-review-page.ts`/`.html` — added the `employees`
    selectSignal (the collection was already being loaded for
    `onApprove`'s own dispatch, just not read anywhere) and passed it
    into the form.
- **Regression tests**: `registration-rules.spec.ts` — 5 new tests for
  `nextEmployeeCode` (highest-plus-one, ignores non-numeric codes, never
  reuses a gap, empty when no numeric code exists, ignores zero/negative
  values). No backend test added — no backend code changed; the existing
  `EmployeeControllerIT` coverage of the unique-code constraint (via
  `ApiExceptionHandler`'s generic branch) already covers this path.
- **Verification**: `npx tsc --noEmit` clean, `ng build` clean, `ng test`
  **259/259 passing** (was 254, +5 new). Backend: `mvnw compile` clean
  (no Java files touched, so the full `mvnw test` run from §2.42,
  **159/159**, still stands).
- **Live-verified against the real running backend/Postgres**: created a
  real employee with `employeeCode: "5000"` via the API, confirmed the
  suggestion math against the live employee list resolves to `5001` —
  the exact example given in the request. A second create attempt with
  the same code (`"5000"`) → real `409` from the existing DB constraint.
  Test employee deleted afterward (`204`).
- **Status**: ✅ Done. Employee Code is now auto-suggested from the real
  employee list on the Registration Request review form, stays editable,
  and is validated for uniqueness both client-side (friendly, instant)
  and server-side (the actual authority, unchanged and already correct).

### 2.44 Registration Request review UX pass: Employee Code, Role, Salary Grade (2026-09-02)

- **Employee Code**: unchanged — confirmed §2.43's editable input +
  auto-suggestion (highest existing numeric code + 1) is already exactly
  the requested shape; not converted to a dropdown, per instruction.
- **Select a Role**: verified, not changed — `registration-review-form.
  html`'s role `<select>` iterates only the `roles()` input, which
  `registration-review-page.ts` already sets to `approvableRegistration
  Roles(this.allRoles())` (§2.40/§2.41). Confirmed Admin cannot reach
  this list: `approvableRegistrationRoles` filters through
  `REQUESTABLE_ROLES = ['Employee', 'HR', 'Accountant']`
  (`registration-rules.ts`), and there is no second, unfiltered role
  source anywhere in the template. No code change needed — already
  correct.
- **Salary Grade**: converted from free-text `<input>` to a `<select>`.
  Inspected the data source first: there is no dedicated salary-grade
  catalog anywhere in the backend (`employee.salary_grade` is a plain
  string column, no FK, no lookup table) and `salary-rules-page.ts`'s
  own collections (salary structures, tax slabs, PF rules) don't cover
  it either — the only real "predefined grades" are the distinct values
  already used across the live employee list. Added
  `existingSalaryGrades(employees)` to `registration-rules.ts`
  (dedupes + sorts `employee.salaryGrade`, ignoring blanks) and used it
  to populate the new `<select>` — reusing the real data instead of
  hardcoding a second list. The old `GRADE_PAY` mock-seed constants
  (`core/mock-db/seed/pay.ts`, grades `M1`–`W3`) were deliberately not
  reused: they're a disconnected legacy fixture, not reachable from the
  real backend, and reusing them would itself have been "a hardcoded
  duplicate list" of the kind the request asked to avoid.
- **Files changed**: `registration-rules.ts` (`existingSalaryGrades`),
  `registration-review-form.ts` (`salaryGrades` computed),
  `registration-review-form.html` (input → select).
  `registration-review-page.ts`/`.html` untouched — `employees` was
  already wired through in §2.43.
- **Regression tests**: `registration-rules.spec.ts` — 3 new tests for
  `existingSalaryGrades` (dedupes + sorts, ignores blanks, empty list
  when no employee exists yet).
- **Verification**: `npx tsc --noEmit` clean, `ng build` clean, `ng test`
  **262/262 passing** (was 259, +3 new). No backend file touched.
- **Status**: ✅ Done. Employee Code and role restriction confirmed
  already correct and left untouched; Salary Grade is now a dropdown
  sourced from the real employee list, no new hardcoded options. Existing
  approve/reject business logic unchanged.

### 2.45 Registration Request review: Salary Grade derived from Designation, not independently selected (2026-09-02)

- **Context**: reviewed Department/Designation/Salary Grade architecture
  before implementing (per instruction, a recommendation-only turn
  first). Found Department and Designation dropdowns were already fully
  real-backend-driven (done earlier, no gap). Found Designation has no
  `deptId` — filtering it by Department isn't possible without a schema
  change, so not implemented (flagged as a separate decision, not taken
  up here). Found the real salary-grade master this project already has:
  `Designation.grade` (`designation` table, DB-backed, managed by Admin
  on `organisation-page.ts` — the correct master-data area) — better
  than §2.44's employee-list-derived dropdown, which only echoed grades
  already in use rather than reading the actual catalog. Recommended
  **not** creating a new `SalaryGrade` table (would duplicate
  `Designation.grade`) and offered two options; user chose auto-derive.
- **Implemented**: Salary Grade is no longer an independent form field.
  `registration-rules.ts` — new `gradeForDesignation(designationId,
  designations)`, a plain lookup returning `''` when nothing is selected
  or the selected designation has no grade set. `registration-review-
  form.ts` — removed the `salaryGrade` form control and its
  `Validators.required` entirely (no more separate validation that could
  disagree with the Designation); added `selectedDesignationId` (a
  `toSignal` view of the Designation control's own live value) and
  `derivedSalaryGrade`/`gradeMissing` computed signals; `submit()` blocks
  on `gradeMissing()` and merges the derived value into the emitted
  `RegistrationApproval` (whose shape is unchanged — `registration-
  review-page.ts` and the Employee-create it dispatches needed no
  changes). `registration-review-form.html` — Salary Grade is now a
  `readonly` input showing the derived value or "No grade set for this
  Designation" (the shared empty state for both "nothing selected" and
  "selected designation has no grade"), with an inline error only once
  Admin has attempted to submit with no grade available. Removed §2.44's
  now-dead `existingSalaryGrades` (and its 3 tests) — fully superseded.
- **Regression tests**: `registration-rules.spec.ts` — 4 new tests for
  `gradeForDesignation` (resolves the selected designation's grade, empty
  when nothing selected, empty when the designation has no grade, empty
  rather than throwing for an unknown id).
- **Verification**: `npx tsc --noEmit` clean, `ng build` clean, `ng test`
  **263/263 passing** (was 262, net +1: −3 removed, +4 added). No
  backend file touched — `RegistrationApproval`'s shape, and everything
  downstream of it, is unchanged.
- **Status**: ✅ Done. Salary Grade can no longer disagree with the
  selected Designation — it is read off `Designation.grade` directly, the
  one real master this project has for it, with no new table and no
  separate selection to get out of sync.

### 2.46 Final Settlement end-to-end audit, then two confirmed fixes: server-side transition guard + auto loan-closure/separation (2026-09-02)

- **Audit** (role-by-role, frontend + backend + DB + live trace):
  role split already matches HR-initiates/Accountant-decides/Admin-
  oversight-only exactly, self-approval blocked
  (`canDecideSettlement`), one-open-settlement-per-employee enforced at
  the DB layer (`uq_final_settlement_open_employee`, V24), completed
  settlements genuinely immutable (`SettlementService.assertMutable`),
  audit logging complete (actor/role/action/id/amount/reason). Two real
  gaps found and **live-verified** against the running backend/Postgres:
  1. **Critical**: completing a settlement via a direct `PUT`
     (bypassing `settlement-detail.ts`'s own client code) left the
     employee `active` and their loans untouched — closing loans and
     separating the employee were entirely frontend-orchestrated side
     effects, not backend-enforced. Live-verified: completed a test
     settlement via raw `curl`, then confirmed the employee's status
     stayed `active` — a genuine double-payment risk, since
     `runPayroll` only excludes `separated` employees.
  2. A `rejected` settlement could be `PUT` straight to `completed`,
     skipping the rule that a decision must start from `pending` —
     `SettlementService` only ever checked whether the *existing* row
     was already completed, never what the *incoming* status was
     allowed to become. Live-verified: rejected a test settlement, then
     `PUT` it again with `status: "completed"` — succeeded (`200`).
  One design question surfaced (PF/approved-but-unpaid bonus not
  factored into the settlement calculation) and one UX gap (employee
  picker had no status filter, same class as §2.42/§2.44) — flagged in
  the audit; only the UX gap was in the "fix now" set, the calculation
  question needs separate scope confirmation.
- **Fixed**:
  1. `SettlementService.update()` — new `assertLegalTransition`: a
     settlement may only move to `completed`/`rejected` from `pending`.
     On completion, `closeOutstandingLoans` (new `LoanRecordRepository.
     findByEmployeeIdAndStatus`) and `separateEmployee` now run in the
     same transaction as the status change — no longer solely the
     frontend's job.
  2. `settlement-detail.ts` — removed the now-redundant client-side
     loan-`upsertMany` dispatch and the manual `/employees/{id}/separate`
     PATCH call (the backend does both atomically now); `approve()`/
     `reject()` gate the audit-log entry and employee notification
     behind the settlement `upsertSuccess` action (same
     `actions$.pipe(ofType(...), take(1))` pattern already used in
     `registration-review-page.ts`) instead of firing unconditionally —
     an `errorBanner` surfaces a failed decision instead of silently
     logging/notifying a false outcome.
  3. `settlement-form.ts`/`.html` — new `eligibleEmployees` computed
     filters the "Initiate settlement" employee picker to
     `status === 'active'`, same fix shape as §2.42's Create User
     picker.
- **Regression tests**: `FinalSettlementControllerIT.java` — 2 new
  tests: `aRejectedSettlementCannotBeDirectlyCompleted` (the exact live-
  reproduced bypass, now `409`) and
  `completingASettlementAutomaticallyClosesActiveLoansAndSeparatesThe
  Employee` (dedicated fixture employee + active loan, completes via
  `PUT`, then asserts the employee is `separated` and the loan is
  `closed`/`0.00`). `pendingSettlementCanStillBeCompletedWithPayment
  Details` updated to use a dedicated fixture employee instead of the
  shared demo account `e4` — completion now has a real side effect
  (separation), so it can no longer safely share a demo login's
  employee record. No frontend spec added — `settlement-detail.ts`/
  `settlement-form.ts` are component `.ts` files, verified live instead,
  per this project's established convention.
- **Verification**: `npx tsc --noEmit` clean, `ng build` clean, `ng test`
  **263/263 passing** (unchanged — no rules-file logic changed). Backend:
  `mvnw compile` clean, `mvnw test` exit `0`, **161/161 passing** (was
  159, +2 new). Backend dev server restarted on the new build.
- **Live-verified end-to-end against the real running backend/Postgres**:
  traced one full realistic settlement — HR initiates (`201`) →
  Accountant completes with payment details (`200`) → employee
  auto-`separated` (confirmed via `GET`) → the employee's active loan
  auto-`closed`, `outstandingBalance: 0.00` (confirmed via `GET`) →
  further edits to the completed settlement `409` → a second open
  settlement for the same (now separated) employee `409`. Separately
  re-ran the exact reject-then-complete bypass that succeeded before the
  fix — now `409`, `"Only a pending settlement can be approved or
  rejected."`. All ephemeral employees/loans/settlements deleted
  afterward via `psql`.
- **Status**: ✅ Done. Final Settlement can no longer leave a paid-out
  employee `active` (closing the double-payment risk) or resurrect a
  rejected settlement into a completed one. Role design, audit logging,
  and DB-level duplicate prevention were already correct and are
  unchanged. PF/bonus inclusion in the settlement calculation remains an
  open design question, not implemented.

### 2.47 PF/Bonus design audit, then Bonus implemented (PF deliberately not) (2026-09-02)

- **Audit** (recommendation-only turn first): traced PF through
  `payroll-engine.ts` and found there is no PF ledger anywhere in this
  project — `employerContributionPct` is used only for a cost-reporting
  figure (`reports-page.ts`), never accumulated or stored; each cycle's
  employee contribution is deducted and gone. **Recommendation: do not
  include PF in Final Settlement** — there is no accumulated balance to
  pay out; building one would be a genuine new feature (a real per-
  employee PF fund ledger), not a settlement-calculation change, and the
  user confirmed not to build it. Traced Bonus through `payroll-engine.ts`
  and `BonusRecord` (no `paid` status — only `pending/approved/rejected`)
  and found the real gap: an approved bonus whose `paymentDate` never
  reached a payroll cycle before the employee separates is permanently
  stranded — `runPayroll` never processes a `separated` employee again.
  **Recommendation, approved**: settle it as its own positive line item,
  distinguishing paid/unpaid/pending/rejected exactly as specified.
- **Implemented** (backend + frontend, reusing existing architecture,
  no new tables):
  - `V31__settlement_bonus_encashment.sql` — `final_settlement.
    bonus_encashment` (NUMERIC, default 0) and `bonus_record.
    settlement_id` (nullable FK to `final_settlement`, the actual
    double-payment guard — see below).
  - `FinalSettlement`/`BonusRecord` entities — new fields, matching
    doc comments explaining why `bonusEncashment` is a separate line
    item that **adds** to `netSettlementAmount`, never folded into
    `pendingDues` (money owed BY the employee).
  - `SettlementService` — three new pieces, all inside the existing
    `update()` transaction, same "recompute the real state at
    completion time, don't trust the client's initiation-time snapshot"
    pattern already used for loan closure (§2.46):
    1. `assertNoPendingBonuses` — blocks completion with a `409` while
       any bonus for the employee is still `pending`.
    2. `claimUnpaidApprovedBonuses` — for every `approved` bonus not
       already claimed (`settlementId == null`), checks whether it was
       already disbursed through a `paid` `PayrollBatch` whose cycle
       covers its `paymentDate` (mirrors `payroll-engine.ts`'s own
       inclusion rule exactly, cross-referencing real `Payslip`/
       `PayrollBatch` rows, not just `BonusRecord.status` — there is no
       `paid` flag on the bonus itself). If not, claims it by setting
       `settlementId`. Already-claimed bonuses are always skipped —
       this field, not the client-supplied `bonusEncashment` figure, is
       the actual mechanism that prevents double payment, including
       across settlement recalculations.
    3. New repository finders: `LoanRecordRepository`-style
       `BonusRecordRepository.findByEmployeeIdAndStatus`,
       `PayslipRepository.findByEmployeeId`.
  - `settlement-rules.ts` — `isBonusAlreadyDisbursed`,
    `unpaidApprovedBonuses`, `bonusEncashmentAmount`,
    `hasUndecidedBonus`; `netSettlementAmount` gained a 5th
    `bonusEncashment` parameter (defaults to 0, existing 3–4 arg call
    sites unchanged).
  - `settlement-form.ts`/`.html` — new `bonuses`/`payslips`/
    `payrollBatches` inputs, live "Unpaid approved bonus" breakdown line
    and a pending-bonus warning (mirrors the backend block, surfaced
    before the request even goes out); `settlements-page.ts`/`.html`
    wire the three new collections through (already loaded elsewhere in
    the app, just not previously read here).
  - `settlement-detail.ts`/`.html`, `settlements-page.html` — display
    the `bonusEncashment` line item; `approve()` now also reloads
    `bonusesFeature` after a successful completion.
  - `core/models/hr.ts` — `FinalSettlement.bonusEncashment`,
    `BonusRecord.settlementId`.
- **Found and fixed a real tooling gap while verifying**: this session's
  bare `npx tsc --noEmit` checks had been silently checking **zero
  files** all along — the root `tsconfig.json` is a solution-style
  config (`"files": []`, only project references), and plain `tsc`
  (not `tsc -b`) against it type-checks nothing. Switched to
  `npx tsc --noEmit -p tsconfig.app.json` / `-p tsconfig.spec.json`,
  which caught two real fixture gaps immediately (`core/mock-db/seed/
  pay.ts`, `settlement-rules.spec.ts`, both missing the new required
  `bonusEncashment` field) — both fixed. `ng build`/`ng test` were
  unaffected by this and had been reliable all along (Angular's own
  build resolves the correct tsconfig); only the supplementary bare
  `tsc` checks were vacuous.
  - **Not implemented**: PF is untouched, per explicit instruction — no
    ledger, no PF settlement line, no behavior change.
- **Regression tests**: `settlement-rules.spec.ts` — 17 new tests
  (`isBonusAlreadyDisbursed`, `unpaidApprovedBonuses`/
  `bonusEncashmentAmount` covering all 5 cases — paid/approved-unpaid/
  pending/rejected/already-claimed — `hasUndecidedBonus`,
  `netSettlementAmount`'s new parameter). `FinalSettlementControllerIT.
  java` — 5 new tests, one per case from the request: claims an
  approved-unpaid bonus; does not claim one already disbursed through a
  paid payroll cycle; blocks completion on a pending bonus (and confirms
  nothing else changed); unaffected by a rejected bonus; a bonus already
  claimed by an earlier (real, FK-satisfying) settlement is never
  reclaimed.
- **Verification**: `npx tsc --noEmit -p tsconfig.app.json` and
  `-p tsconfig.spec.json` both clean, `ng build` clean, `ng test`
  **280/280 passing** (was 263, +17 new). Backend: `mvnw compile` clean,
  `mvnw test` exit `0`, **166/166 passing** (was 161, +5 new). Backend
  dev server restarted on the new build; Flyway log confirmed schema
  version 31.
- **Live-verified against the real running backend/Postgres, all 5
  requested cases**: (1) *paid bonus* — approved bonus with a
  `paymentDate` inside a real `paid` batch's cycle (with a matching
  payslip) → completing the settlement left it unclaimed
  (`settlementId: null`), confirming no double payment. (2) *approved
  unpaid bonus* — two approved, never-disbursed bonuses → both claimed
  (`settlementId` set to the real settlement id) on completion.
  (3) *pending bonus* — completion attempt while a bonus was still
  `pending` → real `409`, "approve or reject it before completing the
  settlement"; approving it then let completion proceed. (4) *rejected
  bonus* → excluded throughout (`settlementId` stayed `null`).
  (5) *duplicate/double-payment prevention* — demonstrated by case 1
  (an approved-and-payroll-paid bonus never gets claimed) and by
  `aBonusAlreadyClaimedByAnEarlierSettlementIsNeverReclaimed`'s
  integration coverage (a bonus pre-claimed by one settlement keeps
  that `settlementId` through a second settlement's completion, never
  reassigned). Both traced employees correctly ended up `separated`.
  All ephemeral employees/bonuses/settlements/payslips/batches deleted
  afterward via `psql`.
- **Status**: ✅ Done. Bonus is now correctly settled per the approved
  design; PF is untouched, exactly as instructed.

### 2.48 Audit Log + Reports end-to-end audit, then 3 confirmed fixes (2026-09-02)

- **Audit** (two parallel read-only investigations, recommendation-only
  turn first): Audit Log — 22 frontend call sites cover every major
  module, rejection reasons consistently included, `PUT`/`DELETE`
  already correctly Admin-only. Two confirmed, live-verified gaps:
  `GET /api/audit-logs` was `ALL_ROLES` (every role could read the full
  trail via raw API despite the page being Admin-only), and
  `POST /api/audit-logs` trusted client-supplied `actorRole`/`actorName`
  verbatim — live-verified an authenticated Employee could POST a
  fabricated entry claiming to be Admin. Reports — calculations
  live-recomputed by hand against real payslip/PF-rule data, exact
  match; no duplicate-counting, no mock data, no NaN/crash risk on
  missing config. One gap: `module-registry.ts`'s own comment claims
  domain-scoped visibility ("HR: headcount/leave/overtime; Accountant:
  tax/PF") but `reports-page.ts` had zero role checks — every role saw
  identical content, including full employee-level Tax/PF detail.
- **Fixed**:
  1. `SecurityConfig.java` — new `GET /api/audit-logs/**` rule
     (`hasAuthority(ADMIN)`), inserted before the generic `GET /api/**`
     catch-all so it actually takes effect (first-match-wins). Class
     Javadoc updated — `audit-logs` moved out of the "deliberately left
     broad" list into its own documented exception.
  2. `AuditLogController.create()` — now takes `Authentication`, derives
     `actorName`/`actorRole` from the authenticated `AppUser` principal
     (already resolved and verified by the pre-existing `JwtAuthFilter`,
     which runs globally via `addFilterBefore` — confirmed, not scoped
     to one endpoint despite its own now-stale class comment, untouched
     here as out of scope), overwriting whatever the request body
     claims. `action`/`details`/`outcome`/`moduleName`/`timestamp` all
     pass through unchanged.
  3. `reports-page.ts`/`.html` — new `canSeeTaxPf` computed
     (`['Accountant','Admin'].includes(session.role())`); the two Tax/PF
     KPI tiles and all four Tax/PF section-cards (cycle + per-employee
     detail, both Tax and PF) now render only inside `@if (canSeeTaxPf())`.
     Headcount, audit-activity, payroll-cycle, and leave/overtime
     sections — HR's own legitimate domain — left exactly as they were,
     unconditional.
- **Regression tests**: `AuthorizationIT.java` — 2 new tests:
  `onlyAdminCanReadAuditLogs` (all 4 roles, Employee/HR/Accountant `403`,
  Admin not-forbidden) and `anEmployeeCannotForgeAnAdminIdentityInAn
  AuditLogEntry` (Employee POSTs a body claiming `actorRole: "Admin"`,
  `actorName: "farhana.islam"` → `201`, but the persisted/returned row
  shows the real `Employee`/`tanvir.ahmed`, with `action`/`details`
  unchanged). Existing `everyRoleCanWriteAnAuditLogEntryButOnlyAdminCan
  PutOne`'s stale comment (claiming GET stays open) corrected. No
  frontend spec added for `canSeeTaxPf` — `reports-page.ts` is a
  component `.ts` file with the logic inline, verified live instead,
  per this project's established convention.
- **Verification**: `npx tsc --noEmit -p tsconfig.app.json` and
  `-p tsconfig.spec.json` both clean, `ng build` clean, `ng test`
  **280/280 passing** (unchanged — no `*-rules.ts` logic changed).
  Backend: `mvnw compile` clean, `mvnw test` exit `0`, **168/168
  passing** (was 166, +2 new). Backend dev server restarted on the new
  build.
- **Live-verified against the real running backend/Postgres, all 4
  roles**: `GET /api/audit-logs` — Employee `403`, HR `403`, Accountant
  `403`, Admin `200`. `POST /api/audit-logs` as Employee with a forged
  `actorRole: "Admin"`/`actorName: "farhana.islam"` body → `201`, but
  the response (and Admin's own subsequent `GET` of the same row) shows
  `actorRole: "Employee"`, `actorName: "tanvir.ahmed"` — the real
  identity, forgery blocked; `action`/`details` preserved verbatim. Test
  entry deleted afterward via `psql`. Frontend dev server (Vite, `:4200`)
  confirmed still serving without a compile error after the
  `reports-page.ts`/`.html` change — full visual role-based rendering
  confirmation isn't possible in this environment (no browser-automation
  tool available here, consistent with every prior UI-visual-check
  request this session), so the Reports fix's correctness rests on the
  same code-level + build/typecheck verification as every other
  role-gate already shipped this session (e.g. `canApproveSettlement`,
  `canInitiateSettlement`), not a rendered screenshot.
- **Status**: ✅ Done. Audit Log reads and identity are now
  server-enforced, not just UI-hidden; Reports' Tax/PF detail is scoped
  to Accountant/Admin, matching the design the code already documented.
  Audit Log coverage/rejection-reason logging/`PUT`/`DELETE` restrictions
  and every Reports calculation are unchanged.

### 2.49 Full Admin-role end-to-end audit across every module, then 6 confirmed fixes (2026-09-02)

- **Audit** (4 parallel investigations covering all 18 modules; this
  session's already-fixed/confirmed-correct items — Registration,
  Users & Roles, Settlement, Audit Log, Reports, Bonus decision
  authority — explicitly excluded from re-review). 8 confirmed findings;
  6 fixed now (contained, live-testable), 1 deferred (Change
  Request/Leave unconditional client-side side effects — real, but the
  largest diff for the lowest incremental risk; same fix shape as
  Settlement §2.46, needs its own scoped turn), 1 folded into an
  existing fix (Notification IDOR's create-scoping was intentionally
  left open — see below).
- **Fixed**:
  1. **Notification IDOR (critical)** — `NotificationController`: `GET`
     (list + by-id) and `PUT`/`DELETE` now scoped to the authenticated
     principal's own `userId`, or Admin. Live-verified before the fix:
     an Employee could read every user's notifications (financial
     figures, HR decisions) and overwrite another user's notification
     content. `create()` deliberately left open — notifying *someone
     else* is this module's entire purpose.
  2. **Payslip IDOR (critical)** — `PayslipController`: `GET` (list +
     by-id) now scoped to the caller's own `employeeId` for the
     Employee role; HR/Accountant/Admin keep full cross-employee
     visibility (legitimately needed for payroll processing/reports).
     Live-verified before the fix: any Employee could read every other
     employee's full payslip breakdown via a raw `GET`.
  3. **Loan decision-authority bypass (high)** — `LoanRecordService`:
     new `assertDecisionAuthority` — a transition *out of* `pending`
     into `approved`/`rejected` now requires the caller to be HR,
     closing the gap the `HR_ACCOUNTANT_ADMIN` `PUT` union
     (legitimately needed for Accountant/Admin's separate loan-*closure*
     during payroll, `batch-detail.ts`'s `pay()`) accidentally also
     opened for the *decision* itself. Live-verified before the fix:
     Admin could `PUT` a still-pending loan straight to `approved`,
     bypassing HR entirely.
  4. **Leave: no transition guard (high)** — new `LeaveRequestService`
     (same shape as `ChangeRequestService`): once `approved`/`rejected`,
     immutable. Live-verified before the fix: an already-decided leave
     request could be flipped again via a direct `PUT`, unlike every
     sibling decision-bearing module. The batch `PUT` endpoint stays
     plain `saveAll` (unguarded) — it's genuinely used by
     `leave-page.ts` for new-request inserts (confirmed by an existing
     test), not by the decision flow, which always goes through the
     now-guarded single-record `PUT`.
  5. **Payslip immutability gap (medium)** — `PayslipController.
     create()` now calls `payrollBatchService.assertBatchMutable(...)`,
     matching the guard `PUT`/`DELETE` already had. New
     `V32__payslip_unique_batch_employee.sql` —
     `uq_payslip_batch_employee` unique index (verified no existing
     duplicates before adding).
  6. **Organisation delete UX/wrong error (low)** — `organisation-
     page.ts`'s three delete-confirmation dialogs (Department/
     Designation/Shift) now state the true behavior (blocked while
     referenced) instead of falsely claiming safe deletion.
     `ApiExceptionHandler` now distinguishes Postgres's "is still
     referenced from table" (delete blocked by a child row) from "is
     not present in table" (insert/update referencing a missing parent)
     — previously both produced the same, backwards-for-a-delete
     message.
- **Regression tests**: `NotificationControllerIT.java` (new, 6 tests),
  `PayslipControllerIT.java` (+3: cross-employee `GET`/list blocked,
  `POST` into a paid batch blocked), `LoanRecordControllerIT.java` (+2:
  Admin/Accountant blocked from deciding a pending loan, Accountant
  still can close an active one), `LeaveRequestControllerIT.java` (+1:
  re-decision blocked), `OrganisationDeleteBlockedIT.java` (new, 1
  test: real `dept-demo` delete-blocked message). One self-caught test
  bug: `LeaveRequestControllerIT`'s new test first asserted `DELETE`
  as HR expecting `409`, forgetting `DELETE` is Admin-only at the
  `SecurityConfig` layer (`403` before the service guard is ever
  reached) — fixed to use `adminToken()`.
- **Verification**: `npx tsc --noEmit -p tsconfig.app.json` and
  `-p tsconfig.spec.json` both clean, `ng build` clean, `ng test`
  **280/280 passing** (unchanged — only `organisation-page.ts`'s
  confirm-dialog copy changed on the frontend, no rules-file logic).
  Backend: `mvnw compile` clean, `mvnw test` exit `0`, **181/181
  passing** (was 168, +13 new). Backend dev server restarted on the new
  build; Flyway log confirmed schema version 32.
- **Live-verified against the real running backend/Postgres, all 6
  fixes**: Employee `GET /api/notifications` → only their own 6 rows
  (was every user's). Employee `GET /api/payslips` → only their own 5
  rows (was every employee's). HR creates a pending loan → Admin `PUT`
  to `approved` → real `403`, `"Only HR can approve or reject a loan
  request."`. HR approves a leave request → second `PUT` flipping it to
  `rejected` → real `409`. `DELETE /api/departments/dept-demo` (still
  referenced by the seeded demo employees) → real `409`, `"This record
  is still in use elsewhere and cannot be deleted."` (previously the
  wrong, backwards message). `POST /api/payslips` into a real `paid`
  batch → real `409`, `"A paid payroll batch is immutable and cannot be
  changed."`. All ephemeral loans/leave-requests/payslips/batches
  deleted afterward via `psql`. Separately confirmed: a real Admin
  notification row one investigating fork briefly tampered with during
  its own live-verification (per its report) was correctly restored to
  legitimate content — spot-checked via `psql` after the fact.
- **Status**: ✅ Done for the 6 fixed items. Deferred, not implemented:
  Change Request/Leave's unconditional client-side side-effect dispatch
  (item 7 in the audit) — flagged for a future, separately-scoped fix,
  same shape as Settlement §2.46.

---

## Suggested order of work

**Retired, 2026-09-01** — every numbered item below described work that is
now fully done (frontend submission modules, the Spring Boot/Postgres
skeleton, entities/schema/seed data, every CRUD module, real auth, reports,
bank file export). Items 5/6/7's "port to Java" framing also predates and
contradicts the §2.5 architecture decision to keep business logic in
Angular — kept struck through, not deleted, so the "we once considered
porting the engine" history stays on record; do not act on it.

1. ~~Finish frontend submission-half modules (§1.9)~~ — done
2. ~~Stand up Spring Boot + local PostgreSQL skeleton (§2.1)~~ — done
3. ~~Auth deliberately deferred~~ — done, real BCrypt+JWT, frontend wired (§2.3)
4. ~~Entities + real Flyway schema + seed data (§2.2)~~ — done, `V1`–`V26`
5. ~~Port Leave + Overtime~~ — done as dumb CRUD instead, per §2.5 — never ported, and correctly so
6. ~~Payroll Engine port~~ — deliberately never done; the engine stays in Angular (§2.5)
7. ~~Remaining CRUD modules~~ — done, every collection real-backed (§2.4)
8. ~~Reports, bank file export, real PDF/notification dispatch~~ — done (client-side PDF/reports by design, in-app notifications real, email/SMS deferred pending a provider choice)
9. ~~Loan-to-active conversion and EMI payroll deduction~~ — done, see §1.8
10. ~~Auth API resumes~~ — done, see §2.3

### 2.50 Full payroll-priority audit, 7 confirmed fixes, plus two live-reported auth bugs (2026-09-02)

- **Audit** (priority order per the ask: Salary/Rules → Attendance/Late/Leave
  → Overtime → Loan/EMI → Bonus → PF/Tax → Payroll Batch → Payslip → Payment
  → Reports/Audit), three parallel investigations covering the areas this
  session's own reading (payroll-engine.ts, attendance-rules.ts,
  PayrollBatchService, SecurityConfig) hadn't already directly reviewed.
  Confirmed correct and unchanged: PF/tax percentage-bound validation, bonus
  duplicate-request prevention (V25), settlement immutability/loan-closure/
  employee-separation (§2.46), audit log scoping (§2.48), registration's
  isolation from the employee/payroll tables. 7 confirmed real bugs, all
  fixed:
  1. **Leave/Change Request decision race (data corruption)** — closes the
     item 7 gap §2.49 deferred. `leave-detail.ts`/`change-request-detail.ts`
     dispatched the balance write / employee-field write / audit log /
     notification *unconditionally*, immediately after dispatching the
     decision itself — never waiting for it to actually succeed. A
     concurrent decider (the backend's own already-decided guard, added in
     §2.49) 409s the losing request, but the balance/employee-field write
     fired anyway, corrupting real data behind a decision that never
     persisted. Fixed to the same wait-for-`upsertSuccess`/`upsertFailure`
     pattern `settlement-detail.ts` already used (§2.46).
  2. **Settlement self-approval (IDOR)** — `canDecideSettlement`
     (`settlement-rules.ts`) blocks a decider from ruling on their own
     settlement, client-side only until now. `SettlementService` gained
     `assertNotSelfApproval`: an Accountant/Admin account tied to the same
     `employeeId` as the settlement under decision can no longer `PUT` it
     to `completed`/`rejected` themselves via a raw API call.
  3. **Payment created for a non-approved batch** — `PaymentController.
     create()` had no batch-state check at all, unlike `update`/`delete`.
     New `PayrollBatchService.assertBatchApprovedForPayment`: a Payment can
     now only be recorded once the batch is `approved`, matching what
     `batch-detail.ts`'s `pay()` already only ever does through the UI.
  4. **Overlapping payroll cycles (double-payment risk)** — nothing stopped
     HR creating a second batch whose cycle overlaps an existing one; the
     same attendance day, approved bonus or unpaid-leave day would be paid
     out again in full through the second batch. New
     `PayrollBatchService.create` + `assertNoOverlappingCycle`, checked
     against every existing batch regardless of status.
  5. **Tax slab overlap (wrong tax silently applied)** — `monthlyTax()`
     resolves the slab via `rules.find(...)`, the first array match with no
     tie-break. Two individually-valid overlapping slabs meant the same
     salary's tax rate depended on insertion/query order. New
     `TaxRuleService` rejects a create/update whose `[minIncome,
     maxIncome]` range overlaps another slab's.
  6. **Reports Tax/PF "collected to date" overstated** — summed every
     payslip regardless of the owning batch's status (draft/rejected
     included), inconsistent with the same page's own correctly-`paid`-
     scoped `netPaidToDate`. New `paidPayslips` computed, swapped in
     everywhere Tax/PF totals and cycle/detail rows are built.
  7. *(Registration reviewed, not fixed — see below.)*
- **Regression tests**: backend +6 (`FinalSettlementControllerIT`
  self-approval case, `PaymentControllerIT` non-approved-batch case,
  `PayrollBatchControllerIT` overlap case, new `TaxRuleControllerIT` ×3).
  Frontend: no new pure-logic file (items 1 and 6 are component-level
  async-ordering/filter fixes, matching how this project already draws the
  spec-file line elsewhere).
- **Verification**: backend `mvnw compile` clean, `mvnw test` **187/187
  passing** (was 181). Frontend `npx tsc --noEmit -p tsconfig.app.json` /
  `-p tsconfig.spec.json` both clean, `ng build` clean, `ng test` **280/280
  passing**, unchanged.
- **Repo state found and fixed along the way**: neither the frontend nor
  the backend folder had ever had a commit — the frontend `.git` existed
  with everything staged but zero commits, the backend had no `.git` at
  all. Backend: `git init` + one initial commit (baseline tree, this
  session's four backend fixes included, dev-server `run*.log` files
  excluded as noise). Frontend: two scoped commits (pathspec-limited to
  this session's changed files, not the ~66 other pre-staged-but-unrelated
  files already sitting in the index) — audit fixes, then the auth-bug
  fixes below.
- **Two bugs live-reported by the user this session, reproduced and fixed**:
  1. **Login reads as "stuck" when the backend is unreachable** — not
     actually broken, just slow: `session.ts`'s `tryBackendLogin` had no
     timeout, so "Signing in…" sat frozen for however long the browser
     took to give up on the refused connection (~2.4s observed) before the
     mock fallback took over, with zero visible feedback in between. Fixed:
     capped at 3s via rxjs `timeout()`.
  2. **Sign out as one user, sign in as another → stuck on the sign-in
     screen despite the new session genuinely being established** —
     reproduced live, root-caused, fixed. `session.signOut()`'s own
     "Signed out" audit-log write is dispatched right as the token is
     cleared; by the time the actual HTTP request goes out it carries no
     token and gets a real `401` from the backend. `auth-interceptor.ts`
     treated *any* 401 outside the login call as "the server invalidated
     my session," force-signing-out and redirecting to `/login` with
     `next` captured as `router.url` at that exact moment — which was
     already `/login`. That poisoned `next` for the *next* sign-in:
     `login-page.ts`'s `submit()` genuinely succeeded and
     `router.navigateByUrl(this.next())` genuinely ran, but `next()`
     resolved to `/login` itself, landing back on the sign-in screen with
     a real session already in `sessionStorage`. Fixed two ways: the
     interceptor's 401 handler now checks `session.currentUser()` first —
     no forced sign-out when there's no active session to force out of;
     `login-page.ts`'s `next` computed additionally refuses to ever
     resolve to `/login` itself, as defense in depth against the same
     class of bug from any other source.
  Both live-verified with Playwright against the real running app: sign out
  as Admin → sign in as HR → lands on the real HR dashboard, not the sign-in
  screen. `npx tsc --noEmit` clean, `ng build` clean, `ng test` unchanged at
  **280/280** (no pure-logic file for either — same reasoning as items 1/6
  above).
- **Also done, per explicit ask**: removed the "Request an account" /
  self-registration link from `login-page.ts` (the landing page). The
  underlying feature (`/register` route, `RegistrationRequestController`,
  `registration-review-page.ts`, V28–V30) is **not removed** — still
  reachable by direct URL, still reviewed from
  `registration-review-page.ts` — only the landing-page entry point is
  gone. See the recruitment/registration note below for the full picture.
- **New**: `start.sh`/`stop.sh` (git-bash), `start.bat`/`stop.bat` (cmd.exe)
  at the repo root (`C:\Users\Hp\Desktop\Project_HRPayroll\`, outside both
  the frontend and backend git repos — no `.git` governs that root level).
  Idempotent (skip a server whose port is already listening), stop scripts
  kill by whatever process actually owns the port right now rather than a
  saved launcher PID (mvnw/npx spawn children that hold the real listening
  socket — confirmed the hard way mid-session). A real bug was caught and
  fixed while writing `start.bat`: `call mvnw.cmd` failed to resolve after
  a bare `cd /d` on this machine and needed an explicit `.\mvnw.cmd`
  prefix — would have silently failed to start the backend for anyone
  using the script.
- **Status**: ✅ Done for all 7 audit fixes and both live-reported auth
  bugs. Registration is reviewed and landing-page-hidden, not removed —
  see below for the recommendation. `povlan-plan.md` — this file — is the
  one already-open item (§2.12's standing instruction) this entry itself
  satisfies for today's date.

**Recruitment/registration scope note (2026-09-02, historical — superseded
by §2.52, 2026-09-03)**: this session confirmed `features/registration/*`
was self-service **account** sign-up (an anonymous person requests a login,
Admin/HR approve or reject by reusing the existing employee/user-creation
actions), never a recruitment/hiring pipeline — no job postings, no
candidate records, no interview scheduling anywhere in the repo. Cleanly
isolated (its own package/table on the backend, its own feature folder on
the frontend, nothing else in the app read `RegistrationRequest`), which is
exactly why §2.52 was able to remove it entirely with no payroll-code
impact. The scope decision item 7 below (now removed from "Current next
steps") is resolved: removed, not kept.

### 2.51 Admin → Company Setup audit, 2 confirmed bugs fixed (2026-09-03)

- **Scope**: Admin → Company Setup only (`organisation-page.ts` and its four
  modal forms) — Company Information, Departments, Designations, Shifts,
  Holidays. "Leave Types" and "Payroll Cycle" are **not** Company Setup
  screens in this app's design (confirmed, not an oversight): the leave
  equivalent is `LeaveRule`, owned by the separate Leave feature
  (`leave/leave-rules.ts`), and there is no standalone admin "payroll cycle"
  entity — `cycleStart`/`cycleEnd` are set per-batch in Payroll Batches.
  "Financial/payroll settings" is the separate Salary & Rules feature
  (`salary-rules/`). None of the three were touched.
- **Traced end-to-end** (Admin UI → NgRx store/`HybridApiService` → Spring
  Boot → PostgreSQL → reload) for all five Company Setup tabs. Confirmed
  correct and unchanged: `HybridApiService`'s per-collection real-backend
  routing (companies/departments/designations/shifts/holidays are all
  `BACKED_COLLECTIONS`, not mock — no hardcoded/mock data in this module);
  `SecurityConfig`'s Admin-only POST/PUT/DELETE gating on all five
  resources, public GET on `companies` only (deliberate, for the sign-in
  screen's branding — verified live, unauthenticated `GET /api/companies`
  succeeds); `ApiExceptionHandler`'s FK "still referenced" (delete blocked)
  vs. "not present" (bad insert/update reference) distinction, matching the
  three delete-confirmation dialogs' wording; the department/designation/
  shift/holiday edit-modal signal-input timing fix (`effect()`, not
  constructor read); Employee's `dept_id`/`designation_id`/`shift_id` FKs
  (`NOT NULL REFERENCES`, no `ON DELETE CASCADE`) correctly back that
  delete-block. 2 confirmed real bugs, both fixed:
  1. **Weekly off day shows the wrong day (display bug)** — the Company
     tab's day `<select>` bound its selection via `[value]` on the `<select>`
     element itself, evaluated before Angular renders its `@for`-generated
     `<option>` children into the DOM. The browser's native `<select>` value
     setter silently falls back to the first option when no matching
     `<option>` exists yet at assignment time, and never retries once the
     real option appears — so the dropdown always rendered "Sunday"
     regardless of the company's actual `weeklyOffDay` (seeded/persisted as
     5 = Friday). Confirmed live: `GET /api/companies/c1` correctly returned
     `weeklyOffDay: 5`, but the rendered `<select>` had `selectedIndex: 0`
     ("Sunday"). The underlying value was never corrupted by this (the save
     path reads the committed `Company` object, not the select's DOM state,
     unless the admin actually changes the selection), but the settings
     screen was misleading about the company's real configuration. Fixed by
     moving the selection onto each `<option>`'s own `[selected]` binding
     instead of the parent `<select>`'s `[value]` — verified live post-fix:
     `selectedIndex` now correctly resolves to "Friday".
  2. **Company tab had no required-field validation or error feedback** —
     unlike the other four Organisation tabs (all `FormGroup` +
     `Validators.required`, blocking submission with an inline message),
     the Company tab bypassed reactive forms entirely: a blank Name/
     Address/Timezone/Currency could be dispatched straight to the backend,
     which correctly rejects it (`@NotBlank`, covered by
     `CompanyControllerIT.blankNameIsRejectedByBeanValidation`) — but the
     page never read `companiesFeature.selectors.error`, so the failure was
     completely silent, and `saveCompany()` cleared the draft signals
     unconditionally right after dispatching, regardless of whether the
     save actually succeeded. Fixed: added the same required-field
     inline-error pattern as the other four tabs (blocks the dispatch
     client-side, mirroring the backend's own `@NotBlank` fields) and wired
     `companyError` into the template so a failed save is no longer silent.
     Verified live: clearing Name and clicking Save now shows "This field
     is required." and sends nothing; the seeded row is unchanged
     (`GET /api/companies/c1` still returns the original values).
- **Files changed**: `organisation-page.ts`, `organisation-page.html` only.
  No backend, migration, or model changes — none were needed.
- **Verified**: `tsc --noEmit` clean, `ng build` clean, `CompanyControllerIT`
  6/6 passing (unaffected — no backend change), live browser session as
  Admin against the running dev servers confirmed both fixes and confirmed
  no other Organisation tab/data was affected.
- **Not done / explicitly out of scope**: no dedicated backend integration
  tests exist for Department/Designation/Shift/Holiday controllers (only
  `CompanyControllerIT` does) — a real test-coverage gap, but writing four
  new IT suites is net-new work beyond "fix confirmed issues," not done
  here. `Holiday` has no DB-level uniqueness constraint on `date` (a
  duplicate holiday row is possible) — not flagged as a bug since multiple
  holiday entries can legitimately share a date (e.g. two festival
  observances), just noted as a soft gap. Designation still has no
  `deptId` (pre-existing, deliberate per §2.50-era notes) — filtering
  designations by department remains unavailable, unchanged.
- **Status**: Admin Company Setup is ready for the next Employee Setup
  step — Department/Designation/Shift FKs, delete-blocking, and validation
  all trace correctly end-to-end, and the two bugs found here were both
  presentation-layer (display + missing client validation), not data-model
  or persistence defects that Employee Setup would inherit.

### 2.52 Registration Request module removed entirely (2026-09-03)

- **Why**: explicit decision (resolving the §2.16/§2.50 open scope item) —
  this project's scope is Payroll Automation and salary generation, not
  recruitment/account self-registration. The feature was already confirmed
  cleanly isolated (see the scope note above), so full removal carried no
  risk to Employee/Users & Roles/Login/payroll code.
- **Frontend removed**: the entire `features/registration/` folder
  (`register-page.ts/.html`, `registration-review-page.ts/.html`,
  `registration-review-form.ts/.html`, `registration-rules.ts` +
  `.spec.ts`) — 8 files. The `register` (public self-signup) and
  `registration-requests` (Admin/HR review queue) routes removed from
  `app.routes.ts`. The "Registration Requests" entry removed from
  `module-registry.ts` (sidebar nav). `registrationRequestsFeature` removed
  from `core/store/features.ts`. `RegistrationRequest`/`RegistrationStatus`
  removed from `core/models/hr.ts`. `RegisterPayload`/`AuthApiService
  .register()` removed from `core/auth/auth-api.ts`. `registrationRequests`
  removed from `HybridApiService`'s `BACKED_COLLECTIONS`
  (`core/http-api.ts`). `REGISTRATION_REQUESTS` mock fixture removed from
  `core/mock-db/seed/governance.ts`, and its wiring removed from
  `core/mock-db/mock-db.ts`.
- **Backend removed**: the entire `registration` package —
  `RegistrationRequestController`, `RegisterRequest` (DTO),
  `RegistrationRequest` (entity), `RegistrationRequestRepository` — plus
  `RegistrationRequestControllerIT`. `AppUserRepository.findByRole_NameIn`
  removed (dead code — its only caller was the deleted controller's
  reviewer-notification step). `SecurityConfig` had its three
  registration-specific rules removed: the public
  `POST /api/auth/register` permit, the Admin/HR
  `/api/registration-requests/**` gate, and their explanatory comments.
- **Database**: added `V33__drop_registration_requests.sql`
  (`DROP TABLE IF EXISTS registration_request`) rather than editing the
  historical `V28`/`V29` migration files, which are kept as-is for Flyway
  checksum integrity and historical record. Verified live against the dev
  Postgres instance: `flyway_schema_history` shows V33 applied
  successfully, `to_regclass('registration_request')` now returns null
  (table gone).
- **Intentionally kept, not registration-specific**: `EmployeeRepository
  .existsByEmailIgnoreCase`/`.existsByNationalId` (the deleted controller's
  only other caller was itself, but these are generic Employee-integrity
  helpers, not registration logic — left in place, unused code that's
  trivial to reconnect if a future duplicate-check need arises, not touched
  per "no speculative refactoring"). `Notification.type`'s `'account'`
  value (`hr.ts`) — confirmed via seed data (`governance.ts`'s `n3`,
  "Account activation required") this is a genuine non-registration
  notification category (draft-employee activation reminders), not
  registration-only; kept.
- **Verified**:
  - `tsc --noEmit` clean; `ng build` clean (register-page/
    registration-review-page chunks confirmed gone from the build output).
  - Backend: `mvn compile`/`test-compile` clean; full suite
    176/176 passing (was 187 — the 11 fewer are exactly
    `RegistrationRequestControllerIT`'s tests, removed with it).
  - Frontend: `ng test` 259/259 passing (was 280 — 21 fewer, matching
    `registration-rules.spec.ts`'s removal).
  - Backend restarted against the real dev Postgres DB; confirmed live with
    an Admin JWT that `GET /api/registration-requests` and
    `POST /api/auth/register` both now return `404` (previously `401`
    pre-auth, `200`/`201` with auth — genuinely gone, not just
    re-authorized).
  - **Playwright, live, against the running dev servers**: signed in as
    Admin — sidebar has no "Registration Requests" entry (confirmed between
    "Change Requests" and "Attendance", where it used to sit); direct
    navigation to `/registration-requests` and `/register` both cleanly
    redirect to `/dashboard` (the app shell's wildcard-child /
    top-level-wildcard routes) with no console errors and no broken page;
    Employees (26 records, Add Employee button present), Users & Roles (6
    accounts, 4 roles, permission matrix, role dropdowns all working),
    Audit Log, and sign-out-then-return-to-login all verified working
    end-to-end with real data.
  - One pre-existing, unrelated console error noticed during this pass
    (not caused by this change, not fixed — out of scope): a stray
    `GET /api/audit-logs/audit-<id>-0` 404 fires under some navigation
    paths in the Audit Log feature. Flagged for a future session, not this
    one.
- **Status**: Registration Request/recruitment functionality is fully
  removed. Employee management, Users & Roles, Login/authentication,
  Employee→AppUser linking, and every other Admin/Payroll module verified
  intact, both by build/test and live Playwright E2E.

### 2.53 Step 2 — Employee Setup audit, 3 confirmed bugs fixed (2026-09-05)

- **Why**: scoped audit of the full Employee flow (list, Add/Edit/View,
  Employee Code, Department/Designation/Salary Grade/Shift, joining date,
  status, contact/bank details, Employee→AppUser link) ahead of moving on to
  Payroll Automation — anything wrong here (duplicate identity data, a
  disagreeing salary grade, an authorization gap) feeds bad input into
  salary generation later.
- **Bug 1 — Salary Grade could be typed independently of Designation**:
  `employee-form.ts` had its own free-text `salaryGrade` field, so Add/Edit
  Employee could save a grade that disagreed with the selected Designation's
  real grade (`Designation.grade`, the one DB-backed salary-grade master —
  §2.45). Fixed: `salaryGrade` removed from the form group; a `computed()`
  (`derivedSalaryGrade`) now reads it straight off the selected
  `designationId`, the field is read-only in `employee-form.html`, and
  submit is blocked with "No grade set for this Designation." if the chosen
  Designation has none. No other code path could reintroduce independent
  entry — `change-request-rules.ts`'s `EDITABLE_FIELDS` whitelist for
  self-service change requests does not include `salaryGrade`.
- **Bug 2 — no duplicate email/National ID check on Employee create or
  update**: `EmployeeController.create()`/`update()` did a bare
  `repository.save(...)` with zero uniqueness checking — only
  `employee_code` is DB-unique (`V3__employee.sql`); `email` and
  `national_id` have never had any constraint. Live `psql` against the dev
  DB found this is not hypothetical: 1 duplicate email pair and 4 duplicate
  National ID groups already exist among real, clearly-distinct employee
  records (sloppy demo-data placeholders, not an active double-submit
  incident — confirmed by inspecting each group's name/code/email, all
  different people). Fixed at the **application level only**:
  `EmployeeRepository` gained `existsByEmailIgnoreCaseAndIdNot`/
  `existsByNationalIdAndIdNot`; `create()` now checks
  `existsByEmailIgnoreCase`/`existsByNationalId` and `update()` checks the
  `...AndIdNot` variants, both returning a clean `409` via
  `ResponseStatusException` (same pattern the now-deleted
  `RegistrationRequestController` used). Deliberately **not** adding a
  DB-level `UNIQUE` constraint now — it would fail to apply against the
  existing dirty data — and deliberately **not** touching/merging any
  existing employee rows, since that's a destructive change to real records
  with potential attendance/leave/payslip/settlement ties, requiring a
  human data-cleanup decision first. Flagged as a follow-up: once the
  existing duplicates are manually resolved, add the DB constraint as a
  backstop.
- **Bug 3 — self-service employee PUT had no field-level restriction
  (IDOR)**: `SecurityConfig`'s `adminHrOrOwnEmployeeRecord()` correctly
  gates `PUT /api/employees/{id}` to Admin/HR or the record's own owner (for
  `profile-page.ts`'s self-service contact/photo edit), but only checked
  *whose* record it was — not *which fields* a non-manager could change.
  `profile-page.ts`'s own docstring states "HR-owned fields (department,
  designation, salary grade, joining date…) stay read-only here", but
  nothing server-side enforced that: a crafted direct API call from an
  Employee/Accountant role could PUT their own record with any field
  changed — status flipped to `active`, salary grade, department,
  designation, employee code, overtime eligibility, bank details — all
  fields payroll depends on. Fixed in `EmployeeController.update()`: for a
  non-Admin/HR caller (checked via the request's `Authentication`), every
  field except the self-service ones (phone, email, address, emergency
  contact name/phone, photo — matching exactly what `profile-page.ts`
  exposes) is now forced back to the existing stored value before saving,
  regardless of what the request body contains.
- **Verified correct, no changes needed**: `EmployeeRepository`'s FK columns
  (`dept_id`/`designation_id`/`shift_id`) are `NOT NULL REFERENCES` with no
  cascade, so deletes are correctly blocked while referenced (confirmed by
  the existing `OrganisationDeleteBlockedIT`); `app_user.employee_id` has a
  DB-level `UNIQUE` index (`V30`) enforcing one login account per employee;
  `PATCH /activate` (Admin-only, draft-only) and `PATCH /separate`
  (Accountant/Admin-only) status transitions are correctly gated and
  unchanged; `employee-list.ts`/`employee-detail.ts` read Department/
  Designation/Shift names live from the real NgRx-backed collections, not
  stale/mock data; bank field `@Pattern` validation matches frontend
  exactly.
- **Documentation**: this entry. No other doc (`PLAN.md`, `PROGRESS.md`,
  `PROJECT_WALKTHROUGH.md`, `MODULE_RECIPE.md`, `BUILD_LOG.md`) contained
  Employee Setup content needing correction.
- **Verified**:
  - Backend: `mvn clean verify` — 176/176 tests passing, `BUILD SUCCESS`
    (includes `EmployeeControllerIT`'s 13/13, unaffected by the field-lock
    change since all its callers are `adminToken()`).
  - Frontend: `tsc --noEmit` clean; `ng build` clean; `ng test` — 259/259
    passing.
  - Backend restarted against the real dev Postgres DB to pick up the
    Java changes.
  - **Live API/DB verification**: `POST /api/employees` with an email
    already used by another employee → `409` (console-confirmed); table
    stayed at 26 records, no duplicate persisted. `PUT` on an existing
    employee with a National ID already used by a different employee →
    `409`; `psql` confirmed the stored National ID was untouched.
  - **Playwright, live, against the running dev servers, signed in as
    Admin**: Add Employee — changing Designation from "General Manager" to
    "Operator" live-updated the read-only Salary Grade field from `M1` to
    `W2`; created a real employee (`EMP-PWTEST01`) with unique data,
    `psql` confirmed the row persisted with `salary_grade='W2'`; reloaded
    the Employee Detail page — Grade still showed `W2`, confirming
    persistence survives reload. Edit Employee — changing National ID to
    an already-used value returned `409` and left the stored value
    unchanged. Employees list still showed all 26 real records throughout.
    Users & Roles — 6 real linked accounts, role dropdowns, and permission
    matrix all still functioning. Test employee row removed after
    verification.
  - One pre-existing, unrelated issue noticed (not caused by this audit,
    not fixed — out of scope for Employee Setup): a failed Add Employee
    (e.g. the 409 duplicate-email case) closes the modal with no visible
    error toast — the request fails cleanly server-side but the UI gives
    no feedback to HR/Admin about why nothing was added. This is a
    frontend error-handling gap shared by the generic `create`/`upsert`
    effect used by every collection, not something specific to Employees —
    flagged for a future session rather than touched here.
- **Status**: Step 2 — Employee Setup is ready for the next Payroll
  Automation step. The remaining known data-quality issue (existing
  duplicate emails/National IDs in the dev DB) does not block payroll
  logic — it requires a human decision on how to resolve those specific
  records, not a code fix, and is now guarded against for all future
  entries.

### 2.54 User & Role Setup audit, 3 confirmed bugs fixed (2026-09-05)

- **Why**: scoped audit of Employee-vs-User separation (Employee can exist
  without a login; a User must link to an existing Employee; one Employee
  cannot hold two accounts; the four fixed roles) ahead of Payroll
  Automation — a login that outlives its employee's real status, or a
  weak/duplicate credential, is an authentication-layer risk independent of
  payroll logic itself.
- **Bug 1 — a separated employee's account could still obtain a real JWT by
  calling the login API directly (confirmed authentication bypass)**:
  `session.ts` fetches the token, *then* checks the linked employee's
  status and only clears the token client-side if separated — its own
  comment already admitted this was "the one business rule the real backend
  doesn't check yet". `AuthController.login()` never checked employee
  status at all, only the account's own `active` flag. A caller that skips
  the Angular app entirely (curl/Postman) and logs in as a separated
  employee's still-enabled account received a fully valid, fully-scoped
  token. Live-reproduced before the fix: `POST /api/auth/login` with a
  separated employee's correct credentials returned `200` with a live
  `accessToken`. Fixed: `AuthController` now injects `EmployeeRepository`
  and rejects login (`401`, same generic "Invalid username or password"
  message as any other failed login, to avoid disclosing employment status
  to an unauthenticated caller) when the linked employee's status is
  `separated`. Regression test added:
  `AuthControllerIT.aSeparatedEmployeesAccountCannotLogInEvenWithTheCorrect
  Password`. Live-reproduced again after the fix: same request now
  correctly returns `401`.
- **Bug 2 — no minimum password length on account creation**:
  `ResetPasswordRequest` already enforced 8 characters, but
  `CreateUserRequest.password` had only `@NotBlank` — a crafted
  `POST /api/users` could set an arbitrarily weak initial password (the
  frontend's own `tempPassword()` always generates a compliant one, so this
  was only reachable by bypassing the UI). Fixed: added the same
  `@Size(min = 8)` to `CreateUserRequest.password`. Live-verified: a create
  request with password `"abc"` now returns `400` with the same validation
  message shape every other field-length rule already uses.
- **Bug 3 — no duplicate-email prevention for user accounts**: `app_user`
  had a DB-level `UNIQUE` on `username` but nothing on `email`, and neither
  `CreateUserRequest` nor `UpdateUserRequest` checked it — two accounts
  could share one email. Also found while checking username uniqueness:
  V17's `username` constraint is case-*sensitive*, so `"Rakib.Hasan"` and
  `"rakib.hasan"` could both exist as genuinely separate logins even though
  `AppUserRepository.existsByUsernameIgnoreCase` already existed, unused,
  for exactly this check. Fixed with `V34__app_user_email_unique.sql` — two
  new unique indexes, `uq_app_user_email` on `lower(email)` and
  `uq_app_user_username_ci` on `lower(username)` (verified against live dev
  data first: no existing duplicates of either kind, so both applied
  cleanly). `ApiExceptionHandler`'s existing generic "unique" branch turns
  either violation into a clean `409`, same pattern as V25/V26/V27/V30 —
  no controller change needed. Live-verified: creating a second account
  with the same email, or a case-different duplicate username, both now
  return `409`.
- **Verified correct, no changes needed** (business design, not touched
  per "don't change the design"):
  - `app_user.employee_id` is `NOT NULL REFERENCES employee(id)` (V17) —
    an invalid/non-existent Employee ID on create or update is already a
    clean `400` ("This request references a record that does not exist"),
    confirmed live.
  - `uq_app_user_employee_id` (V30) already blocks a second account for
    the same employee with a clean `409`, confirmed live.
  - `SecurityConfig`'s blanket `hasAuthority(ADMIN)` on all of
    `/api/users/**`, `/api/roles/**`, `/api/permissions/**` means there is
    no self-service surface on these endpoints at all — no BOLA/IDOR
    vector, since only Admin can reach any id, which is the intended
    design. Confirmed live: HR gets `403` on `GET /api/users` and on a
    crafted `PUT` attempting to grant itself Admin.
  - **Admin creating another Admin is explicitly allowed by this
    project's own prior decision** (§2.40: "An authenticated Admin can
    still create another Admin account through the existing internal
    'Users & Roles → Create user' page... offers the full unfiltered role
    list exactly as it always has") — this audit's instruction to check
    "cannot create another Admin unless business rules explicitly allow
    it" is satisfied by that existing, documented decision; deliberately
    left unrestricted, not a bug.
  - `AppRoleController` only allows editing a role's `description` and
    `permissionIds` — the four roles themselves can't be created, renamed,
    or deleted through the API, matching the "roles are fixed" design.
  - `user-form.ts`'s `eligibleEmployees` already filters to
    `status === 'active'` and excludes already-linked employees for the
    Create User picker — a UI-level nicety on top of the two DB
    constraints above, not the actual enforcement boundary (which is
    server-side, as covered above).
  - `AppUserController.create()`/`update()` never touch the `employee`
    table, and `employee-form.ts`/`EmployeeController` never touch
    `app_user` — Users & Roles cannot accidentally create an Employee, and
    Add Employee cannot accidentally create a login. Confirmed by reading
    both controllers and both frontend forms.
  - Deleting a User leaves the Employee record untouched (separate tables,
    no cascade either direction beyond the FK); deleting an Employee that
    still has a linked User is blocked by the FK (`still referenced from`
    → clean `409`), same pattern as every other referenced-record delete
    in this backend.
  - Password reset/creation is always BCrypt-hashed server-side
    (`PasswordEncoder`); the plain value is never stored, logged, or
    echoed back (`UserResponse` has no password field at all).
  - Audit logging: every Users & Roles action (create user, role change,
    description edit, permission toggle, enable/disable, password reset)
    already calls `AuditLogService.record()` in `users-page.ts`.
- **Known, pre-existing side effect noted, not caused by this session and
  not fixed here** (belongs to §2.53's employee duplicate-check fix, not
  this one): an employee who already shares a duplicate National ID/email
  with another record (the demo-data quality issue flagged in §2.53) is
  now blocked from *any* `PUT /api/employees/{id}` update at all — even one
  that never touches the National ID/email fields — because the duplicate
  check runs unconditionally, not only when those fields actually change.
  Discovered while restoring a live-tested employee's status after this
  session's login-bypass test (`PUT` back to `active` returned `409`,
  worked around here with a direct `UPDATE employee SET status='active'`
  to undo the test's own side effect, not a data change of substance).
  Flagged as a follow-up for whichever session resolves the existing
  duplicate data — the check should ideally only fire when the field is
  actually changing.
- **Verified**:
  - Backend: `mvn clean verify` — **177/177** tests passing (176 + 1 new
    `AuthControllerIT` regression test), `BUILD SUCCESS`.
  - Frontend: `tsc --noEmit` clean; `ng build` clean; `ng test` — 259/259
    passing (unchanged — no frontend file needed a fix this session).
  - Backend restarted against the real dev Postgres DB; `flyway_schema_
    history` confirms V34 applied successfully.
  - **Live API/DB verification against the real running backend**: created
    a real user (`shahidul.islam`) for an existing active, unlinked
    employee via a direct authenticated `POST /api/users` — `psql`
    confirmed the row persisted with the correct `employee_id`/`role_id`.
    A second `POST` reusing that same `employeeId` → `409`. A `POST` with
    an unknown `employeeId` → `400`. A `POST` with a 3-character password →
    `400`. A `POST` reusing that user's email under a different username →
    `409`. A `POST` with a case-different duplicate username
    (`Shahidul.Islam` vs `shahidul.islam`) → `409`. Separated that same
    test employee via `PATCH /activate`'s sibling `/separate`, then
    attempted `POST /api/auth/login` with the account's correct password →
    `401` (was `200` before this session's fix). HR's token against
    `GET /api/users` → `403`; HR's crafted `PUT` attempting to grant itself
    the Admin role → `403`. All test rows/state reverted after
    verification (test user deleted, test employee's status restored to
    `active`).
  - **Playwright, live, against the running dev servers, signed in as
    Admin**: Users & Roles page loaded 6 real linked accounts; Create User
    form's employee picker correctly listed only unlinked, active
    employees; created a real account through the UI end to end (temp
    password shown on screen, banner confirmed); the account appeared
    immediately in the table with the correct Employee/Email/Role columns.
    Signed in as HR and navigated directly to `/users` — `roleGuard`
    redirected to `/dashboard`, confirming the client-side gate matches
    the server-side one exactly (both block, neither more permissive than
    the other).
- **Status**: User & Role Setup is ready for the next Payroll Automation
  step. The one open item (duplicate-data employees becoming un-editable
  for unrelated fields) is a narrow follow-up on top of §2.53's fix, not a
  User & Role Setup defect, and doesn't block payroll.

### 2.55 Realistic 50-employee payroll test dataset + live payroll run (2026-09-05)

- **Why**: Payroll Automation/Salary Generation is this project's actual
  goal, but the only data on file was a handful of hand-entered employees —
  not enough variety to exercise every deduction/benefit path (PF, tax
  slabs, loans, bonuses, late/absence/leave deductions, overtime, mid-cycle
  proration) in one real run. This adds a large, realistic, internally
  consistent employee base and drives one full real payroll cycle through
  it, live, to prove the engine handles all of it together correctly.
- **New script (not a Flyway migration)**:
  `payroll-automation-backend/scripts/seed-50-test-employees.sql` — plain
  SQL, run manually via `psql -f`, not part of the automatic migration
  chain. Test data, not a schema change, so it deliberately doesn't live in
  `db/migration/` (no reason to carry 50 fake employees in Flyway's
  checksummed history forever). Idempotent: every insert uses fixed,
  deterministic ids (`te-001`..`te-050`, etc.) and `ON CONFLICT (id) DO
  NOTHING`, so re-running it is always safe and never duplicates rows.
  Touches zero existing rows — the real demo accounts/logins, the existing
  26 employees, and all prior payroll_batch history are untouched.
- **50 employees created** (`te-001`..`te-050`, codes `EMP-2001`..
  `EMP-2050`), 100% reusing existing master data (no new departments/
  designations/shifts/company/tax/PF rows — all referenced by id, none
  created): distributed across all 6 real departments and all 7 real
  designation grades in a realistic pyramid (2× M1, 4× M2, 6× M3, 10× E1,
  8× W1, 12× W2, 8× W3), each field internally consistent with the
  designation's own grade — the exact "Salary Grade always derives from
  Designation" rule §2.53 already established for the UI. Every employee
  has a full, distinct set of every field the schema defines: name
  (Bangladeshi names), email, phone, gender, DOB, National ID, address,
  joining date, employment type (mostly permanent, some contract/
  probation), department/designation/shift, status (46 active, 2 draft, 1
  inactive, 1 separated — the separated one also has a `last_working_day`),
  overtime eligibility (shop-floor grades only), and bank details (BRAC/
  DBBL/Islami Bank/City/Eastern, ~10% deliberately left blank to test the
  "no bank on file" case). Verified zero duplicate employee code/email/
  National ID within the new 50, and zero collisions against the existing
  26.
- **Explicitly did NOT create 50 login accounts** — this project's own
  design (§2.54) is Employee ≠ User; creating a login per employee was
  named in the request as something *not* wanted. Verified: `app_user`
  count unchanged at 6 (the real demo accounts only) after the whole
  script ran.
- **Salary structures**: one per employee, grade-tiered (M1 ৳90,000 gross
  down to W3 ৳14,500 gross), `applies_pf` true for permanent employees
  (false for contract/probation, plus one deliberate exception on a
  permanent employee to test the flag), `applies_tax` true except for the
  W3 tier and one deliberate M3 exception (both explicit "tax-exempt flag"
  test cases, on top of the tax slabs' own natural exemption for the
  lowest earners).
- **Payroll scenario coverage** (all inside the existing draft
  `PR-2026-11` batch's cycle, 2026-11-01..30, chosen because it already
  existed with 0 employees — nothing about the prior 8 payroll_batch rows
  or their history was touched):
  - Full-month attendance (present, on-time) generated for every active
    test employee on every non-Friday day — **1,187 attendance rows**.
  - **3 employees** with 5 late check-ins each (above the 3-day free
    allowance, so a real late deduction applies).
  - **2 employees** with 2 unauthorized-absence days each (attendance rows
    deliberately omitted, no leave covering them).
  - **1 employee** with approved Unpaid leave (2 days — the one deduction-
    bearing leave type).
  - **1 employee** with approved Sick leave (2 days — paid, excuses
    absence, no deduction).
  - **1 employee** with a still-pending Casual leave request (1 day) — the
    "pending, not yet charged" path.
  - **3 employees** with approved, payroll-eligible overtime (2.5–4 hours
    each).
  - **8 employees** with active loans mid-recovery (principal ৳20,000–
    ৳60,000, EMI ৳2,000–৳5,000).
  - **10 employees** with approved bonuses (Festival/Performance/
    Attendance types, ৳2,500–৳15,000).
- **Live payroll run, full lifecycle, against the real running backend/
  Postgres, signed in as HR then Accountant**: opened the existing
  `PR-2026-11` draft batch — preflight showed only the expected pre-
  existing warning (11 old employees with no salary structure, unrelated
  to this session); clicked "Lock cycle and run engine" — batch reached
  `calculated` with **55 payslips** (46 new active test employees + 9 of
  the original 26 that already had salary structures), **gross
  ৳2,656,328 / deductions ৳1,342,133 / net ৳1,420,248**. Every scenario
  reconciled exactly against hand-computed expected values: the tax-exempt
  M3 employee showed ৳0 tax; the two absence-test employees showed the
  correct ৳3,533 absence deduction (2 days × their daily rate); the
  unpaid-leave employee's net was exactly gross − tax − PF − leave
  deduction; the pending-leave employee's payslip carried the "1 pending
  leave" flag; the three overtime employees' gross included their OT
  amount; all 8 loan employees showed their EMI deducted and, after the
  run, their `loan_record.outstanding_balance` reduced by exactly that
  EMI (`applyLoanRecovery` verified via `psql`); all 10 bonus employees'
  net included their bonus. Submitted for verification (HR), then signed
  in as Accountant and approved the batch, then generated the bank file
  and marked it paid — hit the pre-existing, already-documented payment/
  batch-write race (`PayrollBatchService` requires the payment row before
  the batch may reach `paid`; the first click recorded the ৳1,420,248
  payment but left the batch at `approved`), which `pay()`'s own built-in
  retry path (`paymentAlreadyRecorded`) resolved on a second click exactly
  as designed — batch reached `paid`. `psql` confirmed both the batch's
  final `status = 'paid'` and the `payment` row (`amount = 1420248.00`,
  `status = 'processed'`).
- **Documentation**: this entry, plus the new script itself (already
  self-documenting via its header comment).
- **Verified**:
  - Backend: `mvn clean verify` — 177/177 passing, `BUILD SUCCESS`
    (unchanged — no backend code touched this session, only data).
  - Frontend: `tsc --noEmit` clean; `ng build` clean; `ng test` —
    259/259 passing (unchanged, no frontend code touched either).
  - **PostgreSQL verification**: 50 employees, 50 salary structures, 1,187
    attendance rows, 3 leave requests, 3 overtime rows, 8 loans, 10
    bonuses, 0 new `app_user` rows — all confirmed via direct `psql`
    queries, cross-checked against the UI's own numbers.
  - **Playwright, live, against the running dev servers**: Employee
    register showed **76 of 76 records** (26 existing + 50 new) as HR;
    searched and opened an individual new employee's detail page — every
    field (grade, department, designation, shift) rendered correctly from
    the real backend. HR's dashboard "Payroll cycles" list and "Leave to
    approve" queue both picked up the new data live (the pending-leave
    test employee appeared in the approval queue by name). The full
    engine-run → submit → approve → pay lifecycle above was driven
    entirely through the real Admin/HR/Accountant UI, not the API
    directly.
- **Missing input for a still-more-complete salary-generation test** (not
  blocking, just not attempted this session): no `leave_balance` rows were
  seeded for the 47 test employees who don't have a leave request (only
  the 3 who do got one, matching what those specific requests needed) —
  harmless for payroll math (`runPayroll` never reads `leave_balance`, only
  `leave_request`), but the Leave module's own balance display would show
  "not entitled" for those 47 if HR tried to raise a new leave request for
  them; no additional holidays were added inside the November cycle
  (there weren't any pre-existing ones either, so this changes nothing
  about the engine's behavior, just something a reviewer might expect to
  see); and the 11 pre-existing employees with no salary structure
  (flagged by preflight, not created this session) remain excluded from
  every payroll run until someone gives them one — a known, unrelated gap,
  not something this dataset was meant to fix.
- **Status**: A realistic, varied, 50-employee payroll test dataset exists
  and a complete real payroll cycle (calculate → submit → approve → pay)
  has been run against it end to end, live, with every number verified
  against the database. Payroll Automation has real data to keep testing
  against going forward.

### 2.56 Step 4 — Salary Structure Assignment audit, 2 confirmed bugs fixed (2026-09-05)

- **Why**: scoped audit of how `SalaryStructure` links to `Employee`, how
  Gross is derived, and whether the payroll engine can trust what it reads
  — the same "no confirmed bug feeds bad numbers into salary generation"
  goal as the Employee/User audits before it.
- **Business design confirmed (not changed)**: this project's real design
  is **one current salary structure per employee**, edited in place on a
  raise — not a versioned history table. Confirmed from
  `salary-structure-form.ts`'s own `employeesWithoutStructure` computed
  signal, which already restricts the "Add structure" picker to employees
  with none yet; editing an existing row always keeps its id/employeeId
  (an in-place overwrite, never a new row). `effective_from` is real,
  stored, required-on-the-form metadata — but genuinely decorative:
  `payroll-engine.ts` never reads it anywhere, so it records *when a rate
  became effective* without the engine ever checking a payroll cycle
  against it. Given the one-row-per-employee design has no second row to
  fall back to even if it did check, adding real effective-dated selection
  would be a new feature (multi-row salary history), not a bug fix — left
  alone per "don't change the business design."
- **Bug 1 — no server-side enforcement of "one structure per employee"**:
  the frontend's own `employeesWithoutStructure` filter was the *only*
  thing preventing a second row — `SalaryStructureController.create()` did
  a bare `repository.save()` with zero duplicate-employee check. A second
  row (a crafted request, or any future UI bug) would make
  `payroll-engine.ts`'s `structures.find((s) => s.employeeId === emp.id)`
  pick an arbitrary one of the two, silently paying the wrong amount —
  confirmed live: `POST` a second structure for `e4` (already has one)
  returned `201` before the fix. Fixed with
  `V35__salary_structure_employee_unique.sql` (`uq_salary_structure_
  employee_id`, same shape as V30/V34), `ApiExceptionHandler`'s existing
  generic "unique" branch turning the violation into a clean `409` — no
  controller change needed for this part. Verified against the live dev
  DB first: no employee had more than one row, so it applied cleanly.
- **Bug 2 — `grossSalary` never validated against `basic + hra +
  allowances`**: `salary-structure-form.ts` always computes `grossSalary`
  as their sum, but the backend trusted whatever the request sent.
  `payroll-engine.ts` recomputes the *actually-paid* gross itself from
  `basic`/`hra`/`allowances` (so the real take-home pay was never at
  risk) — but it separately uses `structure.grossSalary` verbatim for two
  things: `monthlyTax`'s annual-income tax-slab selection, and the
  `dailyRate` that drives late/unpaid-leave/unauthorized-absence
  deductions. A crafted request with an inconsistent `grossSalary` could
  silently move someone into the wrong tax bracket or the wrong daily
  deduction rate while their visible basic/hra/allowances stayed normal.
  Fixed: `SalaryStructureController.create()`/`update()`/`putMany()` now
  reject (`400`, "grossSalary must equal basic + hra + allowances") any
  request where `grossSalary` doesn't equal the sum, via a new private
  `assertGrossMatchesComponents` helper. Verified against the live dev DB
  first: zero existing mismatches, so nothing on file was affected.
- **Verified correct, no changes needed**:
  - `salary_structure.employee_id` is `NOT NULL REFERENCES employee(id)`
    (V5) — correctly linked, always a real employee.
  - Employee-specific salary is fully supported — one independent
    basic/hra/allowances/gross per employee, no grade-band restriction
    (confirmed: no FK or column ties `salary_structure` to
    `designation`/grade at all — Designation.grade informs the *typical*
    band HR chooses, per the seed script's own tiers, but nothing in the
    schema enforces it, which is the existing, correct design — Admin
    sets each employee's actual number).
  - Authorization: `SecurityConfig`'s `POST`/`PUT /api/salary-structures/
    **` are Admin-only (already covered by `AuthorizationIT.
    accountantCanReadButNotWriteSalaryStructures`); confirmed live that a
    non-Admin (HR) direct API call is `403`. No IDOR risk — the gate is a
    flat role check, not per-record, so there's no "modify *another*
    employee's salary" path to begin with; only Admin can modify *any*.
  - Payroll Engine genuinely reads the assigned structure: confirmed live
    in §2.55's 50-employee payroll run — every payslip's basic/hra/
    allowances/gross traced exactly back to that employee's own
    `salary_structure` row.
- **Documentation**: this entry, plus the new migration and
  `SalaryStructureControllerIT` (new — this controller had no tests
  before this session).
- **Verified**:
  - Backend: `mvn clean verify` — **181/181** passing (177 + 4 new), `BUILD
    SUCCESS`.
  - Frontend: `tsc --noEmit` clean; `ng build` clean; `ng test` — 259/259
    passing (unchanged — no frontend file needed a fix).
  - Backend restarted against the real dev Postgres DB; `flyway_schema_
    history` confirms V35 applied successfully.
  - **Live API verification**: a second `POST` for an already-structured
    employee (`e4`) → `409`; a mismatched-gross `POST` for an unstructured
    employee → `400` with the exact validation message; an HR token
    `POST` → `403`.
  - **Playwright, live, against the running dev servers, signed in as
    Admin**: Salary & Rules page showed 60 real structures ("One per
    employee"); opened "Add structure" — the employee picker correctly
    listed only employees without one; created a real structure for
    "mukta" (basic ৳40,000 / HRA ৳15,000 / allowances ৳6,000), confirmed
    the auto-computed "Gross salary: ৳61,000" preview matched, submitted,
    and `psql` confirmed the row persisted with `gross_salary = 61000.00`
    — a genuine, previously-missing structure now on file, not test
    pollution.
- **Status**: Step 4 — Salary Structure Assignment is ready for payroll
  generation. The one known non-bug limitation (no effective-dated salary
  history — a single current row per employee, by design) is documented
  here for anyone who later expects historical payroll re-runs to reflect
  a past rate; it doesn't block current-cycle payroll generation.

### 2.57 50-employee payroll-ready salary data verified, Medical/Transport/Other allowance breakdown documented (2026-09-05)

- **Why**: confirm the 50 test employees seeded in §2.55 (and the two
  gaps §2.56 closed) genuinely add up to complete, correct, payroll-ready
  salary data under the current Designation/Grade/Tax/PF rules — and give
  the single `allowances` figure a documented, realistic composition
  (Medical/Transport/Other) without adding new columns.
- **No new fields, no schema change**: `salary_structure` has one lump
  `allowances` column (no separate Medical/Transport columns exist, and
  none were added — "no new master rules" and this project's own
  established "don't invent new database fields" rule both apply). Each
  grade tier's existing `allowances` total (unchanged from §2.55) is
  documented here as the sum of three realistic Bangladeshi-payroll
  components:

  | Grade | Medical | Transport | Other | Total (unchanged) |
  |---|---|---|---|---|
  | M1 | ৳3,000 | ৳3,000 | ৳4,000 | ৳10,000 |
  | M2 | ৳2,500 | ৳2,500 | ৳3,000 | ৳8,000 |
  | M3 | ৳2,000 | ৳2,000 | ৳2,000 | ৳6,000 |
  | E1 | ৳1,500 | ৳1,500 | ৳1,000 | ৳4,000 |
  | W1 | ৳1,000 | ৳1,000 | ৳1,000 | ৳3,000 |
  | W2 | ৳800 | ৳700 | ৳500 | ৳2,000 |
  | W3 | ৳500 | ৳500 | ৳500 | ৳1,500 |

- **Verified live against the current DB** (query joining `employee` →
  `designation` → `salary_structure` for all 50 `te-*` rows): **zero**
  `employee.salary_grade` vs `designation.grade` mismatches; **zero**
  `gross_salary` vs `basic+hra+allowances` mismatches; **zero** duplicate
  or missing structures (all 50 have exactly one, enforced by §2.56's
  `uq_salary_structure_employee_id`); basic/hra/allowances are identical
  within each grade tier and strictly decrease M1 → W3, matching the
  pyramid; `applies_pf`/`applies_tax` correctly differentiate permanent
  vs. contract/probation and the deliberate exemption test cases from
  §2.55, unchanged.
- **Live payroll run against the current data**: created a brand-new
  batch, `PR-2027-02` (February 2027 — the first previously-untouched
  cycle), and ran the engine against it live as Admin. `psql` confirmed
  every one of the 57 resulting payslips' `basic`/`hra`/`allowances`/
  `gross_salary` traces exactly to that employee's `salary_structure` row
  (zero mismatches), `pf` is exactly 10% of `basic` per the PF rule, and
  `tax` is `0` for every tax-exempt employee (W3 grade, plus the two
  deliberate M3/E1 exceptions) and correctly non-zero for everyone else.
  Note: this cycle has no attendance seeded (it's a fresh month, not
  §2.55's November dataset), so `assessUnauthorizedAbsence` correctly
  treats every working day as unpaid absence for everyone, driving nearly
  all payslips' net pay to `0` — this is the engine working exactly as
  designed on an attendance-empty cycle, not a salary-structure defect;
  the basic/hra/allowances/tax/pf figures this audit cares about are
  unaffected by it and were verified directly. The batch was left at
  `calculated` (not submitted/approved/paid) — a genuine, harmless
  calculated cycle, not corrupted data.
- **Documentation**: this entry (the Medical/Transport/Other table above
  is the only new "data" — no rows changed).
- **Verified**: backend `mvn test` — 181/181 passing, `BUILD SUCCESS`
  (unchanged, no code touched). Frontend `tsc --noEmit`/`ng build` clean,
  `ng test` 259/259 passing (unchanged). Playwright, live, signed in as
  Admin: created `PR-2027-02` through the real "Create payroll batch" →
  "Lock cycle and run engine" flow; Salary & Rules page re-confirmed 61
  structures, all previously-verified figures unchanged.
- **Status**: all 50 employees remain fully payroll-ready under the
  current Designation/Grade/Tax/PF rules — no bugs found this pass (§2.56
  already closed the two real gaps). The 10 pre-existing (non-test)
  employees still without a salary structure (item 15 below) are
  unaffected and unrelated to this verification.

### 2.58 Step 5 — Daily Attendance audit, 3 confirmed bugs fixed (2026-09-05)

- **Why**: scoped audit of check-in/out → late/early-leave/absence →
  overtime detection → payroll eligibility, the last data-integrity link
  before payroll generation — a tampered or wrong-dated attendance row
  feeds directly into late/absence deductions and overtime pay.
- **Bug 1 — any role could create an attendance row for *any other*
  employee (confirmed IDOR)**: `AttendanceController.create()` saved
  whatever `employeeId` the request body carried, with no ownership check.
  `attendance-page.ts`'s self-service `checkIn()` only ever creates a row
  for the caller's own `session.employeeId()`, so this path was only
  reachable by skipping the Angular app. Live-reproduced before the fix: a
  Employee-token `POST` with `employeeId: "e1"` created a row for `e1`, not
  the caller. Fixed: non-Admin/HR callers now have `employeeId` silently
  forced to their own (derived from the authenticated `AppUser` principal)
  before saving — mirrors the field-lock pattern already used for
  Employee's own self-service PUT (§2.53). Live-reproduced again after the
  fix: the same request now creates the row under the caller's own id.
- **Bug 2 — any role could edit *another* employee's existing attendance
  row (confirmed IDOR)**: `SecurityConfig`'s `PUT /api/attendance/**` is
  necessarily role-open (self-checkout for every role — it has no way to
  know which employee an existing row belongs to before a controller
  loads it), and `AttendanceController.update()` had no ownership check
  either — a comment in `SecurityConfig` had flagged this as a known,
  accepted gap ("out of scope"), but it's a real, live-exploitable path:
  any Employee could `PUT` a colleague's attendance to mark them absent,
  present, on-time, or change their hours, all of which feed payroll
  deductions directly. Live-reproduced before the fix: an Employee-token
  `PUT` against a different employee's row succeeded (`200`). Fixed:
  `update()` now loads the existing row first; a non-Admin/HR caller whose
  own employeeId doesn't match the row's `employeeId` gets `403`. For a
  legitimate self-checkout (the one non-manager `PUT` path that remains),
  every field except `checkOut`/`workedHours` is additionally forced back
  to the row's existing value — closes the residual gap where the *body*
  could still reassign the row to someone else, backdate it, or fabricate
  a not-late/present status, even after passing the ownership check.
  Live-reproduced again after the fix: the same cross-employee request now
  returns `403`; a genuine self-checkout with a spoofed `employeeId` in
  the body still succeeds but silently keeps the caller's own id.
- **Bug 3 — check-in date computed in UTC, check-in time in local time
  (confirmed timezone bug)**: `attendance-page.ts`'s `todayIso()` used
  `new Date().toISOString().slice(0, 10)` (UTC) while `nowHHMM()` used
  `new Date().toTimeString().slice(0, 5)` (local) — for any employee
  checking in between local midnight and ~6am in Bangladesh (UTC+6), the
  two disagree: the row would file under *yesterday's* UTC date while
  displaying today's early-morning local time, an internally inconsistent
  record that would also make that employee wrongly show as absent for
  the actual calendar day they worked. Fixed: `todayIso()` now builds the
  date from local `getFullYear()`/`getMonth()`/`getDate()`, matching
  `nowHHMM()`'s reference frame. Scoped to this one file only — the same
  `toISOString().slice(0,10)` "today" pattern exists in ~9 other feature
  files (settlements, leave, bonus, loan, change requests, dashboard) that
  don't pair a UTC date against a local clock read in the same action, so
  they don't have this specific inconsistency; fixing them is a separate,
  unrelated, out-of-scope concern, not touched here.
- **Verified correct, no changes needed**:
  - Shift-based required hours, late detection (`isLateCheckIn`, grace
    period from the employee's shift), early-leave detection, and the
    late-deduction free-allowance are all correctly wired and unchanged.
  - Holiday/weekend handling: `assessUnauthorizedAbsence` correctly
    excludes `Company.weeklyOffDay` and `Holiday` dates before ever
    checking attendance/leave — confirmed already correct in §2.55's live
    payroll run.
  - Duplicate attendance prevention: `uq_attendance_employee_date` (V25)
    already enforces one row per employee per day at the DB level; the UI
    also only shows "Check in" when no row exists for today.
  - Missing-checkout handling: a checked-in-but-not-checked-out row still
    counts as "attended" (excused from absence) at `workedHours: 0` — a
    correction fixes it later, matching the existing HR-correction design;
    not a bug.
  - Overtime cannot automatically become payroll overtime: every
    auto-calculated claim (`syncOvertimeForToday`) is created with
    `status: 'pending'` and `payrollEligible: false`; only
    `overtime-detail.ts`'s `approve()` (HR/Admin only, self-approval
    blocked by `canDecideOvertimeClaim`) sets `payrollEligible: true`.
    `payroll-engine.ts` independently checks both `status === 'approved'`
    **and** `payrollEligible` before counting a claim. Live-verified: zero
    rows in the DB have `payrollEligible = true` with `status <>
    'approved'`, and zero `pending` rows are payroll-eligible.
  - Overtime write authorization: `PUT /api/overtime/**` is Admin/HR-only
    (no self-service PUT exists for overtime at all, unlike attendance),
    so there's no equivalent cross-employee IDOR on this endpoint.
  - No mock/hardcoded attendance or overtime data — both collections are
    real-backend-only in `HybridApiService.BACKED_COLLECTIONS`.
- **Documentation**: this entry; new/expanded `AttendanceControllerIT`
  tests (3 new: create-spoof, update-IDOR, self-checkout-with-spoofed-id).
- **Verified**:
  - Backend: `mvn clean verify` — **184/184** passing (181 + 3 new),
    `BUILD SUCCESS`.
  - Frontend: `tsc --noEmit` clean; `ng build` clean; `ng test` — 259/259
    passing (unchanged).
  - Backend restarted against the real dev Postgres DB.
  - **Live API verification**: an Employee-token `POST` for a different
    `employeeId` → row created under the caller's own id instead; an
    Admin-created row for a different employee, then an Employee-token
    `PUT` against it → `403`.
  - **Playwright, live, against the running dev servers**: signed in as
    Admin — full check-in/check-out cycle completed, persisted to
    Postgres under the correct real calendar date. Signed out, signed in
    as Employee (a non-manager, exercising the field-lock code path) —
    full check-in/check-out cycle completed and persisted correctly under
    the caller's own employee id and the correct date.
- **Status**: Step 5 — Daily Attendance is payroll-ready. The two IDOR
  fixes close a real path for tampering with the data late/absence/
  overtime deductions are computed from; the timezone fix keeps a
  Bangladesh-hours check-in filed under the correct calendar day.

### 2.59 Step 6 — Employee Leave Request audit, 3 confirmed bugs fixed (2026-09-05)

- **Why**: scoped audit of Employee → Leave Type → Date → Reason → Submit
  → PENDING → HR/Admin decision → payroll impact — the request record an
  approved Unpaid day's deduction is computed from must be trustworthy end
  to end.
- **Bug 1 — any role could submit a leave request for *another* employee
  (confirmed IDOR)**: `LeaveRequestController.create()` saved whatever
  `employeeId` the body carried, no ownership check — `leave-form.ts`
  never lets anyone apply on any id but their own (unlike Attendance,
  there is no "on behalf of" feature at all here), so this was only
  reachable by skipping the app. Live-reproduced before the fix: an
  Employee-token `POST` with `employeeId: "e1"` created the row under
  `e1`. Fixed: `employeeId` is now always forced to the caller's own
  (derived from the authenticated `AppUser`) — no manager exception,
  since no role ever legitimately files leave for someone else. Live-
  reproduced again: the same request now creates the row under the
  caller's own id.
- **Bug 2 — an HR/Admin account could approve or reject its *own* leave
  request (confirmed self-approval bypass)**: `canDecideLeaveRequest`'s
  self-check (`requesterEmployeeId !== approverEmployeeId`) was enforced
  only in `leave-detail.ts` — `LeaveRequestService.update()` (the guarded
  decision endpoint) checked the terminal-state lock but never who the
  request belonged to. Live-reproduced before the fix: an HR-token `PUT`
  approving that HR account's own pending request succeeded. Fixed:
  `update()` now rejects (`403`) any decision where the caller's own
  employeeId matches the request's. Live-reproduced again: the same
  self-approval attempt now returns `403`, while HR approving a
  *different* employee's request (the legitimate case) still works —
  verified live end to end (Employee submits → HR approves → balance
  moves from `remaining` to `taken` in Postgres).
- **Bug 3 — `PUT /api/leave-requests/batch` could re-decide an
  already-approved/rejected request, bypassing the terminal-state lock the
  single-record endpoint enforces**: `putMany()` called a raw
  `repository.saveAll()` with no check at all — `LeaveRequestService`'s
  own Javadoc describes exactly this class of bug (a second decision
  double-moving balance) as already fixed for `PUT /{id}`, but the batch
  endpoint reintroduced the identical gap through a different door. Only
  reachable by Admin/HR (the endpoint's own role gate), but that's exactly
  who legitimately calls it. Live-reproduced before the fix: an HR-token
  batch `PUT` flipped an already-approved request straight to `rejected`.
  Fixed: `putMany()` now checks each incoming row against any existing row
  with the same id and rejects (`409`) if that existing row is already
  `approved`/`rejected`; a genuinely new id (no row on file) still inserts
  normally, unchanged. Live-reproduced again: the same flip attempt now
  returns `409`, and `psql` confirmed the request's status was untouched.
- **Verified correct, no changes needed**:
  - Leave types come from the fixed `Casual/Sick/Earned/Maternity/Unpaid`
    set matching the DB `CHECK` constraint; entitlement per type is
    genuinely HR/Admin-configured (`leave_rule`, read live in the Apply
    form — 10/14/18/112 days shown matched the seeded rules exactly).
  - Date-range validation: `endDate >= startDate` enforced by both the
    frontend and a DB-level `@AssertTrue` on the entity.
  - Overlapping/duplicate leave prevention: `excl_leave_request_overlap`
    (V26, a GIST exclusion constraint scoped to `status <> 'rejected'`)
    already enforces this at the DB level, independent of the frontend's
    own clash check — confirmed still correctly scoped per-employee and
    correctly excluding rejected requests, via the rewritten `Leave
    RequestControllerIT` tests.
  - Past/future-date rules and working-days-vs-calendar-days: no
    restriction on filing leave for a past date, and `countDays()`
    deliberately counts whole calendar days including weekends/holidays
    within the range — both are the project's own stated, deliberate
    design (a `Sick` leave is often reported after the fact; the day-count
    convention is documented in `countDays()`'s own comment), not bugs.
  - Correct HR/Admin approval authority: `PUT /api/leave-requests/**` is
    Admin/HR-only server-side (`SecurityConfig`), matching
    `leave-page.ts`'s own `canApprove` gate; an Employee token gets `403`
    on any decision attempt.
  - Approved Unpaid leave correctly affects payroll, pending/rejected
    leave does not: `payroll-engine.ts` only sums
    `status === 'approved' && leaveType === 'Unpaid'` days into the
    deduction — unchanged, already verified correct in §2.55/§2.58's live
    payroll runs.
  - No mock/hardcoded data: `leave-requests`/`leave-balances`/`leave-rules`
    are all real-backend-only in `HybridApiService.BACKED_COLLECTIONS`.
  - Audit logging: `leave-page.ts`'s submit and `leave-detail.ts`'s
    approve/reject both already call `AuditLogService.record()`.
- **Not fixed, out of scope for this step**: `LeaveBalanceController
  .create()` has the same missing-ownership-check shape (any role could
  POST a fabricated balance row for another employee's id) — noted here,
  not fixed, since Step 6's checklist is about the *request* workflow;
  `OvertimeService` has the same missing self-approval check as Leave's
  Bug 2 above (an HR/Admin account could verify its own overtime claim) —
  also noted, not fixed, since Step 5 (Attendance/Overtime) was already
  closed in §2.58 and reopening it wasn't requested. Both are real,
  same-shape gaps a future session should close.
- **Documentation**: this entry; `LeaveRequestControllerIT` — 2 existing
  tests rewritten (their premise depended on `create()` trusting the
  body's `employeeId`, no longer true) and 2 new tests added (self-
  approval block, batch re-decide block).
- **Verified**:
  - Backend: `mvn clean verify` — **186/186** passing, `BUILD SUCCESS`.
  - Frontend: `tsc --noEmit` clean; `ng build` clean; `ng test` — 259/259
    passing (unchanged — no frontend file needed a fix).
  - Backend restarted against the real dev Postgres DB.
  - **Live API verification**: employeeId-spoofed `POST` → row created
    under the caller's own id; HR self-approval `PUT` → `403`; HR batch
    `PUT` re-deciding an already-approved request → `409`, DB unchanged.
  - **Playwright, live, against the running dev servers**: signed in as
    Employee (Tanvir Ahmed) — submitted a real Casual leave request
    (2 days), saw it land as `pending`; signed out, signed in as HR
    (Nasrin Akter) — the request appeared in the approval queue, opened
    it, approved it; `psql` confirmed `status = 'approved'`,
    `approved_by = 'nasrin.akter'`, and the Casual `leave_balance` row
    correctly moved from `remaining: 10` to `remaining: 8` /
    `taken: 2`.
- **Status**: Step 6 — Employee Leave Request is payroll-ready. The three
  fixes close real tampering/bypass paths around the request record that
  approved-Unpaid payroll deductions are computed from.

### 2.60 Step 8 — Overtime audit, 5 confirmed bugs fixed (2026-09-05)

- **Why**: scoped audit of Attendance → Potential OT detected → OT Request
  → HR verification → Approve/Reject → payroll, verifying every finding
  §2.58/§2.59 explicitly deferred as "same shape, out of scope for that
  step" is now actually closed for Overtime itself.
- **Business flow after fix** (unchanged in shape, now actually enforced
  end to end): an overtime-eligible employee's checkout auto-creates a
  `pending`, `payrollEligible: false` claim for *their own* employee id
  only; HR/Admin (never the claim's own employee) verifies or rejects it;
  verifying is the only path that ever sets `payrollEligible: true`, and
  it's now derived from `status` server-side, not trusted from any
  request body; `payroll-engine.ts` only ever sums claims that are both
  `approved` **and** `payrollEligible`.
- **Bug 1 — any role could create an overtime claim for *another*
  employee (confirmed IDOR)**: `OvertimeController.create()` saved
  whatever `employeeId` the body carried — `attendance-page.ts`'s
  `syncOvertimeForToday()` (the only creator) always claims for the
  caller's own checkout, so this was only reachable by skipping the app.
  Live-reproduced before the fix: an Employee-token `POST` with
  `employeeId: "e1"` created the row under `e1`. Fixed: `employeeId` is
  now always forced to the caller's own, no manager exception — same
  reasoning as Leave's identical fix (§2.59): no role ever legitimately
  claims overtime for someone else.
- **Bug 2 — an HR/Admin account could verify or reject its own overtime
  claim (confirmed self-approval bypass)**: `OvertimeService` had a
  terminal-state lock (`rejected` is final) but no self-decision check at
  all — flagged as a known gap in §2.58/§2.59, now closed. Live-
  reproduced before the fix: HR approving their own pending claim
  succeeded. Fixed: `update()` now rejects (`403`) any decision where the
  caller's own employeeId matches the claim's; a *different* approver
  (e.g. Admin deciding HR's claim) still works, live-verified.
- **Bug 3 — `payrollEligible` and `status` could disagree, and both were
  trusted verbatim from the client (confirmed tampering vector)**: nothing
  stopped a `PUT` from setting `payrollEligible: true` while leaving
  `status: 'pending'` (or the reverse — `approved` with `payrollEligible:
  false`), and nothing stopped a `POST` from creating a claim that was
  already `approved`/payroll-eligible on arrival, skipping verification
  entirely. Fixed: `create()` now always forces a new claim to
  `status: 'pending'`, `payrollEligible: false`, regardless of the body;
  `update()` now derives `payrollEligible` from `status` itself
  (`"approved".equals(status)`), ignoring whatever the client sent. Live-
  reproduced both directions: a pre-approved `POST` body → still created
  `pending`/`false`; a `PUT` claiming `payrollEligible: true` while
  `status` stayed `pending` → still saved as `false`.
- **Bug 4 — no duplicate-claim prevention (confirmed
  overclaiming path)**: an employee can only work one shift per day (no
  multi-shift model), so exactly one overtime claim per employee per day
  is the correct invariant — `syncOvertimeForToday()`'s deterministic
  `ot-{employeeId}-{date}` id already assumes this, but nothing stopped a
  second, differently-id'd claim for the same employee/day via a direct
  API call, double-claiming the same overtime. Fixed:
  `V36__overtime_employee_date_unique.sql` (`uq_overtime_employee_date`,
  same shape as V25/V30/V34/V35), `ApiExceptionHandler`'s existing generic
  "unique" branch turning the violation into a clean `409`. Verified
  against the live dev DB first: no existing employee had two claims on
  the same date, so it applied cleanly. Live-reproduced: a second claim
  for the same employee/date → `409`.
- **Bug 5 — the Bangladesh Labour Act daily (4h) and weekly (12h) overtime
  ceilings existed only in `overtime-rules.ts` (`cappedOvertimeHours`),
  never enforced server-side**: a direct `POST` could claim any number of
  hours in a day, or push an employee arbitrarily far past the legal
  weekly overtime limit, since nothing but the auto-calculation path (the
  one place the frontend actually calls `cappedOvertimeHours`) ever
  applied the cap. Fixed: `OvertimeService.create()` now rejects (`400`)
  any claim exceeding 4 hours in a single day, and separately sums the
  employee's own non-rejected hours in the same ISO (Monday-anchored)
  week — matching `overtime-rules.ts`'s `weeklyHours` exactly — rejecting
  (`400`) if the new claim would push the week's total past 12 hours.
  Scoped to `create()` only, not `update()` — overtime-detail.ts's
  "Correct" action is a deliberate HR override for exceptional cases (a
  missed check-out found after approval), and the frontend's own cap
  never applied there either, so correction stays uncapped by design.
  Live-reproduced: a single 6-hour claim → `400`; three 4-hour claims
  across a week (12 total, at the ceiling) all succeeded, a fourth
  1-hour claim on top (13 total) → `400` with the exact running total in
  the message.
- **Verified correct, no changes needed**:
  - OT detection from attendance already correctly reads the employee's
    own shift (`scheduledMinutes` from `shift.startTime`/`endTime`/
    `breakMinutes`) and only fires for `overtimeEligible && status ===
    'active'` employees — unchanged, already audited in §2.58.
  - Who can create/submit claims: `POST /api/overtime/**` stays open to
    every role (self-service auto-calc), unchanged and correct.
  - HR-only approve/reject: `PUT /api/overtime/**` is Admin/HR-only
    server-side (`SecurityConfig`), matching `session.canApproveOvertime`.
  - State transitions: `rejected` remains a locked terminal state (`409`
    on any further change); `approved` deliberately stays correctable
    (documented, unrelated, pre-existing design for the missed-checkout
    case) — unchanged.
  - Audit logging: `overtime-detail.ts`'s `approve()`/`reject()` already
    call `AuditLogService.record()` with actor role/name, action, outcome,
    and a details string carrying the employee, date, hours, claim id,
    and (for rejection) the reason — all present already, no gap.
  - Payroll engine correctly uses only `approved && payrollEligible`
    claims, and OT amount/rate flow into `payslip.overtimeAmount`/
    `grossSalary` unchanged — reconfirmed against §2.58's live payroll
    run, no regression from today's changes (no payroll code touched).
  - PostgreSQL constraints: `employee_id` FK (`NOT NULL REFERENCES
    employee(id)`, since V4) already correct; `hours`/`rate`/`amount`
    validated `@Positive`/`@PositiveOrZero`; `status`/`payrollEligible`
    `@NotBlank`/`@NotNull`.
- **Documentation**: this entry; `OvertimeControllerIT` — 7 new tests
  (ownership IDOR, pre-approved-body ignored on create, payrollEligible/
  status-mismatch ignored on update, self-approval block, duplicate
  claim, daily cap, weekly cap).
- **Verified**:
  - Backend: `mvn clean verify` — **193/193** passing (186 + 7 new),
    `BUILD SUCCESS`.
  - Frontend: `tsc --noEmit` clean; `ng build` clean; `ng test` — 259/259
    passing (unchanged — no frontend file needed a fix).
  - Backend restarted against the real dev Postgres DB; `flyway_schema_
    history` confirms V36 applied successfully.
  - **Live API verification**: all 5 bugs reproduced pre-fix and
    re-verified closed post-fix, exactly as described above, against the
    real running backend/Postgres.
  - **Playwright, live, against the running dev servers, signed in as
    HR**: a real pending claim (seeded directly in Postgres for an
    overtime-eligible test employee, since none of the four login-capable
    demo accounts are overtime-eligible) appeared correctly in the
    Overtime approval queue and records table, marked "Not included";
    opened it, clicked "Verify record" — `psql` confirmed
    `status='approved'`, `payroll_eligible=true`, `approved_by=
    'nasrin.akter'`, and the UI immediately reflected "Verified" /
    "Included in Payroll".
- **Status**: Step 8 — Overtime is payroll-ready. All five fixes close
  real tampering/bypass/overclaiming paths around the exact flag
  (`payrollEligible`) and record `payroll-engine.ts` trusts.

### 2.61 Step 9/10 — Loan Request & Bonus audit, 4 confirmed bugs fixed (2026-09-05)

- **Why**: scoped audit of both flows — Employee/HR → Loan Request →
  EMI/Repayment → HR review → Approve/Reject → Loan schedule → monthly
  payroll recovery; HR → Create Bonus → Accountant approval → payroll —
  verifying the same class of gaps found and closed in Steps 5/6/8 (§2.58/
  §2.59/§2.60) don't also exist here.
- **Business design confirmed (not changed)**: unlike Attendance/Leave/
  Overtime (pure self-service, no "on behalf of" path), Loan and Bonus
  both have a real, intentional on-behalf-of path: `loan-form.ts`'s
  `canChooseEmployee` lets HR raise a loan for any worker (an Employee may
  only raise for themselves); `bonus-form.ts` is HR-only with an
  unconditional employee picker (there is no employee self-service bonus
  path at all). Both fixes below respect that split rather than forcing
  every caller to their own id.
- **Bug 1 — an Employee could raise a loan request for *another* employee
  (confirmed IDOR)**: `LoanRecordController.create()` saved whatever
  `employeeId` the body carried regardless of caller role — the frontend's
  own `canChooseEmployee` split was never enforced server-side. Live-
  reproduced before the fix: an Employee-token `POST` with `employeeId:
  "e1"` created the row under `e1`. Fixed: `LoanRecordService.create()`
  now forces `employeeId` to the caller's own unless the caller is HR
  (mirroring the frontend's exact split); an HR caller's chosen
  `employeeId` is still honored, unchanged.
- **Bug 2 — an HR account could approve/reject its own loan request, and
  an Accountant could approve/reject its own bonus (confirmed
  self-approval bypass, both modules)**: `LoanRecordService
  .assertDecisionAuthority()` already checked "is this caller HR" (a
  2026-09-02 fix) but never "is this HR account also the requester";
  `BonusRecordService.update()` had no decision-authority check at all
  beyond the terminal-state lock. Both gaps were explicitly named in the
  frontend's own `canDecideLoanRequest`/`canDecideBonusRequest` comments
  as still-relevant scenarios, enforced only client-side. Live-reproduced
  before the fix: HR approving their own pending loan succeeded;
  Accountant approving their own pending bonus succeeded. Fixed: both
  services now reject (`403`) a decision where the caller's own
  employeeId matches the record's, alongside the existing role checks.
  **Known, accepted structural consequence, not a new bug**: since loan
  decisions are HR-only with no Admin override (an existing, deliberate
  design choice — session.ts has no `canApproveLoans` override), and this
  dev environment seeds only one HR account, that account's own loan
  requests can now never be approved by anyone in this environment. This
  is exactly what "no self-approval, HR-only, single HR seeded" implies
  together; not something this fix changed the shape of.
- **Bug 3 — no duplicate/overlapping-open-loan prevention (confirmed
  overclaiming path), and no EMI-vs-principal sanity check**: `loan-
  rules.ts`'s "one open loan (pending/approved/active) per employee" and
  "EMI cannot exceed principal" were both frontend-only — nothing stopped
  a direct API call from creating a second open loan for an employee who
  already had one, or an EMI larger than the principal itself. Unlike
  Bonus (which already has `uq_bonus_record_open_employee_type_date`,
  V25), Loan had no DB-level equivalent. **Live dev data already has a
  real violation** (a separated employee, Sultana Razia, carries two open
  loans — pre-existing demo-data noise, not touched, same "don't
  auto-remediate real records" call as §2.53's duplicate-email finding) —
  so, matching that same precedent, this is enforced at the
  **application level only**, not a blocking DB constraint that would
  fail to migrate against the existing dirty row. Fixed:
  `LoanRecordService.create()` now checks the employee's existing loans
  and rejects (`409`) a second open one, and rejects (`400`) an EMI
  exceeding the principal. Live-reproduced: a second loan for an
  already-open employee → `409`; an EMI larger than the principal → `400`.
- **Verified correct, no changes needed**:
  - EMI calculation and outstanding balance: `payroll-engine.ts`'s
    `desiredLoanRecovery`/`applyLoanRecovery` already correctly recover
    `min(emiAmount, outstandingBalance)` per active loan each cycle,
    close the loan at zero, and reopen it on a downward correction —
    unchanged, reconfirmed against §2.55's live payroll run (8 loan
    employees' balances all reduced by exactly their EMI).
  - Loan close behavior: `batch-detail.ts`'s `pay()` legitimately closes
    an active loan (Accountant/Admin, `PUT` scoped to exactly that
    transition by `assertDecisionAuthority`'s narrower "only pending→
    approved/rejected is a decision" check) — unaffected by today's
    changes, confirmed by the existing `accountantCanStillCloseAnActive
    LoanDuringPayroll` test still passing.
  - Approved/unpaid bonus handling and double-payment prevention:
    `payroll-engine.ts` only sums `status === 'approved'` bonuses whose
    `paymentDate` falls in the batch's own cycle; `batch-form.ts` already
    blocks creating two batches for the same month, and non-overlapping
    calendar-month cycles mean the same bonus can't be picked up by two
    different regular payroll runs. `BonusRecord.settlementId` prevents a
    Final Settlement from double-claiming an already-settled bonus; by
    the time a bonus is claimed by a settlement the employee is already
    `separated` (settlement completion separates the employee — §1.8),
    which independently excludes them from every future regular payroll
    run's `status === 'active'` filter. No gap found.
  - Pending bonus/loan behavior: `payroll-engine.ts` only reads `status
    === 'approved'` for both — pending and rejected records contribute
    nothing to any payslip, unchanged.
  - Audit logging: both `loans-bonuses-page.ts` (submit) and `loan-
    detail.ts`/`bonus-detail.ts` (approve/reject) already call
    `AuditLogService.record()` with actor role/name, action, outcome, and
    a details string carrying employee, amount, and (for rejection) the
    reason.
  - PostgreSQL constraints: `employee_id` FK on both tables (since V5);
    `principal`/`emiAmount`/`amount` `@Positive`, `outstandingBalance`
    `@PositiveOrZero`; Bonus's own duplicate-open constraint (V25)
    unaffected.
- **Documentation**: this entry; `LoanRecordControllerIT` — switched to a
  dedicated fixture employee (e4 already carries a real active loan in
  the seed data, which the new duplicate check now correctly rejects
  against) and 4 new tests; `BonusRecordControllerIT` — 1 new test;
  `AuthorizationIT.employeeCanRaiseALoanRequest` — updated to assert
  `notForbidden()` instead of `isCreated()` for the same seed-data reason,
  matching that test class's own established convention for a case where
  authorization clears but a business rule still applies.
- **Verified**:
  - Backend: `mvn clean verify` — **198/198** passing (193 + 5 new),
    `BUILD SUCCESS`.
  - Frontend: `tsc --noEmit` clean; `ng build` clean; `ng test` — 259/259
    passing (unchanged — no frontend file needed a fix).
  - Backend restarted against the real dev Postgres DB.
  - **Live API verification**: all 4 bugs reproduced pre-fix and
    reconfirmed closed post-fix (employeeId spoof corrected; EMI-exceeds-
    principal → `400`; second open loan → `409`; HR self-approving own
    loan → `403`; Accountant self-approving own bonus → `403`).
  - **Playwright, live, against the running dev servers**: signed in as
    HR — raised a real loan request for an employee with no existing
    loan, opened it, approved it — `psql` confirmed `status='active'`
    (loans go straight to the recovery-ready `active` status on approval,
    matching "Loan schedule" in the business flow), `approved_by=
    'nasrin.akter'`. Raised a real bonus request for the same employee;
    signed out, signed in as Accountant — approved it through the real
    UI — `psql` confirmed `status='approved'`, `approved_by='rakib.
    hasan'`, `amount=5000.00`.
- **Status**: Step 9 (Loan Request) and Step 10 (Bonus) are both
  payroll-ready. All four fixes close real ownership/self-approval/
  overclaiming paths around the exact records `payroll-engine.ts` trusts
  for recovery and bonus disbursement.

### 2.62 Step 11/12 — PF & Tax Calculation audit, 3 confirmed bugs fixed (2026-09-05)

- **Why**: scoped audit of Gross/eligible salary → PF Rule → Employee PF +
  Employer PF, and Salary → taxable components → configured slabs →
  monthly withholding — the two remaining configuration-driven deduction
  paths payroll depends on.
- **Bug 1 — a second PF rule could be created, making PF calculation
  nondeterministic (confirmed payroll-correctness bug)**: `salary-rules-
  page.ts` only ever offers "Edit rule" once a PF rule exists (`pfForm.set
  (pfRules().at(0) ?? 'new')` — there's no "Add" path when one is already
  on file) — this project's real design is exactly one current PF rule,
  same shape as Salary Structure's "one per employee" (§2.56). `batch-
  detail.ts` reads `pfRules()[0]` with **no effective-date selection at
  all** — the *first* row, in whatever order the backend returns it —
  exactly the same "insertion/query order decides the outcome" hazard
  `TaxRuleService` was already built to prevent for tax slabs
  (2026-09-02). Nothing stopped a second `PfRule` via a direct API call.
  Fixed: `V37__pf_rule_singleton.sql` — a unique index on the constant
  expression `(true)` (the standard Postgres idiom for "at most one row in
  this table"), `ApiExceptionHandler`'s existing generic "unique" branch
  turning the violation into a clean `409`. Verified against the live dev
  DB first: exactly one PF rule exists, so it applied cleanly. Live-
  reproduced: a second `POST` → `409`; the existing rule is still freely
  editable in place.
- **Bug 2 & 3 — editing an existing PF rule or tax slab opened a blank
  form instead of the current values (confirmed, live-reproducible UI
  bug, both modules)**: both `PfRuleForm` and `TaxRuleForm` read
  `this.existing()` directly in their constructors — but Angular signal
  inputs are not populated until *after* the constructor runs, so this
  always saw the default `null`, even when "Edit" genuinely bound the
  current rule. This exact anti-pattern (and its fix) is already
  documented elsewhere in this codebase — `attendance-correction-form.ts`
  ("record is a required input — not guaranteed to be bound yet while the
  constructor runs — so it's read inside `effect()` instead"); these two
  forms just never got it. Live-reproduced before the fix: clicking "Edit
  rule" on the one PF rule, and "Edit" on any tax slab, opened a form with
  every field blank/zeroed rather than the real current values — a real
  risk of an Admin not noticing and saving 0%/blank over a genuine
  configured rate. Fixed: both constructors now read `existing()` inside
  `effect()`, matching the established pattern exactly. Live-reproduced
  again: both forms now correctly prefill every field.
- **Verified correct, no changes needed**:
  - PF calculation accuracy: `pf = round(basic * pfRule
    .employeeContributionPct / 100)`, using the already-prorated `basic`
    (mid-cycle joiners/leavers scale correctly) — reconfirmed against live
    payslips: te-001 (basic ৳60,000, 10%) → `pf = 6000.00` exactly;
    te-019 (`appliesPF: false`) → `pf = 0`.
  - Employee vs employer PF: `employerContributionPct` is stored on the
    rule for configuration/display only — it is never read anywhere in
    `payroll-engine.ts` or written to any `Payslip` field, so "Employer PF
    must never reduce employee net salary" is satisfied *by construction*
    (there is no code path where it could). Only `employeeContributionPct`
    feeds the deduction. Building out employer-PF tracking/reporting
    (e.g. for company-side accounting) would be a new feature, not a bug
    fix — not attempted here.
  - Tax slab/rule selection and calculation: `monthlyTax` selects the slab
    off the employee's nominal full-month gross (`nominalGross`) and
    applies the resolved rate to the actually-prorated amount
    (`appliedGross`) — reconfirmed against live payslips: te-001 (annual
    ৳1,080,000 → 15% slab) → `tax = 13500.00` exactly; te-019 (annual
    ৳444,000 → 5% slab) → `tax = 1850.00` exactly; te-007
    (`appliesTax: false`) → `tax = 0`. All match hand-computed values
    exactly, no rounding drift found.
  - Configurable, not hardcoded: both `pf_rule` and `tax_rule` are
    entirely DB-driven and Admin-editable through the real UI/API — no
    hardcoded rate or slab anywhere in `payroll-engine.ts`.
  - Effective dates/rule conflicts (Tax): `TaxRuleService`'s overlap check
    (2026-09-02, unchanged) already prevents two slabs with overlapping
    income ranges — the actual rule-conflict hazard for a module where
    multiple simultaneously-active rows is the correct design (unlike
    PF's singleton). The `effective_from` field itself (on both PF and
    Tax) is stored/displayed metadata only, not consulted by the engine
    against a payroll cycle's date — the same already-accepted,
    documented limitation as Salary Structure's `effectiveFrom` (§2.56):
    no historical-rule-versioning feature exists anywhere in this
    project, so this isn't a new bug, just the same design applied
    consistently.
  - API/server-side validation and tampering: both `PfRule`/`TaxRule`
    writes are Admin-only (`SecurityConfig`), confirmed live (`403` for
    an HR token); percentage/rate fields are bounded `0–100`
    (`@DecimalMin`/`@DecimalMax`); Tax's income range is `@PositiveOrZero`
    with `maxIncome > minIncome` enforced by `@AssertTrue`. No tampering
    path found beyond the two bugs above.
  - Payroll engine integration and payslip display: both figures flow
    into `Payslip.tax`/`Payslip.pf` and render on the batch/payslip
    detail views unchanged — reconfirmed against §2.55/§2.61's live
    payroll data, no regression.
  - Rounding/zero/negative edge cases: `Math.round` on non-negative inputs
    throughout — no path produces a negative or `NaN` PF/tax value;
    missing rule (`pfRule` undefined, or no matching tax slab) degrades to
    `0`, never throws.
  - DB constraints: `employee_id`-independent config tables, both with
    `@NotNull`/bounded columns; Tax's overlap constraint enforced at the
    service layer (not DB-level, since ranges aren't a simple equality/
    overlap the DB can check without the same GIST-exclusion machinery
    V26 uses for leave — the service-layer check is this project's
    existing, sufficient answer here, unchanged).
  - Audit logging: `salary-rules-page.ts`'s `savePf()`/`saveTax()` already
    call `AuditLogService.record()` with actor, action, and a details
    string naming the scheme/slab and the new values.
- **Documentation**: this entry; new `PfRuleControllerIT` (this
  controller had no tests before this session) — 3 tests (edit-in-place,
  second-rule conflict, non-Admin write forbidden).
- **Verified**:
  - Backend: `mvn clean verify` — **201/201** passing (198 + 3 new),
    `BUILD SUCCESS`.
  - Frontend: `tsc --noEmit` clean; `ng build` clean; `ng test` — 259/259
    passing (one run hit an unrelated Vitest worker crash/timeout — a
    known environmental flake, no code involved — the immediate retry
    passed cleanly).
  - Backend restarted against the real dev Postgres DB; `flyway_schema_
    history` confirms V37 applied successfully.
  - **Live API verification**: a second PF rule `POST` → `409`; the
    existing rule's `PUT` still succeeds; hand-computed PF/tax figures
    for 4 real employees matched the live payslip data exactly.
  - **Playwright, live, against the running dev servers, signed in as
    Admin**: opened "Edit rule" on the Provident Fund tab — confirmed
    blank before the fix, confirmed fully prefilled (name, both
    percentages, effective date) after; opened "Edit" on a real tax slab
    — confirmed the same blank-before/prefilled-after result. No changes
    were saved during verification — `psql` confirmed both tables
    unchanged (1 PF rule, 5 tax slabs) throughout.
- **Status**: Step 11 (PF Calculation) and Step 12 (Tax Calculation) are
  both payroll-ready. The PF singleton fix closes a real payroll-
  correctness hazard; the two form fixes close a real risk of an Admin
  accidentally overwriting a live rate with zero/blank values.

### 2.63 Step 13-21 — Payroll Lifecycle audit, 2 confirmed bugs fixed (2026-09-05)

- **Why**: scoped audit of the full payroll lifecycle end to end — DRAFT →
  collect inputs → CALCULATED → HR/Accountant review → APPROVED → LOCKED →
  payslip → payment → PAID — against `PayrollBatchController`/
  `PayrollBatchService`, `PaymentController`, `PayslipController`, and their
  entities. Nearly the entire state machine, immutability, and IDOR surface
  was already correctly built in a prior 2026-09-02 session (§2.50); this
  audit re-verified every item live rather than trusting the prior read.
- **Bug 1 — an Admin could approve or reject their own submitted payroll
  batch via a direct API call (confirmed security bypass)**: `payroll-
  rules.ts`'s `canApproveBatch(requestedByUsername, approverUsername)`
  self-check — closing exactly the case of an Admin who both ran/submitted
  a batch (via `canRequestPayroll`) and also holds `canApproveBatch` — was
  enforced client-side only. `PayrollBatchService.update()` already checked
  transition legality, the payment-before-paid race, and identity/totals
  locking, but nothing stopped a raw `PUT` from the same Admin's token
  moving their own `pending-approval` batch to `approved` (or back to
  `draft` via "return with remarks"). Fixed: `update()` now derives the
  caller from `Authentication`, and when the transition is a real decision
  out of `pending-approval` (`to != from`), rejects it with `403` if
  `existing.getRequestedBy()` equals the caller's username.
  Live-reproduced: Admin (`farhana.islam`) submits a batch, then attempts to
  approve it with the same token → `403 "You may not approve or reject a
  payroll batch you submitted yourself."`; Accountant (`rakib.hasan`)
  approving the same batch → `200`, unaffected.
- **Bug 2 — a Payment could be recorded with any amount, not just the
  batch's actual net payable (confirmed financial-integrity gap)**:
  `PaymentController.create()` called `assertBatchApprovedForPayment`,
  which checked the batch's status but never the amount. `batch-detail.ts`'s
  `pay()` always posts `amount: batch.netTotal`, so the UI never drifts —
  but nothing server-side stopped a raw `POST /api/payments` naming any
  amount for an approved batch, which could then walk the batch on to
  `paid` right after (the paid-transition guard only checks a payment
  *exists*, not that it matches). Fixed: `assertBatchApprovedForPayment`
  now also takes the posted `amount` and rejects a mismatch against the
  batch's `netTotal` with `409`. Live-reproduced on a disposable test batch:
  a `POST` with `amount: 1` against a `45000`-net-total approved batch →
  `409 "Payment amount must match the batch's net payable total exactly."`;
  the correct amount → `201`.
- **Verified correct, no changes needed** (re-confirmed live, not just by
  reading code, since this audit's whole point was independent
  verification of the 2026-09-02 work):
  - Overlapping-cycle prevention, full transition table (`draft` →
    `calculated` → `pending-approval` → `approved` → `paid`, rejection back
    to `draft`), paid-batch total immutability, identity-field lock
    (`batchRef`/`month`/cycle dates/`requestedBy`), payment-before-paid race
    guard, and payslip/payment mutability tied to their parent batch's
    mutability — all already correct from §2.50, re-verified against the
    full `mvn clean verify` suite plus fresh Playwright/API checks.
  - Payslip employee-visibility IDOR fix (§2.50): live-confirmed as
    Employee `tanvir.ahmed` — `/payslips` shows only that employee's 5 own
    payslips; a direct URL to another employee's real payslip
    (`ps-pb-202608-1788161765190-e-1787546658330`, from the real paid
    `PR-2026-08` batch) → `404` (not `403`), deliberately indistinguishable
    from missing, matching `PayslipController`'s existing design.
  - HR vs Accountant separation: live-driven through the real UI as HR
    (`nasrin.akter`) creating, running, and submitting a fresh batch
    (`PR-2027-03`), then as Accountant (`rakib.hasan`) approving it —
    correct dates auto-derived (`2027-03-01 → 2027-03-31` from the month
    picker alone), correct cross-role approval succeeding.
  - Correction workflow + authorization + audit log: `batch-detail.ts`
    already calls `AuditLogService.record()` at every stage (create, run,
    submit, approve, reject, pay) — live-confirmed on the audit log page: 4
    entries for `PR-2027-03` (HR created → HR ran engine, "56 payslip(s)
    generated" → HR submitted → Accountant approved), each with actor,
    role, and timestamp.
  - LOCKED/paid immutability: the real, paid August 2026 batch
    (`PR-2026-08`) shows no edit/recalculate/pay controls at all in the UI
    once `paid` — only the read-only bank payment record; its recorded
    payment amount (৳721,137) matches `netTotal` exactly.
  - Calculation accuracy, no unapproved/pending overtime/leave/bonus
    entering payroll, loan recovery/no over-recovery, PF employee-vs-
    employer split, tax calculation, late/unpaid-leave deductions: all
    already deeply verified against live payroll runs in §2.55/§2.58–§2.62;
    re-spot-checked against the real paid `PR-2026-08` batch's 9 payslips
    (e.g. Ruma Begum: gross ৳440,103, tax ৳88,021, PF ৳43,245, net
    ৳308,837) — consistent with the engine logic already re-verified
    module-by-module this session, no drift found.
  - Duplicate payroll/payslip/payment prevention: `batchRef` DB-level
    uniqueness, the overlap-cycle check, `assertBatchApprovedForPayment`,
    and the payment-before-paid race guard together already close every
    duplication path found.
  - A genuinely fresh cycle with no seeded attendance (`PR-2027-03`, used
    only for this audit's live lifecycle/authorization verification, then
    deleted) produces a large absence deduction and near-zero net pay by
    design — the engine correctly treats an unattended period as fully
    absent; this is the same already-documented reason `PR-2027-02` was
    left uncommitted in §2.55, not a new bug.
- **Documentation**: this entry; new `PayrollBatchControllerIT
  .adminCannotApproveTheirOwnSubmittedBatch` and `PaymentControllerIT
  .paymentAmountNotMatchingTheBatchNetTotalIsRejected`.
- **Verified**:
  - Backend: `mvn clean verify` — **203/203** passing (201 + 2 new),
    `BUILD SUCCESS`.
  - Frontend: `tsc --noEmit` clean; `ng build` clean (no frontend files
    changed this audit); `ng test` — 259/259 passing.
  - Backend restarted twice against the real dev Postgres DB to pick up
    both fixes; no schema change, no new Flyway migration needed.
  - **Live API verification**: both bugs reproduced pre-fix-equivalent
    (via a disposable test batch mimicking the vulnerable state) and
    confirmed closed post-fix, as detailed above; all test rows deleted
    afterward, confirmed via `psql` (zero leftover rows).
  - **Playwright, live, against the running dev servers**: full HR-create →
    run-engine → submit → Accountant-approve lifecycle driven through the
    real UI on a fresh cycle; payslip employee-visibility and cross-
    employee IDOR block confirmed as `tanvir.ahmed`; the real paid
    `PR-2026-08` batch's read-only, no-action-buttons state confirmed as
    Admin; the full audit trail confirmed on `/audit`. The test batch and
    its 56 payslips were fully deleted afterward (verified via `psql`); no
    real payroll data was touched or altered.
- **Status**: Step 13–21 (the complete payroll lifecycle, DRAFT through
  PAID) is payroll-ready. Both confirmed bugs were direct-API-bypass gaps
  in server-side enforcement of invariants the UI already respected —
  the same class of gap closed for every other module this session — not
  flaws in the payroll calculation logic itself, which was independently
  re-confirmed correct.

### 2.64 Employee payroll master-data cleanup: 12 orphans deleted, salary/grade fixes, 100% salary-structure coverage (2026-09-05)

- **Why**: after 76 employees accumulated across every prior audit/seeding
  session, an end-to-end data-quality pass — genuinely-orphaned records
  removed, every remaining employee correctly linked through Department →
  Designation → Grade → Salary Structure → PF/Tax, and salary bands
  internally consistent grade-to-grade.
- **Employee cleanup (12 deleted, 64 retained)**: cross-checked every
  employee against all 11 FK-referencing tables (`app_user`, `attendance`,
  `bonus_record`, `change_request`, `final_settlement`, `leave_balance`,
  `leave_request`, `loan_record`, `overtime`, `payslip`, `salary_structure`)
  plus `department.head_employee_id`. 12 employees had **zero** rows in
  every one of those tables — no login, no attendance, no payslip, nothing
  — several with codes/names inconsistent with the real seeding convention
  (`fdfd`; `FIN`/`HRM`/`M3`/`PRD` codes on single-word test names), clearly
  abandoned manual test entries: `EMP-1010` Abdul Karim, `EMP-1011` Nusrat
  Jahan, `EMP-1012` Mizanur Rahaman, `EMP-1013` Shirin Sultana, `EMP-1014`
  Habibur Rahaman, `EMP-1015` Mahmuda Khatun, `EMP-1016` jakia mukta,
  `EMP-1030` fdfd, `FIN` Mahin, `HRM` Araf, `M3` Atiq, `PRD` Mohammad Ali.
  Confirmed with the user before deleting (irreversible). Deleted via the
  real `DELETE /api/employees/{id}` API, not raw SQL. The previously-
  flagged "10/11 employees with no salary structure" list (§2.55/§2.56)
  is fully resolved by this cleanup plus the coverage fix below — every
  name on that list was either deleted here as a true orphan or given a
  structure (below). **Not deleted for lacking a salary structure alone**
  — every survivor was kept purely on having at least one dependent record,
  per the explicit instruction.
- **Bug 1 — an employee's stored `salaryGrade` didn't match their actual
  designation's grade (confirmed data-integrity bug)**: employee `4324`
  "mukta" (General Manager) had `salaryGrade = 'G1'` on file, but her
  designation (`g-1787483885727`, "General Manager") is grade `M1` in the
  `designation` table — `employee-form.ts`'s `derivedSalaryGrade` always
  sets this field from the selected designation, so a real UI save can
  never produce this drift; the row could only have gotten here from a
  raw write bypassing the form. Fixed: `salaryGrade` corrected to `M1` to
  match her real designation.
- **Bug 2 — a Helper-grade (W3) employee's salary was ~30x every other
  Helper's, badly inverting the pay hierarchy (confirmed data bug)**:
  `EMP-1009` Ruma Begum (W3/Helper) had `basic = 432,445.00`, `gross =
  440,103.00` — every other of the 8 real Helper-grade employees is
  `basic = 10,000.00`, `gross = 14,500.00` exactly. This alone violated
  "senior grades must not randomly earn less than junior grades" about as
  badly as possible (a Helper out-earning every General Manager in the
  company, `max M1 gross = 131,000`). Fixed: corrected to the exact
  established Helper band (`basic 10,000 / hra 3,000 / allowances 1,500 /
  gross 14,500`). Her existing paid payslips (`PR-2026-06`–`PR-2026-12`,
  computed off the old wrong salary) were left untouched — paid batches
  are immutable by design; this only affects payroll runs going forward.
- **Salary-structure coverage — 3 created (100% coverage, 64/64)**: the
  three real demo accounts (`DEMO-ADMIN`/`DEMO-HR`/`DEMO-ACCOUNTANT`,
  grade `D1`/"Demo Role") were the last employees with no salary structure
  at all — previously excluded from every payroll run (§2.55's flagged
  gap). Given a structure identical to the existing `DEMO-EMPLOYEE` (`e4`)
  D1 precedent exactly (`basic 30,000 / hra 12,000 / allowances 5,000 /
  gross 47,000`, `appliesTax`/`appliesPF` both true, matching their
  `permanent` employment type) — same grade, same band, for consistency.
  Not a new, invented rate: copied from the one D1 employee already on
  file.
- **Verified correct, no changes needed**:
  - `applies_pf`/`applies_tax` per-employee flags: cross-checked against
    §2.55's own documented seeding design ("`applies_pf` true for
    permanent, false for contract/probation, plus one deliberate exception
    on a permanent employee to test the flag"; same pattern for
    `applies_tax`) — the handful of employees that don't follow the
    permanent→true pattern are confirmed intentional test-scenario data
    from that session, not bugs. Left untouched.
  - Tax slab configuration: the 5 configured Bangladesh slabs (Exempt to
    ৳350,000 at 0%, then 5%/10%/15%/20% up to unbounded) are unchanged,
    real, and already correctly applied by `payroll-engine.ts`'s
    `monthlyTax` per employee's actual nominal annual gross — nothing to
    "assign" per employee beyond the existing `appliesTax` exemption flag,
    since tax slab selection is dynamic, not a stored per-employee field.
    No new tax logic invented.
  - `gross_salary = basic + hra + allowances` exactly, for all 64
    structures, re-verified via `psql` after every edit.
  - Exactly one salary structure per employee, for all 64, re-verified via
    `psql` (`GROUP BY employee_id HAVING count(*) > 1` → 0 rows).
- **Documentation**: this entry. No test files needed changes — this was a
  pure data/configuration cleanup, no code touched.
- **Verified**:
  - Backend: `mvn clean verify` — **203/203** passing, `BUILD SUCCESS`
    (unchanged — no backend code touched, only data via the real API).
  - Frontend: `tsc --noEmit` clean; `ng build` clean; `ng test` —
    259/259 passing (unchanged, no frontend code touched either).
  - **PostgreSQL verification**: 64 employees (down from 76); 64 salary
    structures, exactly one per employee; zero `gross_salary` mismatches;
    grade-band summary now strictly consistent — M1 ৳90,000–131,000 > M2
    ৳68,000–95,800 > M3 ৳53,000–70,000 > E1 ৳37,000–49,800 > W1
    ৳26,000–29,600 > W2 ৳20,000–22,800 > W3 ৳14,500 (D1's ৳47,000 sits
    outside this production ladder, as a demo-login-only grade, internally
    consistent with itself).
  - **Live API verification**: `mukta`'s `salaryGrade` PUT confirmed
    `G1`→`M1`; both salary-structure corrections and all 3 new demo-account
    structures confirmed via `GET` echoing the corrected values.
  - **A fresh draft payroll calculation** (`PR-2027-03`, created, run, then
    fully deleted after verification — no real data touched) confirmed the
    fixes flow through the real engine: `mukta` (M1) → gross ৳90,000, PF
    ৳6,000, tax ৳13,500 (exactly matching the existing M1 entry-band
    precedent `te-001`); Ruma Begum (W3) → gross ৳14,500, PF ৳1,000, tax
    ৳0 (exactly matching the established Helper band, down from the old
    ৳440,103); all 3 demo accounts → gross ৳47,000, PF ৳3,000, tax ৳4,700
    (exactly matching `DEMO-EMPLOYEE`'s existing figures). Net pay reads
    near-zero for this test batch only because it's a fresh cycle with no
    seeded attendance — the same already-documented artifact as
    `PR-2027-02` (§2.55), not a bug; gross/PF/tax (the figures the fixes
    actually touch) are unaffected by attendance and were the ones
    verified.
  - **Playwright, live, against the running dev servers, signed in as
    Admin**: Employee register shows **64 of 64 records**; Salary & Rules
    page shows Ruma Begum's corrected `৳10,000 / ৳3,000 / ৳1,500`, mukta's
    corrected `৳60,000 / ৳20,000 / ৳10,000`, and the new `DEMO-HR` row
    (`৳30,000 / ৳12,000 / ৳5,000`) distinct from the unrelated `EMP-1001`
    namesake — all live, not just via API.
- **Status**: employee payroll master data is clean and complete — every
  active employee traces Department → Designation → Grade → Salary
  Structure → PF/Tax correctly, 64/64 have exactly one valid, internally-
  consistent salary structure, and the grade-pay hierarchy no longer
  inverts anywhere.

### 2.65 Step 22-24 — Notification, Reports & Audit audit, 3 confirmed bugs fixed, Reports module expanded (2026-09-05)

- **Why**: scoped audit of the three governance-facing modules against the
  checklist — notification recipient correctness/IDOR, Reports role-scoped
  calculations, and Audit Log completeness/anti-spoofing.
- **Bug 1 — audit-log entries could be rewritten by a raw PUT, reopening
  the exact spoofing hole `create()` had already closed (confirmed
  integrity bug)**: `AuditLogController.create()` was fixed 2026-09-02 to
  always derive `actorName`/`actorRole` from the authenticated JWT
  principal, never the request body — closing an Employee-can-POST-as-
  Admin hole. `update()`/`putMany()` never got the same fix: both saved
  the request body's `actorName`/`actorRole` verbatim. The verb is
  Admin-only (`SecurityConfig`) and nothing in the frontend calls it today
  (`AuditLogService.record()` only ever POSTs), but the endpoint is still
  live — a raw `PUT` could silently rewrite who a historical action is
  attributed to, undermining the entire evidentiary point of an audit
  trail. Fixed: both now re-derive identity from `Authentication`, same as
  `create()`. This controller had **zero** test coverage before this
  session — new `AuditLogControllerIT` (5 tests) added from scratch.
  Live-reproduced: an Admin `PUT` claiming `actorName: "forged.user"` now
  always saves as `farhana.islam`/`Admin`, the real caller.
- **Bug 2 — HR/Accountant saw a real "Audit activity by module" section
  that always silently showed "No audit events yet" (confirmed misleading
  data)**: `GET /api/audit-logs` is deliberately Admin-only server-side
  (2026-09-02), but `reports-page.html` rendered the "Audit activity by
  module" card unconditionally for every role that can reach `/reports`
  (Admin, HR, Accountant per `module-registry.ts`). For HR/Accountant the
  underlying fetch always 403s, so the table always renders its genuine
  empty state — indistinguishable from "zero governance activity has ever
  happened," when in reality hundreds of real events exist (357
  Authentication, 68 Payroll, 40 Attendance, etc. — confirmed live).
  Live-reproduced as HR: the section rendered with the real heading and
  "No audit events yet," while a `psql` count showed 484 total audit
  rows. Fixed: new `canSeeAuditActivity` gate (`role === 'Admin'`,
  matching the backend's own restriction), section hidden entirely for
  HR/Accountant. Re-verified live: HR no longer sees the section at all;
  Admin still sees it with the real per-module counts, cross-checked
  exactly against `psql` (357/68/40/... matched digit-for-digit).
- **Bug 3 — the Reports module was missing four sections the spec calls
  for (confirmed scope gap, user opted to build all four)**: `reports-
  page.ts` had zero references to `attendance`, `loans`, or `payments`
  collections — Accountant's "loan recovery" and "payments" domains and
  HR's "attendance" domain, plus Admin's "department cost," were entirely
  absent, only headcount/leave/OT/tax/PF/payroll-cycle-totals existed.
  Added, following the exact existing per-cycle-and-detail-row pattern
  Tax/PF already uses:
  - **Attendance by department** (HR/Admin, new `canSeeAttendance` gate):
    present/late/absent/on-leave counts per department, all-time — same
    `present`/`isLate`/`absent` semantics `attendance-page.ts` already
    uses (not mutually exclusive; `late` overlaps `present`).
  - **Loan recovery** + **Loan recovery — employee detail** (Accountant/
    Admin, reusing `canSeeTaxPf` as `canSeeLoansAndPayments` — same role
    set): per-cycle and per-employee totals of `Payslip.loanRecovery`,
    scoped to paid batches only, same convention as Tax/PF.
  - **Payments** (Accountant/Admin): every real `Payment` row on file
    joined to its batch — inherently small and complete since a Payment
    only exists once its batch is genuinely paid (`payment_batch_id_key`
    unique constraint).
  - **Payroll cost by department** (Admin-only, new `canSeeDeptCost`
    gate): per-department gross/deduction/net summed across paid
    payslips — the money-equivalent of the existing headcount-by-
    department table.
  - New route bug found and fixed while wiring this up: `app.routes.ts`'s
    `reports` route provided every NgRx feature the page reads **except**
    `attendanceFeature`/`paymentsFeature` — the exact same "state doesn't
    exist for this route" failure shape a comment two lines above already
    documents for `payslipsFeature`/`pfRulesFeature` (found live during
    the *original* Tax/PF build, never repeated here until now).
    Live-reproduced: navigating to `/reports` threw `Cannot read
    properties of undefined (reading 'ids')` in the console the instant
    either new section's signal was read. Fixed by adding both to the
    route's `providers`.
- **Verified correct, no changes needed**:
  - Notification IDOR (2026-09-02, unchanged): `NotificationController`
    already scopes `GET`/`PUT`/`DELETE` to the owning `userId` or Admin,
    404 (not 403) for a stranger — re-confirmed live via `curl`: HR
    creates a notification for `u1`, Employee's list never includes it,
    direct-ID fetch → `404`.
  - All 5 required notification categories exist and fire correctly:
    payroll processed/payslip ready (`batch-detail.ts`'s `pay()`, one per
    employee in the batch), leave approved/rejected (`leave-detail.ts`),
    loan approved/rejected (`loan-detail.ts`), overtime approved/rejected
    (`overtime-detail.ts`), bonus approved/rejected (`bonus-detail.ts` —
    "bonus added" is realized as "bonus approved," since a bonus is never
    real until approved, matching the same pending→decided design as
    every other request-based module).
  - Every approve/reject/complete action across Payroll, Overtime, Leave,
    Loan, Bonus, and Final Settlement calls `AuditLogService.record()`
    with `actorRole`+`actorName` (client-supplied but always overwritten
    server-side on write, per Bug 1's fix), a structured `outcome`
    (APPROVE/REJECT), `moduleName`, a `details` string carrying the
    affected record's reference/ID and, for rejections, the reason —
    re-confirmed by reading every one of the 6 modules' detail-page
    source.
  - Reports role access and no-hardcoded-values: `canSeeTaxPf` (now also
    `canSeeLoansAndPayments`) correctly restricts Accountant-domain money
    detail from HR; every figure is a live `computed()` over real NgRx
    state, no mock or hardcoded number anywhere in the module.
- **Documentation**: this entry; new `AuditLogControllerIT.java` (5 tests).
- **Verified**:
  - Backend: `mvn clean verify` — **208/208** passing (203 + 5 new),
    `BUILD SUCCESS`.
  - Frontend: `tsc --noEmit` clean; `ng build` clean; `ng test` —
    259/259 passing (no new frontend unit tests added — the new Reports
    aggregation lives in `computed()` signals on the component itself,
    matching the existing Tax/PF sections' own precedent of having no
    dedicated spec file; only `reports-rules.ts`'s pure helpers are
    unit-tested project-wide, and no new pure function was added there).
  - Backend restarted to pick up the `AuditLogController` fix; no schema
    change, no new Flyway migration.
  - **Live API verification**: audit-log spoof attempt via `PUT` → saved
    as the real caller, not the claimed identity; HR/Employee tokens →
    `403` on `GET`/`PUT /api/audit-logs`; notification IDOR re-confirmed
    (404 on cross-user direct fetch, list never leaks another user's row).
  - **Playwright, live, against the running dev servers**: as HR, the
    "Audit activity by module" section confirmed gone (only Attendance
    shown among the new sections); as Accountant, Loan recovery + Payments
    confirmed shown, Attendance + Department cost confirmed hidden; as
    Admin, all four new sections render with real data cross-checked
    exactly against `psql` — Payments 7/7 (matches `SELECT count(*) FROM
    payment`), Loan recovery detail 11/11 (matches paid-payslips with
    `loan_recovery > 0`), Attendance present-count sum 1,201 across 7
    departments (matches `SELECT count(*) FROM attendance` exactly),
    Payroll cost by department 7/7 (matches department count).
- **Status**: Steps 22-24 are payroll/production-ready. The one real
  security-relevant gap (audit-log identity spoofing via `PUT`) is closed
  and now has test coverage where none existed before; the misleading-
  empty-state bug is closed; the Reports module now actually covers every
  role's documented domain instead of half of it.

### 2.66 Employee role E2E audit, 2 confirmed bugs fixed, plus dev-data cleanup (2026-09-05)

- **Why**: full Employee-role walkthrough — Login → Dashboard → Profile →
  Attendance → Leave → Overtime → Loan → Notifications → Payslip →
  Logout — checking ownership/IDOR, API tampering, direct-URL access,
  dashboard accuracy, and console/network errors, live against the real
  frontend/backend/Postgres.
- **Bug 1 — the Employee dashboard's "Payroll cycles" card rendered every
  batch in the company, unconditionally, to every role (confirmed
  internal-data exposure)**: `dashboard-page.html` showed the same
  section (`batchRef`, `month`, `status`, and — critically — the whole
  company's `netTotal` for every payroll cycle ever run) to Admin, HR,
  Accountant, *and* Employee alike, reading the full `payrollBatchesFeature
  .selectors.all` list. `GET /api/payroll-batches` is deliberately broad
  server-side (documented in `SecurityConfig` — every role's dashboard
  needs *some* batch data), but nothing stopped the frontend from
  rendering the *entire* list to a role that should only ever see its own
  cycle — exactly the exposure this audit was asked to check for
  up front. The existing "My recent payslips" card was correctly scoped
  to the viewer's own payslips already, but only showed batch ref + net,
  missing the period/status/gross/deductions the task asked for. Fixed:
  the shared "Payroll cycles" card is now `@if (role() !== 'Employee')`;
  a new "My payroll cycle" card replaces it for Employee, built from a new
  `myPayrollRows` computed that joins each of the viewer's own payslips to
  its batch for period + status only (never rendering any other batch),
  showing exactly period, status, gross, deductions, net, and a "View
  payslip" link to `/payslips/{id}` (not `/payroll/{batchId}`, which
  `roleGuard` blocks for Employee anyway). Live-reproduced before the fix
  (every batch's company-wide net total visible on Tanvir's own
  dashboard) and after (only Tanvir's own 5 payslips shown, each with the
  exact fields requested).
- **Bug 2 — `GET /api/employees` and `/{id}` leaked every employee's full
  PII to every other employee (confirmed IDOR/PII exposure)**: same
  documented broad-GET trade-off as payroll-batches (every dashboard needs
  name/department lookups), but it meant National ID, date of birth,
  phone, home address, bank account/routing number, and salary grade for
  *every* employee in the company were readable by a raw Employee-token
  `curl` call — confirmed live. Nothing in the Employee's actual UI ever
  renders another employee's data this way (`module-registry.ts` gates
  `/employees` to Admin/HR only, and Employee's own pages never list
  peers), so this was a pure raw-API exposure with zero legitimate
  frontend dependency on the leaked fields. Fixed: `EmployeeController`
  now returns the full record only to Admin/HR/Accountant (Accountant
  keeps full access — `batch-detail.ts`'s bank-transfer CSV genuinely
  needs every employee's bank details to pay a whole batch) or to the
  viewer's own record; every other read gets a lean directory view — id,
  code, name, email, gender, joining date, employment type, department/
  designation/shift ids, status, overtime eligibility, photo — with
  National ID/DOB/phone/address/salary grade/bank details/emergency
  contact left `null`. Live-reproduced: Employee `GET /api/employees/e1`
  → National ID/phone/DOB/address/salary grade/bank fields all `null`;
  same Employee `GET /api/employees/e4` (their own) → full data; HR/
  Accountant `GET` on any employee → unaffected, still full. Re-verified
  live in the UI: Employee's own Profile page still shows their full
  contact details; HR's Employee Setup detail page still shows Tanvir's
  full record (National ID, phone, etc.) unchanged.
- **Dev-data cleanup (found while auditing, not a code bug)**: three
  leftover test records directly on the audited Employee account (`e4`/
  Tanvir) from earlier sessions' live Playwright/API verification runs
  were never cleaned up — a `leave_request` (`live-lv-spoof-1`, reason
  "Live IDOR test", approved) and a `bonus_record` (`bn-e2e-notify-check`,
  reason "E2E verification of employee notification on approval",
  approved) were polluting Tanvir's real leave/bonus history on the
  actual dashboard. Both were already-decided/immutable by the app's own
  API (by design), so removing them required a direct DB delete —
  confirmed with the user before each, confirmed no dependents first.
  Tanvir's real `leave_balance` was unaffected by the fake leave request
  (its `taken` count already matched only the genuine approved request).
  A broader scan found two more test-labeled rows on *other* employees
  (`admin-audit-lv1` on e2, `bn-e2e-ui-check` on EMP-1003) — left alone as
  out of this audit's scope (not the Employee account under test), flagged
  below instead. `ln-e4-1788164023593` (reason mentions "testing loan
  recovery... idempotency") was confirmed to be genuine, load-bearing
  data — it backs Tanvir's real, currently-displayed ৳7,206 outstanding
  loan balance — and was left untouched.
- **Verified correct, no changes needed**:
  - Full flow walkthrough (Login → Dashboard → Profile → Attendance →
    Leave → Overtime → Loan → Notifications → Payslip → Logout) live via
    Playwright: every page showed only Tanvir's own data; no console
    errors beyond the already-documented, harmless PUT→403→POST-fallback
    pattern every non-Admin audit-log write goes through (§2.63/§2.65 —
    unrelated to this session, unchanged).
  - Notifications page: exists, works, and is correctly owner-scoped
    (already hardened in §2.65) — this session's mid-task question about
    "why does Employee have no Notifications page" was investigated and
    found to be a non-issue: it isn't a sidebar module for *any* role
    (Admin included), it's reached via the header bell icon app-wide, and
    Employee's copy of it already works identically to every other role's.
    No change made — nothing was missing.
  - Direct-URL IDOR: `/employees/e1` (another employee), `/payroll/*`
    (Accountant/HR/Admin-only module) both correctly bounce Employee back
    to `/dashboard` via `roleGuard`; a cross-employee payslip URL sticks on
    "Loading payslip…" forever (backend `404`, by design — indistinguishable
    from missing).
  - API tampering: Employee `PUT` on their own or another's leave request
    → `403` (Employee holds no leave-decision authority at all, matching
    HR/Admin-only `canDecideLeaveRequest`); spoofed `employeeId` on a new
    leave request → silently corrected to the caller's own (§2.59, still
    working); `PUT` on a payslip → `403`; `DELETE` on attendance → `403`
    (Admin-only verb globally).
  - Logout: `sessionStorage` fully cleared; a post-logout direct navigation
    to `/dashboard` correctly bounces to `/login?next=%2Fdashboard`.
  - Dashboard/Payslip calculation accuracy: every KPI tile and the
    Payslips page's own totals (gross ৳235,000 / deductions ৳83,233 / net
    ৳153,200 across 5 payslips) summed and cross-checked exactly by hand.
- **Documentation**: this entry; 5 new `EmployeeControllerIT` tests.
- **Verified**:
  - Backend: `mvn clean verify` — **213/213** passing (208 + 5 new),
    `BUILD SUCCESS`.
  - Frontend: `tsc --noEmit` clean; `ng build` clean (this session's
    template change — a `keyof typeof BATCH_TONE`-typed helper called with
    a widened `string` — was only caught by `ng build`'s Angular template
    compiler, not `tsc --noEmit`, which never type-checks templates;
    fixed by threading a proper `BatchStatus | undefined` type through);
    `ng test` — 259/259 passing.
  - Backend restarted to pick up the `EmployeeController` fix; no schema
    change, no new Flyway migration.
  - **Live API verification**: full redaction matrix confirmed via
    `curl` — Employee viewing another employee → nulled PII fields;
    Employee viewing themself, and HR/Accountant viewing anyone → full
    record, unchanged.
  - **Playwright, live, against the running dev servers**: dashboard fix
    and employee-record redaction both confirmed as Employee, HR, and
    Accountant; all leftover test data confirmed removed via `psql`
    afterward.
- **Status**: Employee role is production-ready. Both confirmed bugs were
  data-exposure gaps (one UI-level, one raw-API-level) — not calculation
  or workflow defects, which were already independently confirmed correct
  across every module this Employee-role audit touched.
- **Flagged, not fixed** (added to Current next steps below): two
  leftover test-labeled records on other employees (`admin-audit-lv1` on
  e2, `bn-e2e-ui-check` on EMP-1003) found during the dev-data scan, out
  of this audit's Employee-account scope.

### 2.67 Bangladesh HR/payroll compliance audit — 3 confirmed bugs fixed, 1 statutory update, 1 flagged not implemented (2026-09-08)

- **Why**: a fresh audit against current Bangladesh law (Labour Act 2006 +
  the November 2023 maternity amendment; NBR Finance Act 2026 budget for
  individual income tax), asked for explicitly, cross-checked live DB
  config against secondary sources plus the NBR site itself, not against
  memory of prior years' rates.
- **Bug 1 — income tax was flat-rate, not progressive (real calculation
  bug, not a data-freshness issue)**: `payroll-engine.ts`'s `monthlyTax`
  found the single slab an employee's annual income fell into and applied
  that slab's rate to their *entire* income — not Bangladesh's actual
  method, where each bracket is taxed only on the portion of income inside
  it. Confirmed live against a real employee: Farhana Islam (M3, gross
  ৳70,000/mo, annual ৳840,000) — old flat method: ৳10,500/month (15% flat,
  the bracket her income fell into); correct progressive: ৳4,250/month
  (0% on the first 400,000 + 10% on the next 300,000 + 15% on the
  remaining 140,000) — more than double the correct liability for every
  employee whose income clears the first paid bracket. Fixed:
  `monthlyTax` now sums each bracket's own rate against only the income
  inside it, annualized then reduced to the cycle exactly as before.
- **Bug 2 — no minimum-tax floor**: NBR's flat ৳5,000 minimum tax
  (AY2026-27/2027-28, once income clears the exempt threshold) had no
  equivalent anywhere in the engine. Added: annual liability is floored to
  ৳5,000 whenever computed income exceeds the exemption ceiling and the
  slab sum comes out lower.
- **Bug 3 — daily overtime cap allowed 4h, statute caps it at 2h**:
  `overtime-rules.ts`'s `DAILY_OT_CAP` and `OvertimeService`'s matching
  server-side check were both documented as an "independent sanity cap,"
  not sourced from the Labour Act — but §100/102 caps a working day's
  *total* hours at 10 (8 regular + 2 overtime), so the real daily ceiling
  is 2h, not 4h, even though the 12h *weekly* ceiling was already correct.
  Live-reproduced: a 2.5h single-day claim → `400` (was previously
  allowed up to 4h). Both the frontend auto-calc cap and the backend
  `create()` guard updated together; `update()`/correction stays
  uncapped, unchanged (deliberate HR override, pre-existing design).
- **Statutory update — FY2026-27 tax slabs + women/senior-citizen
  category**: NBR's Finance Act 2026 raised the general tax-free
  threshold 350,000 → 400,000, removed the old 5% bracket (lowest paid
  rate is now 10%), and added 25%/30% top brackets. Women and taxpayers
  aged 65+ get a separate, higher threshold (425,000) — new `TaxRule
  .category` (`'general' | 'womenSenior'`), enforced as two independent,
  independently-overlap-checked slab schedules with identical bracket
  *widths*, just shifted up by the larger exemption (the real NBR
  mechanic, not an invented shortcut). New `taxCategoryFor(employee,
  asOfDate)` derives the category from `gender`/`dob` — the only two
  eligibility signals this system holds on an `Employee` record (no
  disability/freedom-fighter status field exists, so those further NBR
  categories are explicitly out of scope, not silently assumed).
  Migration `V38__tax_rule_fy2026_27_category.sql` re-points the 5
  existing live general-slab rows at the new boundaries/rates (keeping
  their ids) and adds the new top general bracket plus all 6
  women/senior-citizen rows; `V39__maternity_leave_120_days.sql` updates
  the Maternity `leave_rule` row 112 → 120 days per the Labour Act's
  November 2023 amendment. `TaxRuleService`'s overlap check is now scoped
  per category — general and women/senior schedules are two independent
  tables and are expected to cover the same income ranges.
- **Flagged, not implemented (legal-policy/data-gap, confirmed with the
  user, not guessed)**:
  - **WPPF (Workers' Participation/Welfare Fund, Labour Act §232-236)** —
    a profit-distribution mechanism gated on paid-up-capital/headcount
    thresholds this system has no way to know the company meets; doesn't
    fit a per-cycle payroll deduction model.
  - **Sector minimum wage** (e.g. RMG wage-board rates) — only applies if
    this company is in a wage-board-covered sector, which nothing on file
    states.
  - **Gratuity default (30 days/yr after only 12 months' service)** —
    statute's actual termination-gratuity schedule is tiered (14 days/yr
    for 1–5 yrs, 30 days/yr for 5+ yrs); the current default is simpler
    than that but was already Admin/HR-configurable before this session
    (§1.4-era design decision) — a policy call on the *default value*, not
    a bug.
  - **Disabled/third-gender/freedom-fighter tax categories** (NBR grants
    these even higher thresholds — 500,000/525,000 per secondary sources,
    not independently confirmed against the primary NBR circular) — no
    corresponding field exists on `Employee`, and the exact figures came
    from lower-confidence secondary sources than the general/women-senior
    ones used above; not implemented rather than guessed.
- **Verified**:
  - Backend: `mvn clean verify` — **213/213** passing, `BUILD SUCCESS`;
    all pre-existing `OvertimeControllerIT` cases exercising the 4h cap
    rewritten for 2h (6×2h claims across the week land exactly on the
    12h ceiling; a 7th is rejected).
  - Frontend: `tsc --noEmit` clean; `ng build` clean; `ng test` —
    **270/270** passing (11 new: `monthlyTax` progressive/category/
    minimum-tax cases, `taxCategoryFor` gender/age-boundary cases).
  - Migrations applied cleanly to the live dev Postgres (`flyway_schema
    _history` V38/V39, both `success = t`); confirmed via `psql` that
    `tax_rule` now carries 6 general + 6 women-senior rows and `leave_rule
    .Maternity.annual_entitlement = 120`.
  - **Live API** (real backend, real Postgres, Admin JWT): `GET
    /api/tax-rules` returns all 12 rows correctly tagged by category;
    `POST /api/overtime` with 2.5h → `400` "Overtime cannot exceed 2
    hours in a single day," 2.0h → `201`; `POST /api/tax-rules` with a
    range overlapping an existing *same-category* slab → `409` naming
    the correct conflicting row (confirms the overlap check is scoped
    per category, not global).
  - **Discovered mid-fix**: Jackson's constructor-based deserialization
    (Lombok's `@AllArgsConstructor` carries an implicit `@Constructor
    Properties` creator) passes `null` for any field missing from the
    request JSON, bypassing the entity's own field initializer — the new
    `category` field came back blank instead of defaulting to
    `'general'`, failing 2 existing `BeanValidationIT` cases. Fixed by
    moving the default into `TaxRuleService.create()`/`update()` instead
    of relying on `@NotBlank` at the entity level.
  - **Not run this session**: a full browser walkthrough (Playwright MCP
    is disconnected in this environment; the Chrome extension bridge
    reported not connected either) — substituted with live API + `psql`
    verification above. The payroll math itself runs client-side
    (`payroll-engine.ts`), so a live UI click-through would be the
    strongest remaining check; flagged as a gap, not skipped silently.
- **Status**: the 3 bugs above are real, independent of any specific
  slab values — they'd have been wrong under the old rates too. The FY
  update is time-sensitive (Bangladesh's Finance Act changes these
  figures roughly annually) and should be revisited each July.
- **Follow-up attempt, same day**: asked explicitly to complete the
  missing browser verification via real Playwright MCP (not the Chrome
  extension). Confirmed unavailable a second time: a system notice at
  the start of that turn explicitly listed every
  `mcp__plugin_playwright_playwright__*` tool as disconnected, and a
  fresh tool search for "playwright" returned zero matches — nothing
  callable exists to reconnect from inside this session. Per explicit
  instruction, did not fall back to the Chrome extension either. UI
  verification of the §2.67 changes (tax category/slab list, Maternity
  120 days, OT 2h cap, a real payroll run's progressive tax + minimum
  tax on a payslip) is **still not done** — re-ran backend `mvn clean
  verify` (213/213) and frontend `ng test`/`tsc --noEmit`/`ng build`
  (270/270, both clean) instead, all unchanged from the first pass. No
  PASS/FAIL UI claims are recorded — none were produced.

### Current next steps (updated 2026-09-08, see §2.67 above for what closed)

1. ~~Project plan / documentation accuracy~~ — done, kept current every
   session per the standing instruction below.
2. ~~Change Request end-to-end audit~~ — done, see §2.50 item 1 (shared fix
   with Leave).
3. **New-user real-JWT login test** — confirm a user created today via
   Users & Roles reaches the real `app_user` table and signs in through the
   real login path, not the mock fallback. Not attempted this session.
4. **Auth fallback safety** — confirm `session.ts`'s mock-login fallback
   can't be used to bypass anything the real backend would otherwise block.
   Not attempted this session (this session's auth work was two specific
   live-reported bugs, not a full fallback-safety audit).
5. **CI for the existing test suites** — 213 backend + 259 frontend tests
   (post-§2.66) currently only run when someone remembers to.
6. ~~A full real-payroll dry run~~ — done, see §2.55: 50-employee dataset,
   full calculate → submit → approve → pay lifecycle run live against the
   real backend/Postgres.
7. ~~Registration — scope decision~~ — resolved 2026-09-03: removed
   entirely. See §2.52.
8. **Real email/SMS notification dispatch** — still deferred pending an
   external provider choice; in-app notifications are real (§1.14).
9. ~~Employee Setup end-to-end audit~~ — done, see §2.53 (Salary Grade
   derivation, duplicate email/National ID checks, self-service PUT
   field-lock).
10. **Existing duplicate National ID data cleanup** — narrowed by §2.64's
    orphan-employee cleanup: the 1 duplicate email pair and 3 of the 4
    duplicate National ID groups were among the 12 deleted orphans and are
    now gone. One group of 6 real, distinct, referenced employees
    (`EMP-1001`, `EMP-1002`, `EMP-1005`, `EMP-1006`, `EMP-1008`,
    `EMP-1009`) still shares National ID `918302391479` (a demo-data
    placeholder from the original 9-employee seed). New duplicates are
    blocked (§2.53); resolving this last real group is a human data
    decision, still not attempted.
11. **Add Employee failure has no visible error feedback** — a rejected
    create (e.g. the new 409 duplicate-email/National-ID case) closes the
    modal silently; the generic create/upsert effect shared by every
    collection doesn't surface the server error to the user. Flagged in
    §2.53, not fixed — shared infra beyond Employee Setup's scope.
12. ~~User & Role Setup end-to-end audit~~ — done, see §2.54 (separated-
    employee login bypass closed, password minimum length on create,
    email/case-insensitive-username uniqueness).
13. **Duplicate-data employees blocked from unrelated-field edits** —
    §2.53's duplicate email/National-ID check on `PUT /api/employees/{id}`
    fires unconditionally, so an employee already sharing a duplicate
    National ID/email with another record (existing demo-data quality
    issue, item 10 above) can't be edited at all right now, even for
    fields that have nothing to do with the duplicate. Should ideally only
    check when those specific fields change. Not attempted this session —
    found while cleaning up a live test in §2.54.
14. ~~Realistic 50-employee payroll test dataset~~ — done, see §2.55.
15. ~~10 pre-existing employees still have no salary structure~~ — done,
    see §2.64: the 9 still missing one turned out to be true zero-
    dependency orphans (deleted, they were never real payroll headcount)
    except the 3 real demo accounts, which were each given a structure.
    64/64 remaining employees now have exactly one.
16. ~~Salary Structure Assignment audit~~ — done, see §2.56 (one-per-
    employee DB constraint, grossSalary-consistency check).
17. ~~Daily Attendance audit~~ — done, see §2.58 (create/update
    cross-employee IDOR closed, check-in date/time timezone mismatch
    fixed).
18. **`toISOString().slice(0,10)` "today" pattern in ~9 other feature
    files** (settlements, leave, bonus, loan, change requests, dashboard)
    — noted in §2.58 as a separate, unrelated concern from the attendance
    fix (those files don't pair a UTC date against a local clock read in
    the same action, so they lack that specific inconsistency); not
    audited or touched this session.
19. ~~Employee Leave Request audit~~ — done, see §2.59 (create-side and
    self-approval IDORs closed, batch re-decide bypass closed).
20. ~~`OvertimeService` missing self/ownership checks~~ — done, see §2.60
    (was flagged in §2.59 as out of Step 6's scope; closed once Step 8's
    own audit covered it directly).
21. **`LeaveBalanceController` missing ownership check** — any role can
    POST a fabricated leave balance for another employee's id, same shape
    as §2.59's Leave bug 1 but on the balance endpoint, not the request
    endpoint. Noted in §2.59, not fixed — out of Step 6's scope.
22. ~~Step 8 — Overtime audit~~ — done, see §2.60 (create-side IDOR,
    self-approval bypass, payrollEligible/status tampering, duplicate-claim
    prevention, daily/weekly overtime cap enforcement).
23. ~~Step 9/10 — Loan Request & Bonus audit~~ — done, see §2.61
    (loan-create-side IDOR, self-approval bypass on both modules,
    duplicate-open-loan and EMI-vs-principal checks).
24. **Sultana Razia (e-1787547833901, separated) carries two open loans**
    — pre-existing demo-data noise found while building §2.61's duplicate
    check; not auto-remediated (destructive change to a real record,
    needs a human decision), same call as §2.53's duplicate-email
    finding. New duplicates are now blocked going forward.
25. ~~Step 11/12 — PF & Tax Calculation audit~~ — done, see §2.62 (PF
    singleton DB constraint; PF-rule-form and tax-rule-form "Edit opens
    blank" bug fixed in both).
26. ~~Step 13-21 — Payroll Lifecycle audit~~ — done, see §2.63
    (payroll-batch self-approval bypass closed; Payment amount now
    validated against the batch's net payable total).
27. ~~Employee payroll master-data cleanup~~ — done, see §2.64 (12
    zero-dependency orphan employees deleted; `mukta`'s desynced
    `salaryGrade` corrected; Ruma Begum's ~30x-inflated W3 salary corrected
    to the established Helper band; 3 demo accounts given a D1 salary
    structure; 64/64 employees now have exactly one valid structure).
28. ~~Step 22-24 — Notification, Reports & Audit audit~~ — done, see §2.65
    (audit-log identity-spoofing closed on `PUT`/`putMany`; misleading
    empty "Audit activity" section hidden from HR/Accountant; Reports
    module expanded with Attendance, Loan recovery, Payments, and
    Department cost sections).
29. ~~Employee role E2E audit~~ — done, see §2.66 (dashboard "Payroll
    cycles" company-wide leak closed for Employee; `GET /api/employees`
    PII redaction added for non-privileged/non-self viewers).
30. **Two leftover test-labeled records on other employees' accounts** —
    `admin-audit-lv1` (leave_request, e2/Accountant, reason "admin audit
    test") and `bn-e2e-ui-check` (bonus_record, EMP-1003, reason "E2E UI
    verification..."), found during §2.66's dev-data scan while cleaning
    up the same class of leftover test data on the Employee account under
    audit. Out of that session's scope (different employees); not
    attempted.
31. **`totalDeductions` not floored to match `netSalary`'s zero-floor** —
   `payroll-engine.ts`: `netSalary` is `Math.max(0, ...)` but
   `totalDeductions` itself isn't, so the two can print inconsistently
   under unrealistically high combined lateness/absence deductions on a
   very low salary. Never observed in real seeded/operational data
   (confirmed against all 68 real payslips on file, 2026-09-02). Flagged,
   not fixed — genuinely never seen in practice, and the "right" floor
   behavior (floor which deduction first?) is a policy call, not a bug fix.
32. ~~Bangladesh HR/payroll compliance audit~~ — done, see §2.67
    (progressive tax calculation, ৳5,000 minimum tax, FY2026-27 slabs +
    women/senior-citizen category, 2h daily overtime cap, 120-day
    maternity leave).
33. **WPPF, sector minimum wage, disabled/third-gender/freedom-fighter tax
    categories** — flagged in §2.67 as out of scope: WPPF is a
    profit-distribution mechanism this system has no data to gate on;
    minimum wage is sector-specific with nothing on file saying which
    sector; the further NBR tax categories need an `Employee` field this
    system doesn't have plus lower-confidence source figures than the
    general/women-senior ones already implemented. Needs a human decision
    on scope before any of the three is attempted.
34. **Live browser walkthrough of the §2.67 changes** — still not run,
    attempted twice: first session had neither Playwright MCP nor the
    Chrome extension connected; a same-day follow-up explicitly requested
    real Playwright MCP only (no Chrome-extension fallback) and it was
    still disconnected (confirmed via an explicit system notice plus a
    zero-result tool search). Substituted both times with live API
    (`curl`) + `psql` verification of the same endpoints/data. An actual
    UI click-through (Salary & Rules → tax slab list showing the new
    Category column, running a real payroll batch and reading a
    payslip's tax line) remains the strongest still-missing check —
    needs Playwright MCP reconnected in this environment before it can
    run.
35. **Gratuity default value vs. the Labour Act's tiered schedule** —
    current default (30 days/yr after 12 months) is simpler than
    statute's actual tiered rule (14 days/yr for 1–5 yrs, 30 days/yr for
    5+ yrs); already fully Admin/HR-configurable, so this is a "does the
    default match your policy" question flagged in §2.67, not a bug.

Demo data/accounts/credentials are kept as-is deliberately — the project is
still in development, not deployed. Credential rotation is a **future
production-checklist item only**, not current work — see §2.12.
