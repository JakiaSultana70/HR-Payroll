# Payroll Build Log — 2026-09-02

End-to-end audit across salary rules, attendance, overtime, loans, bonus,
PF/tax, payroll batches, payslips, payments and reports — plus two auth
bugs reported live during the session.

**Stats:** 7 audit bugs fixed · 2 live auth bugs fixed · backend 187/187
tests passing · frontend 280/280 tests passing.

Full narrative detail: `project-plan.md` §2.50.

---

## Update — 2026-09-08: Bangladesh HR/payroll compliance audit

Full narrative detail: `project-plan.md` §2.67.

**Stats:** 3 confirmed bugs fixed · 1 statutory (FY2026-27 tax) update ·
1 flagged, not implemented · backend 213/213 tests passing · frontend
270/270 tests passing.

- **Fixed — income tax was flat-rate, not progressive.** `monthlyTax`
  applied one matching slab's rate to an employee's *entire* income
  instead of taxing each bracket only on the portion inside it. Real
  example: a M3-grade employee on ৳70,000/mo — old: ৳10,500/month tax;
  correct: ৳4,250/month. More than double the correct liability for
  anyone past the first paid bracket.
- **Fixed — no minimum-tax floor.** NBR's flat ৳5,000 minimum tax
  (once income clears the exemption) had no equivalent; added.
- **Fixed — daily overtime cap was 4h, statute caps it at 2h**
  (Labour Act §100/102: 10h/day total including overtime). Frontend
  (`overtime-rules.ts`) and backend (`OvertimeService`) both updated;
  the 12h weekly ceiling was already correct and is unchanged.
- **Updated — FY2026-27 tax slabs + new women/senior-citizen category.**
  General exempt threshold 350,000 → 400,000; old 5% bracket removed,
  25%/30% top brackets added; women and 65+ taxpayers now get an
  independent, higher-threshold slab schedule (`TaxRule.category`),
  selected per employee via `taxCategoryFor(gender, dob)`. Migrations
  `V38`/`V39` applied live.
- **Flagged, not implemented** (needs a human policy/data-scope call):
  WPPF (profit-distribution fund, no data to gate eligibility on),
  sector minimum wage (sector not on file), disabled/third-gender/
  freedom-fighter tax categories (no matching `Employee` field, and
  source figures were lower-confidence than the two categories actually
  implemented).
- **Not run this session:** a live browser walkthrough — Playwright MCP
  and the Chrome extension bridge were both unavailable in this
  environment. Verified instead via live API (`curl`) + `psql` against
  the real dev backend/Postgres.
- **Follow-up, same day:** explicitly asked to retry with real Playwright
  MCP only (Chrome extension off-limits). Still disconnected — confirmed
  via an explicit system notice and a zero-result tool search, not
  assumed. No UI PASS/FAIL results exist because none were produced.
  Backend `mvn clean verify` (213/213) and frontend `ng test`/`ng build`
  (270/270, clean) re-run and unchanged. Playwright-based UI verification
  of Salary & Rules (category/slabs), Maternity=120, OT 2h cap, and a
  real payroll run's progressive/minimum tax remains outstanding.

---

## Shipped this session

Found by a priority-ordered audit (salary rules → attendance/leave →
overtime → loans → bonus → PF/tax → batch → payslip → payment → reports),
each one a real failure scenario traced to a concrete file and line, not a
style nit.

### 1. Leave & Change Request decisions no longer corrupt data on a losing race
`aa228c9` · frontend · race condition

Approving or rejecting fired the balance write, the employee-field write,
the audit log and the notification *before* confirming the decision itself
had saved.

**Before:** two admins decide the same pending request at once — the
loser's write 409s server-side, but `leave-detail.ts` had already deducted
the leave balance, or `change-request-detail.ts` had already overwritten
the employee's field, against a decision that never actually persisted.

### 2. An Accountant could no longer approve their own final settlement
`5be1263` · backend · IDOR

`canDecideSettlement`'s self-approval block was frontend-only.
`SettlementService` now enforces it server-side too.

**Before:** an Accountant account tied to the settlement's own `employeeId`
could `PUT` straight to `completed` via a raw API call — self-approved
payout, no second signer.

### 3. A Payment can no longer be recorded against an unapproved batch
`5be1263` · backend · state machine

`PaymentController.create()` had zero batch-state check, unlike
`update`/`delete`. New `assertBatchApprovedForPayment`.

**Before:** a Payment row — real financial history — could be created for a
batch still in `draft`/`pending-approval`, skipping the Accountant
verification step entirely.

### 4. Overlapping payroll cycles are now rejected outright
`5be1263` · backend · double payment

New `assertNoOverlappingCycle` on batch creation, checked against every
existing batch regardless of status.

**Before:** nothing stopped HR opening a second batch whose cycle
overlapped an existing one — the same attendance day, approved bonus or
unpaid-leave day would be paid out again in full through the second batch.

### 5. Overlapping tax slabs are now rejected on save
`5be1263` · backend · wrong tax

`monthlyTax()` resolves the applicable slab via the first array match, no
tie-break. New `TaxRuleService` overlap check closes the ambiguity at the
source.

**Before:** two individually-valid overlapping slabs meant the same
salary's tax rate silently depended on database insertion order.

### 6. Reports' "Tax collected to date" no longer counts unpaid cycles
`aa228c9` · frontend · reporting

New `paidPayslips` computed, scoped to `paid` batches only — matching the
same page's own `netPaidToDate`.

**Before:** the figure summed every payslip regardless of batch status, so
a batch still in draft or later rejected still inflated "collected."

### 7. Sign-in no longer reads as stuck when the backend is down
`e981dfd` · frontend · reported live

The backend-login attempt had no timeout. Capped at 3s so the mock
fallback kicks in fast and consistently instead of freezing on "Signing
in…" for however long the network takes to give up.

### 8. Signing in as a different user after sign-out no longer sticks on the login screen
`e981dfd` · frontend · reported live

Root cause: `signOut()`'s own "Signed out" audit-log write races the token
clear and 401s; the interceptor redirected to `/login` with `next`
captured as `/login` itself, poisoning the *next* sign-in's post-login
redirect.

**Reproduced live:** sign out as Admin, sign in as HR — the session was
genuinely established in `sessionStorage`, but the screen stayed on
sign-in. Fixed at both the interceptor (no forced sign-out with no active
session) and the login page (`next` never resolves to `/login`).

---

## Also done

- Removed the "Request an account" link from the sign-in screen, per the
  explicit ask. The self-registration route and its review page were still
  live by direct URL at the time — only the landing-page entry point was
  gone. **Correction, 2026-09-03: superseded — the entire Registration
  Request module (routes, pages, store, backend controller/entity/table)
  was removed. See `project-plan.md` §2.52.**
- Both repos got their first-ever commit this session
  (`payroll-automation-backend` had no `.git` at all; the frontend had one
  with everything staged but nothing committed).
- New `start`/`stop` scripts — `.sh` and `.bat` — at the project root,
  idempotent and killing by whatever process actually owns the port.

---

## Marked incomplete

Nothing here breaks a real payroll run today — these are open decisions,
deferred scope, or edge cases never seen in the real 68 payslips on file.

| Module / area | Status | What's missing |
|---|---|---|
| ~~Registration~~ | **Removed, 2026-09-03** | Self-service account sign-up was decided out of scope and removed entirely (routes, pages, store, backend, table). See `project-plan.md` §2.52. |
| Notification dispatch | Not started | In-app notifications are real. Email/SMS deferred — needs an external provider chosen first. |
| CI for test suites | Not started | 213 backend + 259 frontend tests exist and pass (post-§2.66), but only run when someone remembers to. |
| New-user JWT login path | Not started | Confirm a user created via Users & Roles today reaches the real `app_user` table and signs in for real, not via mock fallback. |
| Mock-login fallback safety | Not started | Confirm the fallback can't bypass anything the real backend would otherwise block. |
| Full real-payroll dry run | **Done, 2026-09-05** | 50-employee realistic test dataset seeded (`scripts/seed-50-test-employees.sql`), full calculate → submit → approve → pay lifecycle run live against the real backend/Postgres. See project-plan.md §2.55. |
| Employee payroll master-data cleanup | **Done, 2026-09-05** | 12 zero-dependency orphan employees deleted (76 → 64); one desynced `salaryGrade` and one ~30x-inflated Helper-grade salary corrected; 3 demo accounts given a salary structure — 64/64 employees now have exactly one. See project-plan.md §2.64. |
| Notification/Reports/Audit audit | **Done, 2026-09-05** | Audit-log identity-spoofing closed on `PUT`/`putMany`; misleading empty "Audit activity" section hidden from HR/Accountant; Reports module expanded with Attendance, Loan recovery, Payments, and Department cost sections. See project-plan.md §2.65. |
| Employee role E2E audit | **Done, 2026-09-05** | Dashboard "Payroll cycles" company-wide leak closed for Employee (own-scoped "My payroll cycle" card added instead); `GET /api/employees` now redacts National ID/DOB/phone/address/bank details/salary grade for non-privileged, non-self viewers. See project-plan.md §2.66. |
| Deduction floor edge case | Flagged, low risk | `totalDeductions` isn't floored to match `netSalary`'s zero-floor. Never seen across all 68 real payslips — needs a policy call, not a quick fix. |

---

**References:** Backend 187/187 · Flyway V32 · commit `5be1263` — Frontend
280/280 · commits `aa228c9` → `e981dfd` — Full detail in `project-plan.md`
§2.50.
