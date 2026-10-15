# Laravel coding guidelines

<!-- harness-meta:start -->
Drop this into a Laravel project as `docs/agents/coding_guidelines.md`. It is the
convention layer agents must follow when writing code in that project: `/init`
and `/plan` decompose against it, `ralph.sh` sessions read it before the first
edit. `/ai-context` copies it there automatically when the target is a Laravel
repo and the file is absent, followed by the frontend layer the project uses:
`guidelines/inertia.md` + `guidelines/react.md` or `guidelines/vue.md` for an
Inertia app, `guidelines/livewire.md` for a Livewire app. `/jharness:update`
refreshes a copy that was never edited. This block is stripped from the copy.

> Keep it hand-written there — without the `/ai-context` banner on line 3 the
> generator never clobbers it. Do not run `/ai-context --adopt` on this file.
<!-- harness-meta:end -->

Stack assumed: **Laravel 13, PHP 8.4, Pest 4**, started from an official starter
kit — React or Vue on Inertia 3 (with or without auth), or Livewire 4 without
Flux. The frontend layer that follows this file adds what is specific to it;
every rule here still applies there.

---

## Golden rules

1. **Code lives in bounded contexts.** Every Action, DTO, event, listener, job,
   exception and controller sits in a context subfolder (`Actions/Billing/`).
   Models stay flat. A context reads another context's models directly, changes
   them only through that context's Actions, and reacts to it through events.
2. **Actions own writes, and orchestrate them.** Every state change goes through an
   Action class with a `handle()` method that opens the transaction and decides,
   top to bottom, everything that happens in its use case: model transitions,
   gateway calls, and the events that announce the result. Nothing else writes.
   The Action orchestrates the write; it never performs it. `create()`, `update()`,
   `save()`, `delete()` and `increment()` are never called from an Action.
3. **Models are rich domain bags that persist themselves — domain rules only.**
   The entity guards its own invariants and its own state machine, and saves. Every
   write is one of its methods: a transition for a change, a named constructor for
   birth. The Action still owns the transaction, and owns every business rule.
4. **Value objects carry their own validity — and exist only where there is a
   rule.** A `Money` that exists is a valid `Money`. A title is a `string`; an
   email, an amount or a period is a VO.
5. **Typed shapes cross class boundaries; arrays never do.** Every public argument
   and every return is a model, VO, DTO, enum, Collection or scalar with no rule
   behind it — never an associative array, never `mixed`. Actions and Gateways go
   further: they return a model, VO, DTO or Collection, never a `bool` or a loose
   primitive.
6. **Enums are always string-backed, and they own every rule.** A business enum is
   stored through a lookup table — an `id` and a `label` behind a foreign key —
   mapped on the model by one memoized `Attribute`. The table is storage, never
   logic.
7. **Entry points validate, authorize, delegate.** Controllers, console commands
   and frontend components that talk to the server (Livewire) do those three
   things and nothing else. Policies and gates run **only** there, and **never
   inside an Action** — an Action assumes its caller has already authorized.
8. **Jobs and listeners own only their own plumbing.** Retries, backoff, uniqueness,
   overlap — then one Action call.
9. **What happened is an event; what follows is a listener.** An Action announces a
   domain fact (`PaymentPaid`) once it is committed. Each consequence in another
   context — mark the order paid, issue the invoice — is a queued listener calling
   its own Action. The emitting Action never knows who listens.
10. **Every external call goes through a Gateway.** A Client transports, a Gateway
    translates — outbound calls and inbound webhooks alike; more than one vendor
    means a contract plus adapters.
11. **Explicit construction over container bindings.** Autowire concrete classes.
    Anything whose construction needs config or runtime data is built by a Factory
    with `new`. Bindings hide what runs; keep them rare.
12. **FormRequests are shape only.** Required, max, unique, format. Never a business
    rule.
13. **Domain failures are domain exceptions; HTTP is decided in `bootstrap/app.php`.**
    An Action or a model throws a typed domain exception carrying a
    `DomainErrorKind`; `withExceptions()` maps that kind to a response once.
    Never `abort()`, never an `HttpException` below the entry point, and no
    `try`/`catch` plumbing at entry points.
14. **Reads are Eloquent + scopes, composed in an Action.** `#[Scope]` attributes are
    the vocabulary; a bare `where()` in an Action and raw SQL (`whereRaw`) are both
    banned. A report or specific read gets a `Get*` Action of its own, and one that
    returns a list takes a `*Filter` DTO.
15. **Everything typed; only DTOs and VOs are `final readonly`.** No `mixed`, no
    untyped properties. Every other class stays open — no `final` on Actions,
    models, gateways, factories, controllers or jobs.
16. **Internal ids stay internal.** Primary keys are auto-increment `bigint`. A model
    whose identity leaves the application gets a `public_id` — a prefixed base58
    ULID (`ord_…`) — and that is the only id a URL, a prop or an API response ever
    carries.
17. **Test everything, backend features first.** Feature tests of backend behavior
    come before anything else; unit, gateway and frontend tests follow.
18. **Rules that can be checked mechanically are.** Pest arch tests, Larastan, Pint
    and Rector run on every change. A rule a machine can catch is never left to
    review.
19. **Code explains itself; comments are for shenanigans.** Names and types carry
    the meaning. A comment appears only when the code cannot say it. The only
    allowed docblock is one PHP types cannot express: a generic or an array shape.

---

## Bounded contexts

A **context** is an area of the business with its own vocabulary and its own rules:
`Billing`, `Sales`, `Catalog`, `Identity`. The project declares its contexts in its
project description (or `AGENTS.md`), and every new class is placed in one. A small
application may have a single context; it is still named.

### Layout

Plain Laravel, grouped by type, with a context subfolder inside each type folder.
Every `make:` command, IDE and starter kit keeps working.

```
app/
  Actions/Billing/ChargeOrder.php
  Actions/Billing/GetOverdueInvoices.php
  Actions/Sales/PayOrder.php
  Data/Billing/ChargeData.php
  Data/Billing/InvoiceRowView.php
  Events/Billing/PaymentPaid.php
  Listeners/Sales/MarkOrderAsPaid.php
  Jobs/Billing/RetryFailedCharge.php
  Exceptions/Billing/ChargeRejected.php
  Http/Controllers/Billing/InvoiceController.php
  Http/Requests/Billing/StoreInvoiceRequest.php
  ValueObjects/Money.php              shared across contexts
  ValueObjects/Billing/InvoiceNumber.php
  Models/Invoice.php                  flat
  Models/Order.php                    flat
  Enums/InvoiceStatus.php             flat, next to the model
  Policies/InvoicePolicy.php          flat, one per model
  Casts/MoneyCast.php                 flat
  Gateways/Pagarme/…                  per vendor, not per context
```

- **Context subfolders** under `Actions`, `Data`, `Events`, `Listeners`, `Jobs`,
  `Exceptions`, `Http/Controllers`, `Http/Requests`, `Console/Commands` and
  context-specific `ValueObjects`.
- **Flat** for `Models`, `Enums`, `Policies` and `Casts` — Eloquent conventions,
  factories and policy discovery stay untouched. A model belongs to exactly one
  context; the project description records which.
- **Shared** value objects (`Money`, `Email`, `Period`, `Pagination`) live at the
  root of `app/ValueObjects/`.
- No `Domain/`, no `src/Modules/`, no per-context service providers.

### Crossing a boundary

| From another context, you may | How |
|---|---|
| **read** its models | relations, scopes, `Get*` Actions — directly |
| **change** its state, and it must succeed with your write | inject its Action and call `handle()` inside your transaction |
| **change** its state as a consequence of your fact | dispatch your event; it listens in its own context and calls its own Action |
| call its model transitions or named constructors | **never** — only its Actions write it |

```php
namespace App\Actions\Billing;

class ChargeOrder
{
    public function __construct(
        private readonly PaymentGatewayFactory $gateways,
        private readonly ReserveStock $reserveStock,    // Catalog action, same transaction
    ) {}

    public function handle(Order $order): Payment
    {
        return DB::transaction(function () use ($order) {
            $this->reserveStock->handle($order);

            $result = $this->gateways->make()->charge(ChargeData::fromOrder($order));
            $payment = Payment::record($order, $result);

            PaymentPaid::dispatch($payment);           // Sales reacts on its own

            return $payment;
        });
    }
}
```

- An Action never calls `$order->markPaid()` when `Order` belongs to another
  context — it calls `Sales\PayOrder`, or dispatches an event `Sales` listens to.
- A listener lives in the context that **reacts**: `Listeners/Sales/MarkOrderAsPaid`
  listens to `Events/Billing/PaymentPaid`.
- Data from another context is read, never copied into your tables to "own" it.
- Two contexts calling each other's Actions in both directions means the boundary
  is wrong; merge them or move the rule.

---

## Layer map

| Layer | Path | Owns | Never |
|---|---|---|---|
| Controller | `app/Http/Controllers/<Context>/*Controller.php` | authorize + validate (via FormRequest), call one Action, respond | business rules, queries, transactions |
| Console command | `app/Console/Commands/<Context>/*Command.php` | validate options, call Action, report | business rules, queries, transactions |
| FormRequest | `app/Http/Requests/<Context>/*Request.php` | shape validation of input, authorization | business rules, persistence |
| API Resource | `app/Http/Resources/V1/*Resource.php` | the public JSON API representation | rules, queries, internal ids |
| Job | `app/Jobs/<Context>/*.php` | retries, backoff, timeout, uniqueness, overlap, `failed()` — then one Action call | validation, authorization, business rules |
| Event | `app/Events/<Context>/*.php` | a past-tense domain fact + its aggregate model | behavior, rules, knowing its listeners |
| Listener | `app/Listeners/<Context>/*.php` | one reaction to one event: queue config — then one Action call | validation, authorization, business rules, deciding whether to react |
| Action | `app/Actions/<Context>/*.php` | every write, business rules, orchestration, transaction boundary, composing reads from scopes, reports, caching a read | authorization, HTTP/UI concerns, shape validation, persistence calls, bare `where()`, raw SQL, re-checking model invariants, `abort()`, a second public method, `static` |
| Model | `app/Models/*.php` | domain rules: invariants, transitions, named constructors, relations, casts, `#[Scope]` predicates, enum ⇄ lookup id mapping, same-row derivation hooks | business rules, cross-aggregate orchestration, events, config, static finders |
| Value object | `app/ValueObjects/[<Context>/]*.php` | its own validity + behavior | persistence, container access |
| DTO | `app/Data/<Context>/*Data.php`, `*Result.php`, `*Filter.php`, `*View.php` | typed transport across an Action or frontend boundary | rules, behavior, persistence |
| Gateway | `app/Gateways/<Vendor>/*Gateway.php` | domain ⇄ vendor translation, vendor errors → domain exceptions | HTTP mechanics, reading config |
| Client | `app/Gateways/<Vendor>/*Client.php` | transport: base URL, auth, headers, timeout, transport retries | domain knowledge, reading config |
| Factory | `app/Gateways/<Vendor>/*GatewayFactory.php` | building Client + Gateway with `new` from config and runtime data | calling the vendor, business rules |
| Contract | `app/Contracts/*.php` | the domain-shaped interface a vendor must satisfy | vendor vocabulary |
| Enum | `app/Enums/*.php` | closed sets, transition tables, labels, every rule about the value | queries, reading its own lookup table |
| Lookup table | `<name>_status`, `<name>_type`, … | `id` + `label`, referenced by FK | behavior, rules, an Eloquent model |
| Cast | `app/Casts/*.php` | VO ⇄ column mapping | rules of any kind |
| Policy | `app/Policies/*.php` | authorization, per model and global abilities | state changes |
| Exception | `app/Exceptions/<Context>/*.php` | domain failure + its `DomainErrorKind` | status codes, `Request`, `render()`, control flow for expected branches |
| Exception mapping | `bootstrap/app.php` `withExceptions()` | `DomainErrorKind` → response, per request type | domain knowledge, per-class special cases |

---

## Actions

One class, one intent. `handle()` is the only public method on the class, and it
opens the transaction.

```php
namespace App\Actions\Blog;

class PublishPost
{
    public function __construct(
        private readonly Dispatcher $events,
    ) {}

    public function handle(Post $post, PublishedAt $at): Post
    {
        return DB::transaction(function () use ($post, $at) {
            $post->publish($at);
            $post->author->countPublishedPost();
            $this->events->dispatch(new PostPublished($post));

            return $post;
        });
    }
}
```

### Actions own writes, and orchestrate them

The Action is the only place a write starts, and the only place that decides the
order of its effects. Reading `handle()` top to bottom tells the whole story of the
use case: which transitions run, which other aggregates change, which gateway is
called, which events and jobs go out — and in what order.

- **Nothing writes behind its back.** Controllers, console commands, components,
  jobs and listeners never call `save()`, `update()`, `create()` or `delete()`.
  Observers and model hooks never write another row either (see *Model hooks*).
- **The Action does not write either — it says which writes happen, and in what
  order.** `save()`, `update()`, `create()`, `delete()`, `increment()`, `attach()`
  and `sync()` never appear in `handle()`. Every line that changes state is a call
  to a method on the entity that owns the invariant: a transition for a change
  (`$post->publish($at)`), a named constructor for birth (`Post::draft(...)`). Plain
  CRUD is no exception: editing a profile is `$user->changeProfile($data)`. If an
  Action needs a persistence call there is no method for, the missing method is on
  the model.
- **The model executes, the Action orchestrates.** `$post->publish($at)` changes
  and persists one entity; deciding that publishing also bumps a counter and
  notifies followers is the Action's job.
- **An Action may compose other Actions** — of its own context, or of another one
  when the change must succeed together: inject them and call their `handle()`. The
  outermost Action owns the transaction; the inner ones join it.
- **Effects are explicit calls, in order.** Events are dispatched, jobs queued and
  notifications sent by the Action after the state they describe exists — never
  from a model hook.
- **Its own use case directly, other contexts through events.** What must succeed
  or fail together with the write is a direct call inside the transaction; what
  merely reacts to it is a listener on the event the Action dispatches.

Rules:

- **Name it after the intent**: verb + noun. `PublishPost`, `CancelSubscription`,
  `RefundInvoice`. Never `PostService`, never `PostManager`. CRUD intents are named
  the same way: `CreatePost`, `UpdatePost`, `DeletePost`.
- **`handle()` always**, even for a one-liner.
- **`handle()` is the only public method.** Everything else is `private`. A second
  public method is a second responsibility, and a second Action.
- **Never `static`.** `handle()` is an instance method, always called on an injected
  instance. No `PublishPost::run(...)`, no static helpers, no static state.
- **`DB::transaction()` wraps the whole body of every write Action**, including
  single-write ones. Nested Actions join it, and `ShouldDispatchAfterCommit` events
  rely on it.
- **Dependencies via constructor injection**, typed and `readonly`.
- **The Action is the source of business rules.** Anything that depends on the use
  case — other aggregates, config, quotas, the actor, time policies, the order
  effects run in — is decided here.
- **Never re-check a model invariant.** If the model already refuses the transition,
  the Action lets it throw. The one exception is **at-least-once input** — a
  redelivered webhook, a retried queued listener: there "already applied" is an
  expected branch, so the Action checks the state and returns early.
- **In and out are models, VOs, DTOs or Collections — never arrays, never a loose
  primitive that means something.** `handle(Post $post, PublishedAt $at): Post`,
  not `handle(int $postId, string $date): array`.
- **More than three arguments collapse into one DTO** — for `handle()` and for model
  named constructors alike.
- **Return the thing the caller needs** — the affected model, a VO, a result DTO or
  a paginator. Never `bool`, never `void` when there is something to return.
- **No `request()`, no `auth()`, no session** inside an Action. Actor and input
  arrive as arguments.

### Reads

There is no repository layer and no query-object layer. The query language is
**Eloquent: rich domain + active record + the builder.** Reads come in two shapes.

**1 — Ordinary reads: the Action composes the builder from scopes.**

```php
class SendOverdueReminders
{
    public function handle(Reminder $reminder): Collection
    {
        return Invoice::query()
            ->overdue()
            ->withoutReminderSince($reminder->cooldown())
            ->with('customer')
            ->get()
            ->each(/* … */);
    }
}
```

- **Every predicate is a scope**, declared with `#[Scope]` on the model. A bare
  `->where('status_id', 3)` in an Action means a scope is missing. Inside a scope
  body, the builder's own `where` family is exactly the right tool.
- **Scope bodies use the builder, never raw SQL.** `whereBelongsTo`,
  `whereRelation`, `whereHas`, `whereIn`, `whereBetween`, `whereNull`, `when()`.
- **Ordering that carries meaning is a scope too** — `#[Scope] latestFirst()`.
- **Eager load explicitly** (`with()`); lazy loading is disabled in non-production
  (`Model::preventLazyLoading()`).
- The Action returns models, VOs or a paginator — never a `Builder`.

**2 — Reports and specific reads: wrapped in their own `Get*` Action.**

When the query stops being a filtered list of an aggregate — a report, an
aggregate, a projection into a shape that is not a model — it gets an Action of its
own, named `Get` plus what it answers.

```php
class GetMonthlyRevenueByRegion
{
    /** @return Collection<int, RegionRevenue> */
    public function handle(GetMonthlyRevenueByRegionFilter $filter): Collection
    {
        return Invoice::query()
            ->issuedWithin($filter->period)
            ->selectRaw('region_id, SUM(total_cents) AS revenue_cents')
            ->groupBy('region_id')
            ->get()
            ->map(fn (object $row) => new RegionRevenue(
                regionId: $row->region_id,
                revenue: Money::fromCents($row->revenue_cents, Currency::BRL),
            ));
    }
}
```

- **A raw expression is allowed only here**, and only for what the builder cannot
  express — aggregates, window functions. Filtering still goes through scopes, and
  every value is a binding.
- **Name it `Get` plus the answer**: `GetMonthlyRevenueByRegion`. Never
  `InvoiceReportAction`, never `InvoiceQuery`.
- **Return VOs or read DTOs**, not `stdClass` rows and not arrays.
- One report Action per report. No `$groupBy` flags.

A read Action has no `DB::transaction()`. That absence is the signal it is a read.

**Every `Get*` Action that returns a list takes one `*Filter` DTO**, named after the
Action, carrying the filters, the search term and pagination:

```php
namespace App\Data\Billing;

final readonly class GetOverdueInvoicesFilter
{
    public function __construct(
        public Pagination $pagination,
        public ?Customer $customer = null,
        public ?string $search = null,
    ) {}

    public static function fromRequest(OverdueInvoicesRequest $request): self
    {
        // ...
    }
}

class GetOverdueInvoices
{
    public function handle(GetOverdueInvoicesFilter $filter): LengthAwarePaginator
    {
        return Invoice::query()
            ->overdue()
            ->when($filter->customer, fn (Builder $q, Customer $c) => $q->forCustomer($c))
            ->when($filter->search, fn (Builder $q, string $term) => $q->matching($term))
            ->latestFirst()
            ->with('customer')
            ->paginate($filter->pagination->perPage());
    }
}
```

- **Pagination is a VO on the filter**, not two loose ints; it guards its own size
  limits. `paginate()` resolves the page from the query string — the one sanctioned
  implicit request read.
- A bounded report (twelve months, one row per region) returns a `Collection` and
  its filter has no `Pagination`.
- **A `Get*` that returns a single model or a scalar answer takes no filter.**

### Caching a read

Caching is opt-in, and it lives **only inside a `Get*` Action**:

```php
class GetDashboardTotals
{
    public function handle(Period $period): DashboardTotals
    {
        return Cache::flexible(
            "dashboard-totals:{$period->key()}",
            [300, 900],
            fn () => $this->compute($period),
        );
    }
}
```

- **The key is named** after the Action and its arguments; no anonymous keys.
- **Invalidation belongs to the writer**: the Action that changes the data forgets
  the key, or a listener on its event does. A cache nobody invalidates carries an
  explicit TTL and a reason the staleness is acceptable.
- Never cache in a controller, a model, a component or a View DTO.

---

## Models

**Rich domain bag + active record.** The model carries the entity's own vocabulary
and its own consistency, and it persists itself. It carries **domain rules only** —
business rules belong to the Action.

```php
use Illuminate\Database\Eloquent\Attributes\Scope;

class Post extends Model
{
    use HasPublicId;

    protected $fillable = ['title', 'body', 'published_at'];

    public static function draft(User $author, string $title, string $body): self
    {
        throw_if(trim($body) === '', new CannotDraftEmptyPost);

        return self::create([
            'author_id' => $author->id,
            'title'     => $title,
            'body'      => $body,
            'status'    => PostStatus::Draft,
        ]);
    }

    public function publish(PublishedAt $at): void
    {
        throw_unless(
            $this->status->canTransitionTo(PostStatus::Published),
            new CannotPublishPost($this->public_id, $this->status),
        );

        $this->update([
            'status'       => PostStatus::Published,
            'published_at' => $at,
        ]);
    }

    public function isPublished(): bool
    {
        return $this->status === PostStatus::Published;
    }

    protected function casts(): array
    {
        return [
            'published_at' => PublishedAtCast::class,
        ];
    }

    protected function publicIdPrefix(): string
    {
        return 'post_';
    }

    #[Scope]
    protected function published(Builder $query): void
    {
        $query->where('post_status_id', self::statusId(PostStatus::Published));
    }

    #[Scope]
    protected function authoredBy(Builder $query, User $author): void
    {
        $query->whereBelongsTo($author, 'author');
    }

    // status Attribute + statusId() helper: see *Enums and lookup tables*
}
```

### Domain rule or business rule?

| | Domain rule — **model** | Business rule — **Action** |
|---|---|---|
| About | this entity alone | a use case |
| Decided with | the entity's own attributes and relations | other aggregates, config, actor, time, quotas |
| True | always, in every flow, at every entry point | in this flow, under these conditions |
| Examples | a published post cannot be published again; an invoice total is the sum of its lines; an archived post cannot go back to draft | only three active plans per account; publishing notifies followers; a refund is allowed within 7 days on the current plan; at most 10 posts a day per actor |

Two questions settle it:

1. **Would the rule still hold if this entity lived in a completely different
   application?** Yes → domain rule, model. No → business rule, Action.
2. **Does enforcing it need a query, a config value, the clock as policy, or another
   aggregate?** Then it is a business rule, and it does not belong on the model.

Rules:

- **State transitions are methods**, and each one guards its own **invariants**
  before changing anything. `$post->publish($at)`, never `$post->status = ...` from
  the outside.
- **Invariants only — never use-case policy.** A transition never reads config,
  never queries another aggregate, never asks who the actor is.
- **The method persists.** A transition `save()`s or `update()`s itself; the
  surrounding Action provides the transaction. The model is the *only* place these
  calls appear.
- **Birth is a named constructor** — `Post::draft(...)` — which checks the
  invariants that must hold from the first row, inserts, and returns the model.
  More than three arguments → `Post::fromData(DraftPostData $data)`.
- **Named constructors are not static finders.** `Post::findPublishedBySlug()` is
  banned; it is a scope plus a call site, or a `Get*` Action.
- **Predicates return `bool`** — `isPublished()`, `canBeRefunded()`, `hasMember()`.
  The no-`bool` rule is for Action and Gateway boundaries, not for questions an
  entity answers about itself.
- **Casts and relations are the model's job.** Every column with meaning gets a
  cast — enum mapping, VO cast, `immutable_datetime`, `decimal:2`.
- **Scopes carry every reusable predicate**, always in **attribute form** —
  `#[Scope]` on a `protected` method typed `void` with a `Builder` first parameter.
  Never the `scopeXxx()` prefix.
- **No cross-aggregate orchestration**, no events, no notifications, no jobs from
  the model.
- **No container, no `config()`, no `auth()`** inside a model.
- **`$fillable` declared deliberately** on every model; never `$guarded = []`.
- **Lazy loading is a bug**: `Model::preventLazyLoading(! app()->isProduction())`
  and `Model::shouldBeStrict()` in `AppServiceProvider`.

### Model hooks

`booted()` hooks and observers are allowed for **one thing only: deriving a column
of the same row** while it is being written.

- Allowed, in `creating` / `saving`: filling `public_id`, a slug from the title, a
  normalized copy of a column (`email_normalized`), a UUID/ULID column.
- Banned, in any hook: writing another row, dispatching events, queuing jobs,
  sending notifications, calling gateways, enforcing a business rule, reading
  config or the actor.

If a hook would need anything outside its own row, it is a step of the Action.

### Public ids

Primary keys are auto-increment `bigint`, used for foreign keys and joins. A model
whose identity leaves the application — in a URL, an Inertia prop, an API response,
a webhook — also gets a `public_id`: a short prefix naming the model, then a ULID in
base58.

```php
namespace App\Models\Concerns;

trait HasPublicId
{
    abstract protected function publicIdPrefix(): string;

    protected static function bootHasPublicId(): void
    {
        static::creating(function (self $model): void {
            $model->public_id ??= str($model->publicIdPrefix())
                ->append(Str::ulid()->toBase58())
                ->toString();
        });
    }

    public function getRouteKeyName(): string
    {
        return 'public_id';
    }
}
```

```php
$table->id();
$table->string('public_id', 40)->unique();
```

- **Prefixes are short, lowercase, unique per model, end in `_`**: `ord_`, `inv_`,
  `usr_`, `post_`. A prefix never changes once rows exist.
- **Route model binding resolves `public_id`**; controllers never see the integer.
- **The integer `id` never leaves the application.** View DTOs, API Resources,
  events crossing a queue to a vendor, logs shown to users — all carry
  `public_id`. Domain exceptions carry it too when the id ends up in a message.
- A model that is never exposed (a lookup table, an internal ledger line) has no
  `public_id`.

### Relations: when a pivot becomes a model

A `belongsToMany` is fine while the join table is genuinely nothing but a link.
The moment the link itself has something to say, it becomes an entity, with its own
model and its own name.

**Promote the pivot to a model when any of these is true:**

- it carries a column beyond the two foreign keys — `role`, `status`, `joined_at`,
  `expires_at`, `position`
- there is a rule about the link itself — an invariant, a transition, "a family has
  exactly one owner"
- the link has a lifecycle: created, revoked, expired
- it needs a policy, a factory, a domain event, or an enum-backed column
- anything references the link by id

Then `Family hasMany FamilyMember`, `User hasMany FamilyMember`, and `FamilyMember
belongsTo` both. The table is named after the entity — `family_members` — and the
model gets everything any model gets.

```php
class FamilyMember extends Model
{
    public static function join(User $user, Family $family, FamilyRole $role): self
    {
        throw_if($family->hasMember($user), new AlreadyAMember($family->public_id, $user->public_id));

        return self::create([
            'user_id'   => $user->id,
            'family_id' => $family->id,
            'role'      => $role,
        ]);
    }

    public function promote(FamilyRole $role): void
    {
        throw_if($this->role === $role, new AlreadyInRole($role));

        $this->update(['role' => $role]);
    }
}
```

**`withPivot` and `->pivot->` are banned outright**; grepping them should return
nothing. **A surviving `belongsToMany` still writes through a model method** —
`$family->admitMember($user)` wraps `attach()` — never `attach()`, `detach()` or
`sync()` in an Action.

---

## Value objects and casts

Plain PHP, no package. A VO validates in its named constructor and is immutable.

```php
final readonly class Money
{
    private function __construct(
        public int $cents,
        public Currency $currency,
    ) {}

    public static function fromCents(int $cents, Currency $currency): self
    {
        throw_if($cents < 0, new NegativeMoney($cents));

        return new self($cents, $currency);
    }

    public function plus(self $other): self
    {
        throw_unless(
            $this->currency === $other->currency,
            new CurrencyMismatch($this->currency, $other->currency),
        );

        return new self($this->cents + $other->cents, $this->currency);
    }

    public function isZero(): bool
    {
        return $this->cents === 0;
    }
}
```

### When a value becomes a VO

**Only when the value has a rule or behavior of its own.**

| VO | Stays a scalar |
|---|---|
| `Money`, `Email`, `Cpf`, `PhoneNumber`, `Period`, `Pagination`, `PublishedAt`, `Percentage`, `InvoiceNumber` | a title, a name, a body, a note, a search term, a free-text label, an integer quantity whose only limit is a FormRequest `min` |

- The test: **does anything need to refuse an invalid value, or ask the value a
  question** (`$money->plus()`, `$cpf->masked()`, `$period->contains()`)? Yes → VO.
  A `max:120` in the FormRequest is shape, not a rule, and does not make a VO.
- A scalar that crosses a boundary is still typed: `string $title`, never `mixed`.
- When a scalar grows a rule, it becomes a VO in that change.

Rules:

- **`final readonly`, private constructor, named constructors** (`fromCents`,
  `fromString`, `now`). The constructor is the only place validity is decided.
- **Operations return new instances.** No setters, no mutation.
- **Equality is explicit** — `equals(self $other): bool`; never `==`.
- **A closed set is an enum, not a VO.**
- **A VO never touches the container, the DB, or config.** It is pure.

### Casts

- **Casts are declared in the `casts()` method**, never the `$casts` property.
- **A VO reused across models, or one spanning several columns, gets a cast class**
  in `app/Casts/`, doing nothing but mapping:

  ```php
  class MoneyCast implements CastsAttributes
  {
      public function get(Model $model, string $key, mixed $value, array $attributes): ?Money
      {
          return $value === null
              ? null
              : Money::fromCents((int) $value, Currency::from($attributes['currency']));
      }

      public function set(Model $model, string $key, mixed $value, array $attributes): array
      {
          if (! $value instanceof Money) {
              throw new InvalidArgumentException('Expected '.Money::class);
          }

          return ['total_cents' => $value->cents, 'currency' => $value->currency->value];
      }
  }
  ```

- **A single-column VO used by one model may use an inline anonymous cast** in
  `casts()`. The moment a second model needs it, it moves to `app/Casts/`.
- **The VO may carry its own cast** via `Castable::castUsing()` when every model
  would declare the identical cast.

---

## Boundaries: DTOs and VOs

Nothing crosses a class boundary loose. Every argument and return value of an Action
or Gateway is one of:

| Shape | When | Example |
|---|---|---|
| **Model** | the Action acts on an existing aggregate | `handle(Post $post, ...)` |
| **Value object** | the value has rules of its own | `PublishedAt`, `Money`, `Cpf` |
| **Scalar** | the value has no rule beyond its type | `string $title` |
| **DTO** | several values travel together as one input or one result | `RegisterCustomerData`, `PublishResult` |
| **Collection / paginator** | many of one thing | `Collection<int, Post>` |

### Arrays stay inside one class

This holds for **every class in the codebase**.

**An array is a private implementation detail.** Inside a class it is fine: a local
variable, a private property, an argument or return of a `private` or `protected`
method.

**The moment an array would travel to another class, it is banned.** Public and
constructor arguments, public returns, DTO fields, event payloads, job and listener
constructors, gateway inputs and outputs, Inertia props — all typed.

```php
// Banned — the array crosses into another class
$publish->handle(['post_id' => 12, 'at' => '2026-01-01']);
public function handle(array $data): array
new PaymentPaid(['id' => $id, 'amount' => $cents]);
$gateway->charge(['amount' => 1000, 'currency' => 'BRL']);
Inertia::render('blog/posts/show', ['post' => $post->toArray()]);
```

Two narrow exceptions, both of which keep the array from travelling:

- **A framework contract that is an array by definition** — `rules()`, `casts()`,
  `$fillable`, `middleware()`, a config file, `toArray()` on an API Resource, the
  outer props array of `Inertia::render()` and `share()`.
- **Edge translation into a typed shape.** A DTO's or VO's named constructor may
  take the outside world's array — `fromRow(array $row)`, `fromPayload(array $payload)`
  — because the array dies inside that constructor.

### Collections

A Collection is the answer for "many Posts". **Type it:** a generic docblock
(`/** @return Collection<int, Post> */`) or a dedicated collection class when the
set has behavior. A Collection of arrays is still an array; one item type per
Collection. When the list has rules of its own (non-empty, a maximum), it is a VO
wrapping it.

### VO or DTO?

- A **value object** has invariants and behavior; it refuses to exist when invalid.
- A **DTO** has no rules. It is a typed envelope: named fields, immutable, no
  behavior beyond named constructors. Its fields are VOs, enums, models and scalars
  that need no rule.

```php
namespace App\Data\Sales;

final readonly class RegisterCustomerData
{
    public function __construct(
        public string $name,
        public Email $email,
        public Cpf $document,
        public Money $creditLimit,
    ) {}

    public static function fromRequest(RegisterCustomerRequest $request): self
    {
        return new self(
            name: $request->string('name')->value(),
            email: Email::fromString($request->string('email')->value()),
            document: Cpf::fromString($request->string('document')->value()),
            creditLimit: Money::fromCents($request->integer('credit_limit_cents'), Currency::BRL),
        );
    }
}
```

- **The conversion happens at the edge.** The entry point turns validated input into
  VOs and a DTO; the Action never parses a string again.
- **A named constructor per source** — `fromRequest()`, `fromForm()`, `fromRow()`,
  `fromModel()`.
- **DTOs live in `app/Data/<Context>/`**, plain PHP, `final readonly`, promoted
  public properties, no package. The suffix says the role:

| Suffix | Role |
|---|---|
| `*Data` | input of an Action |
| `*Result` | output of an Action that answers more than one thing |
| `*Filter` | input of a `Get*` Action returning a list |
| `*View` | what a page receives from the server (Inertia props; see the frontend layer) |

- **No behavior creep.** The moment a DTO grows a rule, that rule belongs to a VO,
  the model, or the Action.

---

## Enums and lookup tables

**Always string-backed.** Never `int`, never a pure enum for anything persisted.
Case names are `PascalCase`; backing values are `snake_case` and stable forever.

```php
enum PostStatus: string
{
    case Draft = 'draft';
    case Published = 'published';
    case Archived = 'archived';

    public function canTransitionTo(self $next): bool
    {
        return match ($this) {
            self::Draft     => $next === self::Published,
            self::Published => $next === self::Archived,
            self::Archived  => false,
        };
    }

    public function label(): string
    {
        return __("post.status.{$this->value}");
    }
}
```

**Every rule about the value lives on the enum**: transitions, labels, colors,
visibility, ordering. The enum never queries and never touches the container.

### The lookup table

A value the business names — a status, a type, a category, a kind — gets a lookup
table and a foreign key. A closed technical set nobody joins on (`Currency`,
`Locale`) stays a string column with the native enum cast.

The table is `id` + `label`, singular, named after the concept, and seeded from the
enum in the same migration:

```php
Schema::create('post_status', function (Blueprint $table) {
    $table->id();
    $table->string('label')->unique();
});

DB::table('post_status')->insert(
    collect(PostStatus::cases())
        ->map(fn (PostStatus $case) => ['label' => $case->value])
        ->all(),
);

Schema::create('posts', function (Blueprint $table) {
    $table->id();
    $table->foreignId('post_status_id')->constrained('post_status')->restrictOnDelete();
    // ...
});
```

- `label` holds the enum's **backing value verbatim**. It is the join key, not
  display text — display text comes from `$status->label()`.
- A new case is one enum case plus one forward migration inserting its row. Never
  insert by hand, never delete a row a foreign key still points at.
- **No Eloquent model for the lookup table.** No timestamps, no extra columns.
  Anything beyond `id` + `label` is a real entity.

### Mapping it on the model

The model that uses the enum implements one `Attribute` that converts both ways.
It locates the row **by the enum's label through the `DB` facade**, and memoizes the
whole label ⇄ id map in a static property, so the table is read once per process:

```php
/** @var array<string, int> */
private static array $statusIds = [];

protected function status(): Attribute
{
    return Attribute::make(
        get: fn (mixed $value, array $attributes): PostStatus => PostStatus::from(
            array_search($attributes['post_status_id'], self::statusIds(), true),
        ),
        set: fn (PostStatus $status): array => [
            'post_status_id' => self::statusId($status),
        ],
    );
}

private static function statusId(PostStatus $status): int
{
    return self::statusIds()[$status->value];
}

/** @return array<string, int> */
private static function statusIds(): array
{
    return self::$statusIds = self::$statusIds
        ?: DB::table('post_status')->pluck('id', 'label')->all();
}
```

Rules:

- **The attribute is named after the concept** (`status`); the column stays
  `post_status_id`. Nothing outside the model mentions the `*_id` column.
- **The mutator takes the enum, never a string or an id.**
- **`DB` facade, not a relation.** A `belongsTo` would drag a lookup model in.
- **Scopes resolve through the same helper** (`self::statusId(...)`).
- **The memo is safe because the map only changes with a deploy**: a new case
  arrives in a migration, and a deploy restarts every worker (Octane, Horizon,
  queue workers). Tests are deterministic too — the seeding migration inserts the
  same ids in the same order every run.
- The lookup table is queried only by that attribute and its helper.

---

## Entry points

An **entry point** is where something outside the application asks for work: an
HTTP request (web, Inertia, API, webhook), a terminal invocation, a Livewire
interaction. All follow the same contract, in the same order:

1. **Authorize** — policy or gate, for the actor performing the intent.
2. **Validate shape** — FormRequest, Form object, or an explicit validator for
   console options. Format only.
3. **Call one Action**, then present its result — redirect, Inertia page, resource,
   console output.

Nothing else lives at an entry point: no query building, no transactions, no
persistence, no business rules, no event chains.

### Controllers

**Every controller method is a resource method** — `index`, `create`, `store`,
`show`, `edit`, `update`, `destroy`. Never `__invoke`, never a custom method.
Routes may be `Route::resource()` or direct routes pointing at those methods.

- A CRUD controller (`InvoiceController`) maps each method to **one Action**:
  `store` → `CreateInvoice`, `update` → `UpdateInvoice`, `destroy` →
  `DeleteInvoice`, `index` → `GetInvoices`.
- An intent that is not CRUD — publish, refund, approve, cancel — is its own
  controller named after it, `PublishPostController` mirroring `PublishPost`.
  **`store` performs the intent and `destroy` undoes it** (publish / unpublish),
  each calling its own Action:

  ```php
  // routes/web.php
  Route::post('/posts/{post}/publish', [PublishPostController::class, 'store'])
      ->name('posts.publish.store');
  Route::delete('/posts/{post}/publish', [PublishPostController::class, 'destroy'])
      ->name('posts.publish.destroy');
  ```

- Never a custom method (`publish()`) on a CRUD controller.

```php
namespace App\Http\Controllers\Blog;

class PublishPostController
{
    public function store(
        PublishPostRequest $request,
        Post $post,
        PublishPost $publish,
    ): RedirectResponse {
        $publish->handle($post, PublishedAt::now());

        return to_route('posts.show', $post)->with('success', __('Post published.'));
    }

    public function destroy(
        UnpublishPostRequest $request,
        Post $post,
        UnpublishPost $unpublish,
    ): RedirectResponse {
        $unpublish->handle($post);

        return to_route('posts.show', $post)->with('success', __('Post unpublished.'));
    }
}
```

```php
class PublishPostRequest extends FormRequest
{
    public function authorize(): bool
    {
        return $this->user()->can('publish', $this->route('post'));
    }

    public function rules(): array
    {
        return [
            'scheduled_for' => ['nullable', 'date', 'after:now'],
        ];
    }
}
```

- **A FormRequest on every write endpoint**, even one with no rules — it is where
  authorization lives. Read endpoints authorize with `Gate::authorize()` in the
  controller method, or a FormRequest when they take filters.
- **Actions arrive by method injection** on the controller method.
- **A write calls exactly one Action.** A read method rendering a page may compose
  several `Get*` Actions, one per prop.
- Route model binding converts public ids to models; the controller never calls
  `find()`.
- The response is the controller's only other job: a redirect, an Inertia page with
  View DTOs, an API Resource. Mapping a model to a View DTO or a Resource is
  presentation and belongs here.
- **Webhooks are controllers too**: the FormRequest verifies the vendor's signature
  in `authorize()`, then one Action. See *Events*.

### Public JSON API

When a project needs an API for mobile apps or third parties:

- **Routes in `routes/api.php` under `/v1`**, controllers in
  `app/Http/Controllers/Api/V1/<Context>/`, **Sanctum** tokens.
- **API Resources are the public contract** — `app/Http/Resources/V1/InvoiceResource.php`.
  They expose `public_id` as `id`, enum backing values, VO primitives
  (`amount_cents`, `currency`) and never internal ids or hidden columns.
- **The same Actions** serve web and API. Inertia View DTOs and API Resources stay
  separate: a UI change must never change the public contract.
- A breaking change is a new version folder (`V2`), never an edit to `V1`.
- Errors are the same `DomainErrorKind` mapping, rendered as JSON.

### Console command

Commands run **as the system**: no actor, no policy call — unless the command takes
one (`--as=`), in which case it authorizes with `Gate::forUser()`. Options are input
like any other, so they are validated.

```php
class PublishScheduledPostsCommand extends Command
{
    protected $signature = 'posts:publish-scheduled {--limit=100}';

    public function handle(GetDueScheduledPosts $due, PublishPost $publish): int
    {
        $data = Validator::make($this->options(), [
            'limit' => ['required', 'integer', 'min:1', 'max:1000'],
        ])->validate();

        $due->handle((int) $data['limit'])
            ->each(fn (Post $post) => $publish->handle($post, PublishedAt::now()));

        return self::SUCCESS;
    }
}
```

- The command does not query — a `Get*` Action supplies what it iterates.
- Exit codes are meaningful: `SUCCESS`, `FAILURE`, `INVALID`.
- Scheduling lives in `routes/console.php`, scheduling commands or jobs only.

---

## Jobs and listeners

Jobs and listeners are **not entry points**. They run inside the application: the
input already arrived typed, and the edge that dispatched them already authorized.

**Own:** `$tries`, `$backoff`, `$timeout`, `retryUntil()`, `ShouldBeUnique`,
`middleware()` (`WithoutOverlapping`, `RateLimited`), queue and connection choice,
`failed()`.

**Never:** validation, authorization, business rules, transactions, queries, writes.

```php
class PublishScheduledPost implements ShouldQueue
{
    use Queueable;

    public int $tries = 5;

    public int $timeout = 30;

    public function __construct(
        public readonly Post $post,
    ) {}

    public function backoff(): array
    {
        return [10, 60, 300];
    }

    public function middleware(): array
    {
        return [new WithoutOverlapping($this->post->id)];
    }

    public function handle(PublishPost $publish): void
    {
        $publish->handle($this->post, PublishedAt::now());
    }
}
```

- **Jobs resolve Actions by method injection** on `handle()`; **listeners by
  constructor injection**.
- **Constructors carry models and VOs** — serializable payload, nothing else.
- **`handle()` is one Action call.**
- **Retry policy is a job concern, not a business rule.**
- Idempotency is designed into the Action: an Action fed by retries returns early
  when its state is already applied.

### Queue infrastructure

- **Database queue driver** to start — no extra infrastructure.
- **Redis + Horizon** once volume demands it; the code does not change, only the
  connection.
- No transactional outbox: events are dispatched after commit
  (`ShouldDispatchAfterCommit`) and failed jobs are monitored (`queue:failed`,
  Horizon) and retried.

---

## External services: gateways

No Action, model, component, job or controller ever calls `Http::` directly. Every
call out of the application goes through a Gateway and its Client, built by a
Factory.

| Class | Speaks | Owns | Never |
|---|---|---|---|
| **Client** | the vendor's wire format | base URL, auth, headers, timeouts, transport retries | domain vocabulary, business rules, reading config |
| **Gateway** | the domain | VOs/DTOs → request payload, response → VOs/DTOs, verifying and translating webhooks, vendor failures → domain exceptions | HTTP mechanics, reading config |
| **Factory** | construction | reading config and runtime data, then `new` Client + Gateway | calling the vendor, business rules |

```php
namespace App\Gateways\Pagarme;

class PagarmeClient
{
    public function __construct(
        private readonly string $baseUrl,
        private readonly string $apiKey,
    ) {}

    /**
     * @param  array<string, mixed>  $payload
     * @return array<string, mixed>
     */
    public function post(string $path, array $payload): array
    {
        return Http::baseUrl($this->baseUrl)
            ->withToken($this->apiKey)
            ->timeout(10)
            ->retry(3, 200)
            ->acceptJson()
            ->post($path, $payload)
            ->throw()
            ->json();
    }
}
```

```php
class PagarmeGateway implements PaymentGateway
{
    public function __construct(
        private readonly PagarmeClient $client,
    ) {}

    public function charge(ChargeData $charge): ChargeResult
    {
        try {
            $response = $this->client->post('/charges', [
                'amount'   => $charge->amount->cents,
                'currency' => $charge->amount->currency->value,
                'document' => $charge->document->digits(),
            ]);
        } catch (RequestException $e) {
            throw ChargeRejected::fromVendor('pagarme', $e);
        }

        return new ChargeResult(
            id: ChargeId::fromString($response['id']),
            status: ChargeStatus::from($response['status']),
            paid: Money::fromCents($response['amount'], Currency::BRL),
        );
    }
}
```

```php
class PagarmeGatewayFactory
{
    public function make(): PagarmeGateway
    {
        return new PagarmeGateway(
            new PagarmeClient(
                baseUrl: config('services.pagarme.url'),
                apiKey: config('services.pagarme.key'),
            ),
        );
    }
}
```

Rules:

- **The Gateway's signature is domain-shaped**: DTOs and VOs in, DTOs and VOs out.
  A vendor field name never leaves the Gateway.
- **The Client is dumb on purpose.** Arrays in, arrays out — the one place raw
  shapes cross a public method, because they are the vendor's wire format.
- **Vendor failures become domain exceptions** in the Gateway, usually
  `DomainErrorKind::Unavailable`. An Action never catches a `RequestException`.
- **Transport retry belongs to the Client**, business retry to the job.
- **The Factory is the only place config meets the gateway.** The factory method is
  named after what varies — `make()` for static config, `forAccount(Account $a)`
  when credentials vary per record. No `env()` outside config files.
- **Actions inject the Factory** (autowired) and call the gateway it returns.
- **No container binding for a gateway.**

### More than one implementation: contract + adapters

The moment a second vendor appears, the Gateway becomes a **contract** and each
vendor an **adapter**, selected by a factory:

```php
namespace App\Contracts;

interface PaymentGateway
{
    public function charge(ChargeData $charge): ChargeResult;

    public function refund(ChargeId $id, Money $amount): RefundResult;
}
```

```php
class PaymentGatewayFactory
{
    public function __construct(
        private readonly PagarmeGatewayFactory $pagarme,
        private readonly StripeGatewayFactory $stripe,
    ) {}

    public function make(): PaymentGateway
    {
        return $this->for(PaymentProvider::from(config('services.payments.provider')));
    }

    public function for(PaymentProvider $provider): PaymentGateway
    {
        return match ($provider) {
            PaymentProvider::Pagarme => $this->pagarme->make(),
            PaymentProvider::Stripe  => $this->stripe->make(),
        };
    }
}
```

- **The interface is written in domain terms.** If an adapter cannot satisfy it,
  throw an `UnsupportedOperation` domain exception; do not widen the interface.
- **One adapter per vendor**, each with its own Client and factory.
- **One contract test, run against every adapter.** Vendor specifics are tested per
  adapter with `Http::fake()`.
- Do not introduce a contract for a single vendor.

---

## Events: facts and reactions

An Action changes its aggregate and **announces the fact**; everything that follows
in other contexts **reacts** to it, each reaction in its own listener and its own
Action.

### The flow, from a payment webhook

```
POST /webhooks/pagarme
  → PagarmeWebhookRequest            authorize(): gateway verifies the signature
  → PagarmeWebhookController         one Action call
  → Billing\ReceivePaymentWebhook    gateway translates payload → domain DTO;
                                     payment->markPaid(); dispatch PaymentPaid
      ⇢ Sales\MarkOrderAsPaid          → Sales\PayOrder
      ⇢ Billing\IssueInvoiceForPayment → Billing\IssueInvoice
      ⇢ Billing\SendPaymentReceipt     → Billing\SendReceipt
```

**Entry point** — the webhook is a controller like any other. "Authorize" means
verifying the vendor's signature, which the Gateway knows how to do:

```php
class PagarmeWebhookRequest extends FormRequest
{
    public function authorize(PagarmeGatewayFactory $gateways): bool
    {
        return $gateways->make()->verifiesWebhook(
            $this->getContent(),
            (string) $this->header('X-Hub-Signature'),
        );
    }

    public function rules(): array
    {
        return [
            'id'          => ['required', 'string'],
            'type'        => ['required', 'string'],
            'data.status' => ['required', 'string'],
        ];
    }
}
```

**Action** — translates through the Gateway, applies the transition to its own
aggregate, and dispatches the fact:

```php
namespace App\Actions\Billing;

class ReceivePaymentWebhook
{
    public function __construct(
        private readonly PagarmeGatewayFactory $gateways,
    ) {}

    public function handle(WebhookPayload $payload): Payment
    {
        $update = $this->gateways->make()->translateWebhook($payload);

        return DB::transaction(function () use ($update) {
            $payment = Payment::query()->forCharge($update->chargeId)->lockForUpdate()->firstOrFail();

            if ($update->status !== PaymentStatus::Paid || $payment->isPaid()) {
                return $payment;                       // not ours to act on, or a redelivery
            }

            $payment->markPaid($update->occurredAt);
            PaymentPaid::dispatch($payment);

            return $payment;
        });
    }
}
```

**Event** — a past-tense fact carrying its aggregate model:

```php
namespace App\Events\Billing;

class PaymentPaid implements ShouldDispatchAfterCommit
{
    use Dispatchable, SerializesModels;

    public function __construct(
        public readonly Payment $payment,
    ) {}
}
```

**Listeners** — in the context that reacts, queued, one Action call:

```php
namespace App\Listeners\Sales;

class MarkOrderAsPaid implements ShouldQueue
{
    public int $tries = 5;

    public function __construct(
        private readonly PayOrder $payOrder,
    ) {}

    public function handle(PaymentPaid $event): void
    {
        $this->payOrder->handle($event->payment->order);
    }
}
```

Whether an invoice is due at all is a business rule of `IssueInvoice`, not a
condition on the listener.

### Direct call or event?

| Direct call inside the Action | Event + listener |
|---|---|
| must succeed or fail together with the write | reacts to a fact that is already true |
| part of what this use case *is* | belongs to another context (order, invoice, notification) |
| the caller needs its result | can run later, retry on its own, fail without undoing the fact |

### Rules

- **Events are domain facts in the past tense**: `PaymentPaid`, `OrderShipped`.
  Never a command (`SendInvoice`), never a technical change (`PaymentUpdated`).
- **Events live in the context that emits them**: `App\Events\Billing\PaymentPaid`.
- **Only Actions dispatch domain events**, after the state they describe exists.
- **`ShouldDispatchAfterCommit` on every domain event.**
- **The payload is the aggregate model**, `public readonly` with `SerializesModels`.
  A listener in another context reads what else it needs from that model — reading
  across contexts is allowed. No behavior, no rules on the event.
- **One listener = one reaction = one Action call**, never an `if` deciding whether
  to react.
- **Listeners are queued by default** (`ShouldQueue`). A reaction that must be
  visible in the same response is not a reaction — it is a direct call.
- **The emitting Action never knows its listeners.**
- **At-least-once, everywhere.** Every Action reached by a webhook or a queued
  listener returns early when its state is already applied, and dispatches its
  event only on the real transition.
- **Chains go through Actions**, shallow, never looping back to the aggregate that
  started them. A listener never dispatches an event itself.
- **Events do not return data.**
- **Registration is event discovery**: the listener's type hint is the
  subscription. `php artisan event:list` shows the wiring.
- **Webhook payloads never reach an Action raw.** The Gateway verifies and
  translates them into a domain DTO.

---

## Construction: factories over container bindings

The container is used for **autowiring**, not for configuration.

- **Autowire concrete classes.** Constructor and method injection need no
  registration.
- **Build with a Factory when construction needs data.**
- **Avoid bindings.** `bind()`, `singleton()`, `scoped()`, contextual binding and
  interface → implementation bindings hide what runs.
- **When one is unavoidable** — a framework or package extension point — keep it in
  `AppServiceProvider` with a comment saying why.
- **No service location.** No `app()`, `resolve()` or `App::make()` in application
  code. (`app()->isProduction()` in a service provider is configuration, not
  location.)
- **Tests may use the container** to swap a factory:
  `$this->instance(PaymentGatewayFactory::class, $fake)`.

---

## Validation boundary

Every entry point validates the shape of its own input, with the tool that fits:
a **FormRequest** in a controller, an explicit **Validator** in a console command, a
**Form object** in a Livewire component.

| Kind of rule | Where |
|---|---|
| required, max, min, date, email, unique, mimes | FormRequest / console validator / Livewire Form object |
| "amount cannot be negative", "currencies must match" | VO named constructor |
| "a published post cannot be published again" — domain rule | Model transition |
| "only three active plans per account", anything cross-aggregate — business rule | Action |

**No validator of any kind runs inside an Action.** `Validator::make()`,
`$this->validate()`, `Rule::` and a `FormRequest` type-hint never appear in
`app/Actions/`. By the time input reaches `handle()` it is already VOs, enums,
models and DTOs. Jobs and listeners validate nothing.

---

## Authorization

Standard Laravel policies and gates, enforced **at the entry point** — the
FormRequest, the controller method, the Livewire action method, or
`Gate::forUser()` in a command. The Action assumes its caller has authorized.

**Policies and gates live on the interface layer, always. Never in an Action.** The
same Action runs from a controller, a console command, a job and a test; only the
interface layer knows which actor is on the other side.

Nothing in `app/Actions/`, `app/Models/`, `app/Jobs/`, `app/Listeners/` or
`app/Gateways/` ever calls `Gate::`, `authorize()`, `can()`, `auth()` or `request()`.
The arch preset enforces it.

### Two kinds of ability

| Kind | Question | Defined in | Reaches the UI as |
|---|---|---|---|
| **Global ability** | may this user use this area at all? (`viewBilling`, `manageUsers`, `exportReports`) | `Gate::define()` in `AppServiceProvider`, or a policy method without a model (`viewAny`, `create`) | the shared ability map (`auth.can`) — see the frontend layer |
| **Record ability** | may this user do this to *this* record? (`update` this post, `refund` this invoice) | the model's policy | a `can` field on that record's View DTO, computed by the controller |

- **One policy per model**, methods named after the intent (`publish`, `refund`).
- **Roles, when a project needs them, are a string-backed enum on the user**
  (`UserRole`), checked only inside policies and gates. No permissions package;
  nothing outside a policy or gate ever compares a role.
- **The frontend checks abilities, never roles.** Hiding a button is never the
  enforcement — the check at the entry point is.
- If an Action needs to know *who* acted — an audit trail, `approved_by` — the actor
  arrives as a typed argument (`User $actor`). Receiving the actor is not
  authorizing it.
- **When the "permission" is really a business rule, it is not a policy.** "A free
  plan cannot publish a fourth post" is a domain exception from the Action.
- Routes carry middleware (`auth`, `verified`, `can:`), so an unauthenticated hit
  never reaches the entry point.

---

## Errors

Domain failures are typed exceptions that say **what broke**, never **what the HTTP
response should be**. Entry points carry no `try`/`catch`.

```php
namespace App\Exceptions\Blog;

class CannotPublishPost extends DomainException
{
    public function __construct(
        public readonly string $postId,
        public readonly PostStatus $status,
    ) {
        parent::__construct("Post {$postId} cannot be published from {$status->value}.");
    }

    public function kind(): DomainErrorKind
    {
        return DomainErrorKind::Conflict;
    }

    public function userMessage(): string
    {
        return __('This post cannot be published right now.');
    }
}
```

- **`App\Exceptions\DomainException`** (abstract) declares `kind(): DomainErrorKind`
  and `userMessage(): string`, and nothing else. `App\Enums\DomainErrorKind` is a
  string-backed enum — `Conflict`, `NotFound`, `Forbidden`, `Invalid`,
  `Unavailable`.
- **`bootstrap/app.php` turns a kind into a response**, once, per request type:

  ```php
  ->withExceptions(function (Exceptions $exceptions) {
      $exceptions->render(function (DomainException $e, Request $request) {
          $status = match ($e->kind()) {
              DomainErrorKind::Conflict    => 409,
              DomainErrorKind::NotFound    => 404,
              DomainErrorKind::Forbidden   => 403,
              DomainErrorKind::Invalid     => 422,
              DomainErrorKind::Unavailable => 503,
          };

          if ($request->expectsJson() && ! $request->header('X-Inertia')) {
              return response()->json(['message' => $e->userMessage()], $status);
          }

          return back()->withInput()->with('error', $e->userMessage());
      });
  })
  ```

  Inertia requests get the redirect back with an `error` flash, rendered as a toast
  (see the Inertia layer). Livewire handles domain exceptions inside the component
  (see the Livewire layer). Adding an exception class does not touch this file —
  only adding a *kind* does.
- **No `render()` on a domain exception, no `Request` in `app/Exceptions/`.**
- **Never `abort()`, `abort_if()`, `abort_unless()`, or any `HttpException`** inside
  `app/Actions/`, `app/Models/`, `app/Jobs/`, `app/Listeners/` or `app/Gateways/`.
- **One exception class per rule**, named after the rule, carrying the public ids
  that explain it.
- Exceptions are for **broken invariants**, not expected branches. "No results" is
  an empty collection; "not found" for a URL is route model binding's 404.

---

## Data conventions

### Migrations

- **Forward-only.** Migrations have an `up()` and no `down()`. A mistake already
  deployed is fixed by a new migration, never by rolling back. Locally,
  `migrate:fresh --seed` resets everything.
- **One concern per migration**, named after it (`add_public_id_to_orders`).
- **A migration that seeds a lookup table** inserts from the enum's cases, so table
  and enum cannot drift.
- Never edit a migration that has run anywhere outside your machine.

### Keys and constraints

- `$table->id()` for every table; `public_id` for exposed models (see *Public ids*).
- **Foreign keys are always constrained**, with an explicit delete behavior:
  `foreignId('order_id')->constrained()->cascadeOnDelete()` for owned children,
  `->restrictOnDelete()` for references, `->nullOnDelete()` for optional links.
  Never an unconstrained `unsignedBigInteger`.
- Index what scopes filter and order on.
- Money is integer cents plus a currency column, never a float.

### Deletes

- **Soft deletes are opt-in.** `SoftDeletes` only when the domain has "archived and
  restorable" as a real concept; it gets `withTrashed()` scopes and tests.
- Otherwise an end of life is either a **transition** (`$post->archive($at)`, with
  a status) or a **hard delete** through a model method (`$draft->discard()`).

### Tenancy

**No tenancy by default.** When `/init` declares a multi-tenant project:

- **Single database, a `tenant_id` column** on every tenant-owned table, constrained.
- **Explicit, never magic**: a `#[Scope] forTenant(Tenant $tenant)` on each model,
  called visibly in every `Get*` Action; `Tenant $tenant` passed as an argument from
  the entry point. **No global scopes** filling or filtering `tenant_id` behind the
  reader's back.
- Named constructors take the `Tenant` and set `tenant_id` themselves.
- Per-tenant vendor credentials come through a factory method (`forTenant(Tenant $t)`).
- One feature test per entry point proving tenant A cannot reach tenant B's records.

---

## User-facing strings

**Every user-facing string goes through `__()`** — messages, labels, enum
`label()`s, `userMessage()`, validation attributes, notifications, mail. Translation
files are JSON in `lang/` (`lang/en.json`, `lang/pt_BR.json`), keyed by the source
string; grouped PHP files only for validation and enum labels. A single-language
project still uses `__()` — adding a language later is then a file, not a refactor.
The frontend layer covers how strings reach React, Vue and Blade.

---

## Comments

**No comment is the default.** Names and types say what the code does. A comment
that repeats them is noise, and it drifts.

There are exactly **two** things a comment is allowed to be:

1. **A shenanigan note** — the *why* behind something surprising: a workaround (link
   the issue), a vendor quirk, ordering or timing not visible in the code, a branch
   that looks wrong but is deliberate, a rule whose reason lives outside the code
   (`// 2.9% + 30¢ — Stripe's US card rate, contract §4`), an unavoidable container
   binding.
2. **A docblock carrying a type PHP cannot express** — a generic
   (`Collection<int, Post>`, `LengthAwarePaginator<Post>`) or an array shape
   (`array{driver: string}`, `list<string>`), and only where an array is legal at
   all.

The test: **could a competent reader work this out from the code alone?** If yes,
no comment.

- Never narrate the code; never state the obvious.
- Needing a comment to explain *what* means a missing name.
- No commented-out code, no section banners, no author tags, no changelogs.
- No `TODO` without a linked issue.
- No `@param` / `@return` repeating the signature; no class summary blocks.

---

## Testing

Pest. **Test everything — in priority order.** A gap in tier 1 is a bug; a gap in
tier 4 is a to-do.

| Tier | What | Assert with |
|---|---|---|
| 1 — **backend feature** | every Action through the entry point that really reaches it: HTTP route, Inertia page, API endpoint, console command, job, listener, Livewire component | persisted state, dispatched events, jobs and notifications, domain exceptions, status codes, redirects, flash, validation errors, Inertia component + props, JSON |
| 2 — domain unit | VOs, enums, model transitions and scopes, casts, DTO named constructors | plain `expect()` |
| 3 — gateways | Gateway + Client per vendor, contract test per adapter | `Http::fake()`, `Http::assertSent()` |
| 4 — frontend | critical user journeys | Pest browser tests |

```php
it('publishes a draft post', function () {
    Event::fake([PostPublished::class]);
    $author = User::factory()->create();
    $post = Post::factory()->draft()->for($author, 'author')->create();

    $this->actingAs($author)
        ->post(route('posts.publish.store', $post))
        ->assertRedirect(route('posts.show', $post));

    expect($post->refresh()->status)->toBe(PostStatus::Published);
    Event::assertDispatched(PostPublished::class);
});

it('refuses to publish twice', function () {
    $post = Post::factory()->published()->create();

    expect(fn () => app(PublishPost::class)->handle($post, PublishedAt::now()))
        ->toThrow(CannotPublishPost::class);
});
```

Rules:

- **Every change ships with its tier-1 test first.**
- **Every Action gets at least**: the happy path, one test per invariant and business
  rule, and — at its entry point — one test for authorization denied and one for
  invalid input.
- **One test per rule.** Each extra entry point gets one test proving it authorizes,
  validates and delegates.
- **Events are tested at both ends, plus once end to end.** The emitting Action
  asserts the event was dispatched — and not dispatched on a redelivery. Each
  listener's Action has its own tests. The wiring gets
  `Event::assertListening(PaymentPaid::class, MarkOrderAsPaid::class)`, and one
  feature test per flow runs with the sync queue and real listeners.
- **Idempotency is tested by redelivery, not by locking.** The test suite runs on
  SQLite, where `lockForUpdate()` is a no-op: deliver the same webhook (or run the
  same listener) twice and assert one transition, one event, one row.
- **Never hit a real vendor.** Swap the gateway factory or `Http::fake()` the vendor.
- **A factory per model**, with named states (`draft()`, `published()`). No seeders
  in tests except the lookup-table migrations, no shared fixture data.
- **Database: SQLite in-memory** (`DB_CONNECTION=sqlite`, `DB_DATABASE=:memory:` in
  `phpunit.xml`) with `RefreshDatabase`. Engine-specific SQL is therefore banned
  outside a `Get*` report, and a report using it gets a test marked for the
  production engine.
- **No coverage gate.** The tier-1 rule above is the requirement; the number is not
  measured.
- **Browser tests** (Pest 4 browser plugin) cover the critical journeys only —
  sign-up, checkout, the one flow that pays the bills — never instead of tier 1.

---

## Tooling and enforcement

Every rule a machine can check is checked. `composer lint` and then `composer test`
run on every change.

| Tool | Config | Gate |
|---|---|---|
| **Pint** | `pint.json`, preset `laravel` | `vendor/bin/pint --test` |
| **Larastan** | `phpstan.neon`, **level 6**, paths `app/` | `vendor/bin/phpstan analyse` — no baseline file on a new project |
| **Rector** | `rector.php` with `driftingly/rector-laravel` sets (Laravel 13, code quality, type declarations, dead code) | `vendor/bin/rector --dry-run` — changes are applied by a human, never by the gate |
| **Pest arch** | `tests/Arch.php` (below) | part of `composer test` |
| **Grep gates** | `scripts/grep-gates.sh` (below) | part of `composer lint` |

```json
"scripts": {
    "lint": ["pint --test", "phpstan analyse", "rector --dry-run", "bash scripts/grep-gates.sh"],
    "test": ["@php artisan config:clear --ansi", "@php artisan test"]
}
```

A frontend layer may add its own checks to `lint` (Inertia adds `@types:fresh`);
they then run wherever `lint` runs.

Larastan level 6 does not check generics, so the arch preset and review carry the
typing rules it misses.

### Arch preset — `tests/Arch.php`

```php
arch()->preset()->php();
arch()->preset()->security();
arch()->preset()->laravel();

arch('actions are use cases')
    ->expect('App\Actions')
    ->toBeClasses()
    ->not->toBeFinal()
    ->toHaveMethod('handle')
    ->not->toUse([
        'Illuminate\Support\Facades\Gate',
        'Illuminate\Support\Facades\Auth',
        'Illuminate\Support\Facades\Validator',
        'Illuminate\Support\Facades\Http',
        'Illuminate\Validation\Rule',
        'Illuminate\Foundation\Http\FormRequest',
        'Illuminate\Http\Request',
        'auth', 'request', 'session', 'abort', 'abort_if', 'abort_unless', 'app', 'resolve',
    ]);

arch('domain below the entry point never authorizes or aborts')
    ->expect(['App\Models', 'App\Jobs', 'App\Listeners', 'App\Gateways', 'App\Data', 'App\ValueObjects'])
    ->not->toUse([
        'Illuminate\Support\Facades\Gate',
        'Illuminate\Support\Facades\Auth',
        'Illuminate\Http\Request',
        'auth', 'request', 'abort', 'abort_if', 'abort_unless', 'app', 'resolve',
    ]);

arch('models carry no config or events')
    ->expect('App\Models')
    ->not->toUse(['config', 'event', 'dispatch', 'Illuminate\Support\Facades\Event']);

arch('dtos and value objects are final readonly')
    ->expect(['App\Data', 'App\ValueObjects'])
    ->classes()
    ->toBeFinal()
    ->toBeReadonly();

arch('nothing else is final')
    ->expect(['App\Actions', 'App\Models', 'App\Gateways', 'App\Http', 'App\Jobs', 'App\Listeners'])
    ->classes()
    ->not->toBeFinal();

arch('dto suffixes')
    ->expect('App\Data')
    ->classes()
    ->toHaveSuffix(['Data', 'Result', 'Filter', 'View']);

arch('only clients talk http')
    ->expect('Illuminate\Support\Facades\Http')
    ->toOnlyBeUsedIn('App\Gateways');

arch('enums are string backed')
    ->expect('App\Enums')
    ->toBeStringBackedEnums();

arch('events are dispatched after commit')
    ->expect('App\Events')
    ->toImplement('Illuminate\Contracts\Events\ShouldDispatchAfterCommit');

arch('listeners are queued')
    ->expect('App\Listeners')
    ->toImplement('Illuminate\Contracts\Queue\ShouldQueue');

arch('domain exceptions carry a kind')
    ->expect('App\Exceptions')
    ->classes()
    ->toExtend('App\Exceptions\DomainException')
    ->ignoring('App\Exceptions\DomainException')
    ->not->toUse(['Illuminate\Http\Request', 'Symfony\Component\HttpKernel\Exception']);
```

### Grep gates — `scripts/grep-gates.sh`

Arch tests see dependencies between classes; they cannot see a method called on an
instance. `$post->update([...])` inside an Action passes every arch test. What they
miss is caught by searching the source as text: `scripts/grep-gates.sh` runs one
search per banned pattern, prints every hit as `file:line`, and exits 1 when there
is any. `composer lint` runs it, so every gate that runs `lint` runs it too.

```bash
#!/usr/bin/env bash
#
# Fails on code patterns the coding guidelines ban but arch tests cannot see:
# method calls on instances, Blade directives, raw SQL. Prints every hit as
# file:line and exits 1 when there is at least one.

set -uo pipefail
cd "$(dirname "$0")/.."

failed=0

# gate <rule> <pattern> <allowed-hit-regex|-> <path>...
gate() {
    local rule="$1" pattern="$2" allowed="$3"
    shift 3

    local paths=() path
    for path in "$@"; do
        [ -e "$path" ] && paths+=("$path")
    done
    [ ${#paths[@]} -gt 0 ] || return 0

    local hits
    hits=$(grep -rnE --include='*.php' -- "$pattern" "${paths[@]}")
    [ "$allowed" = - ] || hits=$(grep -vE -- "$allowed" <<< "$hits")
    [ -n "$hits" ] || return 0

    echo "✗ $rule"
    sed 's/^/    /' <<< "$hits"
    failed=1
}

# uncommented — reads grep hits on stdin, — drops hits whose previous line is a comment.
uncommented() {
    local file line rest
    while IFS=: read -r file line rest; do
        [ -n "$file" ] || continue
        sed -n "$((line - 1))p" "$file" | grep -q '//' || echo "$file:$line:$rest"
    done
}

gate "Actions never write — call a model transition or named constructor" \
    '->(save|update|delete|increment|decrement|attach|detach|sync|forceDelete)\(|::create\(' - \
    app/Actions

gate "A pivot with data is a model — no withPivot, ->pivot->, Pivot subclasses" \
    'withPivot\(|->pivot->|extends Pivot' - \
    app

gate "Scopes use #[Scope], never the scopeXxx() prefix" \
    'function scope[A-Z]' - \
    app/Models

gate "No raw SQL outside a Get* report Action" \
    'whereRaw|havingRaw|orderByRaw|orWhereRaw' '^app/Actions/[^:]*/Get[^/:]*\.php:' \
    app

gate "No bare where() in an Action — every predicate is a #[Scope]" \
    '->(or)?[wW]here(In|NotIn|Null|NotNull|Has|Between|Column|Date)?\(' - \
    app/Actions

gate "Casts go in casts(), never the \$casts property" \
    '\$casts[[:space:]]*=' - \
    app/Models

bindings=$(grep -rnE --include='*.php' -- '->(bind|singleton|scoped)\(' app/Providers 2>/dev/null | uncommented)
if [ -n "$bindings" ]; then
    echo "✗ No container bindings — a factory instead, or a comment above saying why"
    sed 's/^/    /' <<< "$bindings"
    failed=1
fi

if grep -q '"livewire/livewire"' composer.json 2>/dev/null; then
    gate "Livewire components never write, open transactions or query" \
        '->(save|update|create|delete)\(|DB::transaction|::query\(\)' - \
        resources/views/pages resources/views/components

    gate "No @php blocks in templates — use #[Computed]" \
        '@php' - \
        resources/views/pages resources/views/components

    gate "No Flux — use the x-ui.* Blade components" \
        '<flux:' - \
        resources/views
fi

[ "$failed" -eq 0 ] && echo "✓ grep gates clean"
exit "$failed"
```

- **A hit is a violation until proven otherwise.** Fix the code, not the pattern.
- **The one sanctioned escape** is a container binding with a comment on the line
  above saying why (see *Construction*); the script skips those.
- **False positives are rare and specific** — a Collection's `->where()` inside an
  Action is the usual one. Rewrite it with `filter()` rather than widening the
  pattern.
- **Patterns change with the guidelines.** A new mechanical rule that arch tests
  cannot express gets a new `gate` line in the same change.

---

## New projects

A new project starts from `laravel new` with the chosen starter kit (React, Vue —
with or without auth — or Livewire), then, before any feature:

1. **Contexts** from the project description get their folders as the first class
   in each is created — no empty scaffolding.
2. **Tooling**: Pint, Larastan (level 6), Rector with `rector-laravel`, Pest arch
   preset, `scripts/grep-gates.sh`, `composer lint`; SQLite in-memory in `phpunit.xml`.
3. **Foundations**: `DomainException` + `DomainErrorKind` + the `withExceptions()`
   mapping, `HasPublicId`, `Pagination` and `Money` (when money exists),
   `Model::shouldBeStrict()`.
4. **The starter kit's own code is brought under these rules.** Its auth and
   settings controllers write directly to models; they are refactored into Actions
   in an `Identity` context (`RegisterUser`, `UpdateProfile`, `DeleteAccount`,
   `UpdatePassword`), with named constructors and transitions on `User`
   (`User::register(...)`, `$user->changeProfile(...)`), `public_id` on `User`, and
   the kit's tests kept green throughout. This is the project's first phase; no
   kit file is left as an exception.

---

## Anti-patterns

| Do not | Do |
|---|---|
| `app/Billing/Models/…`, `src/Modules/…` | flat by type, context subfolders: `app/Actions/Billing/` |
| an Action in `app/Actions/` with no context folder | `app/Actions/<Context>/` |
| a Billing Action calling `$order->markPaid()` on a Sales model | `Sales\PayOrder`, or an event Sales listens to |
| copying another context's data into your tables | read its models directly |
| `PostService`, `PostManager`, `PostRepository` | one Action per intent |
| a second public method on an Action | a second Action |
| `PublishPost::run($post, $at)` or any `static` on an Action | an injected instance |
| `Post::create([...])` / `$post->update([...])` inside an Action | `Post::draft(...)` / `$post->publish($at)` |
| `$user->update($request->validated())` for "plain CRUD" | `$user->changeProfile(ProfileData::fromRequest($request))` via an Action |
| a write Action without `DB::transaction()` | the whole body in one transaction |
| an observer that sends mail, writes another row or dispatches an event | the Action orders the effect |
| a `creating` hook enforcing a business rule | the rule in the Action |
| integer ids in URLs, props, API responses | `public_id` (`ord_…`), route binding on it |
| `Str::uuid()` as a public id | `prefix + Str::ulid()->toBase58()` |
| a VO for a title or a name | `string`; a VO only when the value has a rule |
| `handle(array $data)` / five loose arguments | one DTO; more than three arguments collapse |
| an Action or Gateway returning `bool` or an associative array | model, VO, result DTO |
| `final class PublishPost`, `final class Post` | `final readonly` only on DTOs and VOs |
| `spatie/laravel-data` or another DTO package | plain `final readonly` PHP |
| int-backed or unbacked enums for stored values | string-backed, snake_case values |
| a status column holding the enum string for a business enum | `*_status` lookup table + FK + memoized `Attribute` |
| an Eloquent model for `post_status` | `id` + `label` table, `DB` facade in one attribute |
| querying the lookup table on every attribute read | the static label ⇄ id memo |
| passing `post_status_id` around | pass the enum |
| `scopePublished()` prefix methods | `#[Scope] protected function published()` |
| `->where('post_status_id', 3)` in an Action | a `#[Scope]` that names the predicate |
| `whereRaw`, interpolated SQL | builder methods, bindings only; raw only for aggregates in a `Get*` |
| a repository or query-object layer | `Model::query()` composed in a `Get*` Action |
| a list `Get*` with loose arguments, `int $perPage` | one `*Filter` DTO with a `Pagination` VO |
| `Cache::remember()` in a controller or model | caching inside a `Get*` Action, invalidated by the writer |
| a custom `publish()` method on a CRUD controller | `PublishPostController@store`, undone by `PublishPostController@destroy` |
| an invokable controller (`__invoke`) | an intent controller performing the intent in `store` |
| a controller that queries, transforms domain data or persists | FormRequest → Action → response |
| reusing Inertia View DTOs as the public API | versioned API Resources |
| `Http::` outside a Client | Gateway + Client |
| a Gateway or Client calling `config()` | a Factory reads it and calls `new` |
| `$this->app->bind(PaymentGateway::class, ...)` | a Factory the Action injects |
| `app(...)` / `resolve(...)` in application code | injection |
| business logic in a job or listener | queue config + one Action call |
| `if (! $account->invoicing) return;` in a listener | the rule in the Action the listener calls |
| a sync listener by default | `ShouldQueue`; same-response effects are direct calls |
| `PaymentUpdated`, `SendInvoice` as event names | `PaymentPaid`, `InvoiceIssued` |
| an event dispatched from a model, observer, controller or component | the Action dispatches it, after commit |
| `Gate::authorize()`, `->can()`, a role check inside an Action | at the entry point |
| a role string compared outside a policy or gate | an ability; roles live in policies only |
| a permissions package for a fixed set of abilities | `Gate::define()` + policies |
| `Validator::make()` inside an Action | shape at the entry point |
| `abort(403)` in an Action or model | a domain exception with a `DomainErrorKind` |
| `try`/`catch` around Actions at entry points | the `withExceptions()` mapping |
| a `down()` method, rolling back a deployed migration | forward-only; fix with a new migration |
| `unsignedBigInteger('order_id')` with no constraint | `foreignId()->constrained()` with delete behavior |
| `SoftDeletes` by reflex | a transition or a hard delete, unless restore is a real concept |
| a global scope filling `tenant_id` | an explicit `forTenant()` scope and a `Tenant` argument |
| a hardcoded user-facing string | `__()` |
| a lockForUpdate-only idempotency test | redeliver twice, assert one transition |
| a feature test hitting a real vendor | swap the gateway factory, or `Http::fake()` |
| a starter-kit controller left writing to `User` | refactored into `Identity` Actions in phase one |
| `// publish the post` above `$post->publish($at)` | nothing |
| commented-out code | delete it |

---

## Review checklist

- [ ] Every new class sits in its context subfolder; models, enums, policies and casts stay flat.
- [ ] Other contexts are read directly, written only through their Actions, reacted to through events.
- [ ] Every write goes through an Action with `handle()` and a transaction.
- [ ] No `create()`, `update()`, `save()`, `delete()`, `increment()`, `attach()` or `sync()` in an Action — every write is a model method, CRUD included.
- [ ] Model hooks only derive columns of the same row.
- [ ] `handle()` is the only public method; no `static`; verb + noun names.
- [ ] More than three arguments collapse into a DTO.
- [ ] Actions and Gateways return models, VOs, DTOs, Collections or paginators — never `bool` or arrays.
- [ ] No array crosses a class boundary outside framework contracts and edge constructors.
- [ ] VOs only where the value has a rule or behavior; `final readonly`, private constructor.
- [ ] DTOs are plain `final readonly`, in `app/Data/<Context>/`, suffixed `Data` / `Result` / `Filter` / `View`.
- [ ] Exposed models use `HasPublicId`; no integer id leaves the application.
- [ ] Business enums use a lookup table with a memoized `Attribute`; enums are string-backed and own every rule.
- [ ] Every predicate is a `#[Scope]`; no bare `where()` in Actions; raw SQL only for aggregates in `Get*`.
- [ ] `Get*` lists take a `*Filter` with `Pagination`; caching only inside `Get*`, invalidated by the writer.
- [ ] Entry points: authorize → validate → one Action → present. Every controller method is a resource method; a non-CRUD intent is its own controller (`store` does it, `destroy` undoes it); no `__invoke`, no custom methods.
- [ ] Public API: `/v1`, Sanctum, API Resources, never Inertia View DTOs.
- [ ] Global abilities via `Gate::define()`/policies; record abilities via policies; roles only inside them.
- [ ] No `Gate::`, `auth()`, `request()`, `abort()` below the entry point.
- [ ] Jobs and listeners: queue config + one Action call; listeners queued; events after commit, past tense, in the emitting context.
- [ ] Every external call goes Gateway → Client, built by a Factory; no bindings.
- [ ] Domain exceptions per rule with `kind()` + `userMessage()`; mapping once in `bootstrap/app.php`.
- [ ] Migrations forward-only; foreign keys constrained with explicit delete behavior; soft deletes only when restore is real.
- [ ] Every user-facing string goes through `__()`.
- [ ] Tier-1 test first; idempotency tested by redelivery; no real vendor.
- [ ] `composer lint` (Pint, Larastan 6, Rector dry-run, `scripts/grep-gates.sh`) and `composer test` (with `tests/Arch.php`) pass.
- [ ] Comments are shenanigan notes or generic/array-shape docblocks only.
