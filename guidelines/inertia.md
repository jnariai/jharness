# Inertia coding guidelines

<!-- harness-meta:start -->
The Inertia layer on top of `guidelines/laravel.md`, shared by React and Vue
projects. `/ai-context` appends it after the Laravel guidelines in
`docs/agents/coding_guidelines.md` when the target's `package.json` requires
`@inertiajs/react` or `@inertiajs/vue3`, followed by `guidelines/react.md` or
`guidelines/vue.md`. `/jharness:update` refreshes a copy that was never edited.
This block is stripped from the copy.
<!-- harness-meta:end -->

Stack assumed: **Inertia 3 + TypeScript**, from the official React or Vue starter
kit (with or without auth), **Wayfinder** for routes,
**spatie/laravel-typescript-transformer** for types, the kit's shadcn components
for UI. Inertia 3 ships its own HTTP client and no longer depends on Axios, `qs`
or `lodash-es`. Every Laravel rule
still applies; this part covers the contract between the server and the page. The
React or Vue layer that follows adds what is specific to the framework.

---

## Inertia version

The project's installed version decides, never this file: `inertiajs/inertia-laravel`
in `composer.lock` and `@inertiajs/react` / `@inertiajs/vue3` in the npm lockfile.
Never upgrade Inertia just to follow a rule here.
On any version other than 2 or 3 this layer and the React/Vue layer do not apply;
`/jharness:update` and `/ai-context` compose `laravel.md` alone.

- **Untagged rules hold for Inertia 2 and 3.**
- **`(Inertia 3)`** marks an API that does not exist in Inertia 2. On Inertia 2 it
  is never used; the table below says what takes its place.
- **`(Inertia 2.x+)`** marks an API added in an Inertia 2 minor. On an older 2.x it
  is not used either: below 2.3.3 there is no Inertia flash, so successes and domain
  errors use the Laravel layer's session flash, shared from `HandleInertiaRequests`.

| Inertia 3 | On Inertia 2 |
|---|---|
| `defer` / `optional` / `merge` inside closures and nested arrays; dot notation in `only`, `except`, `<Deferred>`, `<WhenVisible>` | top-level props only |
| `reloading` slot prop on `<Deferred>`, `preserveErrors` on reloads | not available |
| `<Link instant>`, `<Form instant>` | plain `<Link>` / `<Form>` |
| `optimistic` on `<Form>` | plain `<Form>`; the page waits for the server |
| `useHttp`, `http.onRequest` / `onResponse` / `onError` interceptors, no Axios | Axios, which Inertia 2 ships with, and its interceptors |
| `router.cancelAll()` | `router.cancel()` |
| `httpException` / `networkError` events, `onHttpException` / `onNetworkError` | `invalid` / `exception` events |
| `Inertia::handleExceptionsUsing()` error pages with shared data | `$exceptions->respond()` in `bootstrap/app.php` rendering the error page with `Inertia::render()` |
| default layout in `createInertiaApp({ layout })`, layout props (`layoutProps`, `setLayoutProps`) | per-page layouts; the layout reads shared props |
| `<Form>` generic, `createForm<T>()` in Vue | `useForm<T>()` when the form needs typed errors |
| `@inertiajs/vite`, SSR inside `npm run dev` | `php artisan inertia:start-ssr` in development too |

---

## Golden rules

1. **The server is the store.** Props are the truth; the page renders them and
   sends intents back. No client-side store, no client-side copy of the domain.
2. **Props are View DTOs, never models.** A controller hands `Inertia::render()`
   `*View` DTOs, collections or paginators of them, and nothing else.
3. **Types are generated, never written by hand.** Every View DTO, enum and VO that
   reaches the page is exported to TypeScript by the transformer. A hand-written
   interface for server data is drift waiting to happen.
4. **URLs come from Wayfinder.** No hardcoded path, no Ziggy, no string route name.
5. **The frontend decides nothing.** No business rule, no permission rule, no
   enum label: the server sends abilities, labels and options; the page shows them.
   An optimistic update only predicts what the server will answer; it never
   computes a rule.
6. **Every user-facing string is translated** — server strings through `__()`,
   page strings through the same `lang/*.json` files.
7. **Tier 1 still runs on the server.** Inertia pages are tested by asserting the
   component, its props and its flash in feature tests; browser tests cover
   critical journeys only.

---

## Layer map

| Layer | Path | Owns | Never |
|---|---|---|---|
| Controller | `app/Http/Controllers/<Context>/` | authorize, validate, call one Action, map the result to View DTOs, `Inertia::render()` or redirect with `Inertia::flash()` (Inertia 2.3.3+) | queries, rules, models as props |
| View DTO | `app/Data/<Context>/*View.php` | the exact shape one page or component receives, `fromModel()` | rules, queries, behavior, integer ids |
| Shared props | `app/Http/Middleware/HandleInertiaRequests.php` | `auth.user`, `auth.can` (global abilities), locale | per-page data, flash, queries beyond the current user |
| Error pages | `AppServiceProvider::boot()` → `Inertia::handleExceptionsUsing()` (Inertia 3) | rendering 403/404/500/503 as an Inertia page with shared data | domain errors (those are flash) |
| Generated types | `resources/js/types/generated.d.ts` | TS mirror of View DTOs, enums, VOs | hand edits |
| Hand types | `resources/js/types/global.d.ts`, `resources/js/types/index.d.ts` | the `InertiaConfig` augmentation (shared props, flash, layout props — Inertia 3), `Paginated<T>`, framework glue | shapes of server data |
| Page | `resources/js/pages/<context>/<resource>/<page>` | composing components, forms posting intents, layout props | fetching data, business rules, permissions logic |
| Layout | `resources/js/layouts/` | shell, navigation, toast outlet | page data |
| Component | `resources/js/components/<context>/`, `components/ui/` | presentation, local UI state | server calls other than through Inertia, rules |
| Routes | `resources/js/actions/`, `resources/js/routes/` (generated by Wayfinder) | typed URLs, form targets, page component names | hand edits |

---

## Rendering a page

```php
namespace App\Http\Controllers\Billing;

class InvoiceController
{
    public function index(
        OverdueInvoicesRequest $request,
        GetOverdueInvoices $getOverdue,
        GetInvoiceTotals $getTotals,
    ): Response {
        $user = $request->user();

        return Inertia::render('billing/invoices/index', [
            'invoices' => Inertia::scroll(fn () => $getOverdue
                ->handle(GetOverdueInvoicesFilter::fromRequest($request))
                ->through(fn (Invoice $invoice) => InvoiceRowView::fromModel(
                    $invoice,
                    new InvoiceAbilitiesView(
                        refund: $user->can('refund', $invoice),
                        void: $user->can('void', $invoice),
                    ),
                ))),
            'filters'  => InvoiceFiltersView::fromRequest($request),
            'totals'   => Inertia::defer(fn () => InvoiceTotalsView::fromResult(
                $getTotals->handle(Period::currentMonth()),
            )),
        ]);
    }
}
```

- **The component name is the page path** under `resources/js/pages/` —
  `<context>/<resource>/<page>`, folders lowercase, the file name cased the way the
  framework layer says (`index.tsx` in React, `Index.vue` in Vue).
- **A write method calls one Action.** A page method may compose several `Get*`
  reads, one per prop.
- **Mapping to View DTOs happens in the controller** — it is presentation. The
  Action returns models; the controller decides what the page sees.
- **Writes end in a redirect** — `to_route()` or `back()` — with an
  `Inertia::flash()` (Inertia 2.3.3+) when the user should be told. Never `Inertia::render()` after
  a `POST`.

### Choosing a prop type

Every prop is eager unless one of these fits. `optional`, `defer` and `merge` also
work inside closures and nested arrays, and `only`, `except`, `<Deferred>` and
`<WhenVisible>` target nested props with dot notation (Inertia 3).

| Prop | Use when | Client side |
|---|---|---|
| `Inertia::defer(fn)` | the page can paint without it and it is slow (totals, charts) | `<Deferred data="totals">` with a skeleton fallback; `reloading` slot prop while it refreshes (Inertia 3) |
| `Inertia::optional(fn)` | only some interactions need it (a dialog's data) | `router.reload({ only: ['…'] })` when the interaction opens |
| `Inertia::once(fn)` | reference data that rarely changes (option lists, plans) | remembered while navigating between pages that include it; `->as()` shares it between pages, `->until()` expires it, `->fresh()` forces it |
| `Inertia::scroll(fn)` | a paginated feed or long list loaded on scroll | `<InfiniteScroll data="invoices">`; a filter change visits with `reset: ['invoices']` |
| `Inertia::merge(fn)` | appending to a list the client already holds, outside a paginator | merged on partial reloads only; full visits replace it |
| any of the above | below-the-fold data | `<WhenVisible data="…">` loads it when the element enters the viewport |
| eager | data that changes on its own | `usePoll(ms)` |

- **Chain `->once()`** on `defer`, `optional` and `merge` when the same data is
  safe to remember.
- **`->fresh()` forces a remembered prop to resolve again**, `->fresh($condition)`
  only when the condition holds.
- `Inertia::lazy()` is gone; it is `Inertia::optional()`.

---

## View DTOs

A View DTO is the exact shape a page receives. It lives in `app/Data/<Context>/`,
ends in `View`, and is exported to TypeScript.

```php
namespace App\Data\Billing;

use Spatie\TypeScriptTransformer\Attributes\TypeScript;

#[TypeScript]
final readonly class InvoiceRowView
{
    public function __construct(
        public string $id,
        public string $number,
        public Money $total,
        public InvoiceStatus $status,
        public string $statusLabel,
        public string $customerName,
        public string $issuedAt,
        public InvoiceAbilitiesView $can,
    ) {}

    public static function fromModel(Invoice $invoice, InvoiceAbilitiesView $can): self
    {
        return new self(
            id: $invoice->public_id,
            number: $invoice->number->value,
            total: $invoice->total,
            status: $invoice->status,
            statusLabel: $invoice->status->label(),
            customerName: $invoice->customer->name,
            issuedAt: $invoice->issued_at->toIso8601String(),
            can: $can,
        );
    }
}

#[TypeScript]
final readonly class InvoiceAbilitiesView
{
    public function __construct(
        public bool $refund,
        public bool $void,
    ) {}
}
```

Rules:

- **`id` is the `public_id`.** The integer id never reaches the page.
- **Shaped for the page, not for the model.** A list row and a detail page are two
  View DTOs (`InvoiceRowView`, `InvoiceView`). Never one DTO with half its fields
  null.
- **Labels are server-side.** An enum crosses as its value *and* its translated
  label (`status` + `statusLabel`). Select options cross as `OptionView` lists built
  from the enum — filtered by whatever rule decides which cases are pickable.
- **Record abilities are a `can` field**, an `*AbilitiesView` DTO of booleans computed
  by the controller from the policy. The page reads `invoice.can.refund`; it never
  derives it.
- **Dates cross as ISO-8601 strings**; money crosses as the `Money` VO's public
  shape (`cents`, `currency`) and is formatted on the client with a shared helper.
- **Relations are flattened to what the page shows** (`customerName`) or nested as
  their own View DTO — never a model, never `toArray()`.
- **Paginators cross as paginators**: `$paginator->through(fn ($m) => XView::fromModel($m))`,
  wrapped in `Inertia::scroll()` when the page scrolls instead of paging.
  The page types them with the hand-written `Paginated<T>`.
- `#[TypeScript]` on every View DTO, every enum and every VO a View DTO exposes.

---

## Generated types

`spatie/laravel-typescript-transformer` writes `resources/js/types/generated.d.ts`
from every class and enum marked `#[TypeScript]`.

- **Run the transformer after any change** to a View DTO, an exposed enum or VO,
  and commit the generated file with the PHP change.
- **The gate regenerates and compares** — `composer types:fresh`, part of
  `composer lint`, runs `scripts/types-fresh.sh`:

  ```bash
  #!/usr/bin/env bash
  # Fails when generated.d.ts was stale. The file is regenerated either way,
  # so after a failure it only needs committing.
  set -u
  f=resources/js/types/generated.d.ts
  before=$(cat "$f" 2>/dev/null)
  php artisan typescript:transform || exit 1
  if [ "$before" != "$(cat "$f")" ]; then
      echo "types-fresh: $f was stale; it is regenerated now, commit it" >&2
      exit 1
  fi
  ```

  It compares the file before and after regenerating, never against git: a freshly
  regenerated file that is not committed yet is valid, and `git diff --exit-code`
  would fail it.
- **Inertia projects extend `composer lint`** with the check, from the phase that
  installs the transformer on:

  ```json
  "types:fresh": "bash scripts/types-fresh.sh",
  "lint": ["pint --test", "phpstan analyse", "rector --dry-run", "bash scripts/grep-gates.sh", "@types:fresh"]
  ```
- **Never edit `generated.d.ts`** and never re-declare a server shape by hand.
- Pages import their prop types from the generated namespace:
  `App.Data.Billing.InvoiceRowView`, `App.Enums.InvoiceStatus`.
- **Shared props, flash and layout props are typed once**, by augmenting
  `InertiaConfig` in `global.d.ts` (`sharedPageProps`, `flashDataType` (Inertia 2.3.3+),
  `layoutProps` (Inertia 3)) with generated types — never by passing a `SharedData` generic to
  every `usePage()`. The `App.Data.*` names below follow wherever `UserView` and
  `GlobalAbilitiesView` live in the project:

  ```ts
  // resources/js/types/global.d.ts
  import '@inertiajs/core';

  declare module '@inertiajs/core' {
      export interface InertiaConfig {
          sharedPageProps: {
              auth: {
                  user: App.Data.UserView;
                  can: App.Data.GlobalAbilitiesView;
              } | null;
              locale: string;
          };
          flashDataType: {
              success?: string;
              error?: string;
          };
      }
  }
  ```

- `index.d.ts` holds only `Paginated<T>` and framework glue.

---

## Shared props

`HandleInertiaRequests::share()` carries only what every page needs:

```php
public function share(Request $request): array
{
    $user = $request->user();

    return [
        ...parent::share($request),
        'auth' => $user
            ? Inertia::once(fn () => [
                'user' => UserView::fromModel($user),
                'can'  => $this->abilities($user),
            ])
            : null,
        'locale' => app()->getLocale(),
    ];
}

private function abilities(User $user): GlobalAbilitiesView
{
    $gate = Gate::forUser($user);

    return new GlobalAbilitiesView(
        viewBilling: $gate->allows('viewBilling'),
        manageUsers: $gate->allows('manageUsers'),
        exportReports: $gate->allows('exportReports'),
    );
}
```

- **`auth.can` is the global ability map** — a `GlobalAbilitiesView` DTO with one
  boolean per `Gate::define()` ability. Navigation and section-level UI read it.
- **Abilities, never roles.** The page never receives or compares a role.
- **Record abilities never go here** — they ride on the record's View DTO.
- **Nothing per-page in shared props.** If only one page needs it, it is that page's
  prop.
- **Flash is not a shared prop** — it travels as Inertia flash data (see *Errors and
  flash*).
- **`auth` is a once prop when signed in and `null` when signed out** — the
  pattern from the Inertia docs: the client remembers it across visits, and the
  `null` keeps a remembered user from going stale after logout. `shareOnce()` is
  for app-wide reference data that is the same for every user.
- `sharedPageProps` in `global.d.ts` types this shape.

---

## Routes: Wayfinder

Wayfinder generates typed functions for every controller and named route, with form
variants enabled and `generate.inertia.component` on in `config/wayfinder.php` (so
routes know their page component, for instant visits (Inertia 3)).

- **Every URL in the frontend comes from Wayfinder** —
  `@/actions/App/Http/Controllers/Billing/InvoiceController` for controller
  methods, `@/routes/...` for named routes. A string path or a `route('...')` call
  in a page is a bug.
- **Import the method functions from the controller** —
  `import { store } from '@/actions/App/Http/Controllers/Blog/PublishPostController'`,
  then `store.form(post.id)`. Every controller method is a resource method, so every
  import is one (`store`, `update`, `destroy`); alias it when a page imports
  several (`import { store as publishPost } …`).
- **Wayfinder results pass straight to Inertia** (Inertia 2.1.2+) — `<Form>`'s `action`,
  `useForm(store(), …)`, `form.submit(update(invoice.id))`, `<Link href={show(id)}>`;
  the method and URL are inferred.
- **Route parameters are public ids** — the View DTO's `id`.
- Regenerate after route changes; the generated folders are never edited.

---

## Visits

- **`<Link>` for navigation**, `prefetch` on links the user is likely to follow
  (main navigation, the row's primary link).
- **Instant visits are opt-in per link** (Inertia 3) — `<Link href={show(id)} instant>` swaps
  to the target page before the server answers (`<Form instant>` too). Use them only
  for a target page that can render without its page-specific props, which are
  `undefined` until the response arrives; shared props carry over on their own.
- **Filters, search and pagination live in the query string** — `router.get()`
  with `preserveState` and `preserveScroll`, read back from the filter View DTO.
- **Partial reloads name what they need** — `router.reload({ only: ['invoices'] })`;
  add `preserveErrors: true` (Inertia 3) when a reload must not wipe the form's
  validation errors.
- **Never `router.cancel()`** — it is `router.cancelAll()` (Inertia 3; on Inertia 2
  `router.cancel()` is the API).

---

## Forms

- **`<Form>` with a Wayfinder action is the default** for every plain submit:
  create, edit, an intent button with a confirmation. Validation errors arrive from
  the FormRequest into the slot's `errors` and render inline next to their field.
  `disableWhileProcessing`, `resetOnSuccess` and `options` (`preserveScroll`,
  `only`, …) cover the usual tweaks without leaving `<Form>`.
- **Optimistic updates live on the `<Form>` too** (Inertia 3) — the `optimistic` prop for
  toggles and list appends the user should see at once (mark done, like, add a
  row). The callback mirrors what the server will return, from the current props
  and the form data; Inertia rolls back on any failure. Never optimistic for money,
  stock, or anything a rule may refuse.
- **`useForm` only when the page holds real client state** before submitting:
  multi-step wizards, dynamic rows, a draft the user edits for a while.
- **Field components read the parent form with `useFormContext()`** (Inertia 2.3.9+) instead of
  receiving `errors` and `processing` as props.
- **Field names match the FormRequest keys** (`snake_case`), so `errors.credit_limit_cents`
  maps 1:1. Type the form with the `<Form>` generic (`createForm<T>()` in Vue) when
  the slot reads `errors` by key (Inertia 3).
- **No client-side validation of rules.** HTML attributes for UX (`required`,
  `maxlength`, `type="email"`) are fine; the FormRequest is the check.
- **Live validation is Precognition, built into `<Form>` and `useForm`** (Inertia 2.3+) — opt-in
  for long forms: `HandlePrecognitiveRequests` on the route, `validate('field')`
  from the form. The FormRequest still runs every rule; no `laravel-precognition`
  package.
- **Intents that are not forms** (publish, archive) are still `<Form>` with a
  button — never `fetch` or `useHttp` to your own backend.

---

## HTTP outside the page

This section is Inertia 3. On Inertia 2 the same rules hold with Axios in place of
`useHttp` and Axios interceptors in place of `http.*`.

- **`useHttp` only for requests that are not page data** — a third-party endpoint,
  an upload straight to a presigned URL, the app's own public `/v1` API when the
  page genuinely consumes it. It never loads or changes what a page renders; that
  is a visit.
- **Request-wide concerns are interceptors** (`http.onRequest`, `http.onResponse`,
  `http.onError`) registered once at app boot — never a hand-rolled wrapper.
- **No Axios.** If a library forces it, wire it through `axiosAdapter()` in
  `createInertiaApp`.

---

## Errors and flash

- **Validation errors** come from the FormRequest and render inline on the form.
- **The `with('success'|'error')` flashes of the Laravel layer are written
  `Inertia::flash()` in an Inertia app** (Inertia 2.3.3+), including in the domain-exception
  handler:

  ```php
  return Inertia::flash('success', __('Invoice refunded.'))->back();

  // bootstrap/app.php, DomainException branch for Inertia requests
  return Inertia::flash('error', $e->userMessage())->back();
  ```

  Inertia flash data is not kept in history, so a toast never replays on back/
  forward navigation.
- **One toast outlet in the app layout** listens to the router's `flash` event
  (`router.on('flash', …)`, removed on unmount with the callback `router.on`
  returns) and shows each message. Pages never render their own error banners for domain
  errors.
- **HTTP errors render as an Inertia error page** through one handler (Inertia 3):

  ```php
  // app/Providers/AppServiceProvider.php
  Inertia::handleExceptionsUsing(function (ExceptionResponse $response) {
      if (in_array($response->statusCode(), [403, 404, 500, 503])) {
          return $response->render('errors/show', [
              'status' => $response->statusCode(),
          ])->withSharedData();
      }
  });
  ```

  `withSharedData()` gives the error page the shared props (a 404 never reaches
  the middleware otherwise). Returning `null` falls through to Laravel's default
  rendering.
- **Client error hooks use the v3 names** (Inertia 3) — `httpException` /
  `onHttpException` and `networkError` / `onNetworkError`. On Inertia 3 a listener
  on `invalid` or `exception` never fires; on Inertia 2 those are the names.
- Unexpected errors are never swallowed.

---

## Layouts

- **The default layout is set once** (Inertia 3) in `createInertiaApp({ layout })`; the callback
  receives the page name and returns `null` for pages that must not get it. A
  per-page layout always takes precedence.
- **Pages send data to the layout through layout props** (Inertia 3) — static
  (`[AppLayout, { breadcrumbs }]`, or a callback reading page props) or dynamic
  (`setLayoutProps({ … })`) — typed by `layoutProps` in `global.d.ts`. Never a
  wrapper component re-declared per page just to pass a title.
- Anything a layout shows from the server comes from shared or layout props.

---

## State

- **Props are the state.** Changing data means sending an intent and receiving new
  props.
- **Local UI state only** — open dialogs, the active tab, an unsaved input.
- **No Redux, Zustand, Pinia or any global store.** A page that genuinely needs
  one is a client application and is discussed before it is built.
- **No data fetching in components** — no `fetch`, `useHttp` or
  `useEffect`/`onMounted` loading server data. Deferred, optional, once and scroll
  props, partial reloads, polling (`usePoll`) and `WhenVisible` cover it.

---

## Translations

- **Strings live in `lang/*.json`**, shared by Laravel and the frontend, read
  through a `__()`-compatible helper (`laravel-react-i18n` / `laravel-vue-i18n`).
- **Server-provided labels** (enum labels, `userMessage()`, flash) arrive already
  translated; the page translates only its own copy.
- The active locale comes from the `locale` shared prop.

---

## Frontend layout

```
resources/js/
  pages/<context>/<resource>/<page>     one page per Inertia component name
  pages/errors/                         the error page rendered by handleExceptionsUsing
  components/ui/                        kit primitives (shadcn)
  components/<context>/                 context components (invoice-table)
  components/                           app-wide components (toast-outlet, app-sidebar)
  layouts/                              app, auth, settings layouts
  types/generated.d.ts                  transformer output, never edited
  types/global.d.ts                     InertiaConfig augmentation
  types/index.d.ts                      Paginated<T>
  actions/  routes/                     Wayfinder output, never edited
  lib/                                  pure helpers: formatMoney, formatDate, cn
```

- **Contexts mirror the backend**: `pages/billing/…`, `components/billing/…`.
- **Kit primitives in `components/ui/` stay generic** — no domain names, no server
  calls.
- **`lib/` is pure** — formatting and class helpers, no state, no requests.

---

## Testing

- **Tier 1 asserts the page from the server**:

  ```php
  it('lists overdue invoices', function () {
      $user = User::factory()->create();
      Invoice::factory()->overdue()->count(3)->create();

      $this->actingAs($user)
          ->get(route('invoices.index'))
          ->assertInertia(fn (AssertableInertia $page) => $page
              ->component('billing/invoices/index')
              ->has('invoices.data', 3)
              ->where('invoices.data.0.can.refund', true)
              ->missing('invoices.data.0.customer_id')
              ->missing('totals')
              ->loadDeferredProps(fn (AssertableInertia $reload) => $reload
                  ->has('totals')));
  });

  it('refunds an invoice', function () {
      // ...
      $this->actingAs($user)
          ->post(route('invoices.refund', $invoice))
          ->assertRedirect()
          ->assertInertiaFlash('success', __('Invoice refunded.')); // Inertia 2.3.3+

      expect($invoice->fresh()->status)->toBe(InvoiceStatus::Refunded);
  });
  ```

- **Assert the integer id never leaks** on pages that expose records.
- **Deferred props are asserted absent first, then loaded** with
  `loadDeferredProps()`; optional props through `reloadOnly()`.
- **Writes are tested as redirects + state + `assertInertiaFlash()`**, never through
  the page; a domain error asserts the `error` flash.
- **SSR is off in tests** (`INERTIA_SSR_ENABLED=false` in `phpunit.xml`).
- **Browser tests** (Pest 4) for critical journeys only — and for every optimistic
  form, to see the rollback.
- Frontend unit tests are not written unless a component holds real logic, which
  should be rare given the rules above.

---

## Tooling

The kit's scripts are gates alongside the PHP ones:

| Gate | Command |
|---|---|
| types | `npm run types` (`tsc --noEmit` / `vue-tsc --noEmit`) |
| lint | `npm run lint` (ESLint) |
| format | `npm run format:check` (Prettier) |
| generated types fresh | `composer types:fresh` (part of `composer lint`) |
| build | `npm run build` |

SSR, when the project uses it with the `@inertiajs/vite` plugin (Inertia 3), runs
inside `npm run dev`; `vite build --ssr` and `php artisan inertia:start-ssr` are for
production only.

---

## Anti-patterns

| Do not | Do |
|---|---|
| `Inertia::render('…', ['post' => $post])` | `PostView::fromModel($post, …)` |
| `$post->toArray()`, `$post->only([...])` as a prop | a View DTO |
| `id: $post->id` in a View DTO | `id: $post->public_id` |
| a hand-written `interface Invoice` for server data | the generated `App.Data.Billing.InvoiceRowView` |
| `usePage<SharedData>()` in every component | `sharedPageProps` in `global.d.ts` |
| editing `generated.d.ts` or Wayfinder output | change the PHP, regenerate |
| `href="/invoices/" + id`, `route('invoices.show')` | Wayfinder `show(invoice.id)` |
| `if (user.role === 'admin')` in a page | `auth.can.manageUsers` or `invoice.can.refund` |
| translating an enum value on the client | `statusLabel` from the server |
| one View DTO with optional fields for list and detail | one View DTO per shape |
| `fetch`, `axios` or `useHttp` to your own backend from a page | Inertia props, deferred/optional/once props, partial reloads |
| `useEffect` / `onMounted` loading data | deferred or optional props |
| a "load more" button concatenating pages in `useState` / `ref` | `Inertia::scroll()` + `<InfiniteScroll>` |
| re-sending static option lists on every visit | `Inertia::once()` |
| a Redux, Zustand or Pinia store | props + local UI state |
| client-side business validation | FormRequest errors, Precognition for live feedback |
| `useForm` + manual state juggling for an optimistic toggle | `<Form optimistic={…}>` (Inertia 3) |
| optimistic UI on money, stock or a refusable rule | wait for the server |
| `Inertia::render()` after a `POST` | redirect with `Inertia::flash()` |
| `back()->with('success', …)` / a `flash` shared prop | `Inertia::flash('success', …)->back()` |
| a page rendering its own domain-error banner | the toast outlet on the `flash` event |
| per-page data in `HandleInertiaRequests` | a prop on that page |
| a View DTO with a query or a rule | the controller maps, the Action reads |
| `Inertia::lazy()`, `router.cancel()`, `invalid` / `exception` listeners | `Inertia::optional()`, `router.cancelAll()`, `httpException` / `networkError` (Inertia 3) |
| hardcoded UI copy | `lang/*.json` through the i18n helper |

---

## Review checklist

- [ ] Every prop is a View DTO (or a collection/paginator of them); no models, no `toArray()`.
- [ ] View DTOs are `#[TypeScript]`, `final readonly`, in `app/Data/<Context>/`, with `id` = `public_id`.
- [ ] Slow props deferred, interaction-only props optional, static reference data `once`, feeds `scroll`.
- [ ] Enum labels and select options come from the server; record abilities ride on a `can` DTO.
- [ ] `generated.d.ts` regenerated and committed; shared props, flash and layout props typed in `global.d.ts`; no hand-written server types.
- [ ] Every URL comes from Wayfinder; route parameters are public ids; `instant` only on pages built to render without their props.
- [ ] Forms use `<Form>` + Wayfinder; `useForm` only for real client state; optimistic only for safe, reversible changes.
- [ ] Successes and domain errors use `Inertia::flash()` and render in the layout toast; HTTP errors render through `handleExceptionsUsing` (Inertia 3).
- [ ] On Inertia 2: nothing tagged `(Inertia 3)`, nothing tagged above the installed 2.x minor.
- [ ] No client store, no client data fetching, no Axios, `useHttp` only for non-page requests, no business or permission logic in pages.
- [ ] Global abilities via `auth.can` (`auth` a once prop, `null` when signed out); no roles on the client.
- [ ] Tier-1 `assertInertia` tests for every page (deferred props loaded), `assertInertiaFlash` on writes; browser tests for critical journeys and optimistic forms.
- [ ] `npm run types`, `lint`, `format:check`, `build` and `composer types:fresh` pass.
